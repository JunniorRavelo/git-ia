#!/usr/bin/env python3
import os
import sys
import json
import subprocess
import tempfile
import time
from pathlib import Path
import httpx

__version__ = "1.9.0"

# 0. Archivo de configuración persistente (~/.config/git-ai/config.env)
#    Se carga antes que nada: las variables de entorno ya definidas tienen prioridad
#    sobre el archivo, así funciona tanto de forma automática como manual.
_CONFIG_DIR = Path(os.getenv("GIT_AI_CONFIG_DIR", os.path.expanduser("~/.config/git-ai")))
_CONFIG_FILE = _CONFIG_DIR / "config.env"

def _load_config_file():
    """Carga variables desde el archivo de config. No sobrescribe vars ya definidas en el entorno."""
    if not _CONFIG_FILE.is_file():
        return
    for line in _CONFIG_FILE.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, _, value = line.partition("=")
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        if key and key not in os.environ:
            os.environ[key] = value

_load_config_file()

# Colores: se respetan NO_COLOR y la salida no interactiva (pipes/redirecciones)
_USE_COLOR = sys.stdout.isatty() and os.getenv("NO_COLOR") is None
_GREEN_COLOR = "\033[92m" if _USE_COLOR else ""
_RESET_COLOR = "\033[0m" if _USE_COLOR else ""

# El catálogo de modelos ya no es una lista fija: `git ai -c` lo consulta en
# vivo al API (GET {NVIDIA_BASE_URL}/models). Como ese endpoint no informa las
# capacidades de cada modelo, el filtro es por nombre: se excluyen las familias
# que no generan texto por chat completions y se lista todo lo demás.
_NON_CHAT_PATTERNS = (
    # embeddings / recuperación
    "embed", "rerank", "retriever", "retrieval",
    # clasificación / puntuación / moderación
    "reward", "guard", "safety", "calibration",
    # multimodales no-texto (visión, audio, video, documentos)
    "vision", "vlm", "omni", "clip", "vila", "neva", "kosmos", "fuyu",
    "deplot", "cosmos", "diffusion",
    # OCR / parsing / voz / traducción / detección
    "parse", "riva", "detector",
)

def _is_text_chat_model(model_id: str) -> bool:
    """True si el id del modelo no cae en ninguna familia no-chat."""
    low = model_id.lower()
    return not any(p in low for p in _NON_CHAT_PATTERNS)

def _probe_models(model_ids: list) -> list:
    """Prueba cada modelo con una petición mínima; devuelve los que responden 200.

    El catálogo lista modelos que luego dan 404 al invocarlos; esta prueba
    descarta esos (y los que cuelgan sin generar nada) antes de mostrarlos.
    """
    from concurrent.futures import ThreadPoolExecutor

    def _probar(mid: str):
        headers = {"Accept": "application/json", "Content-Type": "application/json"}
        if os.getenv("NVIDIA_API_KEY"):
            headers["Authorization"] = f"Bearer {os.environ['NVIDIA_API_KEY']}"
        try:
            with httpx.Client(
                trust_env=False,
                timeout=httpx.Timeout(connect=10.0, read=_PROBE_TIMEOUT, write=10.0, pool=10.0),
            ) as http:
                r = http.post(
                    f"{_BASE_URL}/chat/completions",
                    headers=headers,
                    json={
                        "model": mid,
                        "messages": [{"role": "user", "content": "ok"}],
                        "max_tokens": 1,
                        "stream": False,
                    },
                )
            return mid if r.status_code == 200 else None
        except Exception:
            return None

    vivos, total = [], len(model_ids)
    with ThreadPoolExecutor(max_workers=16) as ex:
        for hecho, resultado in enumerate(ex.map(_probar, model_ids), 1):
            if resultado:
                vivos.append(resultado)
            print(f"\r  probando {hecho}/{total}... {len(vivos)} OK", end="", flush=True)
    print()
    return sorted(vivos)

# Configuración desde variables de entorno (con defaults)
_BASE_URL = os.getenv("NVIDIA_BASE_URL", "https://integrate.api.nvidia.com/v1")
_MODEL = os.getenv("COMMIT_IA_MODEL", "deepseek-ai/deepseek-v4.1-flash")
_LANG = os.getenv("COMMIT_IA_LANG", "es")

# Límite de tiempo (segundos) para generar el mensaje; evita esperas infinitas
try:
    _TIMEOUT = float(os.getenv("GIT_AI_TIMEOUT", "60"))
    if _TIMEOUT <= 0:
        raise ValueError
except ValueError:
    _TIMEOUT = 60.0

# Verificación de modelos: el catálogo /models lista más de lo que se puede
# invocar (los caídos dan 404 "Not found for account" al usarlos), así que
# `git ai -c` prueba cada candidato de verdad y cachea el resultado.
_CACHE_FILE = _CONFIG_DIR / "models-cache.json"
_CACHE_TTL = 7 * 24 * 3600  # la verificación cacheada dura 7 días
_PROBE_TIMEOUT = 20.0       # segundos máximos de respuesta por modelo en la prueba
_BLACKLIST_FILE = _CONFIG_DIR / "blacklist.json"  # modelos caídos: no se re-testean

def _cargar_blacklist() -> set:
    """Modelos conocidos como caídos (404/cuelgues): se omiten en cada verificación."""
    try:
        data = json.loads(_BLACKLIST_FILE.read_text(encoding="utf-8"))
        return set(data) if isinstance(data, list) else set()
    except (OSError, ValueError):
        return set()

def _guardar_blacklist(blacklist: set) -> None:
    _CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    _BLACKLIST_FILE.write_text(json.dumps(sorted(blacklist)), encoding="utf-8")

def cmd_configure():
    """Consulta el catálogo del API, verifica qué modelos responden y permite elegir/guardar el activo."""
    print(f"git-ai v{__version__} — Configuración de modelo\n")

    # 1) Caché de la última verificación (salvo que se pida --refresh)
    if not _FORCE_REFRESH:
        try:
            data = json.loads(_CACHE_FILE.read_text(encoding="utf-8"))
            edad = time.time() - float(data.get("checked", 0))
            if data.get("models") and edad < _CACHE_TTL:
                print(f"✔ Lista verificada hace {edad / 3600:.1f} h (caché: {_CACHE_FILE}).")
                print("   Usa 'git ai -c --refresh' para volver a probar los modelos.")
                return _listar_y_elegir(data["models"], f"{len(data['models'])} verificados")
        except (OSError, ValueError, AttributeError):
            pass  # sin caché o corrupta → camino en vivo

    # 2) Catálogo en vivo
    print("Consultando el catálogo de modelos en NVIDIA build API...")
    _t0 = time.monotonic()
    headers = {"Accept": "application/json"}
    # El endpoint /models es público; si hay API key se manda por si esto cambia.
    if os.getenv("NVIDIA_API_KEY"):
        headers["Authorization"] = f"Bearer {os.environ['NVIDIA_API_KEY']}"
    try:
        with httpx.Client(trust_env=False, timeout=30) as http:
            resp = http.get(f"{_BASE_URL}/models", headers=headers)
            resp.raise_for_status()
            catalog = resp.json()
    except httpx.HTTPStatusError as e:
        if e.response.status_code in (401, 403):
            print(f"❌ Error: la API rechazó tu NVIDIA_API_KEY (HTTP {e.response.status_code}).")
        else:
            print(f"❌ Error HTTP {e.response.status_code} al consultar el catálogo.")
        sys.exit(1)
    except (httpx.RequestError, ValueError) as e:
        print(f"❌ Error de comunicación con la API: {e}")
        sys.exit(1)

    print(f"✔ Catálogo recibido en {time.monotonic() - _t0:.1f} s")
    all_ids = sorted(
        str(m.get("id", "")) for m in catalog.get("data", []) if m.get("id")
    )
    candidatos = [mid for mid in all_ids if _is_text_chat_model(mid)]
    if not candidatos:
        print("❌ El catálogo no devolvió modelos compatibles con chat de texto.")
        sys.exit(1)

    # 3) Verificación real: el catálogo lista de más y varios modelos dan 404
    #    "Not found for account" al invocarlos (o cuelgan sin generar nada).
    #    Los caídos van a lista negra y ya no se re-testean; los modelos nuevos
    #    que aparezcan en el catálogo se prueban solos al aparecer.
    api_key = os.getenv("NVIDIA_API_KEY")
    if api_key:
        blacklist = _cargar_blacklist()
        a_probar = [m for m in candidatos if m not in blacklist]
        omitidos = len(candidatos) - len(a_probar)
        if a_probar:
            detalle = f" ({omitidos} en lista negra se omiten)" if omitidos else ""
            print(f"Probando {len(a_probar)} modelos{detalle}...")
            models = _probe_models(a_probar)
        else:
            models = []
            print(f"Los {len(candidatos)} candidatos están en lista negra; nada que probar.")
        muertos = sorted(set(a_probar) - set(models))
        if muertos:
            blacklist.update(muertos)
            _guardar_blacklist(blacklist)
            print(f"⛔ {len(muertos)} añadidos a lista negra ({_BLACKLIST_FILE})")
        _CONFIG_DIR.mkdir(parents=True, exist_ok=True)
        _CACHE_FILE.write_text(
            json.dumps({"checked": time.time(), "models": models}), encoding="utf-8"
        )
        print(f"✔ {len(models)} de {len(candidatos)} disponibles; caché en {_CACHE_FILE}")
        if not models:
            print("❌ Ningún modelo disponible. Revisa tu NVIDIA_API_KEY y tu conexión.")
            print(f"   (borra {_BLACKLIST_FILE} para re-testear todo)")
            sys.exit(1)
        titulo = f"{len(models)} disponibles; {len(blacklist)} en lista negra sin re-testear"
    else:
        models = candidatos
        titulo = f"{len(models)} de {len(all_ids)} del catálogo; SIN verificar (define NVIDIA_API_KEY)"

    return _listar_y_elegir(models, titulo)

def _listar_y_elegir(models: list, titulo: str) -> None:
    """Muestra la lista numerada (actual en verde) y guarda el modelo elegido."""
    print(
        f"\nModelos disponibles ({titulo};"
        " se excluyen embeddings, visión, safety, reward, parsing, riva, etc.):\n"
    )
    for i, mid in enumerate(models, 1):
        if mid == _MODEL:
            print(f"{_GREEN_COLOR}  {i}. {mid}  (actual){_RESET_COLOR}")
        else:
            print(f"  {i}. {mid}")
    print()
    while True:
        try:
            sel = input("Selecciona un modelo por número o id (o 'q' para salir sin guardar): ").strip()
        except (EOFError, KeyboardInterrupt):
            print("\nNo se guardaron cambios.")
            sys.exit(0)
        if sel.lower() in ("q", "quit", "exit", ""):
            print("No se guardaron cambios.")
            sys.exit(0)
        chosen = None
        if sel.isdigit():
            idx = int(sel) - 1
            if 0 <= idx < len(models):
                chosen = models[idx]
        elif sel in models:
            chosen = sel
        if chosen is None:
            print("❌ Selección inválida. Intenta de nuevo.")
            continue
        break
    _CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    _CONFIG_FILE.write_text(f'COMMIT_IA_MODEL="{chosen}"\n', encoding="utf-8")
    print(f"\n✔ Modelo guardado en {_CONFIG_FILE}")
    print(f'  COMMIT_IA_MODEL="{chosen}"')
    print("\nPara usarlo manualmente (ej. en ~/.bashrc), añade:")
    print(f'  export COMMIT_IA_MODEL="{chosen}"')
    print("\nNota: la variable de entorno manual tiene prioridad sobre el archivo de config.")
    sys.exit(0)

def cmd_help():
    """Muestra la ayuda con los comandos y opciones disponibles."""
    print(f"git-ai v{__version__} — Genera mensajes de commit con IA (API de NVIDIA build)\n")
    print("Uso: git ai [opción]")
    print("     git-ai [opción]\n")
    print("Opciones:")
    print("  (sin opción)   Analiza los cambios en stage (git diff --cached) y propone")
    print("                 un mensaje de commit siguiendo Conventional Commits.")
    print("  -y, --yes      Acepta automáticamente el mensaje propuesto y hace el commit")
    print("                 sin mostrar el prompt de confirmación.")
    print("  -c, configure  Consulta el catálogo del API de NVIDIA, prueba cada modelo")
    print("                 de chat de texto, manda los caídos a lista negra (cachea 7")
    print("                 días) y elige el activo (~/.config/git-ai/config.env).")
    print("  --refresh      Junto con -c: re-verifica sin caché; la lista negra no")
    print("                 se re-testea (solo vivos y modelos nuevos).")
    print("  -h, --help     Muestra esta ayuda.")
    print("  -V, --version  Muestra la versión instalada.\n")
    print("Variables de entorno:")
    print("  NVIDIA_API_KEY   (obligatoria) Tu API key de NVIDIA (https://build.nvidia.com).")
    print("  COMMIT_IA_MODEL  Modelo a usar (por defecto: deepseek-ai/deepseek-v4.1-flash).")
    print("  COMMIT_IA_LANG   Idioma del mensaje del commit, código ISO 639-1 (por defecto: es).")
    print("  GIT_AI_TIMEOUT   Límite de tiempo en segundos para generar el mensaje (60).")
    print("                   Si se agota, se cancela y sugiere cómo proceder.\n")
    print("Tras generar el mensaje: s=confirmar / n=cancelar / e=editar / r=regenerar.")
    sys.exit(0)

# 0. Manejo de argumentos: -h/--help ; --version/-V ; -c/configure ; -y/--yes ;
#    --refresh (junto con -c: fuerza re-probar los modelos sin usar la caché).
#    Se recorre argv completo para que las banderas puedan ir en cualquier orden.
_AUTO_YES = False
_FORCE_REFRESH = "--refresh" in sys.argv[1:]
for _arg in sys.argv[1:]:
    if _arg in ("-h", "--help", "help"):
        cmd_help()
    if _arg in ("--version", "-V", "version"):
        print(f"git-ai v{__version__}")
        sys.exit(0)
    if _arg in ("-c", "configure", "--configure"):
        cmd_configure()
    if _arg in ("-y", "--yes", "yes"):
        _AUTO_YES = True

# 1. Capturar los cambios en stage (git diff --cached)
try:
    diff_result = subprocess.run(["git", "diff", "--cached"], capture_output=True, text=True, check=True)
    diff_text = diff_result.stdout.strip()
except subprocess.CalledProcessError:
    print("❌ Error: Asegúrate de estar dentro de un repositorio de Git.")
    sys.exit(1)

if not diff_text:
    print("❌ No hay archivos en stage. Usa 'git add' primero.")
    sys.exit(0)

# 2. Mapa de códigos ISO 639-1 -> nombre del idioma (para el prompt)
_LANG_NAMES = {
    "es": "español", "en": "English", "fr": "français", "de": "Deutsch",
    "pt": "português", "it": "italiano", "pl": "polski", "hi": "हिन्दी",
    "ja": "日本語", "zh": "中文", "ru": "Русский", "ko": "한국어",
    "ar": "العربية", "nl": "Nederlands", "tr": "Türkçe",
}
_LANG_NAME = _LANG_NAMES.get(_LANG, _LANG)  # si no está listado, pasa el código tal cual

# 3. Inicializar cliente ignorando proxies corruptos del sistema
# La API key DEBE proporcionarse vía NVIDIA_API_KEY; no se embebe ningún valor.
_API_KEY = os.getenv("NVIDIA_API_KEY")
if not _API_KEY:
    print("❌ Error: define la variable de entorno NVIDIA_API_KEY antes de ejecutar el script.")
    print("   Ejemplo: export NVIDIA_API_KEY=\"nvapi-...\"")
    sys.exit(1)
from openai import OpenAI  # import diferido: -c/-h/-V arrancan sin cargar el SDK
# connect acotado para fallar rápido; read = límite sin recibir ningún dato del stream.
_HTTP_TIMEOUT = httpx.Timeout(connect=10.0, read=_TIMEOUT, write=30.0, pool=10.0)
client = OpenAI(
    base_url=_BASE_URL,
    api_key=_API_KEY,
    timeout=_HTTP_TIMEOUT,
    max_retries=1,  # el default (2) reintentaría timeouts y multiplicaría la espera
    # trust_env ignora proxies corruptos del sistema (típico en Debian).
    http_client=httpx.Client(trust_env=False, timeout=_HTTP_TIMEOUT),
)

SYSTEM_PROMPT = (
    "Eres un ingeniero de software experto. Tu tarea es escribir un mensaje de commit de Git "
    "altamente profesional basado en el 'git diff' proporcionado.\n\n"
    "Debes usar estrictamente el formato de 'Conventional Commits' (ej. feat(scope): desc, fix(scope): desc, docs(scope): desc).\n"
    "El mensaje DEBE incluir:\n"
    "1. Una primera línea concisa (máximo 250 caracteres) en minúsculas.\n"
    "2. Una línea en blanco.\n"
    "3. Un cuerpo detallado con viñetas (-) que explique el PORQUÉ del cambio y los impactos técnicos clave a detalle.\n\n"
    f"Escribe todo el mensaje en {_LANG_NAME}. Responde ÚNICAMENTE con el mensaje del commit, sin bloques de código de markdown (```), sin introducciones ni saludos."
)

def generar_commit(diff_text: str) -> str:
    """Llama a la API y devuelve el mensaje del commit (streaming por stdout)."""
    print(f"{_GREEN_COLOR}--- MENSAJE PROPUESTO ---{_RESET_COLOR}")
    _inicio = time.monotonic()
    completion = client.chat.completions.create(
        model=_MODEL,
        messages=[
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": f"Aquí está el git diff:\n{diff_text}"}
        ],
        temperature=0.2,
        top_p=1,
        max_tokens=2048,
        seed=42,
        stream=True
    )

    commit_message = ""
    for chunk in completion:
        if time.monotonic() - _inicio > _TIMEOUT:
            raise TimeoutError(
                f"Se superó el límite de {_TIMEOUT:.0f} s generando el mensaje con {_MODEL}.\n"
                "   Opciones: export GIT_AI_TIMEOUT=120 (dar más tiempo) o elegir un modelo más rápido con 'git ai -c'."
            )
        if not getattr(chunk, "choices", None): continue
        if len(chunk.choices) == 0 or getattr(chunk.choices[0], "delta", None) is None: continue
        delta = chunk.choices[0].delta
        if getattr(delta, "content", None) is not None:
            content = delta.content
            print(content, end="", flush=True)
            commit_message += content

    print(f"\n{_GREEN_COLOR}------------------------{_RESET_COLOR}\n")
    return commit_message

def editar_commit(mensaje: str) -> str:
    """Abre $EDITOR (o nano/vim) para que el usuario edite el mensaje."""
    editor = os.getenv("EDITOR") or os.getenv("VISUAL") or "nano"
    # Sufijo .txt para que los editores lo traten como texto plano.
    with tempfile.NamedTemporaryFile(
        mode="w", suffix=".txt", delete=False, encoding="utf-8"
    ) as tmp:
        tmp.write(mensaje)
        tmp_path = tmp.name

    try:
        subprocess.run([editor, tmp_path], check=True)
        with open(tmp_path, "r", encoding="utf-8") as f:
            nuevo = f.read().strip()
        return nuevo if nuevo else mensaje
    finally:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass

try:
    print(f"🤖 Analizando cambios con {_MODEL}...\n")
    commit_message = generar_commit(diff_text)

    if _AUTO_YES:
        # Modo --yes: confirmar automáticamente sin preguntar.
        commit_exec = subprocess.run(
            ["git", "commit", "-m", commit_message],
            capture_output=True, text=True, check=True
        )
        print(f"{_GREEN_COLOR}✔ Successfully committed! (--yes){_RESET_COLOR}")
        print(commit_exec.stdout)
    else:
        while True:
            confirm = input(
                "¿Quieres usar este mensaje? (s=confirmar / n=cancelar / e=editar / r=regenerar): "
            ).strip().lower()

            if confirm == 's':
                commit_exec = subprocess.run(
                    ["git", "commit", "-m", commit_message],
                    capture_output=True, text=True, check=True
                )
                print(f"\n{_GREEN_COLOR}✔ Successfully committed!{_RESET_COLOR}")
                print(commit_exec.stdout)
                break
            elif confirm == 'e':
                commit_message = editar_commit(commit_message)
                print(f"\n{_GREEN_COLOR}--- MENSAJE EDITADO ---{_RESET_COLOR}")
                print(commit_message)
                print(f"{_GREEN_COLOR}------------------------{_RESET_COLOR}\n")
                # Tras editar, volvemos a preguntar (loop).
            elif confirm == 'r':
                print("\n♻️  Regenerando mensaje...\n")
                commit_message = generar_commit(diff_text)
            else:
                print("\n❌ Commit cancelado.")
                break
except TimeoutError as e:
    print(f"\n⏱️ {e}")
except Exception as e:
    texto = str(e).lower()
    if "timeout" in texto or "timed out" in texto:
        print(f"\n⏱️ La API tardó demasiado (más de {_TIMEOUT:.0f} s sin respuesta completa).")
        print("   Sube el límite: export GIT_AI_TIMEOUT=120  |  o modelo más rápido: git ai -c")
    elif "not found for account" in texto:
        _guardar_blacklist(_cargar_blacklist() | {_MODEL})
        print(f"\n❌ El modelo {_MODEL} no está disponible para tu cuenta (404).")
        print("   Añadido a la lista negra; elige otro verificado: git ai -c")
    else:
        print(f"\n❌ Error de comunicación con la API: {e}")
except KeyboardInterrupt:
    print("\n\n❌ Operación cancelada por el usuario.")

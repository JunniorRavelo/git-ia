#!/usr/bin/env python3
import os
import sys
import subprocess
import tempfile
from pathlib import Path
import httpx
from openai import OpenAI

__version__ = "1.4.0"

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

# Modelos gratuitos disponibles en NVIDIA build API (verificados 2026-09-27).
# Solo se listan modelos de chat completions (la interfaz que usa este script);
# endpoints de otro tipo (ej. kumo-relational para datos estructurados) no aplican.
_AVAILABLE_MODELS = [
    {
        "id": "deepseek-ai/deepseek-v4.1-flash",
        "name": "DeepSeek V4.1 Flash",
        "desc": "Multimodal (texto+imagen). Sucesor del v4-flash; el ejemplo oficial admite hasta 262144 max_tokens.",
        "url": "https://build.nvidia.com/deepseek-ai/deepseek-v4.1-flash",
    },
    {
        "id": "z-ai/glm-5.3",
        "name": "GLM 5.3",
        "desc": "Modelo de chat de Z.ai, sucesor de GLM-5.2 (EOL 2026-08-21).",
        "url": "https://build.nvidia.com/z-ai/glm-5.3",
    },
    {
        "id": "z-ai/glm-5.3-flash",
        "name": "GLM 5.3 Flash",
        "desc": "Variante flash (ligera y rápida) de GLM-5.3.",
        "url": "https://build.nvidia.com/z-ai/glm-5.3-flash",
    },
    {
        "id": "moonshotai/kimi-k3",
        "name": "Kimi K3",
        "desc": "Multimodal (texto+imagen) de Moonshot AI con reasoning configurable (reasoning_effort).",
        "url": "https://build.nvidia.com/moonshotai/kimi-k3",
    },
    {
        "id": "nvidia/nemotron-3.5-lightning-30b-a3b",
        "name": "Nemotron 3.5 Lightning 30B A3B",
        "desc": "30B MoE (3B activos) de NVIDIA con modo thinking activable (enable_thinking, reasoning_budget).",
        "url": "https://build.nvidia.com/nvidia/nemotron-3.5-lightning-30b-a3b",
    },
    {
        "id": "meta/muse-glimmer-30b",
        "name": "Muse Glimmer 30B",
        "desc": "29.6B multimodal (texto+imagen) con reasoning y tool-calling. 131K contexto.",
        "url": "https://build.nvidia.com/meta/muse-glimmer-30b",
    },
]

# Configuración desde variables de entorno (con defaults)
_BASE_URL = os.getenv("NVIDIA_BASE_URL", "https://integrate.api.nvidia.com/v1")
_MODEL = os.getenv("COMMIT_IA_MODEL", "deepseek-ai/deepseek-v4.1-flash")
_LANG = os.getenv("COMMIT_IA_LANG", "es")

def cmd_configure():
    """Muestra los modelos gratuitos disponibles y permite elegir/guardar el activo."""
    print(f"git-ai v{__version__} — Configuración de modelo\n")
    print("Modelos gratuitos disponibles en NVIDIA build API:\n")
    for i, m in enumerate(_AVAILABLE_MODELS, 1):
        marker = "  (actual)" if m["id"] == _MODEL else ""
        print(f"  {i}. {m['name']}{marker}")
        print(f"     id:   {m['id']}")
        print(f"     {m['desc']}")
        print(f"     {m['url']}\n")
    while True:
        sel = input("Selecciona un modelo por número (o 'q' para salir sin guardar): ").strip().lower()
        if sel in ("q", "quit", "exit", ""):
            print("No se guardaron cambios.")
            sys.exit(0)
        try:
            chosen = _AVAILABLE_MODELS[int(sel) - 1]
        except (ValueError, IndexError):
            print("❌ Selección inválida. Intenta de nuevo.")
            continue
        break
    _CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    _CONFIG_FILE.write_text(f'COMMIT_IA_MODEL="{chosen["id"]}"\n', encoding="utf-8")
    print(f"\n✔ Modelo guardado en {_CONFIG_FILE}")
    print(f'  COMMIT_IA_MODEL="{chosen["id"]}"')
    print("\nPara usarlo manualmente (ej. en ~/.bashrc), añade:")
    print(f'  export COMMIT_IA_MODEL="{chosen["id"]}"')
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
    print("  -c, configure  Lista los modelos gratuitos disponibles en NVIDIA build API y")
    print("                 elige el activo (se guarda en ~/.config/git-ai/config.env).")
    print("  -h, --help     Muestra esta ayuda.")
    print("  -V, --version  Muestra la versión instalada.\n")
    print("Variables de entorno:")
    print("  NVIDIA_API_KEY   (obligatoria) Tu API key de NVIDIA (https://build.nvidia.com).")
    print("  COMMIT_IA_MODEL  Modelo a usar (por defecto: deepseek-ai/deepseek-v4.1-flash).")
    print("  COMMIT_IA_LANG   Idioma del mensaje del commit, código ISO 639-1 (por defecto: es).\n")
    print("Tras generar el mensaje: s=confirmar / n=cancelar / e=editar / r=regenerar.")
    sys.exit(0)

# 0. Manejo de argumentos: -h/--help ; --version/-V ; -c/configure ; -y/--yes
#    Se recorre argv completo para que las banderas puedan ir en cualquier orden.
_AUTO_YES = False
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

_USE_COLOR = sys.stdout.isatty() and os.getenv("NO_COLOR") is None
_GREEN_COLOR = "\033[92m" if _USE_COLOR else ""
_RESET_COLOR = "\033[0m" if _USE_COLOR else ""

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
client = OpenAI(
    base_url=_BASE_URL,
    api_key=_API_KEY,
    http_client=httpx.Client(trust_env=False)  # 🔥 Esto ignora proxies mal configurados en Debian
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
except Exception as e:
    print(f"\n❌ Error de comunicación con la API: {e}")
except KeyboardInterrupt:
    print("\n\n❌ Operación cancelada por el usuario.")

# git-ai

![versión](https://img.shields.io/badge/versión-v1.7.0-blue)
![licencia](https://img.shields.io/badge/licencia-MIT-green)
![python](https://img.shields.io/badge/python-3.8+-yellow)

Extensión de Git CLI que genera mensajes de commit automáticamente usando IA
(a través de la API de NVIDIA build). Analiza tu `git diff --cached` y propone
un mensaje siguiendo la convención **Conventional Commits** en español, con
streaming en tiempo real. Si lo aceptas, hace el commit por ti.

## ¿Cómo funciona?

1. Haces `git add` de los archivos que quieres commitear (como siempre).
2. Ejecutas `git ai` (o `git-ai`).
3. La IA lee el diff en stage y redacta un mensaje profesional.
4. Eliges qué hacer: confirmar (`s`), cancelar (`n`), editar (`e`) o regenerar (`r`).

## Requisitos

- Python 3.8+
- `git`
- Una API key de NVIDIA (la obtienes en https://build.nvidia.com)
- La librería `openai` de Python

## Instalación

### 1. Instalar la librería de Python

```bash
# Debian/Ubuntu (si pip está bloqueado por PEP 668)
pip3 install openai --break-system-packages

# O en un entorno virtual (recomendado)
python3 -m venv .venv
source .venv/bin/activate
pip install openai
```

### 2. Configurar tu API key

El script requiere que proporciones tu propia API key mediante una variable de
entorno (no se embebe ninguna key en el código):

```bash
export NVIDIA_API_KEY="tu-api-key-aqui"
```

Añádelo a tu `~/.bashrc` o `~/.zshrc` para que persista entre sesiones:

```bash
echo 'export NVIDIA_API_KEY="tu-api-key-aqui"' >> ~/.bashrc
source ~/.bashrc
```

### 3. Instalar el comando como subcomando de Git

Git reconoce como subcomandos cualquier ejecutable en el `PATH` cuyo nombre
empiece por `git-`. Copia (o enlaza) el script con el nombre `git-ai`:

```bash
chmod +x git-ai.sh
sudo ln -s "$(pwd)/git-ai.sh" /usr/local/bin/git-ai
```

Ahora puedes usarlo desde cualquier repositorio:

```bash
git ai
```

> Alternativa sin permisos de root: añade el directorio del script a tu `PATH`
> o crea un enlace dentro de `~/.local/bin`:
>
> ```bash
> mkdir -p ~/.local/bin
> ln -s "$(pwd)/git-ai.sh" ~/.local/bin/git-ai
> # asegúrate de tener ~/.local/bin en el PATH
> ```

## Variables de entorno

| Variable           | Descripción                                  | Por defecto                                |
|--------------------|----------------------------------------------|--------------------------------------------|
| `NVIDIA_API_KEY`   | **Obligatoria.** API key de NVIDIA.          | —                                          |
| `NVIDIA_BASE_URL`  | URL base de la API.                          | `https://integrate.api.nvidia.com/v1`      |
| `COMMIT_IA_MODEL`  | Modelo a usar para generar el commit.        | `deepseek-ai/deepseek-v4.1-flash`          |
| `COMMIT_IA_LANG`   | Idioma del mensaje de commit (código ISO 639-1). | `es`                                   |
| `GIT_AI_TIMEOUT`   | Límite de tiempo (segundos) para generar el mensaje; al agotarse se cancela con sugerencias. | `60`                                   |
| `NO_COLOR`         | Si está definida, desactiva los colores.     | —                                          |
| `GIT_AI_CONFIG_DIR`| Directorio del archivo de config persistente. | `~/.config/git-ai`                         |

> Orden de prioridad para `COMMIT_IA_MODEL`: variable de entorno (manual) > archivo de
> config (`~/.config/git-ai/config.env`, escrito por `git ai -c`) > valor por defecto.

### Idiomas soportados

El mensaje del commit se puede generar en distintos idiomas mediante `COMMIT_IA_LANG`.
La interfaz del script (mensajes y prompts) siempre está en español; solo cambia el
idioma del mensaje de commit generado por la IA.

| Código | Idioma     | Código | Idioma     |
|--------|------------|--------|------------|
| `es`   | Español    | `ja`   | 日本語     |
| `en`   | English    | `zh`   | 中文       |
| `fr`   | Français   | `ru`   | Русский    |
| `de`   | Deutsch    | `ko`   | 한국어     |
| `pt`   | Português  | `ar`   | العربية    |
| `it`   | Italiano   | `nl`   | Nederlands |
| `pl`   | Polski     | `tr`   | Türkçe     |
| `hi`   | हिन्दी     |        |            |

También acepta cualquier otro código ISO 639-1 no listado (la IA lo interpretará).

```bash
# Commit en inglés
export COMMIT_IA_LANG=en
git ai

# Commit en francés (solo para esta ejecución)
COMMIT_IA_LANG=fr git ai
```

## Configuración de modelo (`git ai -c`)

Para ver los modelos gratuitos disponibles en NVIDIA build API y elegir cuál usar:

```bash
git ai -c
# o equivalentemente:
git ai configure
```

Consulta **en vivo** el catálogo de modelos del API de NVIDIA
(`GET https://integrate.api.nvidia.com/v1/models`), así que la lista siempre
refleja el estado actual del catálogo (altas y bajas incluidas). La consulta
al catálogo es pública: **no requiere API key** (generar commits sí).

- Lista **solo los modelos que sirven para chat de texto**, la interfaz que usa
  git-ai. Como el endpoint no informa capacidades, el filtro es por nombre y
  excluye automáticamente lo que no aplica: embeddings, rerankers, visión/VLM,
  safety/guard, reward, calibration, OCR/parsing, traducción (riva) y
  detectores.
- Los modelos *coding* (deepseek-coder, codestral, granite-code, codellama...)
  **sí funcionan** para generar commits: son LLM de texto especializados en
  código. Las variantes *instruct*/*chat* siguen bien las instrucciones; los
  modelos *base* (starcoder2, gemma-2b, mixtral-8x22b-v0.1) pueden dar
  resultados peores porque no están afinados a instrucciones.
- Al seleccionar uno por número (o escribiendo su id), la elección se **guarda
  automáticamente** en `~/.config/git-ai/config.env` y se usa en adelante.
  Además se imprime el comando `export COMMIT_IA_MODEL=...` por si quieres
  replicarlo a mano en tu `~/.bashrc`.
- Si el filtro excluyera algún modelo que quieras usar, fórzalo a mano con
  `export COMMIT_IA_MODEL="id-del-modelo"` (la variable de entorno tiene
  prioridad sobre el archivo de config).

## Uso

```bash
git add <archivos>
git ai
```

Para ver la ayuda con todos los comandos y opciones disponibles en español:

```bash
git ai -h
# o equivalentemente:
git ai --help
```

Para aceptar automáticamente el mensaje propuesto sin confirmación interactiva
(útil en scripts o cuando confías en la propuesta de la IA):

```bash
git ai -y
# o equivalentemente:
git ai --yes
```

Ejemplo de salida:

```
🤖 Analizando cambios con deepseek-ai/deepseek-v4.1-flash...

--- MENSAJE PROPUESTO ---
feat(auth): agregar validación de token jwt

- Se añade middleware para verificar la firma del token en cada petición.
- Se rechazan las solicitudes con token expirado devolviendo 401.
- Se documenta el flujo de autenticación en el README.

------------------------

¿Quieres usar este mensaje? (s=confirmar / n=cancelar / e=editar / r=regenerar): s
✔ Successfully committed!
```

Con `-y` el commit se realiza directamente tras generar el mensaje, sin mostrar
el prompt de confirmación.

## Opciones del menú

Tras generar el mensaje, el script te pregunta qué hacer. Puedes combinar
las opciones libremente hasta confirmar o cancelar:

| Opción | Acción                                                                                          |
|--------|-------------------------------------------------------------------------------------------------|
| `s`    | **Confirmar.** Hace el commit con el mensaje actual.                                            |
| `n`    | **Cancelar.** Aborta sin commitear.                                                             |
| `e`    | **Editar.** Abre tu editor (`$EDITOR`, `$VISUAL` o `nano` por defecto) con el mensaje propuesto para que lo modifiques a mano. Al guardar, se muestra el resultado y se vuelve a preguntar. |
| `r`    | **Regenerar.** Vuelve a llamar a la IA para obtener un nuevo mensaje a partir del mismo diff.    |

### Editar el mensaje

La opción `e` vuelca el mensaje en un archivo temporal y abre el editor que
tengas configurado. Si no defines ninguno, se usa `nano`:

```bash
# Usa vim para editar el mensaje propuesto
export EDITOR=vim

# O nano (por defecto)
export EDITOR=nano
```

Si al guardar dejas el archivo vacío, se conserva el mensaje anterior en
lugar de hacer un commit vacío.

### Regenerar el mensaje

La opción `r` reutiliza el mismo `git diff --cached` y vuelve a consultar a
la IA. Útil si la primera propuesta no te convence y quieres otra redacción
sin tener que cancelar y volver a ejecutar `git ai`.

## Seguridad

- La API key se carga desde la variable de entorno `NVIDIA_API_KEY`.
  **No la hardcodees** en el script ni la commitees.
- Si publicas este proyecto, asegúrate de no incluir tu `.env` ni tu
  `~/.bashrc` con la key real.

## Versión

Para consultar la versión instalada:

```bash
git ai --version
# o equivalentemente:
git ai -V
git ai version
```

Salida esperada:

```
git-ai v1.7.0
```

## Changelog

### v1.7.0

- **feat**: límite de tiempo para generar el mensaje, configurable con `GIT_AI_TIMEOUT` (segundos, por defecto `60`). Al agotarse, la generación se cancela y se sugiere subir el límite o elegir un modelo más rápido (`git ai -c`).
- **fix**: timeouts acotados en el cliente HTTP (conexión: 10 s; lectura: `GIT_AI_TIMEOUT` sin recibir ningún dato) y reintentos reducidos a 1, para no quedarse colgado indefinidamente si la API se cuelga.

### v1.6.0

- **feat**: en `git ai -c`, el modelo seleccionado (actual) se muestra en verde.
- **perf**: import diferido de la librería `openai`: `-c`, `-h` y `-V` arrancan en ~0,15 s sin cargar el SDK (antes ~0,5 s).
- **feat**: `git ai -c` muestra la latencia de la consulta del catálogo (ej. `✔ Catálogo recibido en 0.8 s`). El endpoint no publica la latencia de generación de cada modelo; como referencia general, las variantes *flash*/*nano* son las más rápidas para generar.

### v1.5.0

- **feat**: `git ai -c` ahora consulta **en vivo** el catálogo de modelos del API de NVIDIA (`GET /v1/models`) en lugar de una lista fija en el código; se elimina la constante `_AVAILABLE_MODELS`.
- **feat**: filtro automático por nombre para listar solo modelos de chat de texto: se excluyen embeddings, rerankers, visión/VLM, safety/guard, reward, calibration, OCR/parsing, traducción (riva) y detectores.
- **feat**: la consulta del catálogo no requiere `NVIDIA_API_KEY` (el endpoint `/v1/models` es público); si la variable está definida se manda igualmente.
- **feat**: en el menú se puede seleccionar el modelo por número o escribiendo su id exacto.

### v1.4.0

- **breaking**: actualización del catálogo de modelos de NVIDIA build API (verificados 2026-09-27). Se eliminan `deepseek-ai/deepseek-v4-flash-0731`, `poolside/laguna-xs-2.1` y `minimaxai/minimax-m3`; el default pasa a `deepseek-ai/deepseek-v4.1-flash`.
- **feat**: nuevos modelos disponibles vía `git ai -c`: `deepseek-ai/deepseek-v4.1-flash`, `z-ai/glm-5.3`, `z-ai/glm-5.3-flash`, `moonshotai/kimi-k3` y `nvidia/nemotron-3.5-lightning-30b-a3b`. `meta/muse-glimmer-30b` se mantiene.
- **chore**: solo se listan modelos de chat completions (la interfaz que usa git-ai); endpoints de otro tipo (ej. `kumo-relational` para predicción sobre datos estructurados) quedan fuera del listado.

### v1.3.0

- **feat**: bandera `git ai -h` / `git ai --help` para mostrar la ayuda con todos los comandos, opciones y variables de entorno disponibles, en español.

### v1.2.0

- **feat**: bandera `git ai -y` / `git ai --yes` para aceptar automáticamente el mensaje propuesto y hacer el commit sin prompt de confirmación.
- **refactor**: el parseo de argumentos ahora recorre `argv` completo, por lo que las banderas pueden ir en cualquier orden (ej. `git ai -y`, `git ai --yes`).

### v1.1.0

- **feat**: bandera `git ai -c` / `git ai configure` para listar los modelos gratuitos disponibles en NVIDIA build API y elegir el activo.
- **feat**: persistencia de la configuración en `~/.config/git-ai/config.env` (cargado automáticamente al iniciar; la variable de entorno manual tiene prioridad).
- **breaking**: el modelo por defecto pasa de `z-ai/glm-5.2` (EOL 2026-08-21) a `deepseek-ai/deepseek-v4-flash-0731`.
- **docs**: documentación de los modelos disponibles y del orden de prioridad de `COMMIT_IA_MODEL`.

### v1.0.0

- **feat**: bandera `--version` / `-V` / `version` para consultar la versión del script.
- **feat**: soporte multi-idioma para el mensaje de commit vía `COMMIT_IA_LANG` (códigos ISO 639-1).
- **feat**: opciones para **editar** (`e`) y **regenerar** (`r`) el mensaje propuesto antes de confirmar.
- **feat**: streaming en tiempo real de la respuesta del modelo.
- **feat**: ampliación del límite de caracteres (250) y tokens (2048) para mensajes de commit más ricos.
- **security**: la API key de NVIDIA se exige vía `NVIDIA_API_KEY`; se elimina cualquier token embebido del código.
- **fix**: se ignoran proxies del sistema mal configurados (útil en Debian/Ubuntu) usando `httpx` con `trust_env=False`.
- **chore**: `.devin/` se ignora y se elimina del historial del repositorio.

### v0.1.0

- Versión inicial: genera un mensaje de commit en formato Conventional Commits a partir de `git diff --cached` usando GLM-5.2 (API de NVIDIA) y lo confirma tras aprobación del usuario.

## Licencia

MIT © 2026 J. Santiago Ravelo

# git-ai

![versión](https://img.shields.io/badge/versión-v2.2.0-blue)
![licencia](https://img.shields.io/badge/licencia-MIT-green)
![python](https://img.shields.io/badge/python-3.8+-yellow)

Extensión de Git CLI que genera mensajes de commit automáticamente usando IA
(a través de la API de NVIDIA build). Analiza tu `git diff --cached` y propone
un mensaje siguiendo la convención **Conventional Commits** en español, con
streaming en tiempo real. Si lo aceptas, hace el commit por ti.

## Características

- Streaming en tiempo real del mensaje mientras se genera.
- **Fallback automático**: si el modelo falla (404, timeout, red), salta al
  siguiente verificado y guarda el que funciona como activo.
- **Detector de secretos** en el diff (claves `nvapi-`/`sk-`, AWS, GitHub,
  Slack, claves privadas) antes de enviarlo a la nube.
- **Catálogo de modelos en vivo** con verificación real y lista negra de
  caídos que nunca se re-testean.
- Única dependencia: `httpx` (sin SDK de OpenAI). Instalador incluido.

## ¿Cómo funciona?

1. Haces `git add` de los archivos que quieres commitear (como siempre).
2. Ejecutas `git ai` (o `git-ai`).
3. Se escanea el diff en busca de secretos antes de enviarlo a la nube.
4. La IA lee el diff en stage y redacta un mensaje profesional; si el modelo
   falla o cuelga, git ai salta automáticamente al siguiente verificado.
5. Eliges qué hacer: confirmar (`s`), cancelar (`n`), editar (`e`) o regenerar (`r`).

## Requisitos

- Python 3.8+
- `git`
- Una API key de NVIDIA (la obtienes en https://build.nvidia.com)
- La librería `httpx` de Python (única dependencia; desde v2.0 ya no se usa `openai`)

## Instalación

### 1. Instalar todo con el instalador (recomendado)

```bash
bash install.sh
```

Verifica Python 3.8+, instala `httpx` si falta, crea el enlace `git-ai` en
`~/.local/bin` (o en el directorio que marques con `GIT_AI_INSTALL_DIR`) y
comprueba que esté en tu `PATH`.

### 2. Instalación manual

```bash
# Única dependencia (Debian/Ubuntu con PEP 668 puede necesitar --break-system-packages)
pip3 install httpx --break-system-packages

chmod +x git-ai.sh
mkdir -p ~/.local/bin
ln -sfn "$(pwd)/git-ai.sh" ~/.local/bin/git-ai
# ¿Prefieres instalación en todo el sistema?
# sudo ln -sfn "$(pwd)/git-ai.sh" /usr/local/bin/git-ai
```

### 3. Configurar tu API key

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

## Variables de entorno

| Variable           | Descripción                                  | Por defecto                                |
|--------------------|----------------------------------------------|--------------------------------------------|
| `NVIDIA_API_KEY`   | **Obligatoria.** API key de NVIDIA.          | —                                          |
| `NVIDIA_BASE_URL`  | URL base de la API.                          | `https://integrate.api.nvidia.com/v1`      |
| `COMMIT_IA_MODEL`  | Modelo a usar para generar el commit.        | `deepseek-ai/deepseek-v4.1-flash`          |
| `COMMIT_IA_LANG`   | Idioma del mensaje de commit (código ISO 639-1). | `es`                                   |
| `GIT_AI_TIMEOUT`   | Máx. segundos de inactividad; si la IA sigue respondiendo, se espera a que termine. | `60`                                   |
| `NO_COLOR`         | Si está definida, desactiva los colores.     | —                                          |
| `GIT_AI_CONFIG_DIR`| Directorio del archivo de config persistente. | `~/.config/git-ai`                         |
| `GIT_AI_INSTALL_DIR` | Directorio donde `install.sh` crea el enlace `git-ai`. | `~/.local/bin`                  |

> Orden de prioridad para `COMMIT_IA_MODEL`: variable de entorno (manual) > archivo de
> config (`~/.config/git-ai/config.env`, escrito por `git ai -c`) > valor por defecto.

### Archivos locales (`~/.config/git-ai/`)

| Archivo           | Uso                                                          |
|--------------------|--------------------------------------------------------------|
| `config.env`       | Modelo activo (lo escribe `git ai -c` o el fallback).        |
| `models-cache.json`| Caché de modelos verificados (dura 7 días).                  |
| `blacklist.json`   | Modelos caídos: no se re-testean. Bórralo para re-testear.   |

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
(`GET https://integrate.api.nvidia.com/v1/models`) y, si tienes
`NVIDIA_API_KEY` exportada, **prueba cada modelo con una petición mínima**
para listar solo los que de verdad responden: el catálogo lista de más y
varios modelos devuelven `404 "Not found for account"` al invocarlos
(p. ej. `meta/llama2-70b`, `nvidia/nemotron-4-340b-instruct`,
`deepseek-ai/deepseek-coder-6.7b-instruct`).

- **Verificación con lista negra**: al verificar solo se prueban los modelos
  que no están en la lista negra (`~/.config/git-ai/blacklist.json`); los
  caídos (404 o cuelgues) se añaden ahí y **ya no se vuelven a testear**. Los
  modelos nuevos que aparezcan en el catálogo se prueban automáticamente al
  aparecer. El resultado vigente se cachea en
  `~/.config/git-ai/models-cache.json` (dura 7 días) para que `git ai -c` sea
  instantáneo; `git ai -c --refresh` fuerza re-verificar (solo vivos y
  nuevos). Para re-testear todo, borra `blacklist.json`.
- **Auto-blacklist**: si al generar un commit el modelo configurado responde
  404 (no disponible para tu cuenta), se añade solo a la lista negra y se te
  pide elegir otro.
- Sin `NVIDIA_API_KEY` la lista se muestra **sin verificar** (solo filtro por
  nombre): puede incluir modelos caídos que darán 404 al generar.
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

### Fallback automático de modelo

Si el modelo activo falla al generar (404, inactividad o error de red), `git ai`
prueba automáticamente el siguiente modelo verificado en la caché y continúa
sin intervención:

- El modelo que funciona queda guardado como nuevo activo (`config.env`).
- Los 404 van solos a la lista negra.
- Si al arrancar el modelo activo ya figura en la lista negra, se avisa antes
  de intentarlo (se intenta igualmente; el fallback te cubre si falla).

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

### Diff demasiado grande (límite de tokens)

Si el diff no cabe en el contexto del modelo (el API responde
`maximum context length is N tokens`), `git ai` **deja de probar modelos a
ciegas** y va directo a la lista de exclusión: los archivos se envían
**enteros o no se envían** — nunca se parte ni se trunca un archivo, porque
el mensaje pierde precisión. Se excluyen archivos del *análisis* hasta que
el diff quepa:

```
🚫 ¡Te pasaste de tokens! El diff no cabe en el contexto del modelo.
   Envío: ~4,146,683 tokens
   Límite de nvidia/nemotron-3-super-120b-a12b: 1,000,000 tokens
   Exceso: ~3,146,683 tokens (4.1x el límite)

Archivos por peso estimado (mayor primero):
    1. server.js                       ~4,100,000 tokens  99.0 %  ⚠️ solo ya no cabe
    2. lib/api.js                        ~28,500 tokens   0.7 %
    3. lib/db.js                         ~18,200 tokens   0.4 %

Archivos a EXCLUIR del análisis ('1', '1 3', '2-5', m=otro modelo / q=cancelar):
```

- Eliges por número, rango (`2-5`) o varios a la vez (`1 3 5`); la selección
  es **acumulativa**: si tras excluir aún sobran tokens, se re-lista lo
  restante con cuánto falta hasta que quepa.
- El commit resultante **sigue incluyendo todo lo que está en stage**: solo
  cambia lo que la IA ve. Para quitar archivos del commit usa
  `git restore --staged <archivo>` o commitea por partes.
- El aviso `⚠️ solo ya no cabe` marca los archivos que ni solos cabrían en
  el contexto: esos hay que commitearlos aparte con mensaje manual (o
  probar `m` para saltar a un modelo con más contexto).
- El límite de contexto de cada modelo se **aprende y cachea** en
  `~/.config/git-ai/context-limits.json`: si vuelves a intentarlo con un
  diff que ya se sabe que no cabe, el aviso sale **antes de enviar nada**
  (estimación local, sin gastar la llamada ni subir el diff).
- En modo `git ai -y` no hay pregunta: se aborta con las soluciones
  sugeridas (`git restore --staged`, commitear por partes o cambiar de
  modelo) y código de salida 1.

## Seguridad

- La API key se carga desde la variable de entorno `NVIDIA_API_KEY`.
  **No la hardcodees** en el script ni la commitees.
- **Detector de secretos**: antes de enviar el diff a la IA se escanea en busca
  de claves `nvapi-`/`sk-`, AWS `AKIA...`, tokens de GitHub/Slack y claves
  privadas. Si detecta algo, avisa (sin imprimir el secreto) y pide
  confirmación; en modo `git ai -y` aborta directamente.
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
git-ai v2.2.0
```

## Changelog

### v2.2.0

- **feat**: **aviso y solución al superar el límite de tokens**: cuando el diff no cabe en el contexto del modelo (HTTP 400 `maximum context length`), en vez de saltar de modelo en modelo condenados a fallar, se muestra el exceso con números (envío, límite, múltiplo) y se va directo a la **lista de exclusión de archivos enteros** (por peso, por número/rango/múltiples, acumulativa hasta que quepa). Los archivos se envían completos o se excluyen — nunca se parten ni truncan, para no perder precisión. El commit sigue incluyendo todo el stage; también se puede saltar a otro modelo (`m`) o cancelar.
- **feat**: los límites de contexto se aprenden de los errores 400 y se guardan en `~/.config/git-ai/context-limits.json`; si el diff ya se sabe que no cabe, el aviso sale por **estimación local antes de enviar** (sin subir el diff ni gastar la llamada). Los archivos que ni solos caben se marcan con `⚠️ solo ya no cabe`.
- **fix**: un modelo que responde con un **mensaje vacío** ya se trata como fallo (el fallback prueba el siguiente) en lugar de romper con `git commit -m ''`.
- **fix**: si `git commit` falla (hooks, identidad, etc.) se muestra su stderr real en lugar de `Error inesperado: Command ... non-zero exit status`.

### v2.1.0

- **feat**: `GIT_AI_TIMEOUT` ahora mide **inactividad**, no tiempo total: mientras el modelo siga emitiendo datos (aunque sea lento o esté razonando), se le espera a que termine sin cortarlo. Solo se corta (y aplica el fallback) si pasa ese tiempo sin recibir nada del modelo; los keep-alives del servidor no cuentan como actividad.

### v2.0.1

- **fix**: los fallos sin código HTTP (timeout, red) ya no muestran el prefijo confuso "HTTP 0"; ahora solo el motivo (ej. `timeout: más de 60 s generando el mensaje`).

### v2.0.0

- **feat**: **fallback automático de modelo**: si el activo falla al generar (404, timeout o error de red), `git ai` prueba el siguiente modelo verificado en caché y continúa solo; el que funciona se guarda como nuevo activo.
- **feat**: aviso al arrancar si el modelo activo está en la lista negra (falló antes).
- **feat**: **detector de secretos** en el diff (`nvapi-`, `sk-`, AWS `AKIA`, tokens de GitHub/Slack, claves privadas): avisa antes de enviar a la nube y aborta en modo `--yes`.
- **refactor**: se elimina la dependencia de la librería `openai`; el chat se consume directo por `httpx` (SSE). Única dependencia: `httpx`, y el arranque de `git ai` es tan rápido como el de `-c`.
- **feat**: instalador `install.sh`: dependencias, enlace `git-ai` y verificación en un solo comando.
- **fix**: los fallos terminan con código de salida distinto de cero (1; 130 al cancelar con Ctrl+C), para que los scripts que usen `git ai -y` detecten el error.

### v1.9.0

- **feat**: lista negra persistente (`~/.config/git-ai/blacklist.json`): los modelos caídos (404/cuelgues) se guardan y **ya no se vuelven a testear**; en cada verificación solo se prueban los vivos y los modelos nuevos que aparezcan en el catálogo. Objetivo: automatizar y ahorrar el máximo tiempo.
- **feat**: auto-blacklist al generar: si el modelo configurado responde 404 al crear un commit, se añade solo a la lista negra.
- **fix**: el mensaje de verificación muestra cuántos candidatos se omiten por estar en lista negra.

### v1.8.0

- **feat**: `git ai -c` ahora **verifica de verdad** cada modelo con una petición mínima en paralelo y solo lista los que responden: el catálogo `/v1/models` lista de más y varios modelos devuelven `404 "Not found for account"` al generar (p. ej. `meta/llama2-70b`, `nvidia/nemotron-4-340b-instruct`, `microsoft/phi-3.5-moe-instruct`).
- **feat**: caché local de la verificación en `~/.config/git-ai/models-cache.json` (dura 7 días) para que `-c` sea instantáneo; `git ai -c --refresh` fuerza re-probar.
- **fix**: al generar un commit, si el modelo responde 404 (no disponible para la cuenta) se muestra un mensaje claro que invita a elegir otro verificado, en lugar del error crudo.

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

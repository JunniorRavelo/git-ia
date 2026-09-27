#!/usr/bin/env bash
# Instalador de git-ai: verifica dependencias, crea el enlace y comprueba el PATH.
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEST_DIR="${GIT_AI_INSTALL_DIR:-$HOME/.local/bin}"

echo "== git-ai :: instalador =="

# 1) Python 3.8+
command -v python3 >/dev/null 2>&1 || { echo "❌ python3 no está instalado."; exit 1; }
python3 - <<'PY' || { echo "❌ git-ai requiere Python 3.8+."; exit 1; }
import sys
sys.exit(0 if sys.version_info >= (3, 8) else 1)
PY

# 2) httpx (única dependencia; desde v2.0 ya no se usa la librería openai)
if python3 -c "import httpx" >/dev/null 2>&1; then
    echo "✔ httpx ya está instalado."
else
    echo "→ Instalando httpx..."
    if ! python3 -m pip install --user httpx >/dev/null 2>&1; then
        # Debian/Ubuntu bloquean pip del sistema por PEP 668
        python3 -m pip install --break-system-packages httpx
    fi
fi

# 3) Enlace git-ai
mkdir -p "$DEST_DIR"
ln -sfn "$DIR/git-ai.sh" "$DEST_DIR/git-ai"
echo "✔ Enlace creado: $DEST_DIR/git-ai -> $DIR/git-ai.sh"

# 4) PATH
case ":$PATH:" in
    *":$DEST_DIR:"*) echo "✔ $DEST_DIR está en el PATH." ;;
    *)
        echo "⚠️  $DEST_DIR no está en tu PATH. Añade a tu ~/.bashrc:"
        echo "      export PATH=\"$DEST_DIR:\$PATH\""
        ;;
esac

# 5) Verificación final
"$DEST_DIR/git-ai" --version
echo "✔ Instalación completa. Configura NVIDIA_API_KEY (ver README) y usa: git ai"

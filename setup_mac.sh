#!/bin/bash
# ==============================================================================
#  Zahorí - macOS Quick Setup & Desktop Icon Installer
# ==============================================================================

set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

echo "======================================================================"
echo "  📖 Zahorí — Buscador de Libros & Goodreads (Madrid Libraries)"
echo "  Setting up application for macOS..."
echo "======================================================================"
echo ""

# 1. Verify Python 3
if ! command -v python3 &> /dev/null; then
    echo "❌ Error: python3 is not installed."
    echo "Please install Python 3 using Homebrew (brew install python) or from https://python.org."
    exit 1
fi

echo "✅ Python version: $(python3 --version)"

# 2. Install dependencies
echo "📦 Installing Python dependencies..."
python3 -m pip install -q --upgrade pip
python3 -m pip install -q -r requirements.txt
echo "✅ Dependencies installed."

# 3. Create Desktop App Icon
echo "🎨 Creating Zahorí App icon on Desktop..."
python3 create_desktop_icon.py

echo ""
echo "======================================================================"
echo "🎉 Setup Complete!"
echo ""
echo "You can now launch Zahorí in two easy ways:"
echo " 1. Double-click the 'Zahorí' icon on your Desktop."
echo " 2. Or run: python3 run.py (and open http://localhost:8000)"
echo "======================================================================"

#!/bin/bash
#
# CrateBot Build Script
# Builds the complete application for macOS distribution.
#
# Usage:
#   ./scripts/build.sh          # Build both Python and Electron
#   ./scripts/build.sh python   # Build only Python backend
#   ./scripts/build.sh electron # Build only Electron app
#

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo -e "${BLUE}CrateBot Build Script${NC}"
echo "Project root: $PROJECT_ROOT"
echo ""

# Ensure we're in the project root
cd "$PROJECT_ROOT"

# Function: Build Python backend with PyInstaller
build_python() {
    echo -e "${YELLOW}Building Python backend...${NC}"

    # Check if virtual environment exists
    if [ ! -d "python/venv" ]; then
        echo "Creating virtual environment..."
        python3 -m venv python/venv
    fi

    # Activate virtual environment
    source python/venv/bin/activate

    # Install dependencies
    echo "Installing Python dependencies..."
    pip install -q -r python/requirements.txt
    pip install -q pyinstaller

    # Run PyInstaller
    echo "Running PyInstaller..."
    pyinstaller --clean --noconfirm cratebot_server.spec

    # Move the built onedir bundle to resources
    mkdir -p desktop/resources/python
    rm -rf desktop/resources/python/cratebot-server
    cp -R dist/cratebot-server-dist desktop/resources/python/cratebot-server

    echo -e "${GREEN}Python backend built successfully!${NC}"
    echo "Executable: desktop/resources/python/cratebot-server/cratebot-server"

    deactivate
}

# Function: Build Electron app
build_electron() {
    echo -e "${YELLOW}Building Electron app...${NC}"

    cd desktop

    # Install dependencies
    echo "Installing Node dependencies..."
    npm install

    # Type check
    echo "Running type check..."
    npm run typecheck

    # Build
    echo "Building Electron app..."
    npm run electron:build

    cd ..

    echo -e "${GREEN}Electron app built successfully!${NC}"
    echo "Output: desktop/dist/"
}

# Main
case "${1:-all}" in
    python)
        build_python
        ;;
    electron)
        build_electron
        ;;
    all|*)
        build_python
        echo ""
        build_electron
        echo ""
        echo -e "${GREEN}Build complete!${NC}"
        echo "The packaged app is in: desktop/dist/"
        ;;
esac

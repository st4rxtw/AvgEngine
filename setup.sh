#!/usr/bin/env bash
# Usage: bash setup.sh [--build-type Debug|Release] [--skip-bass] [--skip-glad]
set -eo pipefail

BOLD=$'\033[1m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RED=$'\033[31m'; NC=$'\033[0m'
step() { echo "${BOLD}${GREEN}==>${NC}${BOLD} $*${NC}"; }
warn() { echo "${YELLOW}[warn]${NC} $*"; }
fail() { echo "${RED}[error]${NC} $*" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPS_DIR="$SCRIPT_DIR/deps"
BUILD_DIR="$SCRIPT_DIR/build"
BUILD_TYPE="Release"
SKIP_BASS=false
SKIP_GLAD=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --build-type) BUILD_TYPE="$2"; shift 2 ;;
        --skip-bass)  SKIP_BASS=true;  shift ;;
        --skip-glad)  SKIP_GLAD=true;  shift ;;
        *) fail "Unknown option: $1  (valid: --build-type, --skip-bass, --skip-glad)" ;;
    esac
done

step "Checking prerequisites..."

MISSING=()
for tool in git cmake curl unzip; do
    command -v "$tool" &>/dev/null || MISSING+=("$tool")
done
if [[ ${#MISSING[@]} -gt 0 ]]; then
    echo "[error] Missing tools: ${MISSING[*]}" >&2
    echo "  Arch/CachyOS:   sudo pacman -S ${MISSING[*]}" >&2
    echo "  Debian/Ubuntu:  sudo apt install ${MISSING[*]}" >&2
    exit 1
fi

CMAKE_VER=$(cmake --version | awk 'NR==1{print $3}')
CMAKE_MAJOR=$(echo "$CMAKE_VER" | cut -d. -f1)
CMAKE_MINOR=$(echo "$CMAKE_VER" | cut -d. -f2)
if [[ "$CMAKE_MAJOR" -lt 3 || ( "$CMAKE_MAJOR" -eq 3 && "$CMAKE_MINOR" -lt 20 ) ]]; then
    fail "CMake >= 3.20 required (found $CMAKE_VER)"
fi

PYTHON=""
for py in python3 python; do
    if command -v "$py" &>/dev/null; then
        if "$py" -c "import sys; sys.exit(0 if sys.version_info>=(3,6) else 1)" 2>/dev/null; then
            PYTHON="$py"; break
        fi
    fi
done

echo "  cmake  $CMAKE_VER"
echo "  git    $(git --version | awk '{print $3}')"
if [[ -n "$PYTHON" ]]; then
    echo "  $PYTHON  $($PYTHON --version 2>&1 | awk '{print $2}')"
else
    warn "Python 3 not found -- glad.h will need to be placed manually."
fi

step "Installing system packages..."

if command -v pacman &>/dev/null; then
    PKGS=(
        base-devel cmake git unzip
        glfw-wayland
        glm
        pugixml
        boost
        mesa
        libgl
    )
    echo "  Running: sudo pacman -S --needed ${PKGS[*]}"
    sudo pacman -S --needed --noconfirm "${PKGS[@]}"

elif command -v apt &>/dev/null; then
    PKGS=(
        build-essential cmake git unzip
        libglfw3-dev
        libglm-dev
        libpugixml-dev
        libboost-dev
        libgl-dev
    )
    echo "  Running: sudo apt install ${PKGS[*]}"
    sudo apt update -qq
    sudo apt install -y "${PKGS[@]}"
else
    warn "Unrecognised package manager. Install these libraries manually:"
    warn "  GLFW3, GLM, Dear ImGui (+GLFW & OpenGL3 backends), implot, pugixml, Boost"
fi

step "Cloning imgui and implot..."
mkdir -p "$DEPS_DIR"

IMGUI_DIR="$DEPS_DIR/ImGui"
IMPLOT_DIR="$DEPS_DIR/implot"

if [[ -d "$IMGUI_DIR/.git" ]]; then
    echo "  imgui already cloned, pulling latest..."
    git -C "$IMGUI_DIR" pull --ff-only -q
else
    echo "  Cloning imgui from github.com/ocornut/imgui..."
    git clone https://github.com/ocornut/imgui.git "$IMGUI_DIR" --depth=1 -q
fi

if [[ -d "$IMPLOT_DIR/.git" ]]; then
    echo "  implot already cloned, pulling latest..."
    git -C "$IMPLOT_DIR" pull --ff-only -q
else
    echo "  Cloning implot from github.com/epezent/implot..."
    git clone https://github.com/epezent/implot.git "$IMPLOT_DIR" --depth=1 -q
fi

echo "  imgui  -> $IMGUI_DIR"
echo "  implot -> $IMPLOT_DIR"

step "Creating case-alias symlink for GLM in AvgEngine/Includes/..."
INCDIR="$SCRIPT_DIR/AvgEngine/Includes"
mkdir -p "$INCDIR"

for candidate in "/usr/include/glm" "/usr/local/include/glm"; do
    if [[ -d "$candidate" ]]; then
        if [[ ! -e "$INCDIR/Glm" ]]; then
            ln -sfn "$candidate" "$INCDIR/Glm"
            echo "  $INCDIR/Glm -> $candidate"
        else
            echo "  $INCDIR/Glm already exists, skipping."
        fi
        break
    fi
done

BASS_SDK_DIR="$DEPS_DIR/bass"
BASS_DIR_FLAG="-DBASS_DIR=$BASS_SDK_DIR"

if $SKIP_BASS; then
    warn "Skipping BASS download (--skip-bass). Pass -DBASS_DIR=<path> to cmake manually."
    BASS_DIR_FLAG=""
elif [[ -f "$BASS_SDK_DIR/Bass/bass.h" ]]; then
    echo "  BASS SDK already present at $BASS_SDK_DIR"
else
    step "Downloading BASS audio SDK from un4seen.com..."
    TMP="$DEPS_DIR/.tmp_bass"
    mkdir -p "$TMP" "$BASS_SDK_DIR/Bass" "$BASS_SDK_DIR/lib"

    BASS_URL="https://www.un4seen.com/files/bass24-linux.zip"
    echo "  Fetching $BASS_URL ..."
    if curl -fsSL --connect-timeout 15 -o "$TMP/bass.zip" "$BASS_URL"; then
        unzip -q -o "$TMP/bass.zip" -d "$TMP/bass"
        find "$TMP/bass" -maxdepth 4 -name "bass.h"     -exec cp {} "$BASS_SDK_DIR/Bass/" \;
        find "$TMP/bass" -maxdepth 4 -name "libbass.so" -exec cp {} "$BASS_SDK_DIR/lib/"  \;
        echo "  BASS core installed."
    else
        warn "Could not download BASS. Place files manually:"
        warn "  bass.h     -> $BASS_SDK_DIR/Bass/bass.h"
        warn "  libbass.so -> $BASS_SDK_DIR/lib/libbass.so"
        BASS_DIR_FLAG=""
    fi

    BASSFX_URL="https://www.un4seen.com/files/bass24-fx.zip"
    echo "  Fetching $BASSFX_URL ..."
    if curl -fsSL --connect-timeout 15 -o "$TMP/bass_fx.zip" "$BASSFX_URL"; then
        unzip -q -o "$TMP/bass_fx.zip" -d "$TMP/bass_fx"
        find "$TMP/bass_fx" -maxdepth 4 -name "bass_fx.h"     -exec cp {} "$BASS_SDK_DIR/Bass/" \;
        find "$TMP/bass_fx" -maxdepth 4 -name "libbass_fx.so" -exec cp {} "$BASS_SDK_DIR/lib/"  \;
        echo "  BASS_FX installed."
    else
        warn "Could not download BASS_FX. Place manually:"
        warn "  bass_fx.h     -> $BASS_SDK_DIR/Bass/bass_fx.h"
        warn "  libbass_fx.so -> $BASS_SDK_DIR/lib/libbass_fx.so"
    fi

    rm -rf "$TMP"
fi

GLAD_H="$SCRIPT_DIR/AvgEngine/Includes/Glad/glad.h"
KHR_H="$SCRIPT_DIR/AvgEngine/Includes/KHR/khrplatform.h"

if $SKIP_GLAD; then
    warn "Skipping glad generation (--skip-glad)."
elif [[ -f "$GLAD_H" ]]; then
    echo "  glad.h already present, skipping."
else
    step "Generating glad.h (glad 0.1.x, GL 3.2 compatibility)..."
    if [[ -n "$PYTHON" ]]; then
        GLAD_OUT="$DEPS_DIR/.glad_gen"
        echo "  Installing glad Python package (0.1.x)..."
        "$PYTHON" -m pip install --quiet --upgrade "glad<0.2"

        "$PYTHON" -m glad \
            --profile=compatibility \
            --api="gl=3.2" \
            --generator=c \
            --out-path="$GLAD_OUT"

        mkdir -p "$(dirname "$GLAD_H")" "$(dirname "$KHR_H")"
        cp "$GLAD_OUT/include/glad/glad.h"       "$GLAD_H"
        cp "$GLAD_OUT/include/KHR/khrplatform.h" "$KHR_H"
        rm -rf "$GLAD_OUT"
        echo "  glad.h        -> AvgEngine/Includes/Glad/glad.h"
        echo "  khrplatform.h -> AvgEngine/Includes/KHR/khrplatform.h"
    else
        warn "Python not available. Generate manually:"
        warn "  pip install 'glad<0.2'"
        warn "  python -m glad --profile=compatibility --api=gl=3.2 --generator=c --out-path=/tmp/glad_gen"
        warn "  cp /tmp/glad_gen/include/glad/glad.h        AvgEngine/Includes/Glad/glad.h"
        warn "  cp /tmp/glad_gen/include/KHR/khrplatform.h  AvgEngine/Includes/KHR/khrplatform.h"
    fi
fi

step "Configuring CMake ($BUILD_TYPE)..."

CMAKE_ARGS=(
    -B "$BUILD_DIR"
    -S "$SCRIPT_DIR"
    -DCMAKE_BUILD_TYPE="$BUILD_TYPE"
)
[[ -n "$BASS_DIR_FLAG" ]] && CMAKE_ARGS+=("$BASS_DIR_FLAG")

cmake "${CMAKE_ARGS[@]}"

echo ""
step "Setup complete!"
echo ""
echo "  Build:           cmake --build $BUILD_DIR"
echo "  Parallel build:  cmake --build $BUILD_DIR -j\$(nproc)"
echo "  Clean rebuild:   cmake --build $BUILD_DIR --clean-first"
echo ""
if [[ -z "$BASS_DIR_FLAG" ]]; then
    warn "BASS was not configured. Once you have the SDK, re-run cmake:"
    warn "  cmake -B build -DBASS_DIR=$BASS_SDK_DIR"
fi
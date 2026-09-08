#!/bin/bash
# ============================================
# Operation Flashpoint - Cold War Crisis
# macOS Build Script (Optimized for Monterey)
# ============================================

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}   Operation Flashpoint - Cold War Crisis${NC}"
echo -e "${BLUE}   macOS Build Script (Monterey x86_64)${NC}"
echo -e "${BLUE}============================================${NC}"

# ============================================
# Detect System
# ============================================
echo -e "${CYAN}🔍 Detecting system...${NC}"
OS_VERSION=$(sw_vers -productVersion)
ARCH=$(uname -m)
echo -e "   macOS: $OS_VERSION"
echo -e "   Architecture: $ARCH"
echo -e "   Compiler: $(clang --version | head -1)"

# ============================================
# Step 1: Verify Dependencies
# ============================================
echo -e "\n${YELLOW}[1/7] Checking system dependencies...${NC}"

# Check Homebrew
if ! command -v brew &> /dev/null; then
    echo -e "${RED}Homebrew not found! Installing...${NC}"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
else
    echo -e "${GREEN}✓ Homebrew: $(brew --version | head -1)${NC}"
fi

# Install required tools (these have bottles for Monterey)
echo -e "${YELLOW}   Installing build tools...${NC}"
brew install cmake ninja git pkg-config autoconf automake libtool 2>/dev/null || true

# Verify compilers
if command -v clang &> /dev/null; then
    echo -e "${GREEN}✓ Clang: $(clang --version | head -1)${NC}"
else
    echo -e "${RED}❌ Clang not found! Install Xcode Command Line Tools${NC}"
    exit 1
fi

echo -e "${GREEN}✓ System dependencies ready${NC}"

# ============================================
# Step 2: Setup vcpkg
# ============================================
echo -e "\n${YELLOW}[2/7] Setting up vcpkg...${NC}"

if [ ! -d "$HOME/vcpkg" ]; then
    echo -e "   Cloning vcpkg..."
    git clone https://github.com/Microsoft/vcpkg.git ~/vcpkg
    cd ~/vcpkg
    ./bootstrap-vcpkg.sh
else
    echo -e "${GREEN}✓ vcpkg found at ~/vcpkg${NC}"
    cd ~/vcpkg
    git pull 2>/dev/null || true
    ./bootstrap-vcpkg.sh 2>/dev/null || true
fi

# Set VCPKG_ROOT permanently
if ! grep -q "VCPKG_ROOT" ~/.zshrc 2>/dev/null; then
    echo 'export VCPKG_ROOT=~/vcpkg' >> ~/.zshrc
    echo 'export PATH="$VCPKG_ROOT:$PATH"' >> ~/.zshrc
fi

export VCPKG_ROOT=~/vcpkg
export PATH="$VCPKG_ROOT:$PATH"

echo -e "${GREEN}✓ vcpkg ready: $(~/vcpkg/vcpkg --version | head -1)${NC}"

# ============================================
# Step 3: Locate Source
# ============================================
echo -e "\n${YELLOW}[3/7] Locating source code...${NC}"

# Try common locations
SOURCE_DIR=""
for dir in "." "/Users/gabrielmay/Documents/igiteam/___openofpcwr" "/Users/gabrielmay/Documents/igiteam/d3wasm/neo"; do
    if [ -f "$dir/CMakeLists.txt" ] && grep -q "cwr\|Poseidon\|OperationFlashpoint" "$dir/CMakeLists.txt" 2>/dev/null; then
        SOURCE_DIR="$dir"
        echo -e "${GREEN}✓ Found source: $SOURCE_DIR${NC}"
        break
    fi
done

if [ -z "$SOURCE_DIR" ]; then
    echo -e "${YELLOW}Enter the path to the Operation Flashpoint source code:${NC}"
    read -p "Path: " SOURCE_DIR
    
    if [ ! -f "$SOURCE_DIR/CMakeLists.txt" ]; then
        echo -e "${RED}Error: CMakeLists.txt not found in $SOURCE_DIR${NC}"
        exit 1
    fi
fi

cd "$SOURCE_DIR"
echo -e "${GREEN}✓ Working in: $(pwd)${NC}"

# ============================================
# Step 4: Remove openal-soft from manifest
# ============================================
echo -e "\n${YELLOW}[4/7] Checking vcpkg.json...${NC}"

if [ -f "vcpkg.json" ]; then
    # Check if openal-soft is in the manifest
    if grep -q "openal" vcpkg.json; then
        echo -e "${YELLOW}   Removing openal-soft from vcpkg.json (fails on Monterey)...${NC}"
        cp vcpkg.json vcpkg.json.backup
        
        python3 << 'PYEOF'
import json
with open('vcpkg.json', 'r') as f:
    data = json.load(f)
if 'dependencies' in data:
    data['dependencies'] = [d for d in data['dependencies'] 
                           if 'openal-soft' not in str(d) and 'openal' not in str(d).lower()]
with open('vcpkg.json', 'w') as f:
    json.dump(data, f, indent=2)
PYEOF
        echo -e "${GREEN}✓ Removed openal-soft from manifest${NC}"
    else
        echo -e "${GREEN}✓ openal-soft not in manifest${NC}"
    fi
else
    echo -e "${YELLOW}   No vcpkg.json found, creating one...${NC}"
    cat > vcpkg.json << 'EOF'
{
  "name": "operationflashpoint",
  "version": "1.0.0",
  "dependencies": [
    "sdl3",
    "libpng",
    "freetype",
    "libogg",
    "libvorbis",
    "spdlog",
    "glm",
    "catch2",
    "cjson",
    "cli11",
    "stb",
    "mimalloc",
    "zstd",
    "opus",
    "fmt"
  ]
}
EOF
fi

# ============================================
# Step 5: Install Dependencies via vcpkg
# ============================================
echo -e "\n${YELLOW}[5/7] Installing dependencies via vcpkg...${NC}"

# Install all dependencies from manifest (openal-soft already removed)
~/vcpkg/vcpkg install --triplet x64-osx

echo -e "${GREEN}✓ Dependencies installed${NC}"

# ============================================
# Step 6: Create OpenAL Config for macOS
# ============================================
echo -e "\n${YELLOW}[6/7] Creating OpenAL config for macOS...${NC}"

# Create OpenAL config directory (this is the key fix!)
mkdir -p cmake/OpenAL

# Create OpenALConfig.cmake that uses system framework
cat > cmake/OpenAL/OpenALConfig.cmake << 'EOF'
# OpenALConfig.cmake - macOS system OpenAL framework
# This file is found by find_package(OpenAL) when OpenAL_DIR is set

# Tell CMake we found OpenAL
set(OPENAL_FOUND TRUE)

# Set the library and include paths
set(OPENAL_LIBRARY "-framework OpenAL" CACHE STRING "OpenAL library" FORCE)
set(OPENAL_INCLUDE_DIR "/System/Library/Frameworks/OpenAL.framework/Headers" CACHE PATH "OpenAL include" FORCE)
set(OPENAL_LIBRARIES ${OPENAL_LIBRARY})
set(OPENAL_INCLUDE_DIRS ${OPENAL_INCLUDE_DIR})

# Create the imported target that PoseidonOpenAL expects
if(NOT TARGET OpenAL::OpenAL)
    add_library(OpenAL::OpenAL INTERFACE IMPORTED)
    set_target_properties(OpenAL::OpenAL PROPERTIES
        INTERFACE_INCLUDE_DIRECTORIES "${OPENAL_INCLUDE_DIR}"
        INTERFACE_LINK_LIBRARIES "${OPENAL_LIBRARY}"
    )
endif()

# Also create the legacy target name some projects might expect
if(NOT TARGET OpenAL)
    add_library(OpenAL INTERFACE IMPORTED)
    set_target_properties(OpenAL PROPERTIES
        INTERFACE_INCLUDE_DIRECTORIES "${OPENAL_INCLUDE_DIR}"
        INTERFACE_LINK_LIBRARIES "${OPENAL_LIBRARY}"
    )
endif()

message(STATUS "OpenAL: Using macOS system framework: ${OPENAL_LIBRARY}")
EOF

# Verify system OpenAL exists
if [ -f "/System/Library/Frameworks/OpenAL.framework/Headers/al.h" ]; then
    echo -e "${GREEN}✓ System OpenAL found${NC}"
else
    echo -e "${YELLOW}⚠️  System OpenAL not found!${NC}"
fi

echo -e "${GREEN}✓ OpenAL config created at cmake/OpenAL/OpenALConfig.cmake${NC}"

# ============================================
# Step 7: Configure and Build
# ============================================
echo -e "\n${YELLOW}[7/7] Configuring and building...${NC}"

# Clean build
if [ -d "build" ]; then
    echo -e "${YELLOW}   Removing old build directory...${NC}"
    rm -rf build
fi

mkdir -p build
cd build

# Detect CPU cores
CPU_CORES=$(sysctl -n hw.ncpu)
echo -e "${GREEN}✓ Using $CPU_CORES CPU cores${NC}"

# Configure with vcpkg + OpenAL_DIR pointing to our config
echo -e "${YELLOW}   Running CMake...${NC}"
cmake .. \
    -DCMAKE_TOOLCHAIN_FILE="$HOME/vcpkg/scripts/buildsystems/vcpkg.cmake" \
    -DVCPKG_TARGET_TRIPLET=x64-osx \
    -DOpenAL_DIR="$PWD/../cmake/OpenAL" \
    -DCMAKE_C_COMPILER=/usr/bin/clang \
    -DCMAKE_CXX_COMPILER=/usr/bin/clang++ \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DCMAKE_CXX_STANDARD=20 \
    -DCMAKE_EXPORT_COMPILE_COMMANDS=ON

echo -e "${GREEN}✓ CMake configured${NC}"

# Build using all cores
echo -e "${YELLOW}   Compiling (this will take 15-30 minutes)...${NC}"
cmake --build . --config RelWithDebInfo -j$CPU_CORES

echo -e "${GREEN}✓ Build complete!${NC}"

# ============================================
# Results
# ============================================
echo -e "\n${BLUE}============================================${NC}"
echo -e "${GREEN}✅ Operation Flashpoint built successfully!${NC}"
echo -e "${BLUE}============================================${NC}"

# Find executable
GAME_EXE=$(find . -name "operationflashpoint" -type f 2>/dev/null | head -1)
if [ -z "$GAME_EXE" ]; then
    GAME_EXE=$(find . -name "Game" -type f 2>/dev/null | head -1)
fi
if [ -z "$GAME_EXE" ]; then
    GAME_EXE=$(find . -name "*.app" -type d 2>/dev/null | head -1)
fi

if [ -n "$GAME_EXE" ]; then
    echo -e "${GREEN}📂 Game executable:${NC}"
    echo -e "   $(pwd)/$GAME_EXE"
    echo -e ""
    echo -e "${YELLOW}To run the game:${NC}"
    echo -e "   cd $(pwd) && ./$GAME_EXE"
else
    echo -e "${YELLOW}⚠️  Could not find game executable${NC}"
    echo -e "   Check in: $(pwd)"
    echo -e "   Look for: operationflashpoint, Game, or .app bundle"
fi

echo -e "${BLUE}============================================${NC}"

# Ask if user wants to run
echo -e "${YELLOW}Run the game now? (y/n)${NC}"
read -p "> " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]] && [ -n "$GAME_EXE" ]; then
    echo -e "${GREEN}Starting Operation Flashpoint...${NC}"
    ./$GAME_EXE
fi

echo -e "\n${BLUE}============================================${NC}"
echo -e "${CYAN}Troubleshooting tips:${NC}"
echo -e "1. If vcpkg fails: cd ~/vcpkg && git pull && ./bootstrap-vcpkg.sh"
echo -e "2. OpenAL is using macOS system framework via OpenAL_DIR"
echo -e "3. For Debug build: add -DCMAKE_BUILD_TYPE=Debug to CMake"
echo -e "4. VCPKG_ROOT: $VCPKG_ROOT"
echo -e "5. If you get linker errors, try: make clean && make -j$CPU_CORES"
echo -e "6. Check cmake/OpenAL/OpenALConfig.cmake exists"
echo -e "${BLUE}============================================${NC}"
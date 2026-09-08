#!/bin/bash
echo "========================================="
echo "🔍 DEVELOPMENT ENVIRONMENT CHECK"
echo "========================================="
echo ""

# 1. Check macOS version
echo "📌 macOS Version:"
sw_vers -productVersion
echo ""

# 2. Check CPU architecture
echo "📌 Architecture:"
uname -m
echo ""

# 3. Check Xcode Command Line Tools
echo "📌 Xcode Command Line Tools:"
if xcode-select --version 2>/dev/null; then
    echo "   ✅ Installed"
    echo "   Location: $(xcode-select -p)"
else
    echo "   ❌ NOT INSTALLED"
fi
echo ""

# 4. Check Compilers
echo "📌 Compilers:"
if command -v clang &> /dev/null; then
    echo "   ✅ Clang: $(clang --version | head -1)"
fi
if command -v clang++ &> /dev/null; then
    echo "   ✅ Clang++: $(clang++ --version | head -1)"
fi
if command -v gcc &> /dev/null; then
    echo "   ✅ GCC: $(gcc --version | head -1)"
fi
echo ""

# 5. Check Build Tools
echo "📌 Build Tools:"
for tool in cmake ninja make autoconf automake libtool pkg-config; do
    if command -v $tool &> /dev/null; then
        echo "   ✅ $tool: $(command -v $tool)"
    else
        echo "   ❌ $tool: NOT INSTALLED"
    fi
done
echo ""

# 6. Check Version Control
echo "📌 Version Control:"
if command -v git &> /dev/null; then
    echo "   ✅ Git: $(git --version | head -1)"
else
    echo "   ❌ Git: NOT INSTALLED"
fi
if command -v svn &> /dev/null; then
    echo "   ✅ SVN: $(svn --version | head -1)"
fi
echo ""

# 7. Check Package Managers
echo "📌 Package Managers:"
if command -v brew &> /dev/null; then
    echo "   ✅ Homebrew: $(brew --version | head -1)"
    echo "      Prefix: $(brew --prefix)"
fi
if [ -d "$HOME/vcpkg" ]; then
    echo "   ✅ vcpkg: $(~/vcpkg/vcpkg --version 2>/dev/null | head -1 || echo 'Found but version check failed')"
fi
echo ""

# 8. Check Homebrew Dependencies
echo "📌 Installed Homebrew Packages:"
packages="sdl3 libpng freetype libogg libvorbis openal-soft spdlog glm doxygen cmake ninja git clang-format"
for pkg in $packages; do
    if brew list --formula 2>/dev/null | grep -q "^$pkg$"; then
        version=$(brew info $pkg 2>/dev/null | grep -E "^$pkg:" | head -1 | sed 's/.*: //' | cut -d' ' -f1)
        echo "   ✅ $pkg: $version"
    else
        echo "   ❌ $pkg: NOT INSTALLED"
    fi
done
echo ""

# 9. Check vcpkg Dependencies
if [ -d "$HOME/vcpkg/installed/x64-osx" ]; then
    echo "📌 vcpkg Installed Packages (x64-osx):"
    # Check for key packages
    packages="brotli bzip2 catch2 cjson cli11 curl enkits fmt freetype glslang imgui libogg libpng libvorbis mimalloc openssl opus sdl3 spdlog stb vcpkg-cmake zlib zstd"
    for pkg in $packages; do
        if ls $HOME/vcpkg/installed/x64-osx/lib/lib$pkg* 2>/dev/null | grep -q .; then
            echo "   ✅ $pkg"
        else
            # Check for different naming
            if ls $HOME/vcpkg/installed/x64-osx/lib/*$pkg* 2>/dev/null | grep -q .; then
                echo "   ✅ $pkg (found with different naming)"
            else
                echo "   ❌ $pkg: NOT FOUND"
            fi
        fi
    done
else
    echo "   ⚠️  vcpkg x64-osx packages not found or not installed"
fi
echo ""

# 10. Check OpenAL Configuration
echo "📌 OpenAL Configuration:"
if [ -f "/System/Library/Frameworks/OpenAL.framework/Headers/al.h" ]; then
    echo "   ✅ System OpenAL found"
else
    echo "   ⚠️  System OpenAL not found"
fi

if [ -f "$(pwd)/cmake/OpenAL/OpenALConfig.cmake" ] 2>/dev/null; then
    echo "   ✅ Custom OpenAL config found at cmake/OpenAL/"
else
    echo "   ❌ Custom OpenAL config not found"
fi
echo ""

# 11. Check Environment Variables
echo "📌 Environment Variables:"
echo "   VCPKG_ROOT: ${VCPKG_ROOT:-NOT SET}"
echo "   PATH: ${PATH}"
echo ""

# 12. Check Project
echo "📌 Operation Flashpoint Project:"
PROJECT_ROOT=$(find ~ -name "CMakeLists.txt" -path "*/igiteam/*" -type f 2>/dev/null | head -1)
if [ -n "$PROJECT_ROOT" ]; then
    PROJECT_DIR=$(dirname "$PROJECT_ROOT")
    echo "   ✅ Found at: $PROJECT_DIR"
    echo "   📄 CMakeLists.txt: $(ls -lh $PROJECT_ROOT 2>/dev/null | awk '{print $5}')"
    echo "   📁 Build directory: $(ls -d $PROJECT_DIR/build* 2>/dev/null | wc -l) build directories"
    
    # Check vcpkg.json
    if [ -f "$PROJECT_DIR/vcpkg.json" ]; then
        echo "   📦 vcpkg.json found"
        if grep -q "openal" "$PROJECT_DIR/vcpkg.json"; then
            echo "   ⚠️  vcpkg.json contains openal-soft (should be removed for macOS)"
        else
            echo "   ✅ openal-soft not in vcpkg.json"
        fi
    else
        echo "   ❌ vcpkg.json not found"
    fi
else
    echo "   ❌ Project not found"
    echo "   Searching in: ~/igiteam, ~/Documents, ~/Desktop"
fi
echo ""

# 13. Check Build Status
echo "📌 Build Status:"
if [ -d "$PROJECT_DIR/build" ] 2>/dev/null; then
    if [ -f "$PROJECT_DIR/build/CMakeCache.txt" ]; then
        echo "   ✅ CMake configured"
    else
        echo "   ⚠️  CMake not configured (no CMakeCache.txt)"
    fi
    
    # Check for executables
    EXE=$(find "$PROJECT_DIR/build" -name "operationflashpoint" -type f 2>/dev/null | head -1)
    if [ -n "$EXE" ]; then
        echo "   ✅ Executable found: $EXE"
    else
        echo "   ❌ No executable found (not built yet)"
    fi
else
    echo "   ❌ No build directory found"
fi
echo ""

# 14. Summary
echo "========================================="
echo "📊 SUMMARY"
echo "========================================="
echo ""

# Check if everything is ready
READY=true
if ! command -v clang &> /dev/null; then
    echo "❌ Missing: Clang compiler"
    READY=false
fi
if ! command -v cmake &> /dev/null; then
    echo "❌ Missing: CMake"
    READY=false
fi
if ! command -v git &> /dev/null; then
    echo "❌ Missing: Git"
    READY=false
fi
if [ ! -d "$HOME/vcpkg" ]; then
    echo "❌ Missing: vcpkg"
    READY=false
fi
if [ ! -f "/System/Library/Frameworks/OpenAL.framework/Headers/al.h" ]; then
    echo "⚠️  System OpenAL not found (may cause issues)"
fi

if [ "$READY" = true ]; then
    echo "✅ Environment is ready for building!"
    echo ""
    echo "To build:"
    echo "  cd $PROJECT_DIR"
    echo "  rm -rf build && mkdir build && cd build"
    echo "  cmake .. -DCMAKE_TOOLCHAIN_FILE=\"\$HOME/vcpkg/scripts/buildsystems/vcpkg.cmake\" -DVCPKG_TARGET_TRIPLET=x64-osx -DOpenAL_DIR=\"\$PWD/../cmake/OpenAL\""
    echo "  make -j\$(sysctl -n hw.ncpu)"
else
    echo "❌ Environment is not ready. Please install missing items."
fi

echo ""
echo "========================================="
echo "✅ Environment check complete!"
echo "========================================="
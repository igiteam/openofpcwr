#!/bin/bash
echo "========================================="
echo "🎮 COMPLETE GAME DEVELOPMENT SETUP"
echo "========================================="
echo ""

# =============================================
# 1. CHECK IF HOMEBREW IS INSTALLED
# =============================================
echo "📌 Checking Homebrew..."
if ! command -v brew &> /dev/null; then
    echo "   ❌ Homebrew not installed!"
    echo "   Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
else
    echo "   ✅ Homebrew installed: $(brew --version | head -1)"
fi
echo ""

# =============================================
# 2. UPDATE HOMEBREW
# =============================================
echo "📌 Updating Homebrew..."
brew update
brew upgrade
echo ""

# =============================================
# 3. INSTALL ALL GAME DEVELOPMENT DEPENDENCIES
# =============================================
echo "📌 Installing Game Development Packages..."
echo ""

# Graphics & Image Libraries
echo "   🎨 Graphics & Image Libraries:"
brew install sdl2           # SDL2 (most game devs still use SDL2)
brew install sdl3           # SDL3 (newest)
brew install glfw           # GLFW (OpenGL windowing)
brew install glew           # GLEW (OpenGL extension wrangler)
brew install glm            # OpenGL Mathematics
brew install libpng         # PNG image loading
brew install libjpeg        # JPEG image loading
brew install freetype       # Font rendering
brew install harfbuzz       # Text shaping
brew install stb            # STB single-header libraries (via Homebrew)
brew install assimp         # Asset import library
echo ""

# Audio Libraries
echo "   🔊 Audio Libraries:"
brew install libogg         # OGG audio format
brew install libvorbis      # Vorbis audio codec
brew install libflac        # FLAC audio codec
brew install libsndfile     # Audio file loading
brew install openal-soft    # OpenAL audio (software)
brew install portaudio      # PortAudio (cross-platform audio)
brew install libsamplerate  # Sample rate conversion
brew install libsoxr        # SoXR (high-quality resampling)
brew install mp3lame        # MP3 encoding
brew install opus           # Opus audio codec
echo ""

# Physics & Math
echo "   🧮 Physics & Math:"
brew install bullet         # Bullet Physics
brew install box2d          # Box2D Physics
brew install eigen          # Eigen (linear algebra)
brew install gsl            # GNU Scientific Library
echo ""

# Networking & Compression
echo "   🌐 Networking & Compression:"
brew install curl           # HTTP networking
brew install libwebsockets  # WebSockets
brew install zeromq         # ZeroMQ messaging
brew install zlib           # Compression
brew install zstd           # Zstandard compression
brew install lz4            # LZ4 compression
brew install bzip2          # Bzip2 compression
echo ""

# Build Tools & Compilers
echo "   🔧 Build Tools & Compilers:"
brew install cmake          # CMake build system
brew install ninja          # Ninja build system
brew install make           # GNU Make
brew install gcc            # GCC compiler
brew install llvm           # LLVM compiler suite
brew install clang-format   # Code formatter
brew install clang-tidy     # Code linter
brew install ccache         # Caching compiler
brew install distcc         # Distributed compilation
echo ""

# Version Control
echo "   📝 Version Control:"
brew install git            # Git
brew install git-lfs        # Git LFS (large files)
brew install svn            # Subversion
echo ""

# Debugging & Profiling
echo "   🐛 Debugging & Profiling:"
brew install gdb            # GNU Debugger
brew install valgrind       # Memory debugging
brew install gprof          # Profiling
brew install massif-visualizer # Valgrind visualizer
brew install kcachegrind    # Call graph visualizer
echo ""

# Documentation
echo "   📚 Documentation:"
brew install doxygen        # Documentation generator
brew install graphviz       # Dot graph visualization
brew install sphinx         # Python documentation
echo ""

# Toolchains & Dependencies
echo "   🛠️  Toolchains & Dependencies:"
brew install pkg-config     # Package config
brew install autoconf       # Autotools
brew install automake       # Autotools
brew install libtool        # Autotools
brew install m4             # Macro processor
brew install wget           # Download tool
brew install unzip          # Archive tool
brew install tar            # Archive tool
echo ""

# Game Development Specific
echo "   🎮 Game Development Specific:"
brew install imgui          # Dear ImGui (GUI)
brew install nfd            # Native File Dialog
brew install tinyxml2       # XML parsing
brew install yaml-cpp       # YAML parsing
brew install jsoncpp        # JSON parsing
brew install toml11         # TOML parsing
brew install fmt            # Formatting library
brew install spdlog         # Fast logging
brew install catch2         # Unit testing
brew install doctest        # Unit testing (header-only)
brew install benchmark      # Benchmarking
echo ""

# =============================================
# 4. SETUP vcpkg (if not already installed)
# =============================================
echo "📌 Setting up vcpkg..."
if [ ! -d "$HOME/vcpkg" ]; then
    echo "   vcpkg not found. Installing..."
    git clone https://github.com/Microsoft/vcpkg.git ~/vcpkg
    ~/vcpkg/bootstrap-vcpkg.sh
    echo 'export VCPKG_ROOT=$HOME/vcpkg' >> ~/.zshrc
    echo 'export PATH=$VCPKG_ROOT:$PATH' >> ~/.zshrc
else
    echo "   ✅ vcpkg found at: $HOME/vcpkg"
    echo "   Updating vcpkg..."
    cd ~/vcpkg && git pull && ./bootstrap-vcpkg.sh
fi
echo ""

# =============================================
# 5. INSTALL vcpkg Dependencies
# =============================================
echo "📌 Installing vcpkg Dependencies (x64-osx)..."
cd ~/vcpkg

# Core libraries
./vcpkg install fmt spdlog catch2 benchmark \
    boost-system boost-filesystem boost-asio \
    eigen3 glm glfw3 sdl2 sdl3 \
    freetype harfbuzz assimp \
    libpng libjpeg-turbo openal-soft \
    imgui tinyxml2 yaml-cpp jsoncpp \
    zlib zstd lz4 bzip2 brotli

echo ""

# =============================================
# 6. SETUP ENVIRONMENT VARIABLES
# =============================================
echo "📌 Setting up Environment Variables..."

# Check if already in ~/.zshrc
if ! grep -q "VCPKG_ROOT" ~/.zshrc; then
    echo '# Game Development Environment Variables' >> ~/.zshrc
    echo 'export VCPKG_ROOT=$HOME/vcpkg' >> ~/.zshrc
    echo 'export PATH=$VCPKG_ROOT:$PATH' >> ~/.zshrc
    echo 'export CMAKE_PREFIX_PATH=$VCPKG_ROOT/installed/x64-osx:$CMAKE_PREFIX_PATH' >> ~/.zshrc
    echo 'export PKG_CONFIG_PATH=$VCPKG_ROOT/installed/x64-osx/lib/pkgconfig:$PKG_CONFIG_PATH' >> ~/.zshrc
    echo 'export SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX14.5.sdk' >> ~/.zshrc
fi

echo "   ✅ Environment variables added to ~/.zshrc"
source ~/.zshrc
echo ""

# =============================================
# 7. CREATE CMake Toolchain File
# =============================================
echo "📌 Creating CMake Toolchain File..."

cat > ~/cmake-toolchain.cmake << 'EOF'
# macOS Game Development Toolchain
set(CMAKE_SYSTEM_NAME Darwin)
set(CMAKE_SYSTEM_PROCESSOR x86_64)

# SDK Path
set(CMAKE_OSX_SYSROOT /Library/Developer/CommandLineTools/SDKs/MacOSX14.5.sdk)

# C++ Standard
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Compiler Flags
set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -std=c++17 -stdlib=libc++")
set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS}")

# vcpkg Integration
set(CMAKE_TOOLCHAIN_FILE $ENV{HOME}/vcpkg/scripts/buildsystems/vcpkg.cmake)
set(VCPKG_TARGET_TRIPLET x64-osx)

# OpenAL (use system OpenAL on macOS)
set(OPENAL_INCLUDE_DIR /System/Library/Frameworks/OpenAL.framework/Headers)
set(OPENAL_LIBRARY /System/Library/Frameworks/OpenAL.framework/OpenAL)

# Framework search paths
set(CMAKE_FRAMEWORK_PATH /System/Library/Frameworks /Library/Frameworks)
EOF

echo "   ✅ CMake toolchain file created at: ~/cmake-toolchain.cmake"
echo ""

# =============================================
# 8. VERIFY INSTALLATION
# =============================================
echo "========================================="
echo "📊 INSTALLATION SUMMARY"
echo "========================================="
echo ""

echo "✅ Game Development Setup Complete!"
echo ""
echo "📦 Installed Packages:"
brew list --formula | wc -l | xargs echo "   Homebrew packages:"
echo ""
echo "📁 vcpkg packages installed:"
ls ~/vcpkg/installed/x64-osx/lib/ 2>/dev/null | wc -l | xargs echo "   vcpkg libraries:"
echo ""
echo "🔧 Environment Variables:"
echo "   VCPKG_ROOT: $VCPKG_ROOT"
echo "   SDKROOT: $SDKROOT"
echo ""
echo "📋 CMake Toolchain: ~/cmake-toolchain.cmake"
echo ""
echo "========================================="
echo "🚀 HOW TO BUILD YOUR GAME:"
echo "========================================="
echo ""
echo "cd /path/to/your/game"
echo "mkdir build && cd build"
echo "cmake .. -DCMAKE_TOOLCHAIN_FILE=\"$HOME/cmake-toolchain.cmake\""
echo "make -j\$(sysctl -n hw.ncpu)"
echo ""
echo "========================================="
echo "✅ Setup complete!"
echo "========================================="
winget install Ccache.Ccache Git.Git Kitware.CMake LLVM.LLVM Ninja-build.Ninja PolarGoose.ClangFormat
winget install Microsoft.VisualStudio.BuildTools --custom '"--add Microsoft.VisualStudio.Workload.VCTools;includeRecommended"'
$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

someone who compiled the source code and said use this but its powershell code explain what it means



That's PowerShell code from the official Windows build instructions for CWR-CE . It's for setting up a native Windows build environment. Let me break down exactly what each line does.
Line 1: Install the core build tools
powershell

winget install Ccache.Ccache Git.Git Kitware.CMake LLVM.LLVM Ninja-build.Ninja PolarGoose.ClangFormat

winget is Windows Package Manager. This single command installs six tools at once:
Package	What it does
Ccache.Ccache	Compiler cache — speeds up rebuilds by caching object files
Git.Git	Version control — needed to clone the CWR-CE repo
Kitware.CMake	Build system generator — configures the project
LLVM.LLVM	Provides the Clang compiler and LLVM toolchain
Ninja-build.Ninja	Fast build system that CMake uses to actually compile
PolarGoose.ClangFormat	Code formatter for C++
Line 2: Install Visual Studio Build Tools
powershell

winget install Microsoft.VisualStudio.BuildTools --custom '"--add Microsoft.VisualStudio.Workload.VCTools;includeRecommended"'

This installs Visual Studio Build Tools (not the full IDE) with the VCTools workload. That workload provides:

    MSVC compiler (cl.exe) — Microsoft's C++ compiler

    Windows SDK — headers and libraries for Windows APIs

    Linker and build utilities — needed to produce .exe files

The includeRecommended flag adds commonly needed optional components. Without VCTools, you cannot build Windows executables with MSVC.
Line 3: Refresh your PATH
powershell

$env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")

When you install software via winget, the installers modify the system PATH, but your current PowerShell session doesn't see the changes until you restart it. This line manually rebuilds your session's PATH by concatenating:

    Machine-level PATH — system-wide installed tools

    User-level PATH — tools installed for your user only

Without this, commands like cmake, ninja, and clang would show "not found" even though they're installed, until you close and reopen PowerShell.
Why your helper gave you this

These commands are the first step of the official Windows build process . After running them, the next steps are:

    Set up vcpkg:
    powershell

    git clone https://github.com/microsoft/vcpkg.git $env:USERPROFILE\vcpkg
    cd $env:USERPROFILE\vcpkg; .\bootstrap-vcpkg.bat
    $env:VCPKG_ROOT = "$env:USERPROFILE\vcpkg"
    $env:PATH = "$env:VCPKG_ROOT;$env:PATH"

    Clone the repo:
    powershell

    cd $env:USERPROFILE; git clone https://github.com/ofpisnotdead-com/CWR-CE.git
    cd CWR-CE

    Build with the Windows preset:
    powershell

    cmake --preset win-x64-clang-rwdi
    cmake --build build/win-x64-clang-rwdi

The catch for you

This is PowerShell for Windows. Your Mac runs zsh/bash, not PowerShell, and winget doesn't exist on macOS. Your helper is giving you the official Windows-native instructions — which means he's likely assuming you're on a Windows machine, or that you'll set up a Windows VM.

If you're staying on your Mac and want to cross-compile, these commands don't apply. You'd use brew instead of winget, and the MinGW-w64 cross-compiler approach I described earlier. If you're setting up a Windows VM on your Mac (Parallels/UTM), then these commands are exactly what you'd run inside that VM.
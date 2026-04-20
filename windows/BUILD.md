# Windows Build Instructions

---

## Part 1 — monitor_switcher.exe (C++ DDC/CI binary)

### Requirements

#### Option A: MinGW-w64 (Recommended)

Install via Chocolatey:

```cmd
choco install mingw
```

Or download from https://www.mingw-w64.org/downloads/

#### Option B: Visual Studio

- Visual Studio 2019 or 2022 (Community edition is free)
- During installation, select "**Desktop development with C++**" workload (includes Windows SDK)

---

### Build

#### MinGW (Recommended)

Using Makefile:

```cmd
cd windows
mingw32-make
```

Or manually:

```cmd
cd windows
g++ -std=c++17 -O2 -static -o ..\bin\monitor_switcher.exe monitor_switcher.cpp -ldxva2 -lgdi32 -luser32
```

Output: `bin\monitor_switcher.exe`

#### Cross-compile on macOS/Linux

If you want to build `monitor_switcher.exe` for Windows from macOS or Linux:

**macOS**:
```bash
# Install mingw-w64
brew install mingw-w64

# Build
cd windows
./build-cross-compile.sh
```

**Linux (Ubuntu/Debian)**:
```bash
# Install mingw-w64
sudo apt-get install mingw-w64

# Build manually
cd windows
mkdir -p ../bin
x86_64-w64-mingw32-g++ -std=c++17 -O2 -static -static-libgcc -static-libstdc++ \
    -o ../bin/monitor_switcher.exe monitor_switcher.cpp -ldxva2 -lgdi32 -luser32
```

> **Note**: The generated `.exe` file can only run on Windows. Transfer it to your Windows machine for testing.

Output: `bin/monitor_switcher.exe`

#### Visual Studio (Command Line)

Open **Developer Command Prompt for VS**:

```cmd
cd path\to\monitor-switcher\windows
cl /EHsc /MT /O2 /std:c++17 monitor_switcher.cpp /link Dxva2.lib Gdi32.lib User32.lib /OUT:..\bin\monitor_switcher.exe
```

> **Note**: `json.hpp` is included in the `windows/` directory and must be present during compilation.

---

### Verify Build

```cmd
bin\monitor_switcher.exe help
bin\monitor_switcher.exe detect
```

---

### Troubleshooting

**Cannot find `PhysicalMonitorEnumerationAPI.h`**
- MinGW: Header should be included by default. If missing, install full mingw-w64 package
- Visual Studio: Ensure "Desktop development with C++" workload is installed (includes Windows SDK)
- Re-run Visual Studio Installer and repair installation if needed

**Cannot find `Dxva2.lib`**
- MinGW: Should link automatically with `-ldxva2` flag
- Visual Studio: Requires Windows SDK. Check Project Properties → Linker → Input → Additional Dependencies

**Cannot find `cl.exe`**
- Must run from Developer Command Prompt for VS, not regular cmd
- Search Start menu for "Developer Command Prompt for VS"

**Cannot find `g++`**
- Ensure MinGW is in PATH: `set PATH=%PATH%;C:\mingw64\bin`
- Or reinstall via Chocolatey: `choco install mingw`

**Build succeeds but missing DLL at runtime**
- Used dynamic linking: rebuild with `/MT` (MSVC) or `-static` (MinGW)
- Or install [Visual C++ Redistributable](https://aka.ms/vs/17/release/vc_redist.x64.exe)

**DDC/CI runtime errors**
- Enable DDC/CI in monitor OSD menu
- Run as Administrator
- Update graphics driver

---

## Part 2 — monitor_hub.exe (Python Flask hub, optional)

`monitor_hub` is the optional network hub service. Build it into a standalone `.exe` with PyInstaller so Python is not required on the target machine.

### Requirements

- Python 3.11+
- pip

```cmd
pip install flask pyinstaller
```

### Build

From the project root:

```cmd
pyinstaller monitor_hub.spec
```

Output: `dist\monitor_hub.exe`

The binary is self-contained — it bundles Flask, Jinja2, the web UI templates, and static files.

### Run

```cmd
REM Copy config and edit mode/ports
copy monitor_hub\config.example.json monitor_hub\config.json
notepad monitor_hub\config.json

REM Start hub (reads config.json from same directory as exe when bundled)
dist\monitor_hub.exe
```

Or copy `monitor_hub.exe` next to `config.json` anywhere and run it directly.

### Verify

```cmd
curl http://localhost:5000/
```

Should return the web UI HTML.

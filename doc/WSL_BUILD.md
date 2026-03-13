# Building qBittorrent on WSL2 / WSLg

This document captures the stable, reusable parts of the WSL-specific build
flow used in this fork.

It is intentionally narrower than [BUILD_LOGBOOK.md](../BUILD_LOGBOOK.md):

- Use this file for the known-good path.
- Use [BUILD_LOGBOOK.md](../BUILD_LOGBOOK.md) for the full troubleshooting
  history, failed attempts, and exact session logs.

## Scope

The steps below were validated on:

- WSL2
- Ubuntu 22.04
- WSLg for GUI display
- qBittorrent `release-5.1.4`

The main reason this path exists is that the stock Ubuntu 22.04 packages in
this environment were too old for the target qBittorrent build:

- Boost `1.74` installed, but qBittorrent requires `>= 1.76`
- libtorrent-rasterbar `2.0.5` installed, but qBittorrent requires `>= 2.0.10`
- Qt `6.2.4` installed, but qBittorrent requires `>= 6.5.0`

## Recommended Approach For Newer Ubuntu Releases

If you are trying this on a newer Ubuntu release under WSL2, such as Ubuntu
24.04, do not assume that you need the full workaround path in this document.

The best default approach is:

1. Start with the normal upstream build flow from [INSTALL](../INSTALL) using
   the distro packages available on that newer Ubuntu release.
2. Only switch to the local-dependency path in this document if the normal
   build fails because the distro packages are still too old, or because WSL-
   specific runtime issues appear.
3. Apply the WSL-specific tweaks incrementally instead of all at once:
   - use a non-Snap CMake binary if the Snap wrapper is broken in WSL
   - build a local Qt only if the distro Qt is too old or missing required
     modules
   - use `QT_QPA_PLATFORM=xcb` only if the local Qt build does not provide a
     working Wayland plugin under WSLg
   - apply the font fix only if the UI renders with empty square glyphs
   - treat the Qt `Threads::Threads` workaround as conditional, not automatic

In other words:

- Ubuntu 22.04 on WSL2 needed the custom route documented here.
- Ubuntu 24.04 on WSL2 should first get a clean attempt with the standard
  build path.
- If that cleaner path works, prefer it.
- If it fails, use this document as the fallback playbook and note which
  steps were actually necessary on the newer distro.

### Ubuntu 22.04 vs 24.04

| Area | Ubuntu 22.04 WSL build | Ubuntu 24.04 WSL build |
|---|---|---|
| Standard upstream build attempt | Not viable with distro packages | Almost viable with distro packages |
| Boost from distro | `1.74`, too old | `1.83`, sufficient |
| libtorrent from distro | `2.0.5`, too old | `2.0.10`, sufficient |
| Qt from distro | `6.2.4`, too old | `6.4.2`, still too old |
| Need custom Boost build | Yes | No |
| Need custom libtorrent build | Yes | No |
| Need custom Qt build | Yes | Yes |
| Qt modules needed locally | `qtbase`, `qttools`, `qtsvg` | `qtbase`, `qttools`, `qtsvg` |
| Need non-Snap/local CMake workaround | Yes | No, system `cmake 3.28.3` worked |
| `Threads::Threads` Qt patch needed | Yes in the known-good 22.04 flow | No for initial `qtbase` configure on this machine |
| Extra Qt source compatibility patch | Not the main differentiator in the final 22.04 path | Yes, guarded missing `XKB_KEY_dead_*` symbols in `qxkbcommon.cpp` |
| Extra XCB/X11 dev packages needed for working `xcb` plugin | Effectively yes in the validated path | Yes, definitely needed before `libqxcb.so` was produced |
| WSL runtime platform that worked | `xcb` | `xcb` |
| Font fix needed | Yes | Yes |
| Best dependency strategy | Full custom stack | Keep distro deps, replace only Qt |

### What Was Observed On Ubuntu 24.04

On the Ubuntu `24.04.4` WSL2 environment used in this workspace:

- Boost `1.83` from the distro packages satisfied qBittorrent.
- libtorrent-rasterbar `2.0.10` from the distro packages satisfied
  qBittorrent.
- Qt `6.4.2` from the distro packages was still too old for qBittorrent's
  `>= 6.5.0` requirement.

That means the standard distro-based build on Ubuntu 24.04 failed only on Qt.
The least invasive fallback on that newer distro is therefore:

1. keep distro Boost / libtorrent / OpenSSL / zlib
2. build only a local Qt `6.5+`
3. add just the extra Qt modules qBittorrent needs (`qttools`, `qtsvg`)

## Required System Packages

Follow the normal project requirements in [INSTALL](../INSTALL) first.

The following additional Linux packages were confirmed necessary in this WSL
setup.

The first batch gets the standard qBittorrent build and the initial Qt build
attempt moving:

- `libgl1-mesa-dev`
- `zlib1g-dev`
- `libx11-xcb-dev`
- `libxcb-glx0-dev`
- `libxcb1-dev`
- `libxkbcommon-dev`
- `libxkbcommon-x11-dev`

On Ubuntu 24.04, a second batch was also needed before the local Qt build would
actually install a working `xcb` platform plugin for WSLg:

- `libxcb-icccm4-dev`
- `libxcb-image0-dev`
- `libxcb-keysyms1-dev`
- `libxcb-render-util0-dev`
- `libxcb-shape0-dev`
- `libxcb-shm0-dev`
- `libxcb-randr0-dev`
- `libxcb-sync-dev`
- `libxcb-xfixes0-dev`
- `libxcb-cursor-dev`
- `libxcb-util-dev`
- `libxrender-dev`
- `libxi-dev`
- `libxext-dev`

If you want a single Ubuntu 24.04 package install command that matches the
working path from this workspace, this is the one:

```bash
sudo apt-get update
sudo apt-get install -y \
  build-essential cmake ninja-build pkg-config \
  qt6-base-dev qt6-tools-dev qt6-svg-dev \
  libboost-dev libtorrent-rasterbar-dev \
  libssl-dev zlib1g-dev \
  libgl1-mesa-dev libx11-xcb-dev libxcb-glx0-dev libxcb1-dev \
  libxkbcommon-dev libxkbcommon-x11-dev \
  libxcb-icccm4-dev libxcb-image0-dev libxcb-keysyms1-dev \
  libxcb-render-util0-dev libxcb-shape0-dev libxcb-shm0-dev \
  libxcb-randr0-dev libxcb-sync-dev libxcb-xfixes0-dev \
  libxcb-cursor-dev libxcb-util-dev libxrender-dev libxi-dev libxext-dev
```

## Recommended Layout

Use your own paths, but keeping the source tree and local Qt install separate
made the workflow much easier to repeat.

Example shell variables:

```bash
export QBT_SRC_DIR="$HOME/src/qBittorrent"
export QT_SRC_DIR="$HOME/src/qt-everywhere-src-6.5.0"
export QT_PREFIX="$HOME/qt6-6.5.0-install"
export CMAKE_BIN="$HOME/.local/bin/cmake"
```

If you are iterating through this flow with local tools or agents, prefer a
persistent workspace path over `/tmp` for the Qt source tarball, extracted
tree, build directory, and install prefix. In this workspace, using a repo-
local directory such as `.wsl-build/` proved easier to resume and audit across
multiple runs.

## Toolchain Notes

### Use a non-Snap CMake binary

In this WSL environment, `cmake` from `/snap/bin/cmake` was not usable.

Use an explicit working CMake binary instead. In this workspace, the
known-good choice was:

```bash
~/.local/bin/cmake --version
```

The successful build record used CMake `3.27.9`.

### Install newer Boost and libtorrent-rasterbar

This fork was built against:

- Boost `1.81`
- libtorrent-rasterbar `2.0.11`

Both were installed into `/usr/local`.

The historical commands used are preserved in
[BUILD_LOGBOOK.md](../BUILD_LOGBOOK.md).

## Build Qt 6.5.0 Locally

### Why a local Qt is required

The system Qt on Ubuntu 22.04 in this WSL setup was `6.2.4`, which is too old
for qBittorrent `5.1.x`.

### WSL-specific Qt workaround

This workaround was required on the Ubuntu 22.04 flow that originally produced
this guide.

On the Ubuntu 24.04.4 WSL2 environment used in this workspace, a clean
repo-local `qtbase` configure completed successfully without applying this
patch first. For newer Ubuntu releases, try an unpatched `qtbase` configure
before editing the Qt source tree.

The Qt build that worked here required a small local patch in:

- `qtbase/cmake/QtPublicTargetHelpers.cmake`

The change was to skip imported-target promotion only for
`Threads::Threads`, while leaving the normal promotion logic intact for the
wrapper targets Qt needs later in the generate step.

Use this function body:

```cmake
function(__qt_internal_promote_target_to_global target)
  get_property(is_global TARGET ${target} PROPERTY IMPORTED_GLOBAL)
  if(NOT is_global)
    if(target STREQUAL "Threads::Threads")
      message(DEBUG "Skipping global promotion for: '${target}'")
      return()
    endif()
    message(DEBUG "Promoting target to global: '${target}'")
    set_property(TARGET ${target} PROPERTY IMPORTED_GLOBAL TRUE)
  endif()
endfunction()
```

Without that surgical change, the Ubuntu 22.04 Qt configure/generate flow in
this WSL environment alternated between:

- `Threads::Threads` imported-global promotion errors, or
- missing wrapper targets such as `WrapZLIB::WrapZLIB` / `WrapPNG::WrapPNG`

### Ubuntu 24.04 xkbcommon compatibility note

On the Ubuntu 24.04.4 WSL2 environment used in this workspace, the local Qt
`qtbase` build later failed in `qtbase/src/gui/platform/unix/qxkbcommon.cpp`
because the system `libxkbcommon-dev` headers did not define several newer
`XKB_KEY_dead_*` keysyms that Qt 6.5 referenced.

The practical fix was to guard those mappings so they are only compiled when
the corresponding keysyms exist:

```cpp
#ifdef XKB_KEY_dead_lowline
        Xkb2Qt<XKB_KEY_dead_lowline,            Qt::Key_Dead_Lowline>,
#endif
#ifdef XKB_KEY_dead_aboveverticalline
        Xkb2Qt<XKB_KEY_dead_aboveverticalline,  Qt::Key_Dead_Aboveverticalline>,
#endif
#ifdef XKB_KEY_dead_belowverticalline
        Xkb2Qt<XKB_KEY_dead_belowverticalline,  Qt::Key_Dead_Belowverticalline>,
#endif
#ifdef XKB_KEY_dead_longsolidusoverlay
        Xkb2Qt<XKB_KEY_dead_longsolidusoverlay, Qt::Key_Dead_Longsolidusoverlay>,
#endif
```

This was not part of the Ubuntu 22.04 flow, but it was required here to finish
the local Qt build on Ubuntu 24.04.

### Configure and build qtbase

```bash
rm -rf "$QT_SRC_DIR/build"
mkdir -p "$QT_SRC_DIR/build"

cd "$QT_SRC_DIR/build"
"$CMAKE_BIN" -Wno-dev --fresh \
  -DQT_BUILD_SUBMODULES='qtbase' \
  -DCMAKE_INSTALL_PREFIX="$QT_PREFIX" \
  -DQT_BUILD_TESTS=FALSE \
  -DQT_BUILD_EXAMPLES=FALSE \
  -DCMAKE_BUILD_TYPE=Release \
  -G Ninja "$QT_SRC_DIR"

"$CMAKE_BIN" --build . --parallel
"$CMAKE_BIN" --install . --prefix "$QT_PREFIX"
```

On the Ubuntu 24.04.4 WSL2 environment used in this workspace, this `qtbase`
configure step succeeded cleanly with:

- system Boost from Ubuntu packages
- system libtorrent-rasterbar from Ubuntu packages
- system CMake `3.28.3`
- no Qt source patch applied yet

After the second XCB/X11 package batch above was installed, re-running this
same `qtbase` configure changed the XCB section to:

- `GLX Plugin`: `yes`
- `XCB GLX`: `yes`
- `EGL-X11 Plugin`: `yes`

and the resulting install contained:

- `$QT_PREFIX/plugins/platforms/libqxcb.so`
- `$QT_PREFIX/plugins/xcbglintegrations/libqxcb-glx-integration.so`
- `$QT_PREFIX/plugins/xcbglintegrations/libqxcb-egl-integration.so`

Verify the install:

```bash
test -f "$QT_PREFIX/lib/cmake/Qt6/Qt6Config.cmake" && echo FOUND
```

### Build and install the extra Qt modules qBittorrent needed

In this WSL build, qBittorrent also required:

- `qttools` for `Qt6LinguistTools`
- `qtsvg` for `Qt6Svg`

If `Qt6LinguistToolsConfig.cmake` is missing, build `qttools` into the same
prefix using the same `qt-configure-module` pattern:

```bash
rm -rf "$HOME/qttools-build"
mkdir -p "$HOME/qttools-build"

cd "$HOME/qttools-build"
"$QT_PREFIX/bin/qt-configure-module" "$QT_SRC_DIR/qttools" -- \
  -DCMAKE_BUILD_TYPE=Release \
  -DQT_BUILD_TESTS=FALSE \
  -DQT_BUILD_EXAMPLES=FALSE \
  -DCMAKE_INSTALL_PREFIX="$QT_PREFIX"

"$CMAKE_BIN" --build . --parallel
"$CMAKE_BIN" --install . --prefix "$QT_PREFIX"
```

`qtsvg` can be built like this:

```bash
rm -rf "$HOME/qtsvg-build"
mkdir -p "$HOME/qtsvg-build"

cd "$HOME/qtsvg-build"
"$QT_PREFIX/bin/qt-configure-module" "$QT_SRC_DIR/qtsvg" -- \
  -DCMAKE_BUILD_TYPE=Release \
  -DQT_BUILD_TESTS=FALSE \
  -DQT_BUILD_EXAMPLES=FALSE \
  -DCMAKE_INSTALL_PREFIX="$QT_PREFIX"

"$CMAKE_BIN" --build . --parallel
"$CMAKE_BIN" --install . --prefix "$QT_PREFIX"
```

Verify:

```bash
test -f "$QT_PREFIX/lib/cmake/Qt6Svg/Qt6SvgConfig.cmake" && echo FOUND
test -f "$QT_PREFIX/lib/cmake/Qt6LinguistTools/Qt6LinguistToolsConfig.cmake" && echo FOUND
```

## Configure and Build qBittorrent

```bash
cd "$QBT_SRC_DIR"
"$CMAKE_BIN" -S . -B build-localqt \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_PREFIX_PATH="$QT_PREFIX;/usr/local" \
  -DQt6_DIR="$QT_PREFIX/lib/cmake/Qt6"

"$CMAKE_BIN" --build build-localqt --parallel
```

The working build in this fork enabled:

- GUI
- WEBUI
- STACKTRACE
- DBUS

## Run Under WSLg

The local Qt build used here did not provide a working `wayland` platform
plugin, so the validated runtime path used `xcb`.

Known-good launch command:

```bash
cd "$QBT_SRC_DIR/build-localqt"
QT_QPA_PLATFORM=xcb \
LIBGL_ALWAYS_SOFTWARE=1 \
LD_LIBRARY_PATH="$QT_PREFIX/lib:/usr/local/lib" \
./qbittorrent
```

### Launching The Local Build

Only part of the local launcher logic is truly WSL-specific.

The WSL-specific runtime pieces are:

- `QT_QPA_PLATFORM=xcb`
- `LIBGL_ALWAYS_SOFTWARE=1`
- `LD_LIBRARY_PATH` including the local Qt `lib` directory

Everything else in this workspace's launcher is mostly local convenience:

- defaulting to this repository's `.wsl-build/qt6-6.5.0-install`
- defaulting to `build-localqt/qbittorrent`
- creating repo-local runtime directories under `.wsl-build/`
- providing a font-directory fallback when needed

So the portable way to think about launching is:

1. make sure the local Qt prefix is on `LD_LIBRARY_PATH`
2. prefer `QT_QPA_PLATFORM=xcb` for this WSLg setup
3. use software rendering if OpenGL acceleration is unreliable

For this workspace specifically, you can also use the repo-root helper:

```bash
./launch-localqt.sh
```

That helper wraps the same `xcb` / software-rendering / local-Qt runtime setup
and also keeps cache, config, and data files inside `.wsl-build/` for easier
cleanup and repeatability.

If you want the repo-local launcher shape used successfully in this workspace,
it can also help to keep the runtime state inside the repository:

```bash
XDG_CACHE_HOME="$QBT_SRC_DIR/.wsl-build/runtime-cache" \
XDG_CONFIG_HOME="$QBT_SRC_DIR/.wsl-build/runtime-config" \
XDG_DATA_HOME="$QBT_SRC_DIR/.wsl-build/runtime-data" \
QT_QPA_PLATFORM=xcb \
LIBGL_ALWAYS_SOFTWARE=1 \
LD_LIBRARY_PATH="$QT_PREFIX/lib:/usr/local/lib" \
./qbittorrent
```

If you want to check the binary without opening the full UI:

```bash
cd "$QBT_SRC_DIR/build-localqt"
QT_QPA_PLATFORM=xcb \
LIBGL_ALWAYS_SOFTWARE=1 \
LD_LIBRARY_PATH="$QT_PREFIX/lib:/usr/local/lib" \
./qbittorrent --version
```

## Font Fix

The local Qt install initially looked for fonts in:

- `$QT_PREFIX/lib/fonts`

If that directory does not exist, UI text may render as empty square glyphs.

The working fix in this WSL setup was:

```bash
ln -s /usr/share/fonts/truetype/dejavu "$QT_PREFIX/lib/fonts"
```

As a temporary alternative, you can also launch with:

```bash
QT_QPA_FONTDIR=/usr/share/fonts/truetype/dejavu
```

If you need broader glyph coverage later, install additional fonts such as
Noto and point Qt at a directory that contains them.

## What Is Local vs. Shareable

The following parts are local policy for this fork and should usually stay out
of an upstream pull request:

- personal absolute paths
- local helper scripts with machine-specific defaults
- references to this workspace's exact build directories

The following parts are the most likely to be useful upstream:

- WSL2/WSLg-specific dependency notes
- the fact that Ubuntu 22.04 system packages are too old for this build
- the required runtime choice of `QT_QPA_PLATFORM=xcb` for this local Qt build
- the missing-font workaround
- any minimal, reproducible Qt build workaround that can be independently
  verified by upstream maintainers

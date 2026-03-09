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

In other words:

- Ubuntu 22.04 on WSL2 needed the custom route documented here.
- Ubuntu 24.04 on WSL2 should first get a clean attempt with the standard
  build path.
- If that cleaner path works, prefer it.
- If it fails, use this document as the fallback playbook and note which
  steps were actually necessary on the newer distro.

## Required System Packages

Follow the normal project requirements in [INSTALL](../INSTALL) first.

The following additional Linux packages were confirmed necessary in this WSL
setup:

- `libgl1-mesa-dev`
- `zlib1g-dev`
- `libx11-xcb-dev`
- `libxcb-glx0-dev`
- `libxcb1-dev`
- `libxkbcommon-dev`
- `libxkbcommon-x11-dev`

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

Without that surgical change, the Qt configure/generate flow in this WSL
environment alternated between:

- `Threads::Threads` imported-global promotion errors, or
- missing wrapper targets such as `WrapZLIB::WrapZLIB` / `WrapPNG::WrapPNG`

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

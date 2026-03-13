#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
qt_prefix="${QBT_LOCAL_QT_PREFIX:-$script_dir/.wsl-build/qt6-6.5.0-install}"
binary_path="${QBT_BINARY_PATH:-$script_dir/build-localqt/qbittorrent}"
runtime_root="${QBT_RUNTIME_ROOT:-$script_dir/.wsl-build}"
runtime_cache="${XDG_CACHE_HOME:-$runtime_root/runtime-cache}"
runtime_config="${XDG_CONFIG_HOME:-$runtime_root/runtime-config}"
runtime_data="${XDG_DATA_HOME:-$runtime_root/runtime-data}"

if [[ ! -x "$binary_path" ]]; then
    echo "error: qBittorrent binary not found or not executable: $binary_path" >&2
    echo "build it first with CMake in $script_dir/build-localqt" >&2
    exit 1
fi

if [[ ! -d "$qt_prefix/lib" ]]; then
    echo "error: local Qt prefix not found: $qt_prefix" >&2
    exit 1
fi

mkdir -p "$runtime_cache" "$runtime_config" "$runtime_data"

font_dir_default="$qt_prefix/lib/fonts"
if [[ ! -d "$font_dir_default" ]]; then
    font_dir_default="/usr/share/fonts/truetype/dejavu"
fi

export XDG_CACHE_HOME="$runtime_cache"
export XDG_CONFIG_HOME="$runtime_config"
export XDG_DATA_HOME="$runtime_data"
export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-xcb}"
export LIBGL_ALWAYS_SOFTWARE="${LIBGL_ALWAYS_SOFTWARE:-1}"
export QT_QPA_FONTDIR="${QT_QPA_FONTDIR:-$font_dir_default}"
export QT_PLUGIN_PATH="${QT_PLUGIN_PATH:-$qt_prefix/plugins}"
export LD_LIBRARY_PATH="$qt_prefix/lib:/usr/local/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

exec "$binary_path" "$@"

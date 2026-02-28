#!/usr/bin/env bash
# =============================================================================
# player-ui-linux.sh — One-command Eclipse UI installer for Linux players
# =============================================================================
# Installs optional client-side UI support for V Rising players:
# - BepInEx pack (if missing)
# - Eclipse (default, most compatible) or EclipsePlus
#
# Usage:
#   ./player-ui-linux.sh install [--ui eclipseplus|eclipse] [--game-dir /path]
#   ./player-ui-linux.sh uninstall [--full] [--game-dir /path]
#   ./player-ui-linux.sh status [--game-dir /path]
# =============================================================================
set -euo pipefail

ACTION="${1:-}"
shift || true

UI_CHOICE="eclipse"
GAME_DIR=""
FULL_UNINSTALL="false"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --ui)
            UI_CHOICE="${2:-}"
            shift 2
            ;;
        --game-dir)
            GAME_DIR="${2:-}"
            shift 2
            ;;
        --full)
            FULL_UNINSTALL="true"
            shift
            ;;
        --help|-h)
            cat <<'EOF'
Usage:
  ./player-ui-linux.sh install [--ui eclipseplus|eclipse] [--game-dir /path]
  ./player-ui-linux.sh uninstall [--full] [--game-dir /path]
  ./player-ui-linux.sh status [--game-dir /path]
EOF
            exit 0
            ;;
        *)
            echo "[FATAL] Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

detect_game_dir() {
    local candidates=()
    local steam_roots=(
        "$HOME/.steam/steam"
        "$HOME/.local/share/Steam"
        "$HOME/.var/app/com.valvesoftware.Steam/.steam/steam"
    )

    local root
    for root in "${steam_roots[@]}"; do
        candidates+=("${root}/steamapps/common/VRising")
        if [[ -f "${root}/steamapps/libraryfolders.vdf" ]]; then
            while IFS= read -r lib; do
                [[ -n "${lib}" ]] && candidates+=("${lib}/steamapps/common/VRising")
            done < <(extract_steam_libraries "${root}/steamapps/libraryfolders.vdf")
        fi
    done

    # Preserve order while removing duplicates.
    local unique_candidates=()
    local seen=""
    local p
    for p in "${candidates[@]}"; do
        if [[ "${seen}" == *"|${p}|"* ]]; then
            continue
        fi
        seen="${seen}|${p}|"
        unique_candidates+=("${p}")
    done

    for p in "${unique_candidates[@]}"; do
        if [[ -d "${p}" ]]; then
            echo "${p}"
            return 0
        fi
    done
    return 1
}

extract_steam_libraries() {
    local vdf_file="$1"
    # Match lines like: "0" "path" "S:\\SteamLibrary"
    python3 - <<'PY' "${vdf_file}"
import re, sys
vdf_path = sys.argv[1]
pattern = re.compile(r'"\d+"\s+"path"\s+"([^"]+)"')
with open(vdf_path, "r", encoding="utf-8", errors="ignore") as fh:
    for line in fh:
        m = pattern.search(line)
        if m:
            print(m.group(1).replace("\\\\", "\\"))
PY
}

require_tools() {
    local missing=()
    command -v curl >/dev/null 2>&1 || missing+=("curl")
    command -v unzip >/dev/null 2>&1 || missing+=("unzip")
    command -v python3 >/dev/null 2>&1 || missing+=("python3")
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "[FATAL] Missing required tools: ${missing[*]}" >&2
        exit 1
    fi
}

resolve_pkg() {
    case "${UI_CHOICE,,}" in
        eclipseplus)
            PKG_AUTHOR="DiNaSoR"
            PKG_NAME="EclipsePlus"
            ;;
        eclipse)
            PKG_AUTHOR="zfolmt"
            PKG_NAME="Eclipse"
            ;;
        *)
            echo "[FATAL] --ui must be eclipseplus or eclipse" >&2
            exit 1
            ;;
    esac
}

download_pkg_zip() {
    local author="$1"
    local name="$2"
    local out_zip="$3"
    local api_url="https://thunderstore.io/api/experimental/package/${author}/${name}/"
    local download_url
    download_url="$(
        curl -fsSL "${api_url}" | python3 -c "import json,sys; print(json.load(sys.stdin)['latest']['download_url'])"
    )"
    curl -fsSL "${download_url}" -o "${out_zip}"
}

install_bepinex_if_missing() {
    if [[ -d "${GAME_DIR}/BepInEx/core" ]]; then
        echo "[INFO] BepInEx already present"
        return 0
    fi

    echo "[INFO] Installing BepInExPack_V_Rising..."
    local tmpdir
    tmpdir="$(mktemp -d)"
    trap 'rm -rf "${tmpdir}"' RETURN
    local zip_file="${tmpdir}/bepinex.zip"
    download_pkg_zip "BepInEx" "BepInExPack_V_Rising" "${zip_file}"
    unzip -q "${zip_file}" -d "${tmpdir}/extract"

    local src="${tmpdir}/extract/BepInExPack_V_Rising/BepInExPack_V_Rising"
    if [[ ! -d "${src}" ]]; then
        src="${tmpdir}/extract/BepInExPack_V_Rising"
    fi
    if [[ ! -d "${src}" ]]; then
        echo "[FATAL] Could not locate BepInEx pack contents in archive" >&2
        exit 1
    fi

    cp -a "${src}/." "${GAME_DIR}/"
    echo "[OK] BepInEx installed"
}

install_ui_pkg() {
    echo "[INFO] Installing ${PKG_AUTHOR}/${PKG_NAME}..."
    mkdir -p "${GAME_DIR}/BepInEx/plugins" "${GAME_DIR}/BepInEx/config"

    local tmpdir
    tmpdir="$(mktemp -d)"
    trap 'rm -rf "${tmpdir}"' RETURN
    local zip_file="${tmpdir}/${PKG_NAME}.zip"
    download_pkg_zip "${PKG_AUTHOR}" "${PKG_NAME}" "${zip_file}"
    unzip -q "${zip_file}" -d "${tmpdir}/extract"

    local dll_count=0
    while IFS= read -r -d '' dll; do
        cp -f "${dll}" "${GAME_DIR}/BepInEx/plugins/"
        dll_count=$((dll_count + 1))
    done < <(find "${tmpdir}/extract" -type f -iname "*.dll" -print0)

    if [[ "${dll_count}" -eq 0 ]]; then
        echo "[FATAL] No DLLs found in package ${PKG_AUTHOR}/${PKG_NAME}" >&2
        exit 1
    fi

    echo "[OK] Installed ${dll_count} plugin DLL(s)"
}

status_ui() {
    echo "GameDir: ${GAME_DIR}"
    if [[ -d "${GAME_DIR}/BepInEx/core" ]]; then
        echo "BepInEx: installed"
    else
        echo "BepInEx: missing"
    fi

    local found
    found="$(find "${GAME_DIR}/BepInEx/plugins" -maxdepth 1 -type f \( -iname "*Eclipse*.dll" -o -iname "*EclipsePlus*.dll" \) 2>/dev/null || true)"
    if [[ -n "${found}" ]]; then
        echo "Eclipse UI DLLs:"
        printf '%s\n' "${found}"
    else
        echo "Eclipse UI DLLs: not found"
    fi
}

uninstall_ui() {
    echo "[INFO] Removing Eclipse UI plugins/config..."
    rm -f "${GAME_DIR}"/BepInEx/plugins/*Eclipse*.dll*
    rm -f "${GAME_DIR}"/BepInEx/plugins/*eclipse*.dll*
    rm -f "${GAME_DIR}"/BepInEx/config/*Eclipse*.cfg*
    rm -f "${GAME_DIR}"/BepInEx/config/*eclipse*.cfg*

    if [[ "${FULL_UNINSTALL}" == "true" ]]; then
        echo "[INFO] Full uninstall requested: removing BepInEx runtime files..."
        rm -rf "${GAME_DIR}/BepInEx"
        rm -f "${GAME_DIR}/doorstop_config.ini"
        rm -f "${GAME_DIR}/winhttp.dll"
        rm -f "${GAME_DIR}/changelog.txt"
        echo "[OK] Full uninstall complete (Eclipse + BepInEx runtime files)"
    else
        echo "[OK] Eclipse UI files removed (if present)"
    fi
}

if [[ -z "${ACTION}" ]]; then
    echo "[FATAL] Missing action. Use install|uninstall|status." >&2
    exit 1
fi

require_tools
resolve_pkg

if [[ -z "${GAME_DIR}" ]]; then
    if ! GAME_DIR="$(detect_game_dir)"; then
        echo "[FATAL] Could not auto-detect VRising install path. Use --game-dir." >&2
        exit 1
    fi
fi

if [[ ! -d "${GAME_DIR}" ]]; then
    echo "[FATAL] Game directory not found: ${GAME_DIR}" >&2
    exit 1
fi

case "${ACTION}" in
    install)
        install_bepinex_if_missing
        install_ui_pkg
        status_ui
        ;;
    uninstall)
        uninstall_ui
        status_ui
        ;;
    status)
        status_ui
        ;;
    *)
        echo "[FATAL] Unknown action: ${ACTION}. Use install|uninstall|status." >&2
        exit 1
        ;;
esac

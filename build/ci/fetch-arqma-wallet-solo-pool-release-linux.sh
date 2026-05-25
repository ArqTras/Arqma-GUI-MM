#!/usr/bin/env bash
# Download prebuilt arqma_flutter_solo_pool from GitHub Releases (Linux/macOS).
# Zips: arqma-wallet-solo-pool-{linux-x86_64|macos-arm64|windows-x86_64-gnu}-{version}.zip
#   https://github.com/ArqTras/FFI/releases/download/<ver>/arqma-wallet-solo-pool-linux-x86_64-<ver>.zip
# Windows: fetch-arqma-wallet-solo-pool-release.ps1
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VERSION="$(bash "${ROOT}/build/ci/resolve-arqma-solo-pool-release-version.sh")"
REPO="${ARQMA_FFI_REPO:-ArqTras/FFI}"
echo "[fetch-solo-pool] ArqTras/FFI release ${VERSION} (${REPO})"
PLATFORMS="${ARQMA_SOLO_POOL_PLATFORMS:-linux-x86_64,macos-arm64}"
CACHE_ROOT="${ROOT}/.prebuilt/arqma-wallet-solo-pool"
VER_DIR="${CACHE_ROOT}/${VERSION}"
BASE_URL="https://github.com/${REPO}/releases/download/${VERSION}"
FORCE="${ARQMA_SOLO_POOL_FORCE:-0}"
ALLOW_MISS="${ARQMA_SOLO_POOL_ALLOW_MISS:-0}"

mkdir -p "${VER_DIR}"

flatten_extracted() {
  local dest="$1"
  local platform="$2"
  local inner="${dest}/${platform}"
  if [[ -d "${inner}" ]]; then
    shopt -s dotglob
    mv -f "${inner}"/* "${dest}/" 2>/dev/null || true
    shopt -u dotglob
    rmdir "${inner}" 2>/dev/null || true
  fi
  local legacy="solo-pool-${platform}"
  inner="${dest}/${legacy}"
  if [[ -d "${inner}" ]]; then
    shopt -s dotglob
    mv -f "${inner}"/* "${dest}/" 2>/dev/null || true
    shopt -u dotglob
    rmdir "${inner}" 2>/dev/null || true
  fi
}

solo_pool_binary_name() {
  case "$1" in
    windows-x86_64-gnu) echo "arqma_flutter_solo_pool.exe" ;;
    *) echo "arqma_flutter_solo_pool" ;;
  esac
}

find_solo_pool_binary() {
  local dir="$1"
  local platform="$2"
  local name
  name="$(solo_pool_binary_name "${platform}")"
  if [[ -f "${dir}/${name}" ]]; then
    echo "${dir}/${name}"
    return 0
  fi
  find "${dir}" -name "${name}" -type f 2>/dev/null | head -1
}

fetch_platform() {
  local platform="$1"
  local dest="${VER_DIR}/${platform}"
  local stamp="${dest}/.extracted"
  if [[ -f "${stamp}" && "${FORCE}" != "1" ]]; then
    echo "[fetch-solo-pool] ${platform} already at ${dest}"
    return 0
  fi
  local zip="arqma-wallet-solo-pool-${platform}-${VERSION}.zip"
  local url="${BASE_URL}/${zip}"
  local tmp
  tmp="$(mktemp -t arqma-solo-pool-XXXXXX.zip)"
  echo "[fetch-solo-pool] downloading ${url}"
  if ! curl -fsSL -o "${tmp}" "${url}"; then
    rm -f "${tmp}"
    if [[ "${ALLOW_MISS}" == "1" ]]; then
      echo "[fetch-solo-pool] miss: ${url} (ALLOW_MISS=1)" >&2
      return 1
    fi
    echo "[fetch-solo-pool] error: failed to download ${url}" >&2
    echo "[fetch-solo-pool] hint: tag ${VERSION} on ${REPO} must include ${zip}, or set ARQMA_SOLO_POOL_BUILD_FROM_SOURCE=1" >&2
    exit 1
  fi
  rm -rf "${dest}"
  mkdir -p "${dest}"
  if ! unzip -q -o "${tmp}" -d "${dest}" 2>/dev/null; then
    echo "[fetch-solo-pool] unzip failed; using python extract"
    rm -rf "${dest}"
    mkdir -p "${dest}"
    python3 "${ROOT}/build/ci/extract_ffi_zip.py" "${tmp}" "${dest}"
  fi
  flatten_extracted "${dest}" "${platform}"
  local bin
  bin="$(find_solo_pool_binary "${dest}" "${platform}")"
  if [[ -z "${bin}" || ! -f "${bin}" ]]; then
    rm -f "${tmp}"
    echo "[fetch-solo-pool] error: binary missing under ${dest} after extract" >&2
    exit 1
  fi
  touch "${stamp}"
  rm -f "${tmp}"
  echo "[fetch-solo-pool] extracted -> ${dest} (${bin})"
}

mirror_tauri_bin() {
  local platform="$1"
  local dir="${VER_DIR}/${platform}"
  local tauri_bin="${ROOT}/rust/tauri-app/src-tauri/bin"
  mkdir -p "${tauri_bin}"
  local src
  src="$(find_solo_pool_binary "${dir}" "${platform}")"
  [[ -n "${src}" && -f "${src}" ]] || return 0
  local name
  name="$(basename "${src}")"
  cp -f "${src}" "${tauri_bin}/${name}"
  chmod +x "${tauri_bin}/${name}" 2>/dev/null || true
  echo "[fetch-solo-pool] rust/tauri-app/src-tauri/bin/ <- ${src}"
}

mirror_rust_target() {
  local platform="$1"
  local dir="${VER_DIR}/${platform}"
  local src
  src="$(find_solo_pool_binary "${dir}" "${platform}")"
  [[ -n "${src}" && -f "${src}" ]] || return 0
  local name
  name="$(basename "${src}")"
  case "${platform}" in
    linux-x86_64|macos-arm64|macos-x86_64)
      local out="${ROOT}/rust/target/release"
      mkdir -p "${out}"
      cp -f "${src}" "${out}/${name}"
      chmod +x "${out}/${name}" 2>/dev/null || true
      echo "[fetch-solo-pool] rust/target/release/ <- ${src}"
      ;;
    windows-x86_64-gnu)
      local out="${ROOT}/rust/target/x86_64-pc-windows-gnu/release"
      mkdir -p "${out}"
      cp -f "${src}" "${out}/${name}"
      echo "[fetch-solo-pool] rust/target/x86_64-pc-windows-gnu/release/ <- ${src}"
      ;;
  esac
}

IFS=',' read -r -a _platforms <<< "${PLATFORMS}"
fetched=0
for p in "${_platforms[@]}"; do
  p="${p// /}"
  [[ -n "${p}" ]] || continue
  if fetch_platform "${p}"; then
    mirror_tauri_bin "${p}"
    mirror_rust_target "${p}"
    fetched=1
  fi
done

if [[ "${fetched}" -eq 0 && "${ALLOW_MISS}" == "1" ]]; then
  echo "[fetch-solo-pool] no platform fetched (ALLOW_MISS=1)" >&2
  exit 1
fi

echo "[fetch-solo-pool] done (version=${VERSION}, cache=${VER_DIR})"

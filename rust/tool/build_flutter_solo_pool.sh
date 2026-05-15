#!/usr/bin/env bash
# Build `arqma_flutter_solo_pool` and install into `rust/tauri-app/src-tauri/bin/` for Flutter desktop bundles.
# Requires libwallet_merged (same as native wallet FFI) — see rust/docs/NATIVE_WALLET2.md.
#
# Usage (from anywhere):
#   bash rust/tool/build_flutter_solo_pool.sh
#   bash rust/tool/build_flutter_solo_pool.sh --skip-upstream   # wallet_merged already built
#
# Windows (MSYS2): same script, or rust/tool/build_flutter_solo_pool.ps1 from PowerShell.
set -euo pipefail

SKIP_UPSTREAM=0
for arg in "$@"; do
  case "$arg" in
    --skip-upstream) SKIP_UPSTREAM=1 ;;
    -h | --help)
      echo "usage: $0 [--skip-upstream]" >&2
      exit 0
      ;;
    *)
      echo "unknown option: $arg" >&2
      exit 2
      ;;
  esac
done

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REPO="$(cd "${ROOT}/.." && pwd)"
TAURI_BIN="${ROOT}/tauri-app/src-tauri/bin"
mkdir -p "${TAURI_BIN}"

export ARQMA_WALLET2_UPSTREAM_DIR="${ARQMA_WALLET2_UPSTREAM_DIR:-${ROOT}/arqma-rpc-upstream}"

if [[ "${SKIP_UPSTREAM}" -eq 0 ]]; then
  if [[ ! -f "${ARQMA_WALLET2_UPSTREAM_DIR}/src/wallet/api/wallet2_api.h" ]]; then
    echo "Missing upstream; run: bash build/ci/clone-arqma.sh" >&2
    exit 1
  fi
  case "$(uname -s)" in
    Darwin)
      bash "${REPO}/build/ci/build-arqma-macos.sh"
      ;;
    Linux)
      bash "${REPO}/build/ci/build-arqma-linux.sh"
      ;;
    MINGW* | MSYS* | CYGWIN*)
      pushd "${ROOT}/tauri-app" >/dev/null
      npm run build:arqma:mingw
      popd >/dev/null
      ;;
    *)
      echo "Unsupported OS for upstream build; set ARQMA_WALLET2_LIB_DIR or build wallet_merged manually." >&2
      exit 2
      ;;
  esac
fi

bash "${REPO}/build/ci/ensure-tauri-dist-stub.sh" "${REPO}"

cd "${ROOT}"
CARGO_ARGS=(build -p arqma-wallet --release --bin arqma_flutter_solo_pool)
case "$(uname -s)" in
  Linux)
    # Match `arqma-wallet-flutter-ffi` on CI: link PIC static Boost/OpenSSL/… from `contrib/depends`
    # (same symbols as `libwallet_merged.a`). Distro `-lboost_*` can be a different Boost → undefined refs.
    DEP_LIB="${ARQMA_WALLET2_UPSTREAM_DIR:-${ROOT}/arqma-rpc-upstream}/contrib/depends/x86_64-unknown-linux-gnu/lib"
    if [[ -d "$DEP_LIB" ]] && compgen -G "${DEP_LIB}/libboost"*.a >/dev/null 2>&1; then
      export ARQMA_WALLET_FFI_STATIC_HYBRID=1
      export ARQMA_WALLET_FFI_USE_DEPENDS=1
    else
      # Dev machines without `make depends`: distro dynamic libs + GNU BFD (rust-lld drops Boost too early).
      export RUSTFLAGS="${RUSTFLAGS:-} -Clink-arg=-fuse-ld=bfd"
    fi
    ;;
  MINGW* | MSYS* | CYGWIN*)
    export CARGO_PROFILE_RELEASE_LTO="${CARGO_PROFILE_RELEASE_LTO:-thin}"
    CARGO_ARGS+=(--target x86_64-pc-windows-gnu)
    ;;
esac

# GitHub macOS runners occasionally shadow `rustc` (broken `rustc -vV`); clear if set.
unset RUSTC 2>/dev/null || true
unset CARGO_BUILD_RUSTC 2>/dev/null || true

cargo "${CARGO_ARGS[@]}"

install_one() {
  local src="$1"
  local dest_name="$2"
  if [[ ! -f "${src}" ]]; then
    return 1
  fi
  cp -f "${src}" "${TAURI_BIN}/${dest_name}"
  chmod +x "${TAURI_BIN}/${dest_name}" 2>/dev/null || true
  echo "Installed ${dest_name} <- ${src}"
  return 0
}

installed=0
for cand in \
  "${ROOT}/target/release/arqma_flutter_solo_pool" \
  "${ROOT}/target/x86_64-pc-windows-gnu/release/arqma_flutter_solo_pool.exe" \
  "${ROOT}/tauri-app/src-tauri/target/release/arqma_flutter_solo_pool" \
  "${ROOT}/tauri-app/src-tauri/target/release/arqma_flutter_solo_pool.exe"; do
  base="$(basename "${cand}")"
  if install_one "${cand}" "${base}"; then
    installed=1
    break
  fi
done

if [[ "${installed}" -ne 1 ]]; then
  echo "::error::arqma_flutter_solo_pool not found under rust/target after build" >&2
  exit 1
fi

echo "Solo pool ready in ${TAURI_BIN}/"

#!/usr/bin/env bash
# Copy dynamic libraries required by libarqma_wallet_flutter_ffi.so into bundle/lib/
# (ICU, zlib, readline/tinfo, …) so the tarball works on distros without the same SONAMEs
# as the build host (e.g. missing libicuuc.so.74).
# Also adds relative symlinks in the bundle root (next to Arqma-Wallet) so loaders that
# search $ORIGIN (exe dir) still find the same SONAMEs.
#
# Usage: ./tool/bundle_linux_ffi_runtime_libs.sh <path-to-linux-release-bundle>
# Example: ./tool/bundle_linux_ffi_runtime_libs.sh build/linux/x64/release/bundle
set -euo pipefail
B="${1:?usage: $0 <path-to-linux-release-bundle>}"
export LC_ALL=C

SO="${B}/lib/libarqma_wallet_flutter_ffi.so"
if [[ ! -f "$SO" ]]; then
  echo "error: missing $SO (build wallet FFI and flutter build linux first)" >&2
  exit 1
fi

LIBDIR="${B}/lib"
mkdir -p "$LIBDIR"

# Skip glibc / pthread / libstdc++ — expect distro baseline; bundle everything else ldd reports.
is_core_system_lib() {
  local base="$1"
  case "$base" in
    ld-linux-*.so.* | ld-linux-x86-64.so.2 | libc.so.* | libm.so.* | libpthread.so.* | libdl.so.* | librt.so.* | \
      libresolv.so.* | libgcc_s.so.* | libstdc++.so.* | linux-vdso.so.* | libnss_dns.so.* | libnss_files.so.* | \
      libnsl.so.* | libutil.so.* | libbsd.so.*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

copy_dep() {
  local dep="$1"
  [[ -f "$dep" ]] || return 0
  local base dest
  base="$(basename "$dep")"
  if is_core_system_lib "$base"; then
    return 0
  fi
  dest="${LIBDIR}/${base}"
  if [[ -e "$dest" ]]; then
    return 0
  fi
  cp -L "$dep" "$dest"
  echo "[bundle_linux_ffi_runtime_libs] ${base} <- ${dep}"
}

mapfile -t DEPS < <(ldd "$SO" | awk '$2 == "=>" && $3 ~ /^\// {print $3}')
if [[ "${#DEPS[@]}" -eq 0 ]]; then
  echo "error: ldd produced no resolved paths for $SO" >&2
  exit 1
fi

for dep in "${DEPS[@]}"; do
  copy_dep "$dep"
done

# Symlink each bundled NEEDED library next to the app binary (same SONAME as under lib/).
for dep in "${DEPS[@]}"; do
  [[ -f "$dep" ]] || continue
  base="$(basename "$dep")"
  if is_core_system_lib "$base"; then
    continue
  fi
  bundled="${LIBDIR}/${base}"
  if [[ ! -f "$bundled" ]]; then
    continue
  fi
  ln -sfn "lib/${base}" "${B}/${base}"
  echo "[bundle_linux_ffi_runtime_libs] symlink ${base} -> lib/${base} (bundle root)"
done

if ldd "$SO" 2>/dev/null | grep -q 'not found'; then
  echo "error: $SO still has unresolved NEEDED entries after bundling:" >&2
  ldd "$SO" >&2 || true
  exit 1
fi

echo "[bundle_linux_ffi_runtime_libs] OK — $SO"

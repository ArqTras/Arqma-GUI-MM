/**
 * Apply MinGW / Tauri native-wallet fixes to a cloned Arqma core tree (after clone, before CMake).
 * Idempotent — safe on every CI run.
 *
 * Usage: node patch-arqma-mingw-gui.js <arqma-upstream-root>
 */
/* eslint-disable no-template-curly-in-string -- CMake uses literal ${ARCH_ID}, not JS interpolation */
const fs = require("fs")
const path = require("path")

const up = process.argv[2]
if (!up) {
  console.error("usage: node patch-arqma-mingw-gui.js <arqma-upstream-root>")
  process.exit(1)
}

function patchRandomarqCMake () {
  const f = path.join(up, "external/randomarq/CMakeLists.txt")
  if (!fs.existsSync(f)) {
    return
  }
  let s = fs.readFileSync(f, "utf8")
  const normalizeAlready =
    "string(TOLOWER \"${ARCH_ID}\" ARCH_ID)"
  if (
    s.includes("Arqma-GUI-MM: normalize ARCH_ID for RandomX JIT") ||
    s.includes(normalizeAlready)
  ) {
    return
  }
  const insert =
    "\n# Arqma-GUI-MM: normalize ARCH_ID for RandomX JIT (Windows CMAKE may pass AMD64).\n" +
    "string(TOLOWER \"${ARCH_ID}\" ARCH_ID)\n\n"
  const reAfterArchEndifArm =
    /(endif\(\)\r?\n)(\s+if\(NOT ARM_ID\))/
  const reAfterProject =
    /(project\(RandomARQ\)\r?\n)/
  if (reAfterArchEndifArm.test(s)) {
    s = s.replace(reAfterArchEndifArm, (_, a, b) => a + insert + b)
  } else if (reAfterProject.test(s)) {
    s = s.replace(reAfterProject, (_, a) => a + insert)
  } else {
    console.warn("[patch-arqma-mingw-gui] skip randomarq CMakeLists.txt (pattern not found)")
    return
  }
  fs.writeFileSync(f, s)
  console.log("[patch-arqma-mingw-gui] patched external/randomarq/CMakeLists.txt")
}

function patchWalletCMake () {
  const f = path.join(up, "src/wallet/CMakeLists.txt")
  if (!fs.existsSync(f)) {
    return
  }
  let s = fs.readFileSync(f, "utf8")
  if (
    s.includes("Arqma-GUI-MM: wallet_merged MinGW daemonizer") ||
    s.includes("list(APPEND libs_to_merge daemonizer)")
  ) {
    return
  }
  const re = /(\s+checkpoints\s*\r?\n\s+version\s*\r?\n\s+net\)\s*\r?\n)(\s+else\(\))/
  if (!re.test(s)) {
    console.warn("[patch-arqma-mingw-gui] skip src/wallet/CMakeLists.txt (pattern not found)")
    return
  }
  const block =
    "    # Arqma-GUI-MM: wallet_merged MinGW daemonizer\n" +
    "    # MinGW GUI link pulls `windows::check_admin` from daemonizer via cryptonote_core headers.\n" +
    "    if(MINGW)\n" +
    "      list(APPEND libs_to_merge daemonizer)\n" +
    "    endif()\n\n"
  s = s.replace(re, (_, a, b) => a + block + b)
  fs.writeFileSync(f, s)
  console.log("[patch-arqma-mingw-gui] patched src/wallet/CMakeLists.txt")
}

function patchStackTrace () {
  const f = path.join(up, "src/common/stack_trace.cpp")
  if (!fs.existsSync(f)) {
    return
  }
  let s = fs.readFileSync(f, "utf8")
  const guardIdx = s.indexOf("#if !defined(ARQMA_SKIP_CXA_THROW_HOOK)")
  if (guardIdx === -1) {
    console.warn("[patch-arqma-mingw-gui] skip stack_trace.cpp (ARQMA_SKIP guard not found)")
    return
  }
  const head = s.slice(0, guardIdx)
  if (/defined\s*\(\s*__MINGW32__\s*\)/.test(head)) {
    return
  }
  const re = /(#if !defined\(ARQMA_SKIP_CXA_THROW_HOOK\))/
  const prefix =
    "// MinGW: STATICLIB builds expect GNU ld `--wrap,__cxa_throw` so `__real___cxa_throw` resolves.\n" +
    "// We do not pass that flag when linking the Tauri cdylib (it breaks other archives); skip the\n" +
    "// hook and use the normal libc++abi symbol instead.\n" +
    "#if defined(__MINGW32__) || defined(__MINGW64__)\n" +
    "#define ARQMA_SKIP_CXA_THROW_HOOK 1\n" +
    "#endif\n\n"
  s = s.replace(re, prefix + "$1")
  fs.writeFileSync(f, s)
  console.log("[patch-arqma-mingw-gui] patched src/common/stack_trace.cpp")
}

patchRandomarqCMake()
patchWalletCMake()
patchStackTrace()

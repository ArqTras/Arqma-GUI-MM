/**
 * Add Wallet API methods required by `arqma-wallet2-api` (Flutter FFI):
 * `exportPendingRelaySlices`, `relayTxFromMetadataHex`.
 * Encoding matches `wallet_rpc_server` relay_tx / get_tx_metadata (binary_archive + hex).
 *
 * Idempotent — safe on every CI run and cached local clones.
 *
 * Usage: node patch-arqma-wallet2-api-relay.js <arqma-upstream-root>
 */
const fs = require("fs")
const path = require("path")

const up = process.argv[2]
if (!up) {
  console.error("usage: node patch-arqma-wallet2-api-relay.js <arqma-upstream-root>")
  process.exit(1)
}

const MARK = "Arqma-GUI-MM: wallet2 api relay export"

function patchWallet2ApiHeader () {
  const f = path.join(up, "src/wallet/api/wallet2_api.h")
  if (!fs.existsSync(f)) {
    return
  }
  let s = fs.readFileSync(f, "utf8")

  // Older script versions inserted these into WalletManagerBase; remove if present.
  const legacyWrong = /\r?\n\r?\n {4}\/\/ Arqma-GUI-MM: wallet2 api relay export \(Flutter FFI[^\r\n]*\r?\n {4}virtual bool exportPendingRelaySlices\([^\r\n]+\r?\n {4}virtual bool relayTxFromMetadataHex\([^\r\n]+\r?\n(?=\r?\n {4}\/\/! checks for an update)/
  if (legacyWrong.test(s)) {
    s = s.replace(legacyWrong, "\n")
    fs.writeFileSync(f, s)
    console.log("[patch-arqma-wallet2-api-relay] removed legacy mistaken insert in wallet2_api.h")
  }

  if (/virtual bool isKeysFileLocked\(\) = 0;\s*\r?\n\s*\/\/ Arqma-GUI-MM: wallet2 api relay export/.test(s)) {
    return
  }

  const re =
    /(virtual bool isKeysFileLocked\(\) = 0;\s*\r?\n)(\s*\/\*!\s*\r?\n\s*\\brief Queries backing device for wallet keys)/
  if (!re.test(s)) {
    console.warn("[patch-arqma-wallet2-api-relay] skip wallet2_api.h (Wallet struct anchor not found)")
    return
  }
  s = s.replace(re, (_, a, b) =>
    `${a}` +
    `    // ${MARK} (Flutter FFI; parity with wallet RPC relay_tx metadata)\n` +
    "    virtual bool exportPendingRelaySlices(PendingTransaction *ptx, std::vector<std::string> &hexes, std::vector<uint64_t> &fees) = 0;\n" +
    "    virtual bool relayTxFromMetadataHex(const std::string &metadata_hex, std::string &tx_hash) = 0;\n" +
    `\n${b}`
  )
  fs.writeFileSync(f, s)
  console.log("[patch-arqma-wallet2-api-relay] patched src/wallet/api/wallet2_api.h")
}

function patchWalletImplHeader () {
  const f = path.join(up, "src/wallet/api/wallet.h")
  if (!fs.existsSync(f)) {
    return
  }
  let s = fs.readFileSync(f, "utf8")
  if (/virtual bool exportPendingRelaySlices/.test(s)) {
    return
  }
  const re =
    /(virtual bool isKeysFileLocked\(\) override;\s*\r?\n)(\s*private:)/
  if (!re.test(s)) {
    console.warn("[patch-arqma-wallet2-api-relay] skip wallet.h (pattern not found)")
    return
  }
  s = s.replace(re, (_, a, b) =>
    `${a}\n` +
    `    // ${MARK}\n` +
    "    virtual bool exportPendingRelaySlices(PendingTransaction *ptx, std::vector<std::string> &hexes, std::vector<uint64_t> &fees) override;\n" +
    "    virtual bool relayTxFromMetadataHex(const std::string &metadata_hex, std::string &tx_hash) override;\n" +
    `\n${b}`
  )
  fs.writeFileSync(f, s)
  console.log("[patch-arqma-wallet2-api-relay] patched src/wallet/api/wallet.h")
}

function patchWalletImplCpp () {
  const f = path.join(up, "src/wallet/api/wallet.cpp")
  if (!fs.existsSync(f)) {
    return
  }
  let s = fs.readFileSync(f, "utf8")
  if (s.includes("WalletImpl::exportPendingRelaySlices")) {
    return
  }

  const incMarker = `${MARK} (includes)`
  if (!s.includes(incMarker)) {
    const incRe = /(#include "common\/util\.h"\s*\r?\n)/
    if (!incRe.test(s)) {
      console.warn("[patch-arqma-wallet2-api-relay] skip wallet.cpp includes (pattern not found)")
    } else {
      s = s.replace(incRe, (_, a) =>
        `${a}// ${incMarker}\n` +
          "#include \"serialization/binary_archive.h\"\n" +
          "#include \"serialization/serialization.h\"\n" +
          "#include \"cryptonote_basic/cryptonote_format_utils.h\"\n" +
          "#include <boost/archive/portable_binary_iarchive.hpp>\n"
      )
    }
  }

  const implRe =
    /(bool WalletImpl::isKeysFileLocked\(\)\s*\r?\n\{\s*\r?\n\s*return m_wallet->is_keys_file_locked\(\);\s*\r?\n\}\s*\r?\n)(\s*PendingTransaction\* WalletImpl::stakePending)/
  if (!implRe.test(s)) {
    console.warn("[patch-arqma-wallet2-api-relay] skip wallet.cpp impl (pattern not found)")
    return
  }
  const implBody =
    "bool WalletImpl::exportPendingRelaySlices(PendingTransaction *ptx, std::vector<std::string> &hexes, std::vector<uint64_t> &fees)\n" +
    "{\n" +
    "    hexes.clear();\n" +
    "    fees.clear();\n" +
    "    auto *pti = dynamic_cast<PendingTransactionImpl *>(ptx);\n" +
    "    if (!pti || pti->m_pending_tx.empty())\n" +
    "        return false;\n" +
    "    for (const auto &pending : pti->m_pending_tx)\n" +
    "    {\n" +
    "        std::ostringstream oss;\n" +
    "        binary_archive<true> ar(oss);\n" +
    "        try\n" +
    "        {\n" +
    "            if (!::serialization::serialize(ar, const_cast<tools::wallet2::pending_tx &>(pending)))\n" +
    "                return false;\n" +
    "        }\n" +
    "        catch (...)\n" +
    "        {\n" +
    "            return false;\n" +
    "        }\n" +
    "        hexes.push_back(epee::string_tools::buff_to_hex_nodelimer(oss.str()));\n" +
    "        fees.push_back(pending.fee);\n" +
    "    }\n" +
    "    return true;\n" +
    "}\n" +
    "\n" +
    "bool WalletImpl::relayTxFromMetadataHex(const std::string &metadata_hex, std::string &tx_hash)\n" +
    "{\n" +
    "    tx_hash.clear();\n" +
    "    std::string blob;\n" +
    "    if (!epee::string_tools::parse_hexstr_to_binbuff(metadata_hex, blob))\n" +
    "        return false;\n" +
    "    bool loaded = false;\n" +
    "    tools::wallet2::pending_tx ptx;\n" +
    "    try\n" +
    "    {\n" +
    "        std::istringstream iss(blob);\n" +
    "        binary_archive<false> ar(iss);\n" +
    "        if (::serialization::serialize(ar, ptx))\n" +
    "            loaded = true;\n" +
    "    }\n" +
    "    catch (...)\n" +
    "    {\n" +
    "    }\n" +
    "    if (!loaded)\n" +
    "    {\n" +
    "        try\n" +
    "        {\n" +
    "            std::istringstream iss(blob);\n" +
    "            boost::archive::portable_binary_iarchive ar(iss);\n" +
    "            ar >> ptx;\n" +
    "            loaded = true;\n" +
    "        }\n" +
    "        catch (...)\n" +
    "        {\n" +
    "        }\n" +
    "    }\n" +
    "    if (!loaded)\n" +
    "        return false;\n" +
    "    try\n" +
    "    {\n" +
    "        m_wallet->commit_tx(ptx);\n" +
    "    }\n" +
    "    catch (...)\n" +
    "    {\n" +
    "        return false;\n" +
    "    }\n" +
    "    tx_hash = epee::string_tools::pod_to_hex(cryptonote::get_transaction_hash(ptx.tx));\n" +
    "    return true;\n" +
    "}\n" +
    "\n"
  s = s.replace(implRe, (_, a, b) => `${a}${implBody}${b}`)
  fs.writeFileSync(f, s)
  console.log("[patch-arqma-wallet2-api-relay] patched src/wallet/api/wallet.cpp")
}

patchWallet2ApiHeader()
patchWalletImplHeader()
patchWalletImplCpp()

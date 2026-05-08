#include "wallet2_api_wrapper.hpp"

#include <memory>
#include <stdexcept>
#include <string>
#include <sstream>
#include <unordered_map>
#include <vector>

#include "wallet2_api.h"

namespace {
Monero::NetworkType to_network(const std::uint8_t network) {
  switch (network) {
    case 1:
      return Monero::TESTNET;
    case 2:
      return Monero::STAGENET;
    case 0:
    default:
      return Monero::MAINNET;
  }
}

std::string json_escape(const std::string& in) {
  std::string out;
  out.reserve(in.size() + 8);
  for (char c : in) {
    switch (c) {
      case '\\': out += "\\\\"; break;
      case '"': out += "\\\""; break;
      case '\n': out += "\\n"; break;
      case '\r': out += "\\r"; break;
      case '\t': out += "\\t"; break;
      default: out.push_back(c); break;
    }
  }
  return out;
}
}

Wallet2Bridge::~Wallet2Bridge() {
  if (wallet != nullptr) {
    for (auto& kv : pending_by_metadata) {
      if (kv.second != nullptr) {
        wallet->disposeTransaction(kv.second);
      }
    }
    pending_by_metadata.clear();
  }
  if (manager != nullptr && wallet != nullptr) {
    manager->closeWallet(wallet, true);
    wallet = nullptr;
  }
}

void clear_pending(Wallet2Bridge& bridge) {
  if (bridge.wallet == nullptr) {
    return;
  }
  for (auto& kv : bridge.pending_by_metadata) {
    if (kv.second != nullptr) {
      bridge.wallet->disposeTransaction(kv.second);
    }
  }
  bridge.pending_by_metadata.clear();
}

std::unique_ptr<Wallet2Bridge> wallet2_open(
  const std::string& path,
  const std::string& password,
  const std::string& daemon,
  std::uint8_t network
) {
  auto bridge = std::make_unique<Wallet2Bridge>();
  bridge->manager = Monero::WalletManagerFactory::getWalletManager();
  if (bridge->manager == nullptr) {
    throw std::runtime_error("WalletManagerFactory::getWalletManager returned null");
  }

  std::string path_s(path);
  std::string pass_s(password);
  std::string daemon_s(daemon);
  bridge->wallet = bridge->manager->openWallet(path_s, pass_s, to_network(network));
  if (bridge->wallet == nullptr) {
    throw std::runtime_error("openWallet returned null");
  }

  if (!daemon_s.empty()) {
    bridge->wallet->init(daemon_s);
    bridge->wallet->startRefresh();
  }
  return bridge;
}

void wallet2_store(Wallet2Bridge& bridge) {
  if (bridge.wallet == nullptr) {
    throw std::runtime_error("wallet is null");
  }
  if (!bridge.wallet->store("")) {
    throw std::runtime_error(bridge.wallet->errorString());
  }
}

void wallet2_close(Wallet2Bridge& bridge) {
  if (bridge.manager == nullptr || bridge.wallet == nullptr) {
    return;
  }
  clear_pending(bridge);
  if (!bridge.manager->closeWallet(bridge.wallet, true)) {
    throw std::runtime_error(bridge.manager->errorString());
  }
  bridge.wallet = nullptr;
}

rust::String wallet2_address(const Wallet2Bridge& bridge) {
  if (bridge.wallet == nullptr) {
    throw std::runtime_error("wallet is null");
  }
  return rust::String(bridge.wallet->address());
}

rust::String wallet2_seed(const Wallet2Bridge& bridge) {
  if (bridge.wallet == nullptr) {
    throw std::runtime_error("wallet is null");
  }
  return rust::String(bridge.wallet->seed());
}

rust::String wallet2_secret_spend_key(const Wallet2Bridge& bridge) {
  if (bridge.wallet == nullptr) {
    throw std::runtime_error("wallet is null");
  }
  return rust::String(bridge.wallet->secretSpendKey());
}

rust::String wallet2_secret_view_key(const Wallet2Bridge& bridge) {
  if (bridge.wallet == nullptr) {
    throw std::runtime_error("wallet is null");
  }
  return rust::String(bridge.wallet->secretViewKey());
}

bool wallet2_set_password(Wallet2Bridge& bridge, const std::string& new_password) {
  if (bridge.wallet == nullptr) {
    throw std::runtime_error("wallet is null");
  }
  return bridge.wallet->setPassword(new_password);
}

bool wallet2_set_tx_note(Wallet2Bridge& bridge, const std::string& txid, const std::string& note) {
  if (bridge.wallet == nullptr) {
    throw std::runtime_error("wallet is null");
  }
  return bridge.wallet->setUserNote(txid, note);
}

bool wallet2_export_key_images(const Wallet2Bridge& bridge, const std::string& filename) {
  if (bridge.wallet == nullptr) {
    throw std::runtime_error("wallet is null");
  }
  return bridge.wallet->exportKeyImages(filename);
}

bool wallet2_add_address_book(Wallet2Bridge& bridge, const std::string& address, const std::string& payment_id, const std::string& description) {
  if (bridge.wallet == nullptr) {
    throw std::runtime_error("wallet is null");
  }
  auto* ab = bridge.wallet->addressBook();
  if (ab == nullptr) {
    throw std::runtime_error("address book is null");
  }
  return ab->addRow(address, payment_id, description);
}

bool wallet2_delete_address_book(Wallet2Bridge& bridge, std::uint64_t row_id) {
  if (bridge.wallet == nullptr) {
    throw std::runtime_error("wallet is null");
  }
  auto* ab = bridge.wallet->addressBook();
  if (ab == nullptr) {
    throw std::runtime_error("address book is null");
  }
  return ab->deleteRow(static_cast<std::size_t>(row_id));
}

rust::String wallet2_get_address_book_json(const Wallet2Bridge& bridge) {
  if (bridge.wallet == nullptr) {
    throw std::runtime_error("wallet is null");
  }
  auto* ab = bridge.wallet->addressBook();
  if (ab == nullptr) {
    return rust::String("{\"entries\":[]}");
  }
  ab->refresh();
  const auto rows = ab->getAll();
  std::ostringstream oss;
  oss << "{\"entries\":[";
  bool first = true;
  for (const auto* row : rows) {
    if (!row) continue;
    if (!first) oss << ",";
    first = false;
    oss << "{"
        << "\"index\":" << row->getRowId() << ","
        << "\"address\":\"" << json_escape(row->getAddress()) << "\","
        << "\"payment_id\":\"" << json_escape(row->getPaymentId()) << "\","
        << "\"description\":\"" << json_escape(row->getDescription()) << "\""
        << "}";
  }
  oss << "]}";
  return rust::String(oss.str());
}

rust::String wallet2_get_transfer_by_txid_json(const Wallet2Bridge& bridge, const std::string& txid) {
  if (bridge.wallet == nullptr) {
    throw std::runtime_error("wallet is null");
  }
  auto* hist = bridge.wallet->history();
  if (hist == nullptr) {
    return rust::String("{}");
  }
  auto* tr = hist->transaction(txid);
  if (tr == nullptr) {
    return rust::String("{}");
  }
  std::ostringstream oss;
  oss << "{"
      << "\"txid\":\"" << json_escape(tr->hash()) << "\","
      << "\"amount\":" << tr->amount() << ","
      << "\"fee\":" << tr->fee() << ","
      << "\"height\":" << tr->blockHeight() << ","
      << "\"timestamp\":" << static_cast<std::uint64_t>(tr->timestamp())
      << "}";
  return rust::String(oss.str());
}

void wallet2_restore_deterministic_wallet(
  Wallet2Bridge& bridge,
  const std::string& path,
  const std::string& password,
  const std::string& seed,
  std::uint64_t restore_height,
  std::uint8_t network,
  const std::string& daemon
) {
  if (bridge.manager == nullptr) {
    throw std::runtime_error("wallet manager is null");
  }
  if (bridge.wallet != nullptr) {
    clear_pending(bridge);
    bridge.manager->closeWallet(bridge.wallet, true);
    bridge.wallet = nullptr;
  }
  std::string path_s(path);
  std::string pass_s(password);
  std::string seed_s(seed);
  std::string daemon_s(daemon);
  bridge.wallet = bridge.manager->recoveryWallet(
    path_s,
    pass_s,
    seed_s,
    to_network(network),
    restore_height
  );
  if (bridge.wallet == nullptr) {
    throw std::runtime_error(bridge.manager->errorString());
  }
  if (bridge.wallet->status() != Monero::Wallet::Status_Ok) {
    throw std::runtime_error(bridge.wallet->errorString());
  }
  if (!daemon_s.empty()) {
    bridge.wallet->init(daemon_s);
    bridge.wallet->startRefresh();
  }
}

void wallet2_generate_from_keys(
  Wallet2Bridge& bridge,
  const std::string& path,
  const std::string& password,
  const std::string& language,
  std::uint64_t restore_height,
  const std::string& address,
  const std::string& view_key,
  const std::string& spend_key,
  std::uint8_t network,
  const std::string& daemon
) {
  if (bridge.manager == nullptr) {
    throw std::runtime_error("wallet manager is null");
  }
  if (bridge.wallet != nullptr) {
    clear_pending(bridge);
    bridge.manager->closeWallet(bridge.wallet, true);
    bridge.wallet = nullptr;
  }
  std::string path_s(path);
  std::string pass_s(password);
  std::string lang_s(language);
  std::string addr_s(address);
  std::string view_s(view_key);
  std::string spend_s(spend_key);
  std::string daemon_s(daemon);
  bridge.wallet = bridge.manager->createWalletFromKeys(
    path_s,
    pass_s,
    lang_s,
    to_network(network),
    restore_height,
    addr_s,
    view_s,
    spend_s
  );
  if (bridge.wallet == nullptr) {
    throw std::runtime_error(bridge.manager->errorString());
  }
  if (bridge.wallet->status() != Monero::Wallet::Status_Ok) {
    throw std::runtime_error(bridge.wallet->errorString());
  }
  if (!daemon_s.empty()) {
    bridge.wallet->init(daemon_s);
    bridge.wallet->startRefresh();
  }
}

void wallet2_create_wallet(
  Wallet2Bridge& bridge,
  const std::string& path,
  const std::string& password,
  const std::string& language,
  std::uint8_t network,
  const std::string& daemon
) {
  if (bridge.manager == nullptr) {
    throw std::runtime_error("wallet manager is null");
  }
  if (bridge.wallet != nullptr) {
    clear_pending(bridge);
    bridge.manager->closeWallet(bridge.wallet, true);
    bridge.wallet = nullptr;
  }
  std::string path_s(path);
  std::string pass_s(password);
  std::string lang_s(language);
  std::string daemon_s(daemon);
  bridge.wallet = bridge.manager->createWallet(path_s, pass_s, lang_s, to_network(network));
  if (bridge.wallet == nullptr) {
    throw std::runtime_error(bridge.manager->errorString());
  }
  if (bridge.wallet->status() != Monero::Wallet::Status_Ok) {
    throw std::runtime_error(bridge.wallet->errorString());
  }
  if (!daemon_s.empty()) {
    bridge.wallet->init(daemon_s);
    bridge.wallet->startRefresh();
  }
}

bool wallet2_rescan_blockchain(Wallet2Bridge& bridge) {
  if (bridge.wallet == nullptr) {
    throw std::runtime_error("wallet is null");
  }
  return bridge.wallet->rescanBlockchain();
}

bool wallet2_rescan_spent(Wallet2Bridge& bridge) {
  if (bridge.wallet == nullptr) {
    throw std::runtime_error("wallet is null");
  }
  return bridge.wallet->rescanSpent();
}

bool wallet2_import_key_images(const Wallet2Bridge& bridge, const std::string& filename) {
  if (bridge.wallet == nullptr) {
    throw std::runtime_error("wallet is null");
  }
  return bridge.wallet->importKeyImages(filename);
}

rust::String wallet2_stake_prepare_json(
  Wallet2Bridge& bridge,
  const std::string& service_node_key,
  const std::string& amount
) {
  if (bridge.wallet == nullptr) {
    throw std::runtime_error("wallet is null");
  }
  std::string snk(service_node_key);
  std::string amt(amount);
  std::string err;
  Monero::PendingTransaction* ptx = bridge.wallet->stakePending(snk, amt, err);
  if (ptx == nullptr) {
    throw std::runtime_error(err.empty() ? "stakePending failed" : err);
  }
  if (ptx->status() != Monero::PendingTransaction::Status_Ok) {
    std::string e = ptx->errorString();
    bridge.wallet->disposeTransaction(ptx);
    throw std::runtime_error(e.empty() ? "stake pending status error" : e);
  }
  const std::string metadata = ptx->multisigSignData();
  if (metadata.empty()) {
    bridge.wallet->disposeTransaction(ptx);
    throw std::runtime_error("stake: empty tx metadata");
  }
  bridge.pending_by_metadata[metadata] = ptx;
  std::ostringstream oss;
  oss << "{"
      << "\"tx_metadata\":\"" << json_escape(metadata) << "\","
      << "\"fee\":" << ptx->fee()
      << "}";
  return rust::String(oss.str());
}

rust::String wallet2_sweep_all_prepare_json(
  Wallet2Bridge& bridge,
  const std::string& address,
  bool do_not_relay
) {
  if (bridge.wallet == nullptr) {
    throw std::runtime_error("wallet is null");
  }
  std::string dst(address);
  Monero::optional<uint64_t> amount;
  std::set<uint32_t> subaddr_indices;
  Monero::PendingTransaction* ptx = bridge.wallet->createTransaction(
    dst,
    "",
    amount,
    0,
    Monero::PendingTransaction::Priority_Low,
    0,
    subaddr_indices
  );
  if (ptx == nullptr) {
    throw std::runtime_error("sweep_all: createTransaction returned null");
  }
  if (ptx->status() != Monero::PendingTransaction::Status_Ok) {
    std::string e = ptx->errorString();
    bridge.wallet->disposeTransaction(ptx);
    throw std::runtime_error(e.empty() ? "sweep_all pending status error" : e);
  }
  std::vector<std::string> txids = ptx->txid();
  const std::string txh = txids.empty() ? "" : txids.front();
  const uint64_t fee = ptx->fee();
  if (do_not_relay) {
    const std::string metadata = ptx->multisigSignData();
    if (metadata.empty()) {
      bridge.wallet->disposeTransaction(ptx);
      throw std::runtime_error("sweep_all: empty tx metadata");
    }
    bridge.pending_by_metadata[metadata] = ptx;
    std::ostringstream oss;
    oss << "{"
        << "\"tx_metadata_list\":[\"" << json_escape(metadata) << "\"],"
        << "\"tx_hash_list\":[\"" << json_escape(txh) << "\"],"
        << "\"fee_list\":[" << fee << "]"
        << "}";
    return rust::String(oss.str());
  }
  if (!ptx->commit()) {
    std::string e = ptx->errorString();
    bridge.wallet->disposeTransaction(ptx);
    throw std::runtime_error(e.empty() ? "sweep_all commit failed" : e);
  }
  bridge.wallet->disposeTransaction(ptx);
  std::ostringstream oss;
  oss << "{"
      << "\"tx_hash_list\":[\"" << json_escape(txh) << "\"],"
      << "\"fee_list\":[" << fee << "]"
      << "}";
  return rust::String(oss.str());
}

rust::String wallet2_relay_tx_json(Wallet2Bridge& bridge, const std::string& metadata_hex) {
  if (bridge.wallet == nullptr) {
    throw std::runtime_error("wallet is null");
  }
  auto it = bridge.pending_by_metadata.find(metadata_hex);
  if (it == bridge.pending_by_metadata.end() || it->second == nullptr) {
    throw std::runtime_error("relay_tx: unknown tx metadata");
  }
  Monero::PendingTransaction* ptx = it->second;
  std::vector<std::string> txids = ptx->txid();
  const std::string txh = txids.empty() ? "" : txids.front();
  if (!ptx->commit()) {
    throw std::runtime_error(ptx->errorString());
  }
  bridge.wallet->disposeTransaction(ptx);
  bridge.pending_by_metadata.erase(it);
  std::ostringstream oss;
  oss << "{"
      << "\"tx_hash\":\"" << json_escape(txh) << "\""
      << "}";
  return rust::String(oss.str());
}

rust::String wallet2_get_accounts_json(const Wallet2Bridge& bridge, std::uint32_t) {
  if (bridge.wallet == nullptr) {
    throw std::runtime_error("wallet is null");
  }
  auto* sa = bridge.wallet->subaddressAccount();
  if (sa == nullptr) {
    return rust::String("{\"subaddress_accounts\":[]}");
  }
  sa->refresh();
  auto rows = sa->getAll();
  std::ostringstream oss;
  oss << "{\"subaddress_accounts\":[";
  bool first = true;
  for (const auto* row : rows) {
    if (!row) continue;
    if (!first) oss << ",";
    first = false;
    oss << "{"
        << "\"account_index\":" << row->getRowId() << ","
        << "\"base_address\":\"" << json_escape(row->getAddress()) << "\","
        << "\"label\":\"" << json_escape(row->getLabel()) << "\","
        << "\"balance\":" << row->getBalance() << ","
        << "\"unlocked_balance\":" << row->getUnlockedBalance()
        << "}";
  }
  oss << "]}";
  return rust::String(oss.str());
}

rust::String wallet2_create_address_json(Wallet2Bridge& bridge, std::uint32_t account_index, const std::string& label) {
  if (bridge.wallet == nullptr) {
    throw std::runtime_error("wallet is null");
  }
  bridge.wallet->addSubaddress(account_index, label);
  const auto count = bridge.wallet->numSubaddresses(account_index);
  if (count == 0) {
    throw std::runtime_error("create_address: no subaddresses");
  }
  const auto new_index = static_cast<uint32_t>(count - 1);
  auto* s = bridge.wallet->subaddress();
  if (s != nullptr) {
    s->refresh(account_index);
    const auto all = s->getAll();
    for (const auto* row : all) {
      if (!row) continue;
      if (row->getRowId() == new_index) {
        std::ostringstream oss;
        oss << "{"
            << "\"address\":\"" << json_escape(row->getAddress()) << "\","
            << "\"address_index\":" << new_index
            << "}";
        return rust::String(oss.str());
      }
    }
  }
  std::ostringstream oss;
  oss << "{"
      << "\"address\":\"\","
      << "\"address_index\":" << new_index
      << "}";
  return rust::String(oss.str());
}

rust::String wallet2_validate_address_json(const Wallet2Bridge& bridge, const std::string& address, bool any_net_type, bool) {
  if (bridge.wallet == nullptr) {
    throw std::runtime_error("wallet is null");
  }
  const std::string addr(address);
  const auto net = bridge.wallet->nettype();
  bool valid = Monero::Wallet::addressValid(addr, net);
  if (!valid && any_net_type) {
    valid = Monero::Wallet::addressValid(addr, Monero::MAINNET)
      || Monero::Wallet::addressValid(addr, Monero::TESTNET)
      || Monero::Wallet::addressValid(addr, Monero::STAGENET);
  }
  std::ostringstream oss;
  oss << "{"
      << "\"valid\":" << (valid ? "true" : "false") << ","
      << "\"integrated\":" << "false" << ","
      << "\"subaddress\":" << "false" << ","
      << "\"nettype\":" << static_cast<int>(net)
      << "}";
  return rust::String(oss.str());
}

rust::String wallet2_transfer_split_prepare_json(
  Wallet2Bridge& bridge,
  const std::string& address,
  std::uint64_t amount,
  std::uint32_t priority,
  bool do_not_relay
) {
  if (bridge.wallet == nullptr) {
    throw std::runtime_error("wallet is null");
  }
  std::string dst(address);
  Monero::optional<uint64_t> amt(amount);
  std::set<uint32_t> subaddr_indices;
  auto pri = Monero::PendingTransaction::Priority_Low;
  switch (priority) {
    case 2: pri = Monero::PendingTransaction::Priority_Medium; break;
    case 3: pri = Monero::PendingTransaction::Priority_High; break;
    case 0:
    case 1:
    default: pri = Monero::PendingTransaction::Priority_Low; break;
  }
  Monero::PendingTransaction* ptx = bridge.wallet->createTransaction(
    dst,
    "",
    amt,
    0,
    pri,
    0,
    subaddr_indices
  );
  if (ptx == nullptr) {
    throw std::runtime_error("transfer_split: createTransaction returned null");
  }
  if (ptx->status() != Monero::PendingTransaction::Status_Ok) {
    std::string e = ptx->errorString();
    bridge.wallet->disposeTransaction(ptx);
    throw std::runtime_error(e.empty() ? "transfer_split pending status error" : e);
  }
  std::vector<std::string> txids = ptx->txid();
  const std::string txh = txids.empty() ? "" : txids.front();
  const uint64_t fee = ptx->fee();
  if (do_not_relay) {
    const std::string metadata = ptx->multisigSignData();
    if (metadata.empty()) {
      bridge.wallet->disposeTransaction(ptx);
      throw std::runtime_error("transfer_split: empty tx metadata");
    }
    bridge.pending_by_metadata[metadata] = ptx;
    std::ostringstream oss;
    oss << "{"
        << "\"tx_metadata_list\":[\"" << json_escape(metadata) << "\"],"
        << "\"tx_hash_list\":[\"" << json_escape(txh) << "\"],"
        << "\"fee_list\":[" << fee << "]"
        << "}";
    return rust::String(oss.str());
  }
  if (!ptx->commit()) {
    std::string e = ptx->errorString();
    bridge.wallet->disposeTransaction(ptx);
    throw std::runtime_error(e.empty() ? "transfer_split commit failed" : e);
  }
  bridge.wallet->disposeTransaction(ptx);
  std::ostringstream oss;
  oss << "{"
      << "\"tx_hash_list\":[\"" << json_escape(txh) << "\"],"
      << "\"fee_list\":[" << fee << "]"
      << "}";
  return rust::String(oss.str());
}

rust::String wallet2_get_transfers_json(
  const Wallet2Bridge& bridge,
  bool in_flag,
  bool out_flag,
  bool pending_flag,
  bool failed_flag,
  bool pool_flag,
  std::uint64_t min_height,
  std::uint64_t max_height
) {
  if (bridge.wallet == nullptr) {
    throw std::runtime_error("wallet is null");
  }
  auto* hist = bridge.wallet->history();
  if (hist == nullptr) {
    return rust::String("{\"in\":[],\"out\":[],\"pending\":[],\"failed\":[],\"pool\":[]}");
  }
  hist->refresh();
  const auto all = hist->getAll();
  std::ostringstream in_s, out_s, pending_s, failed_s, pool_s;
  in_s << "[";
  out_s << "[";
  pending_s << "[";
  failed_s << "[";
  pool_s << "[";
  bool in_first = true, out_first = true, pending_first = true, failed_first = true, pool_first = true;
  for (const auto* tx : all) {
    if (!tx) continue;
    const uint64_t h = tx->blockHeight();
    if (h < min_height || h > max_height) continue;
    std::ostringstream row;
    row << "{"
        << "\"amount\":" << tx->amount() << ","
        << "\"fee\":" << tx->fee() << ","
        << "\"height\":" << h << ","
        << "\"timestamp\":" << static_cast<std::uint64_t>(tx->timestamp()) << ","
        << "\"txid\":\"" << json_escape(tx->hash()) << "\","
        << "\"payment_id\":\"" << json_escape(tx->paymentId()) << "\","
        << "\"type\":\"" << (tx->direction() == Monero::TransactionInfo::Direction_In ? "in" : "out") << "\""
        << "}";
    const std::string row_s = row.str();
    if (tx->isFailed()) {
      if (failed_flag) {
        if (!failed_first) failed_s << ",";
        failed_first = false;
        failed_s << row_s;
      }
      continue;
    }
    if (tx->isPending()) {
      if (pending_flag) {
        if (!pending_first) pending_s << ",";
        pending_first = false;
        pending_s << row_s;
      }
      if (pool_flag) {
        if (!pool_first) pool_s << ",";
        pool_first = false;
        pool_s << row_s;
      }
      continue;
    }
    if (tx->direction() == Monero::TransactionInfo::Direction_In) {
      if (in_flag) {
        if (!in_first) in_s << ",";
        in_first = false;
        in_s << row_s;
      }
    } else {
      if (out_flag) {
        if (!out_first) out_s << ",";
        out_first = false;
        out_s << row_s;
      }
    }
  }
  in_s << "]";
  out_s << "]";
  pending_s << "]";
  failed_s << "]";
  pool_s << "]";
  std::ostringstream oss;
  oss << "{"
      << "\"in\":" << in_s.str() << ","
      << "\"out\":" << out_s.str() << ","
      << "\"pending\":" << pending_s.str() << ","
      << "\"failed\":" << failed_s.str() << ","
      << "\"pool\":" << pool_s.str()
      << "}";
  return rust::String(oss.str());
}

rust::String wallet2_register_service_node_json(Wallet2Bridge& bridge, const std::string& register_service_node_str) {
  (void) bridge;
  (void) register_service_node_str;
  return rust::String("{\"error\":{\"code\":-32603,\"message\":\"register_service_node unavailable in current native build\"}}");
}

rust::String wallet2_can_request_stake_unlock_json(Wallet2Bridge& bridge, const std::string& service_node_key) {
  (void) bridge;
  (void) service_node_key;
  return rust::String("{\"can_unlock\":false,\"msg\":\"can_request_stake_unlock unavailable in current native build\"}");
}

rust::String wallet2_request_stake_unlock_json(Wallet2Bridge& bridge, const std::string& service_node_key) {
  (void) bridge;
  (void) service_node_key;
  return rust::String("{\"unlocked\":false,\"msg\":\"request_stake_unlock unavailable in current native build\"}");
}

std::uint64_t wallet2_height(const Wallet2Bridge& bridge) {
  if (bridge.wallet == nullptr) {
    throw std::runtime_error("wallet is null");
  }
  return bridge.wallet->blockChainHeight();
}

std::uint64_t wallet2_balance(const Wallet2Bridge& bridge) {
  if (bridge.wallet == nullptr) {
    throw std::runtime_error("wallet is null");
  }
  return bridge.wallet->balanceAll();
}

std::uint64_t wallet2_unlocked_balance(const Wallet2Bridge& bridge) {
  if (bridge.wallet == nullptr) {
    throw std::runtime_error("wallet is null");
  }
  return bridge.wallet->unlockedBalanceAll();
}

// `cryptonote_core` in `libwallet_merged.a` references `windows::check_admin` from
// `daemonizer/windows_service.cpp`; some CMake targets omit that TU from `wallet_merged`.
#if defined(WIN32)
#undef UNICODE
#undef _UNICODE
#include <windows.h>
namespace windows {
bool check_admin(bool& result) {
  BOOL is_member = FALSE;
  PSID admin_group = nullptr;
  SID_IDENTIFIER_AUTHORITY nt_auth = SECURITY_NT_AUTHORITY;
  if (AllocateAndInitializeSid(&nt_auth, 2, SECURITY_BUILTIN_DOMAIN_RID,
          DOMAIN_ALIAS_RID_ADMINS, 0, 0, 0, 0, 0, 0, &admin_group)) {
    CheckTokenMembership(nullptr, admin_group, &is_member);
    FreeSid(admin_group);
  }
  result = is_member != FALSE;
  return true;
}
}
#endif

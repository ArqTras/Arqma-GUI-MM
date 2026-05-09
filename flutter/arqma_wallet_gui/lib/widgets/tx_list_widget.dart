import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../core/app_api.dart';
import '../i18n/locale_controller.dart';
import '../store/gateway_store.dart';
import 'format_arqma.dart';
import 'tx_details_dialog.dart';
import 'tx_type_icon.dart';

/// Parity with `components/tx_list.vue` (list, type labels, context actions).
class TxListWidget extends StatelessWidget {
  const TxListWidget({
    super.key,
    this.limit = -1,
    this.filterAddress,
    this.filterAddressMinor,
    this.shrinkWrap = false,
  });

  /// `-1` = no cap (same as Vue `limit: -1`).
  final int limit;

  /// When set, lists transactions related to this address (like the Vue
  /// `set_transactions_filter` used from address book details).
  final String? filterAddress;

  /// Optional `minor` subaddress index from the address book entry.
  final int? filterAddressMinor;

  /// Use inside dialogs / unbounded parents.
  final bool shrinkWrap;

  /// Used by [TxListWidget] rows and [showTxDetailsDialog] for consistent labels.
  static String typeLabelForTx(LocaleController loc, String? type) {
    switch (type) {
      case 'in':
        return loc.tr('components.tx_list.received');
      case 'out':
        return loc.tr('components.tx_list.sent');
      case 'failed':
        return loc.tr('components.tx_list.failed');
      case 'pending':
        return loc.tr('components.tx_list.pending');
      case 'pool':
        return loc.tr('components.tx_list.pending');
      case 'miner':
        return loc.tr('components.tx_list.miner');
      case 'snode':
        return loc.tr('components.tx_list.service_node');
      case 'stake':
        return loc.tr('components.tx_list.stake');
      case 'net':
        return loc.tr('components.tx_list.network');
      default:
        return type ?? '';
    }
  }

  static bool _txMatchesAddressFilter(Map<String, dynamic> tx, String address, int? minorExpected) {
    final Object? si = tx['subaddr_index'];
    if (minorExpected != null && si is Map) {
      final int? m = (si['minor'] as num?)?.toInt();
      if (m == minorExpected) {
        return true;
      }
    }
    final Object? dest = tx['destinations'];
    if (dest is List<dynamic>) {
      for (final Object? d in dest) {
        if (d is Map && '${d['address']}' == address) {
          return true;
        }
      }
    }
    return false;
  }

  static List<dynamic> _transactionsForDisplay(
    GatewayStore store, {
    required String? filterAddress,
    required int? filterAddressMinor,
    required int limit,
  }) {
    final List<dynamic> raw =
        ((store.wallet['transactions'] as Map?)?['tx_list'] as List<dynamic>?) ?? const <dynamic>[];
    Iterable<dynamic> txs = raw;
    if (filterAddress != null && filterAddress.isNotEmpty) {
      txs = txs.where(
        (dynamic x) => _txMatchesAddressFilter(Map<String, dynamic>.from(x as Map), filterAddress, filterAddressMinor),
      );
    } else {
      txs = store.filteredTransactions;
    }
    if (limit > 0) {
      txs = txs.take(limit);
    }
    return txs.toList();
  }

  static String _formatHeight(LocaleController loc, Map<String, dynamic> tx, int walletHeight) {
    final int height = int.tryParse('${tx['height'] ?? 0}') ?? 0;
    final int unlockTime = int.tryParse('${tx['unlock_time'] ?? 0}') ?? 0;
    final int confirms = (walletHeight - height).clamp(0, 1 << 30);
    if (height == 0) {
      return loc.tr('components.tx_list.pending');
    }
    final int thresh = unlockTime > height ? (unlockTime - height) : 10;
    if (confirms < thresh) {
      final String plural = confirms == 1 ? '' : 's';
      return '${loc.tr('components.tx_list.height')} $height ($confirms ${loc.tr('components.tx_list.confirm')}$plural)';
    }
    return '${loc.tr('components.tx_list.height')} $height ${loc.tr('components.tx_list.confirmed')}';
  }

  @override
  Widget build(BuildContext context) {
    final LocaleController loc = context.watch<LocaleController>();
    final GatewayStore store = context.watch<GatewayStore>();
    final List<dynamic> txs = _transactionsForDisplay(
      store,
      filterAddress: filterAddress,
      filterAddressMinor: filterAddressMinor,
      limit: limit,
    );
    if (txs.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(loc.tr('components.tx_list.no_transactions_found')),
      );
    }
    return ListView.separated(
      shrinkWrap: shrinkWrap,
      physics: shrinkWrap ? const ClampingScrollPhysics() : null,
      itemCount: txs.length,
      separatorBuilder: (_, __) => const Divider(height: 1, color: Colors.white12),
      itemBuilder: (BuildContext context, int i) {
        final Map<String, dynamic> tx = Map<String, dynamic>.from(txs[i] as Map);
        final String type = '${tx['type'] ?? ''}';
        final int wh = int.tryParse('${store.walletInfo['height'] ?? 0}') ?? 0;
        final int ts = int.tryParse('${tx['timestamp'] ?? 0}') ?? 0;
        final DateTime dt = DateTime.fromMillisecondsSinceEpoch(ts * 1000, isUtc: true).toLocal();
        final String timeAgo = timeago.format(dt);
        return ListTile(
          leading: SizedBox(
            width: 86,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                TxTypeIcon(type: type, tooltip: true, mainSize: 28),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    typeLabelForTx(loc, type),
                    style: const TextStyle(fontSize: 10, height: 1.15),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          title: FormatArqma(amount: num.tryParse('${tx['amount'] ?? 0}') ?? 0, digits: 5),
          subtitle: Text('${tx['txid']}', style: const TextStyle(fontFamily: 'monospace', fontSize: 10)),
          trailing: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(timeAgo, style: const TextStyle(fontSize: 11)),
              Text(_formatHeight(loc, tx, wh), style: const TextStyle(fontSize: 10, color: Colors.white54)),
            ],
          ),
          onTap: () => showTxDetailsDialog(context, tx),
          onLongPress: () async {
            await showModalBottomSheet<void>(
              context: context,
              backgroundColor: const Color(0xFF1d1d1d),
              builder: (BuildContext c) => SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      title: Text(loc.tr('components.tx_list.show_details')),
                      onTap: () {
                        Navigator.pop(c);
                        showTxDetailsDialog(context, tx);
                      },
                    ),
                    ListTile(
                      title: Text(loc.tr('components.tx_list.copy_transaction_id')),
                      onTap: () async {
                        await context.read<AppApi>().writeText('${tx['txid']}');
                        if (c.mounted) {
                          Navigator.pop(c);
                        }
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(loc.tr('components.tx_list.copied_transaction_id_to_clipboard'))),
                          );
                        }
                      },
                    ),
                    ListTile(
                      title: Text(loc.tr('components.tx_list.view_on_explorer')),
                      onTap: () async {
                        await context.read<AppApi>().send('core', 'open_explorer', <String, dynamic>{
                          'type': 'tx',
                          'id': '${tx['txid']}',
                        });
                        if (c.mounted) {
                          Navigator.pop(c);
                        }
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

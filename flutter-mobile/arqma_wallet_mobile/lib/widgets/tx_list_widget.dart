import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../core/app_api.dart';
import '../core/mobile/mobile_responsive_layout.dart';
import '../core/wallet_daemon_tip_tolerance.dart';
import '../i18n/locale_controller.dart';
import '../store/gateway_store.dart';
import 'format_arqma.dart';
import 'tx_details_dialog.dart';
import 'tx_type_icon.dart';
import '../core/theme/arqma_colors.dart';

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

  static bool _txMatchesAddressFilter(
      Map<String, dynamic> tx, String address, int? minorExpected) {
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

  static Object _txListChangeToken(List<Map<String, dynamic>> list) {
    if (list.isEmpty) {
      return 0;
    }
    int token = list.length;
    for (final Map<String, dynamic> x in list) {
      token = Object.hash(
        token,
        x['txid'],
        x['type'],
        x['height'],
        x['amount'],
        x['timestamp'],
      );
    }
    return token;
  }

  static List<dynamic> _transactionsForDisplay(
    GatewayStore store, {
    required String? filterAddress,
    required int? filterAddressMinor,
    required int limit,
  }) {
    final List<dynamic> raw = ((store.wallet['transactions']
            as Map?)?['tx_list'] as List<dynamic>?) ??
        const <dynamic>[];
    Iterable<dynamic> txs = raw;
    if (filterAddress != null && filterAddress.isNotEmpty) {
      txs = txs.where(
        (dynamic x) => _txMatchesAddressFilter(
            Map<String, dynamic>.from(x as Map),
            filterAddress,
            filterAddressMinor),
      );
    } else {
      txs = store.filteredTransactions;
    }
    if (limit > 0) {
      txs = txs.take(limit);
    }
    return txs.toList();
  }

  /// Notes / payment id — same fields Vue `tx_details` / `tx_list` uses for context.
  static String? _txContextCaption(Map<String, dynamic> tx) {
    final String note = '${tx['note'] ?? tx['description'] ?? ''}'.trim();
    if (note.isNotEmpty) {
      return note.length > 96 ? '${note.substring(0, 93)}…' : note;
    }
    final String pid = '${tx['payment_id'] ?? ''}'.trim();
    if (pid.isNotEmpty && !RegExp(r'^[0\s]+$').hasMatch(pid)) {
      final String short = pid.length > 16 ? pid.substring(0, 16) : pid;
      return pid.length > 16 ? '$short…' : short;
    }
    return null;
  }

  /// Note / payment id, or for non-plain `type` (snode, stake, …) the translated type line.
  static String? _txSubtitleExtra(
      LocaleController loc, Map<String, dynamic> tx) {
    final String? cap = _txContextCaption(tx);
    if (cap != null) {
      return cap;
    }
    final String type = '${tx['type'] ?? ''}'.trim();
    const Set<String> plain = <String>{'in', 'out', 'pending', 'failed', ''};
    if (plain.contains(type)) {
      return null;
    }
    return typeLabelForTx(loc, type.isEmpty ? null : type);
  }

  static String _formatHeight(
      LocaleController loc, Map<String, dynamic> tx, int walletHeight) {
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

  static Widget _buildTxListRow({
    required BuildContext context,
    required LocaleController loc,
    required Map<String, dynamic> tx,
    required String type,
    required int walletHeight,
    required String timeAgo,
    required VoidCallback onTap,
    required VoidCallback onLongPress,
  }) {
    final double layoutWidth = MobileResponsiveLayout.contentWidth(context);
    final EdgeInsets rowPadding = MobileResponsiveLayout.listHorizontalPadding(
      layoutWidth,
    ).copyWith(top: 10, bottom: 10);
    final String? extra = _txSubtitleExtra(loc, tx);
    final String txid = '${tx['txid'] ?? ''}'.trim();
    final String heightLine = _formatHeight(loc, tx, walletHeight);
    const TextStyle metaStyle = TextStyle(
      fontSize: 10,
      color: ArqmaColors.textMuted,
      height: 1.2,
    );
    const TextStyle txidStyle = TextStyle(
      fontFamily: 'monospace',
      fontSize: 11,
      height: 1.25,
      color: ArqmaColors.textSecondary,
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: rowPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TxTypeIcon(type: type, tooltip: true, mainSize: 28),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                typeLabelForTx(loc, type),
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  height: 1.2,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            FormatArqma(
                              amount:
                                  num.tryParse('${tx['amount'] ?? 0}') ?? 0,
                              digits: 5,
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                timeAgo,
                                style: const TextStyle(fontSize: 11),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                heightLine,
                                style: metaStyle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.end,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (txid.isNotEmpty) ...[
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.only(left: 38),
                  child: Text(
                    MobileResponsiveLayout.txidListLabel(txid, layoutWidth),
                    style: txidStyle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                  ),
                ),
              ],
              if (extra != null)
                Padding(
                  padding: const EdgeInsets.only(left: 38, top: 4),
                  child: Text(
                    extra,
                    style: metaStyle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Banner when the wallet height is still far below the daemon tip (same rule as [GatewayStore] / footer).
  static Widget _walletScanProgressBanner(
    LocaleController loc, {
    required int walletH,
    required int daemonTip,
    required bool fullRescanUi,
  }) {
    final int gapBlocks = daemonTip > 0
        ? (daemonTip - walletH).clamp(0, 1 << 62)
        : 0;
    final double pctRaw =
        daemonTip > 0 ? (100.0 * walletH) / daemonTip : 0.0;
    final double pct = pctRaw.clamp(0.0, 100.0);
    final String pctLabel =
        pct >= 10 ? pct.toStringAsFixed(1) : pct.toStringAsFixed(2);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double layoutWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MobileResponsiveLayout.contentWidth(context);
        final EdgeInsets bannerPad =
            MobileResponsiveLayout.listHorizontalPadding(layoutWidth)
                .copyWith(top: 14, bottom: 14);
        return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: ArqmaColors.outlineBright.withValues(alpha: 0.55),
        ),
        color: const Color(0xFF161410),
      ),
      child: Padding(
        padding: bannerPad,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: ArqmaColors.warning,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    loc.tr('pages.wallet.txhistory.scan_progress_title'),
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      height: 1.25,
                      color: ArqmaColors.warning,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: daemonTip > 0 && walletH > 0 ? pct / 100.0 : null,
                minHeight: 7,
                backgroundColor: ArqmaColors.outlineDefault
                    .withValues(alpha: 0.45),
                color: ArqmaColors.arqmaGreenSolid,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              fullRescanUi
                  ? loc.tr(
                      'pages.wallet.txhistory.scan_progress_rescan_detail',
                      named: <String, String>{
                        'current': '$walletH',
                        'target': '$daemonTip',
                        'pct': pctLabel,
                        'left': '$gapBlocks',
                      },
                    )
                  : loc.tr(
                      'pages.wallet.txhistory.scan_progress_detail',
                      named: <String, String>{
                        'current': '$walletH',
                        'target': '$daemonTip',
                        'pct': pctLabel,
                        'left': '$gapBlocks',
                      },
                    ),
              style: const TextStyle(
                fontSize: 13,
                height: 1.4,
                color: ArqmaColors.textSecondary,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              loc.tr('pages.wallet.txhistory.scan_progress_hint'),
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                color: ArqmaColors.textMuted.withValues(alpha: 0.92),
              ),
            ),
          ],
        ),
      ),
    );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final LocaleController loc = context.watch<LocaleController>();
    return Selector<GatewayStore, _TxListUiSnapshot>(
      selector: (_, GatewayStore store) => _TxListUiSnapshot.from(
        store,
        filterAddress: filterAddress,
        filterAddressMinor: filterAddressMinor,
        limit: limit,
      ),
      builder: (BuildContext context, _TxListUiSnapshot snap, Widget? _) {
        return _TxListBody(
          loc: loc,
          snap: snap,
          shrinkWrap: shrinkWrap,
        );
      },
    );
  }
}

final class _TxListUiSnapshot {
  const _TxListUiSnapshot({
    required this.txs,
    required this.walletHeight,
    required this.daemonTip,
    required this.fullRescanUi,
    required this.showScanProgress,
    required this.transactionsRevision,
    required this.filterIndex,
    required this.tidFilter,
    required this.filterAddress,
    required this.filterAddressMinor,
    required this.limit,
  });

  final List<Map<String, dynamic>> txs;
  final int walletHeight;
  final int daemonTip;
  final bool fullRescanUi;
  final bool showScanProgress;
  final int transactionsRevision;
  final int filterIndex;
  final String tidFilter;
  final String? filterAddress;
  final int? filterAddressMinor;
  final int limit;

  static _TxListUiSnapshot from(
    GatewayStore store, {
    required String? filterAddress,
    required int? filterAddressMinor,
    required int limit,
  }) {
    final List<dynamic> rawTxs = TxListWidget._transactionsForDisplay(
      store,
      filterAddress: filterAddress,
      filterAddressMinor: filterAddressMinor,
      limit: limit,
    );
    final List<Map<String, dynamic>> txs = rawTxs
        .map((dynamic x) => Map<String, dynamic>.from(x as Map))
        .toList(growable: false);
    final Map<String, dynamic> daemonInfo =
        store.daemon['info'] as Map<String, dynamic>? ?? {};
    final int daemonTip = () {
      final num h = num.tryParse('${daemonInfo['height']}') ?? 0;
      final num th = num.tryParse('${daemonInfo['target_height']}') ?? 0;
      return (h > th ? h : th).toInt();
    }();
    final int walletH =
        (num.tryParse('${store.walletInfo['height']}') ?? 0).round();
    final int gapBlocks = daemonTip > 0
        ? (daemonTip - walletH).clamp(0, 1 << 62)
        : 0;
    final bool fullRescanUi = store.walletInfo['full_rescan_ui'] == true;
    final bool scanningBehind =
        daemonTip > 0 && gapBlocks > kWalletDaemonTipToleranceBlocks;
    final Map<String, dynamic> tf =
        store.raw['transactions_filter'] as Map<String, dynamic>? ??
            const <String, dynamic>{};
    final Map<String, dynamic> tid =
        store.raw['transaction_id_filter'] as Map<String, dynamic>? ??
            const <String, dynamic>{};
    return _TxListUiSnapshot(
      txs: txs,
      walletHeight: walletH,
      daemonTip: daemonTip,
      fullRescanUi: fullRescanUi,
      showScanProgress: scanningBehind || fullRescanUi,
      transactionsRevision: store.transactionsRevision,
      filterIndex: tf['index'] as int? ?? 0,
      tidFilter: '${tid['value'] ?? ''}',
      filterAddress: filterAddress,
      filterAddressMinor: filterAddressMinor,
      limit: limit,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is _TxListUiSnapshot &&
        other.walletHeight == walletHeight &&
        other.daemonTip == daemonTip &&
        other.fullRescanUi == fullRescanUi &&
        other.showScanProgress == showScanProgress &&
        other.transactionsRevision == transactionsRevision &&
        other.filterIndex == filterIndex &&
        other.tidFilter == tidFilter &&
        other.filterAddress == filterAddress &&
        other.filterAddressMinor == filterAddressMinor &&
        other.limit == limit &&
        TxListWidget._txListChangeToken(other.txs) ==
            TxListWidget._txListChangeToken(txs);
  }

  @override
  int get hashCode => Object.hash(
        walletHeight,
        daemonTip,
        fullRescanUi,
        showScanProgress,
        transactionsRevision,
        filterIndex,
        tidFilter,
        filterAddress,
        filterAddressMinor,
        limit,
        TxListWidget._txListChangeToken(txs),
      );
}

class _TxListBody extends StatelessWidget {
  const _TxListBody({
    required this.loc,
    required this.snap,
    required this.shrinkWrap,
  });

  final LocaleController loc;
  final _TxListUiSnapshot snap;
  final bool shrinkWrap;

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> txs = snap.txs;
    final int walletH = snap.walletHeight;
    final int daemonTip = snap.daemonTip;
    final bool fullRescanUi = snap.fullRescanUi;
    final bool showScanProgress = snap.showScanProgress;

    if (txs.isEmpty && !showScanProgress) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(loc.tr('components.tx_list.no_transactions_found')),
      );
    }

    if (txs.isEmpty && showScanProgress) {
      return SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: TxListWidget._walletScanProgressBanner(
            loc,
            walletH: walletH,
            daemonTip: daemonTip,
            fullRescanUi: fullRescanUi,
          ),
        ),
      );
    }

    final Widget listView = ListView.separated(
      shrinkWrap: shrinkWrap,
      physics: shrinkWrap ? const ClampingScrollPhysics() : null,
      cacheExtent: 480,
      itemCount: txs.length,
      separatorBuilder: (BuildContext context, int index) =>
          const Divider(height: 1, color: ArqmaColors.outlineSubtle),
      itemBuilder: (BuildContext context, int i) {
        final Map<String, dynamic> tx = txs[i];
        final String type = '${tx['type'] ?? ''}';
        final int ts = int.tryParse('${tx['timestamp'] ?? 0}') ?? 0;
        final DateTime dt =
            DateTime.fromMillisecondsSinceEpoch(ts * 1000, isUtc: true)
                .toLocal();
        final String timeAgo = timeago.format(dt);
        final String txid = '${tx['txid'] ?? ''}'.trim();
        return KeyedSubtree(
          key: ValueKey<String>(txid.isEmpty ? 'tx-$i' : txid),
          child: RepaintBoundary(
            child: TxListWidget._buildTxListRow(
              context: context,
              loc: loc,
              tx: tx,
              type: type,
              walletHeight: walletH,
              timeAgo: timeAgo,
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
                          title:
                              Text(loc.tr('components.tx_list.show_details')),
                          onTap: () {
                            Navigator.pop(c);
                            showTxDetailsDialog(context, tx);
                          },
                        ),
                        ListTile(
                          title: Text(loc
                              .tr('components.tx_list.copy_transaction_id')),
                          onTap: () async {
                            await context
                                .read<AppApi>()
                                .writeText('${tx['txid']}');
                            if (c.mounted) {
                              Navigator.pop(c);
                            }
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                    content: Text(loc.tr(
                                        'components.tx_list.copied_transaction_id_to_clipboard'))),
                              );
                            }
                          },
                        ),
                        ListTile(
                          title: Text(
                              loc.tr('components.tx_list.view_on_explorer')),
                          onTap: () async {
                            await context
                                .read<AppApi>()
                                .send('core', 'open_explorer', <String, dynamic>{
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
            ),
          ),
        );
      },
    );
    if (!showScanProgress) {
      return listView;
    }
    final Widget banner = Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: TxListWidget._walletScanProgressBanner(
        loc,
        walletH: walletH,
        daemonTip: daemonTip,
        fullRescanUi: fullRescanUi,
      ),
    );
    if (shrinkWrap) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          banner,
          listView,
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        banner,
        Expanded(child: listView),
      ],
    );
  }
}

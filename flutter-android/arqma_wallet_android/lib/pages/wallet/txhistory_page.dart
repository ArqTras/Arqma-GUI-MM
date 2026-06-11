import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../i18n/locale_controller.dart';
import '../../store/gateway_store.dart';
import '../../core/mobile/mobile_responsive_layout.dart';
import '../../core/mobile/wallet_activity.dart';
import '../../widgets/arqma_field.dart';
import '../../widgets/tx_list_widget.dart';
import '../../core/theme/arqma_colors.dart';

/// Parity with `pages/wallet/txhistory.vue`.
class TxHistoryPage extends StatefulWidget {
  const TxHistoryPage({super.key});

  @override
  State<TxHistoryPage> createState() => _TxHistoryPageState();
}

class _TxHistoryPageState extends State<TxHistoryPage>
    with WidgetsBindingObserver {
  final TextEditingController _txid = TextEditingController();
  int _typeIndex = 0;
  Timer? _txidDebounce;

  static const List<Map<String, dynamic>> _typeOptions = <Map<String, dynamic>>[
    <String, dynamic>{'index': 0, 'label': 'pages.wallet.txhistory.all'},
    <String, dynamic>{'index': 1, 'label': 'pages.wallet.txhistory.incoming'},
    <String, dynamic>{'index': 2, 'label': 'pages.wallet.txhistory.outgoing'},
    <String, dynamic>{'index': 3, 'label': 'pages.wallet.txhistory.pending'},
    <String, dynamic>{
      'index': 4,
      'label': 'pages.wallet.txhistory.service_node'
    },
    <String, dynamic>{'index': 5, 'label': 'pages.wallet.txhistory.stake'},
    <String, dynamic>{'index': 6, 'label': 'pages.wallet.txhistory.failed'},
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final GatewayStore s = context.read<GatewayStore>();
      final Map<String, dynamic> cur =
          Map<String, dynamic>.from(s.raw['transactions_filter'] as Map? ?? {});
      final int idx = cur['index'] as int? ?? 0;
      final Map<String, dynamic> tid = Map<String, dynamic>.from(
          s.raw['transaction_id_filter'] as Map? ?? {});
      final String v = '${tid['value'] ?? ''}';
      setState(() {
        if (_typeOptions.any((Map<String, dynamic> e) => e['index'] == idx)) {
          _typeIndex = idx;
        }
      });
      if (v.isNotEmpty) {
        _txid.text = v;
      }
      // Keep store filters aligned with the text field + dropdown on first paint (Vue watchers do this).
      _pushFilter();
    });
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _txidDebounce?.cancel();
    final String tidSnapshot = _txid.text.trim();
    final int typeSnapshot = _typeIndex;
    _txid.dispose();
    try {
      final GatewayStore s = context.read<GatewayStore>();
      final Map<String, dynamic> opt = Map<String, dynamic>.from(
        _typeOptions
            .firstWhere((Map<String, dynamic> e) => e['index'] == typeSnapshot),
      );
      s.setTransactionsFilter(opt);
      s.setTransactionIdFilter(<String, dynamic>{
        'index': 7,
        'label': 'Transaction',
        'value': tidSnapshot
      });
    } catch (_) {
      // Provider tree may already be torn down.
    }
    super.dispose();
  }

  void _scheduleTxidFilter() {
    _txidDebounce?.cancel();
    _txidDebounce = Timer(const Duration(milliseconds: 280), () {
      if (!mounted) {
        return;
      }
      _pushFilter();
    });
  }

  void _pushFilter() {
    final GatewayStore s = context.read<GatewayStore>();
    final Map<String, dynamic> opt = Map<String, dynamic>.from(_typeOptions
        .firstWhere((Map<String, dynamic> e) => e['index'] == _typeIndex));
    s.setTransactionsFilter(opt);
    s.setTransactionIdFilter(<String, dynamic>{
      'index': 7,
      'label': 'Transaction',
      'value': _txid.text.trim()
    });
  }

  Widget _txidFilterField(LocaleController loc, {bool stretchContent = true}) {
    return ArqmaField(
      stretchContent: stretchContent,
      goldChrome: true,
      label: loc.tr('pages.wallet.txhistory.filter_by_transactionid'),
      disableMenu: false,
      child: TextField(
        controller: _txid,
        style: const TextStyle(
          fontSize: 13,
          color: ArqmaColors.textPrimary,
        ),
        decoration: InputDecoration(
          hintText: loc
              .tr('pages.wallet.txhistory.filter_by_transactionid_placeholder'),
          hintStyle: TextStyle(
            fontSize: 13,
            color: ArqmaColors.textMuted.withValues(alpha: 0.9),
          ),
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.zero,
        ),
        onChanged: (_) => _scheduleTxidFilter(),
      ),
    );
  }

  Widget _typeFilterField(LocaleController loc, {bool stretchContent = true}) {
    return ArqmaField(
      stretchContent: stretchContent,
      goldChrome: true,
      label: loc.tr('pages.wallet.txhistory.filter_by_transaction_type'),
      child: InputDecorator(
        decoration: const InputDecoration(border: InputBorder.none),
        child: DropdownButton<int>(
          value: _typeIndex,
          isDense: true,
          isExpanded: true,
          underline: const SizedBox.shrink(),
          style: const TextStyle(
            fontSize: 13,
            color: ArqmaColors.textPrimary,
          ),
          iconEnabledColor: ArqmaColors.arqmaGreenSolid,
          dropdownColor: const Color(0xFF1d1d1d),
          items: _typeOptions
              .map(
                (Map<String, dynamic> o) => DropdownMenuItem<int>(
                  value: o['index'] as int,
                  child: Text(
                    loc.tr(o['label'] as String),
                    style: const TextStyle(
                      fontSize: 13,
                      color: ArqmaColors.textPrimary,
                    ),
                  ),
                ),
              )
              .toList(),
          onChanged: (int? v) {
            if (v != null) {
              setState(() => _typeIndex = v);
              _pushFilter();
            }
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final LocaleController loc = context.watch<LocaleController>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final bool stackFilters =
                  MobileResponsiveLayout.stackFilters(constraints.maxWidth);
              if (stackFilters) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _txidFilterField(loc, stretchContent: false),
                    const SizedBox(height: 10),
                    _typeFilterField(loc, stretchContent: false),
                  ],
                );
              }
              return IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 5, child: _txidFilterField(loc)),
                    const SizedBox(width: 10),
                    Expanded(flex: 4, child: _typeFilterField(loc)),
                  ],
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            loc.tr('pages.wallet.txhistory.transactions'),
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: ArqmaColors.arqmaGreenSolid,
            ),
          ),
        ),
        // `.scroller` in `txhistory.vue`: `max-height: viewport - 400px`.
        Expanded(
          child: LayoutBuilder(
            builder: (BuildContext ctx, BoxConstraints inner) {
              final double viewportH = MediaQuery.sizeOf(ctx).height;
              final double capByVue = (viewportH - 400).clamp(200.0, 9000.0);
              final double maxListH = math.min(inner.maxHeight, capByVue);
              return ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxListH),
                child: NotificationListener<ScrollNotification>(
                  onNotification: (ScrollNotification n) {
                    if (n is ScrollStartNotification ||
                        n is ScrollUpdateNotification) {
                      WalletActivity.setTxListScrolling(true);
                      WalletActivity.markUserInteraction();
                    } else if (n is ScrollEndNotification) {
                      WalletActivity.setTxListScrolling(false);
                    }
                    return false;
                  },
                  child: const TxListWidget(),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

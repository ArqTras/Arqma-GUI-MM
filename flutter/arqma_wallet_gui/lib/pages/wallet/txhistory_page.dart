import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/app_api.dart';
import '../../i18n/locale_controller.dart';
import '../../store/gateway_store.dart';
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

  /// `pages/wallet/txhistory.vue` watcher → `core::set_daysOfTransactions` (now persists `config.json`).
  int _daysOfTransactions = 1;
  Timer? _daysDebounce;
  GatewayStore? _gatewayForDays;

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
      final int days0 = _readDaysOfTransactionsFromStore(s);
      final Map<String, dynamic> cur =
          Map<String, dynamic>.from(s.raw['transactions_filter'] as Map? ?? {});
      final int idx = cur['index'] as int? ?? 0;
      final Map<String, dynamic> tid = Map<String, dynamic>.from(
          s.raw['transaction_id_filter'] as Map? ?? {});
      final String v = '${tid['value'] ?? ''}';
      setState(() {
        _daysOfTransactions = days0;
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
  void didChangeDependencies() {
    super.didChangeDependencies();
    final GatewayStore g = context.read<GatewayStore>();
    if (!identical(_gatewayForDays, g)) {
      _gatewayForDays?.removeListener(_onGatewayStoreForDays);
      _gatewayForDays = g;
      _gatewayForDays!.addListener(_onGatewayStoreForDays);
    }
  }

  void _onGatewayStoreForDays() {
    if (!mounted || _gatewayForDays == null) {
      return;
    }
    final int d = _readDaysOfTransactionsFromStore(_gatewayForDays!);
    if (d != _daysOfTransactions) {
      setState(() => _daysOfTransactions = d);
    }
  }

  static int _readDaysOfTransactionsFromStore(GatewayStore s) {
    final Map<String, dynamic>? pending = s.app['pending_config'] is Map
        ? Map<String, dynamic>.from(s.app['pending_config'] as Map)
        : null;
    final Map<String, dynamic>? conf = s.app['config'] is Map
        ? Map<String, dynamic>.from(s.app['config'] as Map)
        : null;
    final Map<String, dynamic>? box = (pending?['app'] is Map) ? pending : conf;
    final Object? fromNested = (box?['app'] as Map?)?['daysOfTransactions'];
    final Object? fromRoot = s.app['daysOfTransactions'];
    final int d = int.tryParse('$fromNested') ?? int.tryParse('$fromRoot') ?? 1;
    return d.clamp(1, 30);
  }

  void _scheduleDaysToBackend(int v) {
    _daysDebounce?.cancel();
    _daysDebounce = Timer(const Duration(milliseconds: 400), () async {
      if (!mounted) {
        return;
      }
      try {
        await context.read<AppApi>().send(
          'core',
          'set_daysOfTransactions',
          <String, dynamic>{'daysOfTransactions': v},
        );
      } catch (e, st) {
        debugPrint('[TxHistoryPage] set_daysOfTransactions $e\n$st');
      }
    });
  }

  @override
  void dispose() {
    _gatewayForDays?.removeListener(_onGatewayStoreForDays);
    _gatewayForDays = null;
    WidgetsBinding.instance.removeObserver(this);
    _txidDebounce?.cancel();
    _daysDebounce?.cancel();
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

  @override
  Widget build(BuildContext context) {
    final LocaleController loc = context.watch<LocaleController>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                flex: 4,
                child: ArqmaField(
                  label:
                      loc.tr('pages.wallet.txhistory.filter_by_transactionid'),
                  disableMenu: false,
                  child: TextField(
                    controller: _txid,
                    decoration: InputDecoration(
                      hintText: loc.tr(
                          'pages.wallet.txhistory.filter_by_transactionid_placeholder'),
                      border: InputBorder.none,
                    ),
                    onChanged: (_) => _scheduleTxidFilter(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: ArqmaField(
                  label: loc.tr(
                      'components.general_settings.transactions_to_display'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 2,
                          thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 6),
                        ),
                        child: Slider(
                          min: 1,
                          max: 30,
                          divisions: 29,
                          value: _daysOfTransactions.toDouble().clamp(1, 30),
                          label: '$_daysOfTransactions',
                          onChanged: (double x) {
                            final int v = x.round().clamp(1, 30);
                            setState(() => _daysOfTransactions = v);
                            _scheduleDaysToBackend(v);
                          },
                        ),
                      ),
                      Text(
                        '$_daysOfTransactions${loc.tr('components.general_settings.days')}',
                        style: const TextStyle(
                            fontSize: 11, color: ArqmaColors.textMuted),
                        textAlign: TextAlign.right,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: ArqmaField(
                  label: loc
                      .tr('pages.wallet.txhistory.filter_by_transaction_type'),
                  child: DropdownButtonFormField<int>(
                    value: _typeIndex,
                    dropdownColor: const Color(0xFF1d1d1d),
                    decoration: const InputDecoration(border: InputBorder.none),
                    items: _typeOptions
                        .map(
                          (Map<String, dynamic> o) => DropdownMenuItem<int>(
                            value: o['index'] as int,
                            child: Text(loc.tr(o['label'] as String)),
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
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(loc.tr('pages.wallet.txhistory.transactions')),
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
                child: const TxListWidget(),
              );
            },
          ),
        ),
      ],
    );
  }
}

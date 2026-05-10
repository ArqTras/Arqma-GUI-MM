import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../core/app_api.dart';
import '../i18n/locale_controller.dart';
import '../store/gateway_store.dart';
import 'arqma_field.dart';
import 'format_arqma.dart';
import 'tx_type_icon.dart';
import '../core/theme/arqma_colors.dart';

/// Parity with `components/tx_details.vue` (summary, copy ids, explorer, notes).
Future<void> showTxDetailsDialog(
    BuildContext context, Map<String, dynamic> tx) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext c) =>
        _TxDetailsDialog(tx: Map<String, dynamic>.from(tx)),
  );
}

class _TxDetailsDialog extends StatefulWidget {
  const _TxDetailsDialog({required this.tx});

  final Map<String, dynamic> tx;

  @override
  State<_TxDetailsDialog> createState() => _TxDetailsDialogState();
}

class _TxDetailsDialogState extends State<_TxDetailsDialog> {
  late final TextEditingController _notes;

  @override
  void initState() {
    super.initState();
    _notes = TextEditingController(text: '${widget.tx['note'] ?? ''}');
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  String _typeTitle(LocaleController loc, String type) {
    switch (type) {
      case 'in':
        return loc.tr('components.tx_details.incoming_transaction');
      case 'out':
        return loc.tr('components.tx_details.outgoing_transaction');
      case 'pool':
        return loc.tr('components.tx_details.pending_incoming_transaction');
      case 'pending':
        return loc.tr('components.tx_details.pending_outgoing_transaction');
      case 'failed':
        return loc.tr('components.tx_details.failed_transaction');
      case 'snode':
        return loc.tr('components.tx_list.service_node');
      case 'stake':
        return loc.tr('components.tx_list.stake');
      case 'miner':
        return loc.tr('components.tx_list.miner');
      case 'net':
        return loc.tr('components.tx_list.network');
      default:
        return type.isEmpty ? '—' : type;
    }
  }

  String _incomingCaption(LocaleController loc) {
    final Object? si = widget.tx['subaddr_index'];
    int? minor;
    if (si is Map) {
      minor = (si['minor'] as num?)?.toInt();
    } else if (si is int) {
      minor = si;
    }
    if (minor == null) {
      return '';
    }
    if (minor == 0) {
      return loc.tr('components.tx_details.primary_address');
    }
    return '${loc.tr('components.tx_details.sub_address')}$minor)';
  }

  String? _incomingAddress(GatewayStore store) {
    final Object? si = widget.tx['subaddr_index'];
    int? minor;
    if (si is Map) {
      minor = (si['minor'] as num?)?.toInt();
    } else if (si is int) {
      minor = si;
    }
    if (minor == null) {
      return null;
    }
    final Map<String, dynamic> al = Map<String, dynamic>.from(
        store.wallet['address_list'] as Map? ?? <String, dynamic>{});
    for (final String key in <String>['primary', 'used']) {
      final List<dynamic> list = al[key] as List<dynamic>? ?? const <dynamic>[];
      for (final dynamic e in list) {
        final Map<String, dynamic> m = Map<String, dynamic>.from(e as Map);
        final Object? ai = m['address_index'];
        int? idx;
        if (ai is Map) {
          idx = (ai['minor'] as num?)?.toInt();
        } else if (ai is num) {
          idx = ai.toInt();
        }
        if (idx == minor) {
          return '${m['address']}';
        }
      }
    }
    return null;
  }

  List<Map<String, dynamic>> _outDestinations(GatewayStore store) {
    final Object? d = widget.tx['destinations'];
    if (d is! List) {
      return <Map<String, dynamic>>[];
    }
    final List<Map<String, dynamic>> book = <Map<String, dynamic>>[];
    final Map<String, dynamic> al = Map<String, dynamic>.from(
        store.wallet['address_list'] as Map? ?? <String, dynamic>{});
    for (final dynamic x
        in (al['address_book'] as List<dynamic>? ?? const <dynamic>[])) {
      book.add(Map<String, dynamic>.from(x as Map));
    }
    for (final dynamic x in (al['address_book_starred'] as List<dynamic>? ??
        const <dynamic>[])) {
      book.add(Map<String, dynamic>.from(x as Map));
    }
    final List<Map<String, dynamic>> out = <Map<String, dynamic>>[];
    for (final dynamic raw in d) {
      final Map<String, dynamic> dest = Map<String, dynamic>.from(raw as Map);
      String name = '';
      final String addr = '${dest['address'] ?? ''}';
      for (final Map<String, dynamic> be in book) {
        if ('${be['address']}' == addr) {
          final String n = '${be['name'] ?? ''}';
          final String desc = '${be['description'] ?? ''}';
          name = desc.isEmpty ? n : '$n - $desc';
          break;
        }
      }
      dest['_display_name'] = name.isEmpty ? addr : name;
      out.add(dest);
    }
    return out;
  }

  bool _canOpenExplorer(GatewayStore store) {
    final Map<String, dynamic> cfg =
        store.app['config'] as Map<String, dynamic>? ?? <String, dynamic>{};
    final String net = '${(cfg['app'] as Map?)?['net_type'] ?? ''}';
    return net != 'stagenet';
  }

  Future<void> _copyWithFeedback(String text, String snackTrKey) async {
    if (text.isEmpty) {
      return;
    }
    await context.read<AppApi>().writeText(text);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.read<LocaleController>().tr(snackTrKey))),
    );
  }

  Future<void> _saveNotes(BuildContext context) async {
    final LocaleController loc = context.read<LocaleController>();
    await context
        .read<AppApi>()
        .send('wallet', 'save_tx_notes', <String, dynamic>{
      'txid': '${widget.tx['txid']}',
      'note': _notes.text.trim(),
    });
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(loc
                .tr('components.tx_details.save_transaction_notes_message'))),
      );
    }
  }

  Future<void> _showRawJson(BuildContext context) async {
    final LocaleController loc = context.read<LocaleController>();
    final String pretty = const JsonEncoder.withIndent('  ').convert(widget.tx);
    await showDialog<void>(
      context: context,
      builder: (BuildContext c) => AlertDialog(
        title: Text(loc.tr('components.tx_details.transaction_details_title')),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
              child: SelectableText(pretty,
                  style:
                      const TextStyle(fontFamily: 'monospace', fontSize: 11))),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c),
              child: Text(loc
                  .tr('components.tx_details.transaction_details_ok_label'))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final LocaleController loc = context.watch<LocaleController>();
    final GatewayStore store = context.watch<GatewayStore>();
    final Map<String, dynamic> tx = widget.tx;
    final String type = '${tx['type'] ?? ''}';
    final int ts = int.tryParse('${tx['timestamp'] ?? 0}') ?? 0;
    final DateTime dt =
        DateTime.fromMillisecondsSinceEpoch(ts * 1000, isUtc: true).toLocal();
    final String when = ts > 0 ? DateFormat.yMMMd().add_Hms().format(dt) : '—';
    final String pid = '${tx['payment_id'] ?? ''}'.trim();
    final bool showIncoming = type == 'in' || type == 'pool';
    final bool showOutgoing = type == 'out' || type == 'pending';
    final List<Map<String, dynamic>> outDests =
        showOutgoing ? _outDestinations(store) : <Map<String, dynamic>>[];

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 720),
        child: Scaffold(
          appBar: AppBar(
            leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context)),
            title: Text(loc.tr('components.tx_details.transaction_details')),
            actions: [
              TextButton(
                onPressed: () => _showRawJson(context),
                child: Text(loc.tr('components.tx_details.show_tx_details')),
              ),
              if (_canOpenExplorer(store))
                TextButton(
                  onPressed: () async {
                    await context
                        .read<AppApi>()
                        .send('core', 'open_explorer', <String, dynamic>{
                      'type': 'tx',
                      'id': '${tx['txid']}',
                    });
                  },
                  child: Text(loc.tr('components.tx_details.view_on_explorer')),
                ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  TxTypeIcon(type: type, tooltip: false, mainSize: 40),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(_typeTitle(loc, type),
                        style: Theme.of(context).textTheme.titleMedium),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _InfoCell(
                      label: loc.tr('components.tx_details.amount'),
                      child: FormatArqma(
                          amount: num.tryParse('${tx['amount'] ?? 0}') ?? 0,
                          digits: 12)),
                  _InfoCell(
                    label:
                        '${loc.tr('components.tx_details.fee')}${type == 'in' || type == 'pool' ? ' ${loc.tr('components.tx_details.paid_by_sender')}' : ''}',
                    child: FormatArqma(
                        amount: num.tryParse('${tx['fee'] ?? 0}') ?? 0,
                        digits: 12),
                  ),
                  _InfoCell(
                      label: loc.tr('components.tx_details.height'),
                      child: Text('${tx['height'] ?? 0}')),
                  _InfoCell(
                      label: loc.tr('components.tx_details.timestamp'),
                      child: Text(when)),
                ],
              ),
              const SizedBox(height: 16),
              Text(loc.tr('components.tx_details.transaction_id'),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              Row(
                children: [
                  Expanded(
                      child: SelectableText('${tx['txid']}',
                          style: const TextStyle(
                              fontFamily: 'monospace', fontSize: 11))),
                  IconButton(
                    icon: const Icon(Icons.copy, color: Colors.greenAccent),
                    onPressed: () => _copyWithFeedback('${tx['txid']}',
                        'components.tx_list.copied_transaction_id_to_clipboard'),
                    tooltip:
                        loc.tr('components.tx_details.copy_transaction_id'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(loc.tr('components.tx_details.payment_id'),
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              Row(
                children: [
                  Expanded(
                      child: SelectableText(pid.isEmpty ? 'N/A' : pid,
                          style: const TextStyle(
                              fontFamily: 'monospace', fontSize: 11))),
                  if (pid.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.copy, color: Colors.greenAccent),
                      onPressed: () => _copyWithFeedback(pid,
                          'components.wallet_settings.write_text_ok_message'),
                      tooltip: loc.tr('components.tx_details.copy_payment_id'),
                    ),
                ],
              ),
              if (showIncoming) ...[
                const SizedBox(height: 12),
                Text(
                    loc.tr(
                        'components.tx_details.incoming_transaction_sent_to'),
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                if (_incomingCaption(loc).isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 6),
                    child: Text(_incomingCaption(loc),
                        style: const TextStyle(
                            fontSize: 12, color: ArqmaColors.textSecondary)),
                  ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: SelectableText(
                        _incomingAddress(store) ??
                            loc.tr('components.tx_details.destination_unknown'),
                        style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 11),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy, color: Colors.greenAccent),
                      tooltip:
                          loc.tr('components.tx_details.copy_primary_address'),
                      onPressed: () {
                        final String? a = _incomingAddress(store);
                        if (a != null && a.isNotEmpty) {
                          _copyWithFeedback(
                              a, 'components.tx_details.copy_address_message');
                        }
                      },
                    ),
                  ],
                ),
              ],
              if (showOutgoing) ...[
                const SizedBox(height: 12),
                Text(
                    loc.tr(
                        'components.tx_details.outgoing_transaction_sent_to'),
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                ...outDests.map(
                  (Map<String, dynamic> d) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${d['_display_name']}',
                            style:
                                const TextStyle(fontWeight: FontWeight.w500)),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: SelectableText('${d['address']}',
                                  style: const TextStyle(
                                      fontFamily: 'monospace', fontSize: 11)),
                            ),
                            IconButton(
                              icon: const Icon(Icons.copy,
                                  color: Colors.greenAccent),
                              tooltip:
                                  loc.tr('components.tx_details.copy_address'),
                              onPressed: () => _copyWithFeedback(
                                  '${d['address']}',
                                  'components.tx_details.copy_address_message'),
                            ),
                          ],
                        ),
                        FormatArqma(
                            amount: num.tryParse('${d['amount'] ?? 0}') ?? 0,
                            digits: 8),
                      ],
                    ),
                  ),
                ),
                if (outDests.isEmpty)
                  Text(loc.tr('components.tx_details.destination_unknown')),
              ],
              const SizedBox(height: 16),
              ArqmaField(
                label: loc.tr('components.tx_details.transaction_notes'),
                optional: true,
                disableMenu: false,
                child: TextField(
                  controller: _notes,
                  maxLines: 4,
                  decoration: const InputDecoration(border: InputBorder.none),
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton(
                  onPressed: store.isReady ? () => _saveNotes(context) : null,
                  child: Text(loc.tr('components.tx_details.save_tx_notes')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoCell extends StatelessWidget {
  const _InfoCell({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 160,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 12, color: ArqmaColors.textSecondary)),
          child,
        ],
      ),
    );
  }
}

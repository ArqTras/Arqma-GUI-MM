import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../i18n/locale_controller.dart';
import 'address_identicon.dart';
import 'format_arqma.dart';
import 'receive_common.dart';
import 'tx_list_widget.dart';
import '../core/theme/arqma_colors.dart';

int? _minorFromReceiveRow(Map<String, dynamic> row) {
  final Object? ai = row['address_index'];
  if (ai is Map) {
    return (ai['minor'] as num?)?.toInt();
  }
  if (ai is int) {
    return ai;
  }
  return null;
}

/// Parity with `components/address_details.vue` (opened from `receive_item` → `details()`).
Future<void> showReceiveAddressDetailsDialog(
    BuildContext context, Map<String, dynamic> row) async {
  final String addr = '${row['address'] ?? ''}'.trim();
  if (addr.isEmpty) {
    return;
  }
  await Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (BuildContext c) =>
          _ReceiveAddressDetailsScaffold(row: row, address: addr),
    ),
  );
}

class _ReceiveAddressDetailsScaffold extends StatelessWidget {
  const _ReceiveAddressDetailsScaffold({
    required this.row,
    required this.address,
  });

  final Map<String, dynamic> row;
  final String address;

  @override
  Widget build(BuildContext context) {
    final LocaleController loc = context.watch<LocaleController>();
    final int? minor = _minorFromReceiveRow(row);
    final bool isPrimary = minor == null || minor == 0;
    // Vue `address.used`: unused subaddresses show zeroed stats; missing `used` is treated as having data.
    final bool isUnused = row['used'] == false;
    final num bal =
        isUnused ? 0 : (num.tryParse('${row['balance'] ?? 0}') ?? 0);
    final num unlocked =
        isUnused ? 0 : (num.tryParse('${row['unlocked_balance'] ?? 0}') ?? 0);
    final int outputs = isUnused
        ? 0
        : (int.tryParse('${row['num_unspent_outputs'] ?? 0}') ?? 0);

    final String titleLine = isPrimary
        ? loc.tr('components.address_book_detail.address_header_primary_title')
        : '${loc.tr('components.address_book_detail.address_header_subaddress_title')}$minor )';

    final String usedLabel = !isUnused
        ? loc.tr('components.address_book_detail.used')
        : loc.tr('components.address_book_detail.not_used');
    final String extraLine =
        '${loc.tr('components.address_book_detail.address_header_primary_title')} ($usedLabel) ${loc.tr('components.address_book_detail.this_address')}';

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(loc.tr('pages.wallet.receive.address_details_title')),
        actions: [
          TextButton(
            onPressed: () => showReceiveQrDialog(context, address),
            child: Text(loc.tr('components.receive_item.show_qr_code')),
          ),
          TextButton(
            onPressed: () => receiveCopyAddressWithSnackBar(context, address),
            child: Text(loc.tr('pages.wallet.receive.copy_address_action')),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AddressIdenticon(address: address, size: 48),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(titleLine,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text(extraLine,
                          style: const TextStyle(
                              fontSize: 12, color: ArqmaColors.textMuted)),
                      const SizedBox(height: 8),
                      SelectableText(address,
                          style: const TextStyle(
                              fontFamily: 'monospace', fontSize: 13)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _InfoBox(
                    label: loc.tr('components.address_book_detail.balance'),
                    child: FormatArqma(amount: bal, digits: 4),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _InfoBox(
                    label: loc
                        .tr('components.address_book_detail.unlocked_balance'),
                    child: FormatArqma(amount: unlocked, digits: 4),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _InfoBox(
                    label: loc.tr(
                        'components.address_book_detail.number_of_unspent_outputs'),
                    child:
                        Text('$outputs', style: const TextStyle(fontSize: 14)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Icon(Icons.history, size: 22),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    loc.tr(
                        'components.address_book_detail.recent_incoming_tx_to_this_address'),
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: TxListWidget(
                filterAddress: address,
                filterAddressMinor: minor,
                shrinkWrap: false,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoBox extends StatelessWidget {
  const _InfoBox({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF1a1a1a),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: ArqmaColors.outlineSubtle),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(
                    fontSize: 11, color: ArqmaColors.textMuted)),
            const SizedBox(height: 4),
            DefaultTextStyle.merge(
              style: const TextStyle(fontSize: 13),
              child: child,
            ),
          ],
        ),
      ),
    );
  }
}

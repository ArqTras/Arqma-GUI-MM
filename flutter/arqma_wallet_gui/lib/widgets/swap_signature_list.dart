import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../i18n/locale_controller.dart';
import '../store/gateway_store.dart';
import '../core/theme/arqma_colors.dart';

/// Parity with `components/swap_list_tabular.vue` (list + action by `type`).
class SwapSignatureList extends StatelessWidget {
  const SwapSignatureList({super.key, required this.onActionTap});

  /// User tapped Complete / Claim / etc. (Vue emits `complete-exchange`).
  final void Function(Map<String, dynamic> item) onActionTap;

  @override
  Widget build(BuildContext context) {
    final LocaleController loc = context.watch<LocaleController>();
    final GatewayStore store = context.watch<GatewayStore>();
    final List<dynamic> items =
        (store.raw['signature_data'] as List<dynamic>?) ?? const <dynamic>[];

    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
            loc.tr('components.swap_list_tabular.no_signature_data_found')),
      );
    }

    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, __) =>
          const Divider(height: 1, color: ArqmaColors.dividerLine),
      itemBuilder: (BuildContext context, int i) {
        final Map<String, dynamic> m =
            Map<String, dynamic>.from(items[i] as Map);
        final String type = '${m['type'] ?? ''}';
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _row(loc.tr('components.swap_list_tabular.network'),
                  '${m['network'] ?? ''}'),
              _row(loc.tr('components.swap_list_tabular.block_hash'),
                  '${m['blockHash'] ?? ''}',
                  mono: true),
              _row(loc.tr('components.swap_list_tabular.transaction_hash'),
                  '${m['transactionHash'] ?? ''}',
                  mono: true),
              _row(loc.tr('components.swap_list_tabular.amount'),
                  '${m['amountFormatted'] ?? m['amount'] ?? ''}'),
              Align(
                alignment: Alignment.centerRight,
                child: _buildActionButton(loc, type, m),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildActionButton(
      LocaleController loc, String type, Map<String, dynamic> m) {
    if (type == 'Processing') {
      return ElevatedButton(
          onPressed: null, child: Text(loc.tr('pages.wallet.swap.processing')));
    }
    if (type != 'Exchange' && type != 'AirDrop') {
      return OutlinedButton(
          onPressed: null, child: Text(loc.tr('pages.wallet.swap.queued')));
    }
    final String label = type == 'Exchange'
        ? loc.tr('pages.wallet.swap.accept_transfer')
        : loc.tr('pages.wallet.swap.claim_air_drop');
    return ElevatedButton(
      style: ElevatedButton.styleFrom(
          backgroundColor: type == 'Exchange' ? Colors.green : Colors.blue),
      onPressed: () => onActionTap(m),
      child: Text(label),
    );
  }

  Widget _row(String k, String v, {bool mono = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(k,
                style: const TextStyle(
                    fontSize: 11, color: ArqmaColors.textSecondary)),
          ),
          Expanded(
            child: Text(
              v,
              style: TextStyle(
                  fontSize: 11, fontFamily: mono ? 'monospace' : null),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

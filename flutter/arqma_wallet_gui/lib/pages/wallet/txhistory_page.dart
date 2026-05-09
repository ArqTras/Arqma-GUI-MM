import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/arqma_colors.dart';
import '../../store/gateway_store.dart';
import '../../widgets/format_arqma.dart';

/// Parity with `pages/wallet/txhistory.vue` (list shell + amount coloring).
class TxHistoryPage extends StatelessWidget {
  const TxHistoryPage({super.key});

  Color _amountColor(String? type) {
    if (type == null) {
      return Colors.white70;
    }
    if (type.contains('in') || type.contains('pool') || type.contains('miner')) {
      return ArqmaColors.txIn;
    }
    if (type.contains('stake')) {
      return Colors.amber.shade600;
    }
    return Colors.white70;
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<GatewayStore>();
    final txs = store.filteredTransactions;

    if (txs.isEmpty) {
      return ListView(
        children: const [
          SizedBox(height: 8),
          Text('No transactions', style: TextStyle(color: Colors.white54)),
        ],
      );
    }

    return ListView.separated(
      itemCount: txs.length,
      separatorBuilder: (_, __) => const Divider(height: 1, color: Colors.white12),
      itemBuilder: (BuildContext context, int i) {
        final m = txs[i] as Map<String, dynamic>;
        final type = m['type']?.toString();
        final amount = num.tryParse('${m['amount'] ?? 0}') ?? 0;
        return ListTile(
          title: Text(
            m['txid']?.toString() ?? '',
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: Colors.white70),
          ),
          subtitle: Text(type ?? '', style: const TextStyle(color: Colors.white54)),
          trailing: FormatArqma(
            amount: amount,
            digits: 5,
            textColor: _amountColor(type),
          ),
        );
      },
    );
  }
}

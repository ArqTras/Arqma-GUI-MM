import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../i18n/locale_controller.dart';
import '../../store/gateway_store.dart';
import '../../widgets/wallet_tab_visibility.dart';
import '../../widgets/address_identicon.dart';
import '../../widgets/receive_address_details_dialog.dart';
import '../../widgets/receive_common.dart';
import '../../core/theme/arqma_colors.dart';

Future<void> _receiveOpenAddressSheet(
    BuildContext context, Map<String, dynamic> row) async {
  final String a = '${row['address'] ?? ''}'.trim();
  if (a.isEmpty) {
    return;
  }
  final LocaleController loc = context.read<LocaleController>();
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: const Color(0xFF1a1a1a),
    builder: (BuildContext sheet) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(loc.tr('pages.wallet.receive.address_actions_title'),
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: SelectableText(a,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline,
                color: ArqmaColors.textSecondary),
            title: Text(loc.tr('components.receive_item.show_details')),
            onTap: () {
              Navigator.pop(sheet);
              showReceiveAddressDetailsDialog(context, row);
            },
          ),
          ListTile(
            leading: const Icon(Icons.copy, color: ArqmaColors.textSecondary),
            title: Text(loc.tr('pages.wallet.receive.copy_address_action')),
            onTap: () async {
              if (sheet.mounted) {
                Navigator.pop(sheet);
              }
              if (context.mounted) {
                await receiveCopyAddressWithSnackBar(context, a);
              }
            },
          ),
          ListTile(
            leading:
                const Icon(Icons.qr_code, color: ArqmaColors.textSecondary),
            title: Text(loc.tr('pages.wallet.receive.show_qr_action')),
            onTap: () {
              Navigator.pop(sheet);
              showReceiveQrDialog(context, a);
            },
          ),
        ],
      ),
    ),
  );
}

/// Parity with `pages/wallet/receive.vue` (lists + QR dialog + address actions like `receive_item.vue`).
class ReceivePage extends StatefulWidget {
  const ReceivePage({super.key});

  @override
  State<ReceivePage> createState() => _ReceivePageState();
}

class _ReceivePageState extends State<ReceivePage> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    if (mounted) {
      setState(() {});
    }
  }

  List<Map<String, dynamic>> _primaryList(GatewayStore store) {
    final Map<String, dynamic> al = Map<String, dynamic>.from(
        store.wallet['address_list'] as Map? ?? <String, dynamic>{});
    final List<dynamic> p =
        al['primary'] as List<dynamic>? ?? const <dynamic>[];
    if (p.isNotEmpty) {
      return p.map((dynamic e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    final String addr = '${store.walletInfo['address'] ?? ''}';
    if (addr.isEmpty) {
      return <Map<String, dynamic>>[];
    }
    return <Map<String, dynamic>>[
      <String, dynamic>{
        'address': addr,
        'address_index': <String, dynamic>{'major': 0, 'minor': 0},
        'used': true,
      },
    ];
  }

  List<Map<String, dynamic>> _asMapList(String key, GatewayStore store) {
    final List<dynamic> raw =
        (store.wallet['address_list'] as Map?)?[key] as List<dynamic>? ??
            const <dynamic>[];
    return raw.map((dynamic e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final LocaleController loc = context.watch<LocaleController>();
    final GatewayStore store = context.watchGatewayStore();
    final List<Map<String, dynamic>> primary = _primaryList(store);
    final List<Map<String, dynamic>> used = _asMapList('used', store);
    final List<Map<String, dynamic>> unused = _asMapList('unused', store);

    final List<Widget> listChildren = <Widget>[
      if (primary.isNotEmpty)
        Text(loc.tr('pages.wallet.receive.my_primary_address'),
            style: Theme.of(context).textTheme.titleSmall),
      ...primary.map(
        (Map<String, dynamic> a) => _AddrTile(
          address: a,
          subLabel: loc.tr('pages.wallet.receive.sub_label'),
          onCopy: () =>
              receiveCopyAddressWithSnackBar(context, '${a['address']}'),
          onQr: () => showReceiveQrDialog(context, '${a['address']}'),
          onTileTap: () => showReceiveAddressDetailsDialog(context, a),
          onTileLongPress: () => _receiveOpenAddressSheet(context, a),
        ),
      ),
      if (used.isNotEmpty) ...<Widget>[
        const SizedBox(height: 12),
        Text(loc.tr('pages.wallet.receive.my_used_addresses'),
            style: Theme.of(context).textTheme.titleSmall),
        ...used.map(
          (Map<String, dynamic> a) => _AddrTile(
            address: a,
            subLabel:
                '${loc.tr('pages.wallet.receive.sub_address_label')} ${a['address_index'] is Map ? (a['address_index'] as Map)['minor'] : ''}',
            onCopy: () =>
                receiveCopyAddressWithSnackBar(context, '${a['address']}'),
            onQr: () => showReceiveQrDialog(context, '${a['address']}'),
            onTileTap: () => showReceiveAddressDetailsDialog(context, a),
            onTileLongPress: () => _receiveOpenAddressSheet(context, a),
          ),
        ),
      ],
      if (unused.isNotEmpty) ...<Widget>[
        const SizedBox(height: 12),
        Text(loc.tr('pages.wallet.receive.my_unused_addresses'),
            style: Theme.of(context).textTheme.titleSmall),
        ...unused.map(
          (Map<String, dynamic> a) => _AddrTile(
            address: a,
            subLabel:
                '${loc.tr('pages.wallet.receive.my_unused_address')} ${a['address_index'] is Map ? (a['address_index'] as Map)['minor'] : ''}',
            onCopy: () =>
                receiveCopyAddressWithSnackBar(context, '${a['address']}'),
            onQr: () => showReceiveQrDialog(context, '${a['address']}'),
            onTileTap: () => showReceiveAddressDetailsDialog(context, a),
            onTileLongPress: () => _receiveOpenAddressSheet(context, a),
          ),
        ),
      ],
    ];

    // `.scroller` in `receive.vue`: `max-height: viewport - 230px`.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(
          child: LayoutBuilder(
            builder: (BuildContext ctx, BoxConstraints inner) {
              final double viewportH = MediaQuery.sizeOf(ctx).height;
              final double capByVue = (viewportH - 230).clamp(200.0, 9000.0);
              final double maxListH = math.min(inner.maxHeight, capByVue);
              return ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxListH),
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: listChildren,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _AddrTile extends StatelessWidget {
  const _AddrTile({
    required this.address,
    required this.subLabel,
    required this.onCopy,
    required this.onQr,
    required this.onTileTap,
    required this.onTileLongPress,
  });

  final Map<String, dynamic> address;
  final String subLabel;
  final VoidCallback onCopy;
  final VoidCallback onQr;
  final VoidCallback onTileTap;
  final VoidCallback onTileLongPress;

  @override
  Widget build(BuildContext context) {
    final String addr = '${address['address']}';
    return Card(
      color: const Color(0xFF1a1a1a),
      child: ListTile(
        onTap: onTileTap,
        onLongPress: onTileLongPress,
        leading: AddressIdenticon(address: addr, size: 40),
        title: Text(addr, style: const TextStyle(fontSize: 13)),
        subtitle: Text(subLabel),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.qr_code),
              onPressed: onQr,
            ),
            IconButton(
              icon: const Icon(Icons.copy),
              onPressed: onCopy,
            ),
          ],
        ),
      ),
    );
  }
}

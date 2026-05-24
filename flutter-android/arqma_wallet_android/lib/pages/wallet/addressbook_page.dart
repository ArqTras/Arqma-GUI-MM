import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/app_api.dart';
import '../../i18n/locale_controller.dart';
import '../../store/gateway_store.dart';
import '../../widgets/address_book_details_dialog.dart';
import '../../widgets/address_identicon.dart';
import '../../core/theme/arqma_colors.dart';

/// Parity with `pages/wallet/addressbook.vue`.
class AddressBookPage extends StatelessWidget {
  const AddressBookPage({super.key});

  List<Map<String, dynamic>> _combined(GatewayStore store) {
    final Map<String, dynamic> al = Map<String, dynamic>.from(
        store.wallet['address_list'] as Map? ?? <String, dynamic>{});
    final List<dynamic> starred =
        al['address_book_starred'] as List<dynamic>? ?? const <dynamic>[];
    final List<dynamic> book =
        al['address_book'] as List<dynamic>? ?? const <dynamic>[];
    final List<Map<String, dynamic>> out = <Map<String, dynamic>>[];
    for (final dynamic e in starred) {
      out.add(<String, dynamic>{
        ...Map<String, dynamic>.from(e as Map),
        'starred': true
      });
    }
    for (final dynamic e in book) {
      out.add(<String, dynamic>{
        ...Map<String, dynamic>.from(e as Map),
        'starred': false
      });
    }
    return out;
  }

  void _showEntryContextMenu(
    BuildContext context, {
    required Map<String, dynamic> entry,
    required bool viewOnly,
    required LocaleController loc,
  }) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF1d1d1d),
      builder: (BuildContext sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.info_outline,
                  color: ArqmaColors.textSecondary),
              title: Text(
                loc.tr('pages.wallet.addressbook.show_details'),
                style: const TextStyle(color: ArqmaColors.textPrimary),
              ),
              onTap: () {
                Navigator.pop(sheet);
                showAddressBookDetailsDialog(context,
                    initialEntry: entry, startAsNew: false);
              },
            ),
            ListTile(
              leading: const Icon(Icons.send, color: ArqmaColors.textSecondary),
              title: Text(
                loc.tr('pages.wallet.addressbook.send_to_address'),
                style: const TextStyle(color: ArqmaColors.textPrimary),
              ),
              enabled: !viewOnly,
              onTap: viewOnly
                  ? null
                  : () {
                      Navigator.pop(sheet);
                      final String a =
                          Uri.encodeComponent('${entry['address']}');
                      final String p =
                          Uri.encodeComponent('${entry['payment_id'] ?? ''}');
                      context.push('/wallet/send?address=$a&payment_id=$p');
                    },
            ),
            ListTile(
              leading: const Icon(Icons.copy, color: ArqmaColors.textSecondary),
              title: Text(
                loc.tr('pages.wallet.addressbook.copy_address'),
                style: const TextStyle(color: ArqmaColors.textPrimary),
              ),
              onTap: () {
                Navigator.pop(sheet);
                _copyEntry(context, entry);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _copyEntry(
      BuildContext context, Map<String, dynamic> entry) async {
    final LocaleController loc = context.read<LocaleController>();
    final AppApi api = context.read<AppApi>();
    await api.writeText('${entry['address']}');
    if (!context.mounted) {
      return;
    }
    final String pid = '${entry['payment_id'] ?? ''}';
    if (pid.isNotEmpty) {
      await showDialog<void>(
        context: context,
        builder: (BuildContext c) => AlertDialog(
          title: Text(
              loc.tr('pages.wallet_select.import_view_only.payment_id_title')),
          content: Text(loc
              .tr('pages.wallet_select.import_view_only.payment_id_message')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: Text(loc.tr(
                  'pages.wallet_select.import_view_only.payment_id_ok_label')),
            ),
          ],
        ),
      );
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(loc.tr(
                'pages.wallet_select.import_view_only.payment_id_notify_message'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final LocaleController loc = context.watch<LocaleController>();
    final GatewayStore store = context.watch<GatewayStore>();
    final bool viewOnly = store.walletInfo['view_only'] == true;
    final List<Map<String, dynamic>> entries = _combined(store);

    return Stack(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(loc.tr('pages.wallet.addressbook.address_book'),
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            Expanded(
              child: entries.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(loc.tr(
                          'pages.wallet.addressbook.address_book_is_empty')),
                    )
                  : ListView.builder(
                      itemCount: entries.length,
                      itemBuilder: (BuildContext context, int i) {
                        final Map<String, dynamic> e = entries[i];
                        final bool starred = e['starred'] == true;
                        return ListTile(
                          title: Text('${e['address']}',
                              style: const TextStyle(fontSize: 13)),
                          subtitle: Text('${e['name'] ?? ''}'),
                          leading: AddressIdenticon(
                              address: '${e['address'] ?? ''}', size: 44),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: Icon(
                                    starred ? Icons.star : Icons.star_border,
                                    color: Colors.amber.shade200),
                              ),
                              ElevatedButton(
                                onPressed: viewOnly
                                    ? null
                                    : () {
                                        final String a = Uri.encodeComponent(
                                            '${e['address']}');
                                        final String p = Uri.encodeComponent(
                                            '${e['payment_id'] ?? ''}');
                                        context.push(
                                            '/wallet/send?address=$a&payment_id=$p');
                                      },
                                child: Text(
                                    loc.tr('pages.wallet.addressbook.send')),
                              ),
                            ],
                          ),
                          onTap: () => showAddressBookDetailsDialog(context,
                              initialEntry: e, startAsNew: false),
                          onLongPress: () => _showEntryContextMenu(context,
                              entry: e, viewOnly: viewOnly, loc: loc),
                        );
                      },
                    ),
            ),
          ],
        ),
        Positioned(
          right: 18,
          bottom: 18,
          child: FloatingActionButton(
            onPressed: store.isReady
                ? () => showAddressBookDetailsDialog(context, startAsNew: true)
                : null,
            child: const Icon(Icons.add),
          ),
        ),
      ],
    );
  }
}

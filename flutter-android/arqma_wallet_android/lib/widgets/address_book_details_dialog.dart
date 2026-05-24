import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../core/app_api.dart';
import '../i18n/locale_controller.dart';
import '../store/gateway_store.dart';
import 'address_identicon.dart';
import 'arqma_field.dart';
import 'tx_list_widget.dart';

enum _AddressBookDialogMode { view, newEntry, edit }

/// Parity with `components/address_book_details.vue` (view / new / edit + recent TX).
Future<void> showAddressBookDetailsDialog(
  BuildContext context, {
  Map<String, dynamic>? initialEntry,
  required bool startAsNew,
}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    useSafeArea: false,
    builder: (BuildContext c) => Dialog(
      insetPadding: EdgeInsets.zero,
      child: _AddressBookDetailsBody(
        initialEntry: initialEntry,
        startAsNew: startAsNew,
      ),
    ),
  );
}

class _AddressBookDetailsBody extends StatefulWidget {
  const _AddressBookDetailsBody({
    required this.startAsNew,
    this.initialEntry,
  });

  final bool startAsNew;
  final Map<String, dynamic>? initialEntry;

  @override
  State<_AddressBookDetailsBody> createState() =>
      _AddressBookDetailsBodyState();
}

class _AddressBookDetailsBodyState extends State<_AddressBookDetailsBody> {
  late _AddressBookDialogMode _mode;
  Map<String, dynamic>? _viewEntry;

  late final TextEditingController _address;
  late final TextEditingController _name;
  late final TextEditingController _paymentId;
  late final TextEditingController _description;
  bool _starred = false;

  @override
  void initState() {
    super.initState();
    _address = TextEditingController();
    _name = TextEditingController();
    _paymentId = TextEditingController();
    _description = TextEditingController();
    if (widget.startAsNew) {
      _mode = _AddressBookDialogMode.newEntry;
      _viewEntry = null;
    } else {
      _mode = _AddressBookDialogMode.view;
      _viewEntry =
          Map<String, dynamic>.from(widget.initialEntry ?? <String, dynamic>{});
    }
    _syncFormFromViewOrClear();
  }

  void _syncFormFromViewOrClear() {
    if (_mode == _AddressBookDialogMode.newEntry) {
      _address.clear();
      _name.clear();
      _paymentId.clear();
      _description.clear();
      _starred = false;
      return;
    }
    if (_viewEntry != null &&
        (_mode == _AddressBookDialogMode.view ||
            _mode == _AddressBookDialogMode.edit)) {
      final Map<String, dynamic> e = _viewEntry!;
      _address.text = '${e['address'] ?? ''}';
      _name.text = '${e['name'] ?? ''}';
      _paymentId.text = '${e['payment_id'] ?? ''}';
      _description.text = '${e['description'] ?? ''}';
      _starred = e['starred'] == true;
    }
  }

  int? _minorFromEntry(Map<String, dynamic>? e) {
    if (e == null) {
      return null;
    }
    final Object? ai = e['address_index'];
    if (ai is int) {
      return ai;
    }
    if (ai is Map) {
      return (ai['minor'] as num?)?.toInt();
    }
    return null;
  }

  Map<String, dynamic> _payloadFromForm() {
    return <String, dynamic>{
      'index': _viewEntry?['index'],
      'address': _address.text.trim(),
      'payment_id': _paymentId.text.trim(),
      'name': _name.text.trim(),
      'description': _description.text.trim(),
      'starred': _starred,
    };
  }

  Future<void> _save() async {
    final LocaleController loc = context.read<LocaleController>();
    final String addr = _address.text.trim();
    final String name = _name.text.trim();
    if (addr.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                loc.tr('components.address_book_details.invalid_address'))),
      );
      return;
    }
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text(loc.tr('pages.wallet_select.import.enter_account_name'))),
      );
      return;
    }
    if (name.contains('::')) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(loc.tr(
                'components.address_book_details.name_must_not_contain_colons'))),
      );
      return;
    }
    if (_description.text.contains('::')) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(loc.tr(
                'components.address_book_details.description_must_not_contain_colons'))),
      );
      return;
    }
    final Map<String, dynamic> payload = _payloadFromForm();
    payload.removeWhere((String k, dynamic v) => v == null);
    await context.read<AppApi>().send('wallet', 'add_address_book', payload);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _delete() async {
    final Map<String, dynamic> copy = _payloadFromForm();
    await context.read<AppApi>().send('wallet', 'delete_address_book', copy);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  void _sendToAddress() {
    if (_viewEntry == null) {
      return;
    }
    final String a = Uri.encodeComponent('${_viewEntry!['address']}');
    final String p = Uri.encodeComponent('${_viewEntry!['payment_id'] ?? ''}');
    Navigator.of(context).pop();
    context.push('/wallet/send?address=$a&payment_id=$p');
  }

  @override
  void dispose() {
    _address.dispose();
    _name.dispose();
    _paymentId.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final LocaleController loc = context.watch<LocaleController>();
    final GatewayStore store = context.watch<GatewayStore>();
    final bool viewOnly = store.walletInfo['view_only'] == true;

    if (_mode == _AddressBookDialogMode.view && _viewEntry != null) {
      final Map<String, dynamic> e = _viewEntry!;
      final String addr = '${e['address']}';
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.of(context).pop()),
          title: Text(
              loc.tr('components.address_book_details.address_book_detail')),
          actions: [
            TextButton(
              onPressed: store.isReady
                  ? () {
                      setState(() {
                        _mode = _AddressBookDialogMode.edit;
                        _syncFormFromViewOrClear();
                      });
                    }
                  : null,
              child: Text(loc.tr('components.address_book_details.edit')),
            ),
            TextButton(
              onPressed: viewOnly ? null : _sendToAddress,
              child: Text(loc.tr('components.address_book_details.send_coins')),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AddressIdenticon(address: addr, size: 44),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SelectableText(addr,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w500)),
                      if ('${e['name']}'.isNotEmpty) Text('${e['name']}'),
                      if ('${e['payment_id'] ?? ''}'.isNotEmpty)
                        Text(
                            '${loc.tr('pages.wallet.address_header.payment_id')} ${e['payment_id']}'),
                      if ('${e['description'] ?? ''}'.isNotEmpty)
                        Text(
                            '${loc.tr('components.address_book_details.notes')}: ${e['description']}'),
                    ],
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
                    child: Text(loc.tr(
                        'components.address_book_details.recent_transactions_with_address'))),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 280,
              child: TxListWidget(
                limit: 5,
                filterAddress: addr,
                filterAddressMinor: _minorFromEntry(e),
                shrinkWrap: true,
              ),
            ),
          ],
        ),
      );
    }

    // new / edit
    final String titleKey = _mode == _AddressBookDialogMode.newEntry
        ? 'components.address_book_details.add_address_book_entry'
        : 'components.address_book_details.edit_address_book_entry';

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (_mode == _AddressBookDialogMode.edit && _viewEntry != null) {
              setState(() {
                _mode = _AddressBookDialogMode.view;
                _syncFormFromViewOrClear();
              });
            } else {
              Navigator.of(context).pop();
            }
          },
        ),
        title: Text(loc.tr(titleKey)),
        actions: [
          if (_mode == _AddressBookDialogMode.edit)
            TextButton(
              onPressed: () {
                setState(() {
                  _mode = _AddressBookDialogMode.view;
                  _syncFormFromViewOrClear();
                });
              },
              child: Text(loc.tr('components.address_book_details.cancel')),
            ),
          TextButton(
              onPressed: _save,
              child: Text(loc.tr('components.address_book_details.save'))),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ArqmaField(
            label: loc.tr('components.address_book_details.address'),
            disableMenu: false,
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _address,
                    decoration: const InputDecoration(border: InputBorder.none),
                  ),
                ),
                IconButton(
                  icon: Icon(_starred ? Icons.star : Icons.star_border),
                  onPressed: () => setState(() => _starred = !_starred),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          ArqmaField(
            label: loc.tr('components.address_book_details.name'),
            disableMenu: false,
            child: TextField(
              controller: _name,
              decoration: const InputDecoration(border: InputBorder.none),
            ),
          ),
          const SizedBox(height: 12),
          ArqmaField(
            label: loc.tr('components.address_book_details.payment_id'),
            optional: true,
            child: TextField(
              controller: _paymentId,
              decoration: InputDecoration(
                hintText: loc.tr(
                    'components.address_book_details.payment_id_placeholder'),
                border: InputBorder.none,
              ),
            ),
          ),
          const SizedBox(height: 12),
          ArqmaField(
            label: loc.tr('components.address_book_details.notes'),
            optional: true,
            disableMenu: false,
            child: TextField(
              controller: _description,
              minLines: 2,
              maxLines: 6,
              decoration: InputDecoration(
                hintText: loc.tr(
                    'components.address_book_details.additional_notes_placeholder'),
                border: InputBorder.none,
              ),
            ),
          ),
          if (_mode == _AddressBookDialogMode.edit) ...[
            const SizedBox(height: 24),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade800),
              onPressed: _delete,
              child: Text(loc.tr('components.address_book_details.delete')),
            ),
          ],
        ],
      ),
    );
  }
}

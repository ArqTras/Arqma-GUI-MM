import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/app_api.dart';
import '../core/utils/qr_svg.dart';
import '../i18n/locale_controller.dart';

/// Shared Receive actions (QR dialog, copy) used by [ReceivePage] and receive address details.
Future<void> receiveCopyAddressWithSnackBar(BuildContext context, String address) async {
  final LocaleController loc = context.read<LocaleController>();
  await context.read<AppApi>().writeText(address);
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(loc.tr('pages.wallet.receive.address_copied_to_clipboard'))),
    );
  }
}

Future<void> showReceiveQrDialog(BuildContext context, String address) async {
  final LocaleController loc = context.read<LocaleController>();
  final AppApi api = context.read<AppApi>();
  await showDialog<void>(
    context: context,
    builder: (BuildContext c) => AlertDialog(
      backgroundColor: const Color(0xFF1d1d1d),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(12),
            child: QrImageView(data: address, size: 200),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () async {
            final String svg = buildQrCodeSvg(address);
            await api.writeText(svg);
            if (c.mounted) {
              ScaffoldMessenger.of(c).showSnackBar(
                SnackBar(content: Text(loc.tr('pages.wallet.receive.copied_qr_code_to_clipboard'))),
              );
            }
          },
          child: Text(loc.tr('pages.wallet.receive.copy_qr_code')),
        ),
        TextButton(
          onPressed: () async {
            final String svg = buildQrCodeSvg(address);
            await api.send('core', 'save_svg', <String, dynamic>{'svg': svg, 'type': 'QR Code'});
          },
          child: Text(loc.tr('pages.wallet.receive.save_qr_code')),
        ),
        TextButton(
          onPressed: () => Navigator.pop(c),
          child: Text(loc.tr('pages.wallet.receive.close')),
        ),
      ],
    ),
  );
}

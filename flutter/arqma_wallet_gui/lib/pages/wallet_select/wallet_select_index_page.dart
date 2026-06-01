import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:local_auth/local_auth.dart';
import 'package:provider/provider.dart';

import '../../app_nav.dart';
import '../../core/app_api.dart';
import '../../core/desktop/arqma_paths.dart';
import '../../core/desktop/wallet_biometric_unlock.dart';
import '../../i18n/locale_controller.dart';
import '../../store/gateway_store.dart';
import '../../widgets/address_identicon.dart';
import '../../widgets/app_loading.dart';
import '../../core/theme/arqma_colors.dart';

/// Parity with `pages/wallet-select/index.vue`.
class WalletSelectIndexPage extends StatefulWidget {
  const WalletSelectIndexPage({super.key});

  @override
  State<WalletSelectIndexPage> createState() => _WalletSelectIndexPageState();
}

class _WalletSelectIndexPageState extends State<WalletSelectIndexPage> {
  /// Held for [dispose] — do not call [context.read] there (element already deactivated).
  GatewayStore? _gatewayListenTarget;

  /// Blocks [_onWalletStatus] navigation while the Touch ID enable dialog is shown.
  bool _deferWalletNavigation = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final GatewayStore store = context.read<GatewayStore>();
      final Map<String, dynamic>? merged = mergedFilesystemConfig(store.app);
      unawaited(
        context.read<AppApi>().send(
              'wallet',
              'list_wallets',
              merged ?? <String, dynamic>{},
            ),
      );
    });
    _gatewayListenTarget = context.read<GatewayStore>();
    _gatewayListenTarget!.addListener(_onWalletStatus);
  }

  @override
  void dispose() {
    _gatewayListenTarget?.removeListener(_onWalletStatus);
    _gatewayListenTarget = null;
    super.dispose();
  }

  void _onWalletStatus() {
    final GatewayStore? g = _gatewayListenTarget;
    if (g == null) {
      return;
    }
    final Map<String, dynamic> st =
        g.wallet['status'] as Map<String, dynamic>;
    final int code = st['code'] as int? ?? 1;
    final String errMsg = '${st['message'] ?? ''}';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Use [mounted] only — reading [context.mounted] still touches [context] and throws
      // after dispose ("widget has been unmounted").
      if (!mounted) {
        return;
      }
      if (code == 0) {
        if (_deferWalletNavigation) {
          return;
        }
        AppLoading.hide();
        final String path = GoRouterState.of(context).uri.path;
        if (path != '/wallet') {
          context.go('/wallet');
        }
      } else if (code < 0) {
        AppLoading.hide();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errMsg)),
        );
        context
            .read<GatewayStore>()
            .resetWalletStatus({'code': 1, 'message': null});
      }
    });
  }

  String _netType(GatewayStore store) {
    final Map<String, dynamic>? cfg =
        store.app['config'] as Map<String, dynamic>?;
    return (cfg?['app'] as Map?)?['net_type'] as String? ?? 'mainnet';
  }

  Future<void> _maybeOfferTouchIdEnable({
    required LocaleController loc,
    required String netType,
    required String walletName,
    required String password,
  }) async {
    if (!WalletBiometricUnlock.isNativeBiometricPlatform || password.isEmpty) {
      return;
    }
    if (!await WalletBiometricUnlock.isPlatformSupported()) {
      return;
    }
    if (await WalletBiometricUnlock.isEnabled(netType, walletName)) {
      return;
    }
    if (await WalletBiometricUnlock.wasOfferSkipped(netType, walletName)) {
      return;
    }
    await WalletBiometricUnlock.waitForModalDismiss();
    final BuildContext? dialogContext = appNavigatorKey.currentContext;
    if (dialogContext == null || !dialogContext.mounted) {
      return;
    }
    final bool? enable = await showDialog<bool>(
      context: dialogContext,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (BuildContext c) => AlertDialog(
        backgroundColor: const Color(0xFF1d1d1d),
        title: Text(loc.tr('pages.wallet_select.index.enable_face_id_title')),
        content:
            Text(loc.tr('pages.wallet_select.index.enable_face_id_message')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(loc.tr('pages.wallet_select.index.enable_face_id_skip')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(loc.tr('pages.wallet_select.index.enable_face_id_ok')),
          ),
        ],
      ),
    );
    if (enable != true) {
      if (enable == false) {
        await WalletBiometricUnlock.markOfferSkipped(netType, walletName);
      }
      return;
    }
    try {
      await WalletBiometricUnlock.enable(
        netType: netType,
        walletName: walletName,
        password: password,
        localizedReason:
            loc.tr('pages.wallet_select.index.face_id_enable_reason'),
      );
      if (dialogContext.mounted) {
        ScaffoldMessenger.of(dialogContext).showSnackBar(
          SnackBar(
            content:
                Text(loc.tr('pages.wallet_select.index.face_id_enabled_message')),
          ),
        );
      }
    } catch (e) {
      debugPrint('[WalletSelect] enable Touch ID: $e');
      if (dialogContext.mounted) {
        ScaffoldMessenger.of(dialogContext).showSnackBar(
          SnackBar(
            content:
                Text(loc.tr('pages.wallet_select.index.face_id_failed_message')),
          ),
        );
      }
    }
  }

  Future<void> _enableTouchIdAfterSuccessfulOpen({
    required LocaleController loc,
    required String netType,
    required String walletName,
    required String password,
  }) async {
    WalletBiometricUnlock.scheduleEnable(
      PendingBiometricEnable(
        netType: netType,
        walletName: walletName,
        password: password,
        localizedReason:
            loc.tr('pages.wallet_select.index.face_id_enable_reason'),
        successMessage:
            loc.tr('pages.wallet_select.index.face_id_enabled_message'),
        failureMessage:
            loc.tr('pages.wallet_select.index.face_id_failed_message'),
      ),
    );
  }

  Future<String?> _tryBiometricWalletPassword({
    required LocaleController loc,
    required String netType,
    required String walletName,
    bool showFailureMessage = true,
  }) async {
    if (!WalletBiometricUnlock.isNativeBiometricPlatform) {
      return null;
    }
    if (!await WalletBiometricUnlock.isEnabled(netType, walletName)) {
      return null;
    }
    await WalletBiometricUnlock.waitForModalDismiss();
    if (!mounted) {
      return null;
    }
    final String? bioPassword = await WalletBiometricUnlock.unlockPassword(
      netType: netType,
      walletName: walletName,
      localizedReason: loc.tr('pages.wallet_select.index.face_id_unlock_reason'),
    );
    if (bioPassword != null && bioPassword.isNotEmpty) {
      return bioPassword;
    }
    if (showFailureMessage && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(loc.tr('pages.wallet_select.index.face_id_failed_message')),
        ),
      );
    }
    return null;
  }

  Future<void> _openWallet(Map<String, dynamic> wallet) async {
    final LocaleController loc = context.read<LocaleController>();
    final AppApi api = context.read<AppApi>();
    final GatewayStore store = context.read<GatewayStore>();
    final String name = '${wallet['name']}';
    final String netType = _netType(store);
    final bool pwdProt = wallet['password_protected'] != false;
    String? password;
    bool enableTouchIdAfterOpen = false;
    if (pwdProt) {
      password = await _tryBiometricWalletPassword(
        loc: loc,
        netType: netType,
        walletName: name,
        showFailureMessage: false,
      );
      while (password == null || password.isEmpty) {
        if (!mounted) {
          return;
        }
        final _OpenWalletPasswordDialogResult? picked =
            await showDialog<_OpenWalletPasswordDialogResult>(
          context: context,
          useRootNavigator: true,
          builder: (BuildContext _) => _OpenWalletPasswordDialog(
            loc: loc,
            walletName: name,
            netType: netType,
          ),
        );
        if (picked == null) {
          return;
        }
        if (picked.requestBiometric) {
          password = await _tryBiometricWalletPassword(
            loc: loc,
            netType: netType,
            walletName: name,
          );
          continue;
        }
        password = picked.password;
        enableTouchIdAfterOpen = picked.enableBiometricAfterOpen;
      }
    } else {
      password = '';
    }
    final bool offerTouchIdAfterOpen = pwdProt &&
        WalletBiometricUnlock.isNativeBiometricPlatform &&
        password.isNotEmpty;
    if (offerTouchIdAfterOpen) {
      _deferWalletNavigation = true;
    }
    await AppLoading.show();
    await api.send('wallet', 'open_wallet',
        <String, dynamic>{'name': name, 'password': password});
    AppLoading.hide();
    if (!mounted) {
      return;
    }
    final Map<String, dynamic> st =
        store.wallet['status'] as Map<String, dynamic>;
    final int code = st['code'] as int? ?? 1;
    if (code == 0) {
      if (enableTouchIdAfterOpen) {
        await _enableTouchIdAfterSuccessfulOpen(
          loc: loc,
          netType: netType,
          walletName: name,
          password: password,
        );
      } else if (offerTouchIdAfterOpen) {
        await _maybeOfferTouchIdEnable(
          loc: loc,
          netType: netType,
          walletName: name,
          password: password,
        );
      }
      _deferWalletNavigation = false;
      final BuildContext? navContext = appNavigatorKey.currentContext;
      if (navContext != null && navContext.mounted) {
        final String path = GoRouterState.of(navContext).uri.path;
        if (path != '/wallet') {
          GoRouter.of(navContext).go('/wallet');
        }
      }
      return;
    }
    if (offerTouchIdAfterOpen) {
      _deferWalletNavigation = false;
    }
  }

  Future<void> _copyAddress(String address) async {
    final AppApi api = context.read<AppApi>();
    final LocaleController loc = context.read<LocaleController>();
    await api.writeText(address);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text(loc.tr('pages.wallet_select.index.copy_address_message'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final LocaleController loc = context.watch<LocaleController>();
    final GatewayStore store = context.watch<GatewayStore>();
    final Map<String, dynamic> wallets =
        Map<String, dynamic>.from(store.raw['wallets'] as Map? ?? {});
    final List<dynamic> list =
        (wallets['list'] as List<dynamic>?) ?? const <dynamic>[];
    final List<dynamic> directories =
        (wallets['directories'] as List<dynamic>?) ?? const <dynamic>[];

    final List<Map<String, String>> actions = <Map<String, String>>[
      <String, String>{
        'name': loc.tr('pages.wallet_select.index.create_new_account'),
        'path': '/wallet-select/create'
      },
      <String, String>{
        'name': loc.tr('pages.wallet_select.index.restore_account_from_seed'),
        'path': '/wallet-select/restore'
      },
      <String, String>{
        'name':
            loc.tr('pages.wallet_select.index.restore_account_from_viewkey'),
        'path': '/wallet-select/import-view-only',
      },
    ];
    if (directories.isNotEmpty) {
      actions.add(<String, String>{
        'name':
            loc.tr('pages.wallet_select.index.import_accounts_from_old_gui'),
        'path': '/wallet-select/import-old-gui',
      });
    }

    Widget walletRow(Map<String, dynamic> w) {
      return Card(
        color: const Color(0xFF161410),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: ArqmaColors.outlineDefault.withValues(alpha: 0.75),
            width: 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          leading: AddressIdenticon(address: '${w['address'] ?? ''}', size: 44),
          title: Text(
            '${w['name']}',
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: ArqmaColors.textPrimary,
            ),
          ),
          subtitle: Text(
            '${w['address']}',
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              color: ArqmaColors.textMuted,
              height: 1.35,
            ),
          ),
          onTap: () => _openWallet(w),
          trailing: PopupMenuButton<String>(
            onSelected: (String v) {
              if (v == 'open') {
                _openWallet(w);
              } else if (v == 'copy') {
                _copyAddress('${w['address']}');
              }
            },
            itemBuilder: (BuildContext c) => [
              PopupMenuItem<String>(
                  value: 'open',
                  child:
                      Text(loc.tr('pages.wallet_select.index.open_account'))),
              PopupMenuItem<String>(
                  value: 'copy',
                  child:
                      Text(loc.tr('pages.wallet_select.index.copy_address'))),
            ],
          ),
        ),
      );
    }

    final int appCode = store.appStatusCode;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // `app.status.code == -1`: core startup failed (paths, daemon reachability, or similar). Same idea as
        // Tauri when the user must revisit the welcome flow — `/welcome` lets them fix dirs and node.
        if (appCode == -1)
          Material(
            color: const Color(0xFF3a2a0a),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(
                children: [
                  const Icon(Icons.info_outline,
                      color: Color(0xFFdbd19c), size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      loc.tr('pages.wallet_select.index.setup_required_banner'),
                      style: const TextStyle(
                          fontSize: 12, color: ArqmaColors.textSecondary),
                    ),
                  ),
                  TextButton(
                    onPressed: () => context.push('/welcome'),
                    child: Text(loc
                        .tr('pages.wallet_select.index.setup_wizard_button')),
                  ),
                ],
              ),
            ),
          ),
        if (list.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Text(
                    loc.tr('pages.wallet_select.index.accounts'),
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w500,
                      color: ArqmaColors.textPrimary,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
                const Spacer(),
                PopupMenuButton<Map<String, String>>(
                  icon: const Icon(Icons.add, color: ArqmaColors.arqmaGreenSolid),
                  onSelected: (Map<String, String> a) =>
                      context.push(a['path']!),
                  itemBuilder: (BuildContext c) => actions
                      .map((Map<String, String> a) =>
                          PopupMenuItem<Map<String, String>>(
                              value: a, child: Text(a['name']!)))
                      .toList(),
                ),
              ],
            ),
          ),
          const Divider(height: 24, color: ArqmaColors.dividerLine),
          Expanded(
            child: ListView.separated(
              primary: false,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              itemCount: list.length,
              separatorBuilder: (BuildContext context, int index) =>
                  const SizedBox(height: 8),
              itemBuilder: (BuildContext c, int i) =>
                  walletRow(Map<String, dynamic>.from(list[i] as Map)),
            ),
          ),
        ] else
          Expanded(
            child: ListView(
              primary: false,
              padding: const EdgeInsets.all(16),
              children: actions
                  .map(
                    (Map<String, String> a) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: ElevatedButton(
                        onPressed: () => context.push(a['path']!),
                        child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(a['name']!)),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
      ],
    );
  }
}

/// Result from the open-wallet password dialog (Touch ID runs after dismiss on macOS).
class _OpenWalletPasswordDialogResult {
  const _OpenWalletPasswordDialogResult.biometric()
      : requestBiometric = true,
        password = null,
        enableBiometricAfterOpen = false;
  const _OpenWalletPasswordDialogResult.password(
    this.password, {
    this.enableBiometricAfterOpen = false,
  }) : requestBiometric = false;

  final bool requestBiometric;
  final String? password;
  final bool enableBiometricAfterOpen;
}

/// Owns the password [TextEditingController] for the route lifetime (avoids
/// disposing before the dialog subtree finishes unmounting).
class _OpenWalletPasswordDialog extends StatefulWidget {
  const _OpenWalletPasswordDialog({
    required this.loc,
    required this.walletName,
    required this.netType,
  });

  final LocaleController loc;
  final String walletName;
  final String netType;

  @override
  State<_OpenWalletPasswordDialog> createState() =>
      _OpenWalletPasswordDialogState();
}

class _OpenWalletPasswordDialogState extends State<_OpenWalletPasswordDialog> {
  late final TextEditingController _pw = TextEditingController();
  bool _biometricAvailable = false;
  bool _biometricOfferVisible = WalletBiometricUnlock.isNativeBiometricPlatform;
  bool _enableBiometricAfterLogin = true;
  List<BiometricType> _biometricTypes = <BiometricType>[];

  @override
  void initState() {
    super.initState();
    unawaited(_loadBiometricState());
  }

  Future<void> _loadBiometricState() async {
    if (!WalletBiometricUnlock.isNativeBiometricPlatform) {
      return;
    }
    final bool supported = await WalletBiometricUnlock.isPlatformSupported();
    final List<BiometricType> types =
        await WalletBiometricUnlock.availableBiometrics();
    final bool enabled = await WalletBiometricUnlock.isEnabled(
      widget.netType,
      widget.walletName,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _biometricAvailable = supported && enabled;
      _biometricOfferVisible = supported && !enabled;
      _biometricTypes = types;
    });
  }

  void _submitPassword() {
    Navigator.pop(
      context,
      _OpenWalletPasswordDialogResult.password(
        _pw.text,
        enableBiometricAfterOpen:
            _biometricOfferVisible && _enableBiometricAfterLogin,
      ),
    );
  }

  void _requestBiometricUnlock() {
    Navigator.pop(context, const _OpenWalletPasswordDialogResult.biometric());
  }

  @override
  void dispose() {
    _pw.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final String bioLabel = WalletBiometricUnlock.biometricLabel(
      _biometricTypes,
      faceIdLabel: widget.loc.tr('pages.wallet_select.index.face_id_unlock_button'),
      touchIdLabel:
          widget.loc.tr('pages.wallet_select.index.touch_id_unlock_button'),
      genericLabel:
          widget.loc.tr('pages.wallet_select.index.biometric_unlock_button'),
    );

    return AlertDialog(
      backgroundColor: const Color(0xFF1d1d1d),
      title: Text(
          widget.loc.tr('pages.wallet_select.index.open_wallet_password_title')),
      content: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 300),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_biometricAvailable) ...[
              OutlinedButton.icon(
                onPressed: _requestBiometricUnlock,
                icon: Icon(
                  _biometricTypes.contains(BiometricType.face)
                      ? Icons.face
                      : Icons.fingerprint,
                  color: ArqmaColors.arqmaGreenSolid,
                ),
                label: Text(bioLabel),
              ),
              const SizedBox(height: 16),
            ],
            TextField(
              controller: _pw,
              autofocus: !_biometricAvailable,
              obscureText: true,
              style: const TextStyle(
                color: ArqmaColors.textPrimary,
                fontSize: 15,
              ),
              cursorColor: ArqmaColors.arqmaGreenSolid,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submitPassword(),
              decoration: InputDecoration(
                labelText: widget.loc
                    .tr('pages.wallet_select.index.open_wallet_password_message'),
              ),
            ),
            if (_biometricOfferVisible) ...[
              const SizedBox(height: 12),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _enableBiometricAfterLogin,
                onChanged: (bool? v) {
                  setState(() => _enableBiometricAfterLogin = v ?? false);
                },
                title: Text(
                  widget.loc
                      .tr('pages.wallet_select.index.face_id_enable_switch_label'),
                  style: const TextStyle(fontSize: 13),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(widget.loc
              .tr('pages.wallet_select.index.open_wallet_cancel_label')),
        ),
        TextButton(
          onPressed: _submitPassword,
          child: Text(
              widget.loc.tr('pages.wallet_select.index.open_wallet_ok_label')),
        ),
      ],
    );
  }
}

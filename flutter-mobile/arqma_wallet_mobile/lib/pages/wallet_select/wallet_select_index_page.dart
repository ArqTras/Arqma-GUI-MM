import 'dart:async';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart'
    show debugPrint, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:local_auth/local_auth.dart';
import 'package:provider/provider.dart';

import '../../app_nav.dart';
import '../../core/app_api.dart';
import '../../core/desktop/arqma_paths.dart';
import '../../core/mobile/wallet_biometric_unlock.dart';
import '../../i18n/locale_controller.dart';
import '../../store/gateway_store.dart';
import '../../widgets/address_identicon.dart';
import '../../widgets/app_loading.dart';
import '../../widgets/mobile_remote_connection_banner.dart';
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

  /// Blocks [_onWalletStatus] navigation while the Face ID enable dialog is shown.
  bool _deferWalletNavigation = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      unawaited(_bootstrapAccountsPage());
    });
    _gatewayListenTarget = context.read<GatewayStore>();
    _gatewayListenTarget!.addListener(_onWalletStatus);
  }

  /// Close any lingering FFI session before listing accounts (avoids open_wallet races).
  Future<void> _bootstrapAccountsPage() async {
    if (!mounted) {
      return;
    }
    final GatewayStore store = context.read<GatewayStore>();
    final AppApi api = context.read<AppApi>();
    if (store.hasOpenWallet) {
      try {
        await api.send('wallet', 'close_wallet', <String, dynamic>{});
      } catch (e, st) {
        debugPrint('[WalletSelect] close_wallet on index: $e\n$st');
      }
    }
    if (!mounted) {
      return;
    }
    final Map<String, dynamic>? merged = mergedFilesystemConfig(store.app);
    await api.send(
      'wallet',
      'list_wallets',
      merged ?? <String, dynamic>{},
    );
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
    final Map<String, dynamic>? cfg = store.app['config'] as Map<String, dynamic>?;
    return (cfg?['app'] as Map?)?['net_type'] as String? ?? 'mainnet';
  }

  Future<void> _maybeOfferFaceIdEnable({
    required LocaleController loc,
    required String netType,
    required String walletName,
    required String password,
  }) async {
    if (!Platform.isIOS || password.isEmpty) {
      debugPrint('[WalletSelect] Face ID offer skipped: not iOS or empty password');
      return;
    }
    if (!await WalletBiometricUnlock.isPlatformSupported()) {
      debugPrint('[WalletSelect] Face ID offer skipped: platform unsupported');
      return;
    }
    if (await WalletBiometricUnlock.isEnabled(netType, walletName)) {
      debugPrint('[WalletSelect] Face ID offer skipped: already enabled');
      return;
    }
    if (await WalletBiometricUnlock.wasOfferSkipped(netType, walletName)) {
      debugPrint('[WalletSelect] Face ID offer skipped: user chose Not now');
      return;
    }
    await WalletBiometricUnlock.waitForModalDismiss();
    final BuildContext? dialogContext = appNavigatorKey.currentContext;
    if (dialogContext == null || !dialogContext.mounted) {
      debugPrint('[WalletSelect] Face ID offer skipped: no root navigator context');
      return;
    }
    debugPrint('[WalletSelect] showing Face ID enable dialog');
    final bool? enable = await showDialog<bool>(
      context: dialogContext,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (BuildContext c) => AlertDialog(
        backgroundColor: const Color(0xFF1d1d1d),
        title: Text(loc.tr('pages.wallet_select.index.enable_face_id_title')),
        content: Text(loc.tr('pages.wallet_select.index.enable_face_id_message')),
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
        localizedReason: loc.tr('pages.wallet_select.index.face_id_enable_reason'),
      );
      final BuildContext? snackContext = appNavigatorKey.currentContext;
      if (snackContext != null && snackContext.mounted) {
        ScaffoldMessenger.of(snackContext).showSnackBar(
          SnackBar(
            content: Text(loc.tr('pages.wallet_select.index.face_id_enabled_message')),
          ),
        );
      }
    } catch (e) {
      final BuildContext? snackContext = appNavigatorKey.currentContext;
      if (snackContext != null && snackContext.mounted) {
        ScaffoldMessenger.of(snackContext).showSnackBar(
          SnackBar(
            content: Text(loc.tr('pages.wallet_select.index.face_id_failed_message')),
          ),
        );
      }
      debugPrint('[WalletSelect] enable Face ID: $e');
    }
  }

  Future<void> _enableFaceIdAfterSuccessfulOpen({
    required LocaleController loc,
    required String netType,
    required String walletName,
    required String password,
  }) async {
    WalletBiometricUnlock.scheduleEnable(
      PendingFaceIdEnable(
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
    if (!Platform.isIOS) {
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
          content: Text(loc.tr('pages.wallet_select.index.face_id_failed_message')),
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
    // Tauri parity: prompt unless meta explicitly has password_protected: false.
    final bool pwdProt = wallet['password_protected'] != false;
    String? password;
    bool enableFaceIdAfterOpen = false;
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
        enableFaceIdAfterOpen = picked.enableFaceIdAfterOpen;
      }
    } else {
      password = '';
    }
    final bool offerFaceIdAfterOpen =
        pwdProt && Platform.isIOS && password.isNotEmpty;
    if (offerFaceIdAfterOpen) {
      _deferWalletNavigation = true;
    }
    await AppLoading.show();
    await api.send('wallet', 'open_wallet',
        <String, dynamic>{'name': name, 'password': password});
    AppLoading.hide();
    final Map<String, dynamic> st =
        store.wallet['status'] as Map<String, dynamic>;
    final int code = st['code'] as int? ?? 1;
    if (code == 0) {
      if (enableFaceIdAfterOpen) {
        await _enableFaceIdAfterSuccessfulOpen(
          loc: loc,
          netType: netType,
          walletName: name,
          password: password,
        );
      } else if (offerFaceIdAfterOpen) {
        await _maybeOfferFaceIdEnable(
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
    if (offerFaceIdAfterOpen) {
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

  Future<void> _showWalletDeleteMenu(Map<String, dynamic> wallet) async {
    final LocaleController loc = context.read<LocaleController>();
    final String name = '${wallet['name']}';
    final String deleteLabel =
        loc.tr('components.wallet_settings.delete_account');
    final String cancelLabel = loc.tr('composables.cancel');

    final String? action;
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      action = await showCupertinoModalPopup<String>(
        context: context,
        builder: (BuildContext c) => CupertinoActionSheet(
          title: Text(name),
          actions: <Widget>[
            CupertinoActionSheetAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.pop(c, 'delete'),
              child: Text(deleteLabel),
            ),
          ],
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(c),
            child: Text(cancelLabel),
          ),
        ),
      );
    } else {
      action = await showModalBottomSheet<String>(
        context: context,
        backgroundColor: const Color(0xFF1d1d1d),
        builder: (BuildContext c) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Text(
                  name,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: ArqmaColors.textPrimary,
                  ),
                ),
              ),
              ListTile(
                leading:
                    const Icon(Icons.delete_outline, color: Colors.redAccent),
                title: Text(deleteLabel),
                onTap: () => Navigator.pop(c, 'delete'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
    }
    if (action != 'delete' || !mounted) {
      return;
    }
    await _confirmAndDeleteWallet(wallet);
  }

  Future<void> _confirmAndDeleteWallet(Map<String, dynamic> wallet) async {
    final LocaleController loc = context.read<LocaleController>();
    final AppApi api = context.read<AppApi>();
    final String name = '${wallet['name']}';
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext c) => AlertDialog(
        backgroundColor: const Color(0xFF1d1d1d),
        title: Text(loc.tr('components.wallet_settings.delete_account')),
        content: Text(
          loc.tr('components.wallet_settings.delete_account_message'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(loc.tr(
                'components.wallet_settings.delete_account_cancel_label')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(
              loc.tr('components.wallet_settings.delete_account_ok_label'),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    await api.send(
      'wallet',
      'delete_wallet',
      <String, dynamic>{'name': name},
    );
    if (mounted) {
      final GatewayStore store = context.read<GatewayStore>();
      await WalletBiometricUnlock.disable(_netType(store), name);
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
          onLongPress: () => _showWalletDeleteMenu(w),
          trailing: PopupMenuButton<String>(
            onSelected: (String v) {
              if (v == 'open') {
                _openWallet(w);
              } else if (v == 'copy') {
                _copyAddress('${w['address']}');
              } else if (v == 'delete') {
                unawaited(_confirmAndDeleteWallet(w));
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
              PopupMenuItem<String>(
                value: 'delete',
                child: Text(
                  loc.tr('components.wallet_settings.delete_account'),
                  style: const TextStyle(color: Colors.redAccent),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final int appCode = store.appStatusCode;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const MobileRemoteConnectionBanner(),
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

/// Result from the open-wallet password dialog (Face ID runs after dismiss — iOS).
class _OpenWalletPasswordDialogResult {
  const _OpenWalletPasswordDialogResult.biometric()
      : requestBiometric = true,
        password = null,
        enableFaceIdAfterOpen = false;
  const _OpenWalletPasswordDialogResult.password(
    this.password, {
    this.enableFaceIdAfterOpen = false,
  }) : requestBiometric = false;

  final bool requestBiometric;
  final String? password;
  final bool enableFaceIdAfterOpen;
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
  bool _faceIdOfferVisible = Platform.isIOS;
  bool _enableFaceIdAfterLogin = true;
  List<BiometricType> _biometricTypes = <BiometricType>[];

  @override
  void initState() {
    super.initState();
    unawaited(_loadBiometricState());
  }

  Future<void> _loadBiometricState() async {
    if (!Platform.isIOS) {
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
      _faceIdOfferVisible = supported && !enabled;
      _biometricTypes = types;
    });
  }

  void _submitPassword() {
    Navigator.pop(
      context,
      _OpenWalletPasswordDialogResult.password(
        _pw.text,
        enableFaceIdAfterOpen:
            _faceIdOfferVisible && _enableFaceIdAfterLogin,
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
            if (_faceIdOfferVisible) ...[
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  widget.loc.tr(
                      'pages.wallet_select.index.face_id_enable_switch_label'),
                  style: const TextStyle(
                    color: ArqmaColors.textPrimary,
                    fontSize: 14,
                  ),
                ),
                subtitle: Text(
                  widget.loc.tr(
                      'pages.wallet_select.index.enable_face_id_message'),
                  style: TextStyle(
                    color: ArqmaColors.textPrimary.withValues(alpha: 0.72),
                    fontSize: 12,
                  ),
                ),
                value: _enableFaceIdAfterLogin,
                activeThumbColor: ArqmaColors.arqmaGreenSolid,
                onChanged: (bool value) {
                  setState(() => _enableFaceIdAfterLogin = value);
                },
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

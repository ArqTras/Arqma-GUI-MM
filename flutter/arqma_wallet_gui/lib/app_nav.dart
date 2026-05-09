import 'package:flutter/material.dart';

/// Root navigator for global dialogs / loading (parity with Quasar plugins).
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

/// Global snackbars from `show_notification` (parity with Quasar `Notify`).
final GlobalKey<ScaffoldMessengerState> appScaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

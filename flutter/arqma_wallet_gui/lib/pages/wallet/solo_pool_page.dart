import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../app_nav.dart';
import '../../core/app_api.dart';
import '../../core/services/native_bridge.dart';
import '../../core/utils/deep_merge.dart';
import '../../i18n/locale_controller.dart';
import '../../store/gateway_store.dart';
import '../../core/theme/arqma_colors.dart';

// --- Parity helpers with `pages/wallet/solo-pool.vue` (chart + VarDiff snapshot) ---

Map<String, dynamic>? _snapshotVarDiff(Map<String, dynamic>? vd) {
  if (vd == null) {
    return null;
  }
  return <String, dynamic>{
    'startDiff': int.tryParse('${vd['startDiff']}') ?? 0,
    'minDiff': int.tryParse('${vd['minDiff']}') ?? 0,
    'maxDiff': int.tryParse('${vd['maxDiff']}') ?? 0,
    'targetTime': int.tryParse('${vd['targetTime']}') ?? 0,
    'retargetTime': int.tryParse('${vd['retargetTime']}') ?? 0,
    'variancePercent': int.tryParse('${vd['variancePercent']}') ?? 0,
    'maxJump': int.tryParse('${vd['maxJump']}') ?? 0,
    'fixedDiffSeparator': '${vd['fixedDiffSeparator'] ?? '.'}',
  };
}

bool _varDiffParamsChanged(
    Map<String, dynamic>? before, Map<String, dynamic>? after) {
  final Map<String, dynamic>? a = _snapshotVarDiff(before);
  final Map<String, dynamic>? b = _snapshotVarDiff(after);
  if (a == null && b == null) {
    return false;
  }
  if (a == null || b == null) {
    return true;
  }
  return jsonEncode(a) != jsonEncode(b);
}

int _chartBucketWanted(String chartRange) {
  switch (chartRange) {
    case '15m':
      return 15;
    case '6h':
      return 360;
    default:
      return 60;
  }
}

List<Offset> _soloPoolAggregatePoints(List<Map<String, dynamic>> workersAll,
    String selectedWorker, String chartRange) {
  final int wanted = _chartBucketWanted(chartRange);
  final List<Map<String, dynamic>> src = selectedWorker == '__all__'
      ? workersAll
      : workersAll
          .where((Map<String, dynamic> w) => '${w['miner']}' == selectedWorker)
          .toList();
  final Map<num, double> buckets = <num, double>{};
  for (final Map<String, dynamic> w in src) {
    final Object? g = w['hashrate_graph'];
    if (g is! Map) {
      continue;
    }
    g.forEach((dynamic k, dynamic v) {
      final num key = num.tryParse('$k') ?? 0;
      buckets[key] = (buckets[key] ?? 0) + (num.tryParse('$v') ?? 0).toDouble();
    });
  }
  final List<MapEntry<num, double>> entries = buckets.entries.toList()
    ..sort((MapEntry<num, double> a, MapEntry<num, double> b) =>
        a.key.compareTo(b.key));
  final List<MapEntry<num, double>> slice = entries.length <= wanted
      ? entries
      : entries.sublist(entries.length - wanted);
  final List<double> ordered =
      slice.map((MapEntry<num, double> e) => e.value).toList();
  if (ordered.length < 2) {
    return <Offset>[const Offset(0, 120), const Offset(600, 120)];
  }
  final double maxV = math.max(ordered.reduce(math.max), 1.0);
  return List<Offset>.generate(ordered.length, (int i) {
    final double x = (i / (ordered.length - 1)) * 600;
    final double y = 120 - ((ordered[i] / maxV) * 110);
    return Offset(x, y);
  });
}

const List<Color> _soloChartLineColors = <Color>[
  Color(0xFFdbd19c),
  Color(0xFFa89060),
  Color(0xFFe8d4a8),
  Color(0xFF8b7355),
  Color(0xFFc9a86c),
  Color(0xFFf0e4c4),
  Color(0xFF6d5a40),
  Color(0xFFb89b6a),
];

class _WorkerChartLine {
  const _WorkerChartLine(
      {required this.color, required this.miner, required this.points});
  final Color color;
  final String miner;
  final List<Offset> points;
}

List<_WorkerChartLine> _soloPoolWorkerLines(
    List<Map<String, dynamic>> workersAll, String chartRange) {
  if (workersAll.isEmpty) {
    return <_WorkerChartLine>[];
  }
  final int wanted = _chartBucketWanted(chartRange);
  final List<Map<String, dynamic>> top =
      List<Map<String, dynamic>>.from(workersAll)
        ..sort(
          (Map<String, dynamic> a, Map<String, dynamic> b) =>
              (num.tryParse('${b['hashrate_5min']}') ?? 0)
                  .compareTo(num.tryParse('${a['hashrate_5min']}') ?? 0),
        );
  final List<Map<String, dynamic>> top6 = top.take(6).toList();
  final List<_WorkerChartLine> out = <_WorkerChartLine>[];
  for (int idx = 0; idx < top6.length; idx++) {
    final Map<String, dynamic> w = top6[idx];
    final Object? g = w['hashrate_graph'];
    final Color color = _soloChartLineColors[idx % _soloChartLineColors.length];
    if (g is! Map) {
      continue;
    }
    final List<MapEntry<num, double>> entries = g.entries
        .map(
          (MapEntry<dynamic, dynamic> e) => MapEntry<num, double>(
            num.tryParse('${e.key}') ?? 0,
            (num.tryParse('${e.value}') ?? 0).toDouble(),
          ),
        )
        .toList()
      ..sort((MapEntry<num, double> a, MapEntry<num, double> b) =>
          a.key.compareTo(b.key));
    final List<MapEntry<num, double>> slice = entries.length <= wanted
        ? entries
        : entries.sublist(entries.length - wanted);
    final List<double> ordered =
        slice.map((MapEntry<num, double> e) => e.value).toList();
    if (ordered.length < 2) {
      out.add(_WorkerChartLine(
          color: color,
          miner: '${w['miner']}',
          points: const <Offset>[Offset(0, 120), Offset(600, 120)]));
      continue;
    }
    final double maxV = math.max(ordered.reduce(math.max), 1.0);
    final List<Offset> pts = List<Offset>.generate(ordered.length, (int i) {
      final double x = (i / (ordered.length - 1)) * 600;
      final double y = 120 - ((ordered[i] / maxV) * 110);
      return Offset(x, y);
    });
    out.add(
        _WorkerChartLine(color: color, miner: '${w['miner']}', points: pts));
  }
  return out;
}

double _soloChartTopLabel(List<Offset> aggregate) {
  if (aggregate.length < 2) {
    return 0;
  }
  final double minY = aggregate.map((Offset p) => p.dy).reduce(math.min);
  return (math.max(0, ((120 - minY) / 110 * 1000).round()) * 1000).toDouble();
}

String _formatSoloPoolBlockTime(num? blockTimeMs) {
  final int n = (blockTimeMs ?? 0).toInt();
  if (n <= 0) {
    return '—';
  }
  if (n < 60000) {
    return '${(n / 1000).round()} s';
  }
  if (n < 3600000) {
    return '${(n / 60000).round()} min';
  }
  return '${(n / 3600000).toStringAsFixed(1)} h';
}

class _SoloPoolHashrateChartPainter extends CustomPainter {
  _SoloPoolHashrateChartPainter(
      {required this.aggregate, required this.workerLines});

  final List<Offset> aggregate;
  final List<_WorkerChartLine> workerLines;

  @override
  void paint(Canvas canvas, Size size) {
    double sx(double x) => x / 600 * size.width;
    double sy(double y) => y / 120 * size.height;

    final Paint gridY = Paint()
      ..color = const Color.fromRGBO(200, 175, 130, 0.35)
      ..strokeWidth = 1;
    for (final double gy in <double>[0, 30, 60, 90, 120]) {
      canvas.drawLine(Offset(0, sy(gy)), Offset(size.width, sy(gy)), gridY);
    }
    final Paint gridX = Paint()
      ..color = const Color.fromRGBO(200, 175, 130, 0.18)
      ..strokeWidth = 1;
    for (final double gx in <double>[0, 100, 200, 300, 400, 500, 600]) {
      canvas.drawLine(Offset(sx(gx), 0), Offset(sx(gx), size.height), gridX);
    }

    for (final _WorkerChartLine wl in workerLines) {
      _drawPolyline(canvas, size, wl.points, wl.color, 1.8);
    }
    if (aggregate.length >= 2) {
      _drawPolyline(canvas, size, aggregate, const Color(0xFFd4b76a), 2);
    }
  }

  void _drawPolyline(
      Canvas canvas, Size size, List<Offset> pts, Color color, double strokeW) {
    double sx(double x) => x / 600 * size.width;
    double sy(double y) => y / 120 * size.height;
    if (pts.length < 2) {
      return;
    }
    final Path path = Path()..moveTo(sx(pts[0].dx), sy(pts[0].dy));
    for (int i = 1; i < pts.length; i++) {
      path.lineTo(sx(pts[i].dx), sy(pts[i].dy));
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeW
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _SoloPoolHashrateChartPainter oldDelegate) =>
      true;
}

/// Parity with `pages/wallet/solo-pool.vue` (stats, mining, VarDiff, workers/blocks tables, save).
class SoloPoolPage extends StatefulWidget {
  const SoloPoolPage({super.key});

  @override
  State<SoloPoolPage> createState() => _SoloPoolPageState();
}

class _SoloPoolPageState extends State<SoloPoolPage> {
  bool _loaded = false;
  bool _controllersReady = false;
  Map<String, dynamic> _settings = _soloDefaults();

  late final TextEditingController _miningAddress;
  late final TextEditingController _bindPort;
  String _bindIpValue = '';

  String _chartRange = '60m';
  String _selectedWorker = '__all__';

  late final TextEditingController _blockRefresh;
  late final TextEditingController _minerTimeout;
  bool _enableBlockRefresh = false;

  late final TextEditingController _vdStart;
  late final TextEditingController _vdMin;
  late final TextEditingController _vdMax;
  late final TextEditingController _vdTarget;
  late final TextEditingController _vdRetarget;
  late final TextEditingController _vdVariance;
  late final TextEditingController _vdMaxJump;
  late final TextEditingController _vdSeparator;

  static Map<String, dynamic> _soloDefaults() {
    return <String, dynamic>{
      'server': <String, dynamic>{
        'enabled': false,
        'bindIP': '',
        'bindPort': 3333,
      },
      'mining': <String, dynamic>{
        'address': '',
        'enableBlockRefreshInterval': false,
        'blockRefreshInterval': 5,
        'minerTimeout': 900,
      },
      'varDiff': <String, dynamic>{
        'enabled': true,
        'startDiff': 150000,
        'minDiff': 150000,
        'maxDiff': 10000000,
        'targetTime': 20,
        'retargetTime': 30,
        'variancePercent': 25,
        'maxJump': 200,
        'fixedDiffSeparator': '.',
      },
    };
  }

  static String _commas(num v) =>
      NumberFormat.decimalPattern().format(v.round());

  static String _shortHashrate(num h) {
    double n = h.toDouble();
    const List<String> units = <String>['H/s', 'kH/s', 'MH/s', 'GH/s', 'TH/s'];
    int i = 0;
    while (n >= 1000 && i < units.length - 1) {
      n /= 1000;
      i++;
    }
    return '${n.toStringAsFixed(2)} ${units[i]}';
  }

  @override
  void initState() {
    super.initState();
    _miningAddress = TextEditingController();
    _bindPort = TextEditingController();
    _blockRefresh = TextEditingController();
    _minerTimeout = TextEditingController();
    _vdStart = TextEditingController();
    _vdMin = TextEditingController();
    _vdMax = TextEditingController();
    _vdTarget = TextEditingController();
    _vdRetarget = TextEditingController();
    _vdVariance = TextEditingController();
    _vdMaxJump = TextEditingController();
    _vdSeparator = TextEditingController();
  }

  void _mergeSettingsFromStore(GatewayStore store) {
    final Map<String, dynamic> cfg = Map<String, dynamic>.from(
        store.app['config'] as Map? ?? <String, dynamic>{});
    final Map<String, dynamic>? p = cfg['pool'] as Map<String, dynamic>?;
    final Map<String, dynamic> d = _soloDefaults();
    if (p != null) {
      final Map<String, dynamic> parsed =
          jsonDecode(jsonEncode(p)) as Map<String, dynamic>;
      _settings = deepMergeMaps(d, parsed) as Map<String, dynamic>;
    } else {
      _settings = d;
    }
    final List<dynamic> wallets =
        (store.raw['wallets'] as Map?)?['list'] as List<dynamic>? ??
            const <dynamic>[];
    final String curAddr = '${store.walletInfo['address'] ?? ''}';
    final Map<String, dynamic> mining = Map<String, dynamic>.from(
        _settings['mining'] as Map? ?? <String, dynamic>{});
    if ('${mining['address']}'.isEmpty && wallets.isNotEmpty) {
      mining['address'] = '${(wallets.first as Map)['address'] ?? ''}';
    } else if ('${mining['address']}'.isEmpty && curAddr.isNotEmpty) {
      mining['address'] = curAddr;
    }
    _settings['mining'] = mining;
    final Map<String, dynamic> vd = Map<String, dynamic>.from(
        _settings['varDiff'] as Map? ?? <String, dynamic>{});
    vd['enabled'] = true;
    _settings['varDiff'] = vd;
  }

  void _populateControllers() {
    final Map<String, dynamic> mining = Map<String, dynamic>.from(
        _settings['mining'] as Map? ?? <String, dynamic>{});
    final Map<String, dynamic> server = Map<String, dynamic>.from(
        _settings['server'] as Map? ?? <String, dynamic>{});
    final Map<String, dynamic> vd = Map<String, dynamic>.from(
        _settings['varDiff'] as Map? ?? <String, dynamic>{});
    _miningAddress.text = '${mining['address']}';
    _bindIpValue = '${server['bindIP'] ?? ''}';
    if (_bindIpValue.isEmpty) {
      _bindIpValue = '127.0.0.1';
    }
    _bindPort.text = '${server['bindPort']}';
    _enableBlockRefresh = mining['enableBlockRefreshInterval'] == true;
    _blockRefresh.text = '${mining['blockRefreshInterval'] ?? 5}';
    _minerTimeout.text = '${mining['minerTimeout'] ?? 900}';
    _vdStart.text = '${vd['startDiff']}';
    _vdMin.text = '${vd['minDiff']}';
    _vdMax.text = '${vd['maxDiff']}';
    _vdTarget.text = '${vd['targetTime']}';
    _vdRetarget.text = '${vd['retargetTime']}';
    _vdVariance.text = '${vd['variancePercent']}';
    _vdMaxJump.text = '${vd['maxJump']}';
    _vdSeparator.text = '${vd['fixedDiffSeparator'] ?? '.'}';
  }

  List<String> _bindIpChoices(GatewayStore store) {
    final Set<String> ips = <String>{'127.0.0.1'};
    final Map<String, dynamic> cfg = Map<String, dynamic>.from(
        store.app['config'] as Map? ?? <String, dynamic>{});
    final String? cur = (cfg['pool'] as Map?)?['server']?['bindIP'] as String?;
    if (cur != null && cur.isNotEmpty) {
      ips.add(cur);
    }
    final List<dynamic> remotes =
        store.app['remotes'] as List<dynamic>? ?? const <dynamic>[];
    for (final dynamic r in remotes) {
      if (r is Map) {
        final String h = '${r['host'] ?? r['address'] ?? ''}'.trim();
        if (h.isNotEmpty) {
          ips.add(h);
        }
      }
    }
    final List<String> out = ips.toList()..sort();
    return out;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final GatewayStore store = context.read<GatewayStore>();
    if (!_loaded) {
      _loaded = true;
      _mergeSettingsFromStore(store);
    }
    if (!_controllersReady) {
      _controllersReady = true;
      _populateControllers();
    }
  }

  @override
  void dispose() {
    _miningAddress.dispose();
    _bindPort.dispose();
    _blockRefresh.dispose();
    _minerTimeout.dispose();
    _vdStart.dispose();
    _vdMin.dispose();
    _vdMax.dispose();
    _vdTarget.dispose();
    _vdRetarget.dispose();
    _vdVariance.dispose();
    _vdMaxJump.dispose();
    _vdSeparator.dispose();
    super.dispose();
  }

  List<({String label, String value})> _miningAddressChoices(
      GatewayStore store) {
    final List<dynamic> wallets =
        (store.raw['wallets'] as Map?)?['list'] as List<dynamic>? ??
            const <dynamic>[];
    final String curAddr = '${store.walletInfo['address'] ?? ''}';
    if (curAddr.isNotEmpty) {
      Map<String, dynamic>? activeWallet;
      for (final dynamic w in wallets) {
        if (w is Map && '${w['address']}' == curAddr) {
          activeWallet = Map<String, dynamic>.from(w);
          break;
        }
      }
      final String label = activeWallet != null
          ? '${activeWallet['name']} - ${activeWallet['address']}'
          : curAddr;
      return <({String label, String value})>[(label: label, value: curAddr)];
    }
    final Object? firstWallet = wallets.isNotEmpty ? wallets.first : null;
    if (firstWallet is Map) {
      final Map<String, dynamic> w = Map<String, dynamic>.from(firstWallet);
      return <({String label, String value})>[
        (label: '${w['name']} - ${w['address']}', value: '${w['address']}')
      ];
    }
    return <({String label, String value})>[];
  }

  void _showVarDiffRestartDialog() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final BuildContext? ctx = appNavigatorKey.currentContext;
      if (ctx == null) {
        return;
      }
      final LocaleController loc =
          Provider.of<LocaleController>(ctx, listen: false);
      final NativeBridge bridge = Provider.of<NativeBridge>(ctx, listen: false);
      unawaited(
        showDialog<void>(
          context: ctx,
          builder: (BuildContext c) => AlertDialog(
            title: Text(loc.tr('receiver.restart')),
            content:
                Text(loc.tr('components.solo_pool.vardiff_restart_prompt')),
            actions: <Widget>[
              TextButton(
                  onPressed: () => Navigator.pop(c),
                  child: Text(loc.tr('receiver.cancel'))),
              TextButton(
                onPressed: () {
                  Navigator.pop(c);
                  GoRouter.of(ctx).go('/quit');
                  unawaited(bridge.invoke(
                      'confirm_close', <String, dynamic>{'restart': true}));
                },
                child: Text(loc.tr('receiver.restart')),
              ),
            ],
          ),
        ),
      );
    });
  }

  static Color _statusChipColor(int status) {
    switch (status) {
      case 2:
        return ArqmaColors.arqmaGreenSolid;
      case 1:
        return ArqmaColors.arqmaGreenDarkSolid;
      case -1:
        return ArqmaColors.negative;
      default:
        return ArqmaColors.textMuted;
    }
  }

  Future<void> _save() async {
    final LocaleController loc = context.read<LocaleController>();
    final AppApi api = context.read<AppApi>();
    final GatewayStore store = context.read<GatewayStore>();
    final Map<String, dynamic>? cfg =
        store.app['config'] as Map<String, dynamic>?;
    final Map<String, dynamic>? prevPool =
        cfg?['pool'] as Map<String, dynamic>?;
    Map<String, dynamic>? prevVd;
    if (prevPool != null && prevPool['varDiff'] is Map) {
      prevVd = Map<String, dynamic>.from(prevPool['varDiff'] as Map);
    }

    final String? net = (cfg?['app'] as Map?)?['net_type'] as String?;
    final String daemonType =
        '${(cfg?['daemons'] as Map?)?[net]?['type'] ?? 'remote'}';

    final Map<String, dynamic> mining = Map<String, dynamic>.from(
        _settings['mining'] as Map? ?? <String, dynamic>{});
    mining['address'] = _miningAddress.text.trim();
    mining['enableBlockRefreshInterval'] = _enableBlockRefresh;
    mining['blockRefreshInterval'] = int.tryParse(_blockRefresh.text.trim()) ??
        mining['blockRefreshInterval'];
    mining['minerTimeout'] =
        int.tryParse(_minerTimeout.text.trim()) ?? mining['minerTimeout'];
    _settings['mining'] = mining;

    final Map<String, dynamic> server = Map<String, dynamic>.from(
        _settings['server'] as Map? ?? <String, dynamic>{});
    server['bindIP'] = _bindIpValue;
    server['bindPort'] =
        int.tryParse(_bindPort.text.trim()) ?? server['bindPort'];
    _settings['server'] = server;

    final Map<String, dynamic> vd = Map<String, dynamic>.from(
        _settings['varDiff'] as Map? ?? <String, dynamic>{});
    vd['enabled'] = true;
    vd['startDiff'] = int.tryParse(_vdStart.text.trim()) ?? vd['startDiff'];
    vd['minDiff'] = int.tryParse(_vdMin.text.trim()) ?? vd['minDiff'];
    vd['maxDiff'] = int.tryParse(_vdMax.text.trim()) ?? vd['maxDiff'];
    vd['targetTime'] = int.tryParse(_vdTarget.text.trim()) ?? vd['targetTime'];
    vd['retargetTime'] =
        int.tryParse(_vdRetarget.text.trim()) ?? vd['retargetTime'];
    vd['variancePercent'] =
        int.tryParse(_vdVariance.text.trim()) ?? vd['variancePercent'];
    vd['maxJump'] = int.tryParse(_vdMaxJump.text.trim()) ?? vd['maxJump'];
    vd['fixedDiffSeparator'] = _vdSeparator.text.trim().isEmpty
        ? '.'
        : _vdSeparator.text.trim().substring(0, 1);
    _settings['varDiff'] = vd;

    if (daemonType == 'remote') {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(loc.tr('components.solo_pool.remote_warning')),
              duration: const Duration(seconds: 2)),
        );
      }
      server['enabled'] = false;
      _settings['server'] = server;
    }

    if (mining['address'] == '') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(loc.tr('components.solo_pool.address_required'))),
      );
      return;
    }
    final int port = server['bindPort'] as int? ?? 0;
    if (port < 1024 || port > 65535) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(loc.tr('components.solo_pool.invalid_port'))),
      );
      return;
    }
    final Map<String, dynamic> poolPayload =
        jsonDecode(jsonEncode(_settings)) as Map<String, dynamic>;
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    await api.send('core', 'save_pool_config', poolPayload);
    if (!mounted) {
      return;
    }
    messenger.showSnackBar(
      SnackBar(content: Text(loc.tr('components.solo_pool.saved'))),
    );
    if (prevPool != null && _varDiffParamsChanged(prevVd, vd)) {
      _showVarDiffRestartDialog();
    }
  }

  @override
  Widget build(BuildContext context) {
    final LocaleController loc = context.watch<LocaleController>();
    final GatewayStore store = context.watch<GatewayStore>();
    final Map<String, dynamic> poolState = Map<String, dynamic>.from(
        store.raw['pool'] as Map? ?? <String, dynamic>{});
    final int status = (poolState['status'] as num?)?.toInt() ?? 0;
    final Map<String, dynamic> cfg = Map<String, dynamic>.from(
        store.app['config'] as Map? ?? <String, dynamic>{});
    final String? net = (cfg['app'] as Map?)?['net_type'] as String?;
    final String daemonType =
        '${(cfg['daemons'] as Map?)?[net]?['type'] ?? 'remote'}';
    final Map<String, dynamic> server = Map<String, dynamic>.from(
        _settings['server'] as Map? ?? <String, dynamic>{});

    final Map<String, dynamic> stats = Map<String, dynamic>.from(
        poolState['stats'] as Map? ?? <String, dynamic>{});
    final num netHr = num.tryParse('${stats['networkHashrate'] ?? 0}') ?? 0;
    final num diff = num.tryParse('${stats['diff'] ?? 0}') ?? 0;
    final num height = num.tryParse('${stats['height'] ?? 0}') ?? 0;
    final List<dynamic> workersRaw =
        poolState['workers'] as List<dynamic>? ?? const <dynamic>[];
    final List<Map<String, dynamic>> workers = workersRaw
        .map((dynamic e) => Map<String, dynamic>.from(e as Map))
        .where((Map<String, dynamic> w) => '${w['miner']}' != 'all')
        .toList();
    final int activeWorkers =
        workers.where((Map<String, dynamic> w) => w['active'] == true).length;

    final Map<String, dynamic> hRates =
        Map<String, dynamic>.from(stats['h'] as Map? ?? <String, dynamic>{});
    final num hr5 = num.tryParse(
            '${hRates['hashrate_5min'] ?? stats['hashrate_5min'] ?? 0}') ??
        0;
    final num hr1 = num.tryParse(
            '${hRates['hashrate_1hr'] ?? stats['hashrate_1hr'] ?? 0}') ??
        0;
    final num hr6 = num.tryParse(
            '${hRates['hashrate_6hr'] ?? stats['hashrate_6hr'] ?? 0}') ??
        0;
    final num hr24 = num.tryParse(
            '${hRates['hashrate_24hr'] ?? stats['hashrate_24hr'] ?? 0}') ??
        0;

    final num blockTimeMs = num.tryParse('${stats['blockTime'] ?? 0}') ?? 0;
    final List<Map<String, dynamic>> effortCards = <Map<String, dynamic>>[
      <String, dynamic>{
        'label': loc.tr('components.solo_pool.round_hashes'),
        'value': _commas(num.tryParse('${stats['roundHashes'] ?? 0}') ?? 0)
      },
      <String, dynamic>{
        'label': loc.tr('components.solo_pool.current_effort'),
        'value': '${num.tryParse('${stats['currentEffort'] ?? 0}') ?? 0}'
      },
      <String, dynamic>{
        'label': loc.tr('components.solo_pool.average_effort'),
        'value': '${num.tryParse('${stats['averageEffort'] ?? 0}') ?? 0}'
      },
      <String, dynamic>{
        'label': loc.tr('components.solo_pool.est_block_time'),
        'value': _formatSoloPoolBlockTime(blockTimeMs)
      },
      <String, dynamic>{
        'label': loc.tr('components.solo_pool.blocks_found'),
        'value': '${stats['blocksFound'] ?? 0}'
      },
    ];

    final List<dynamic> blocksRaw =
        poolState['blocks'] as List<dynamic>? ?? const <dynamic>[];
    final List<Map<String, dynamic>> blocks = blocksRaw
        .map((dynamic e) => Map<String, dynamic>.from(e as Map))
        .toList();

    String statusLabel() {
      if (status == 2) {
        return loc.tr('components.solo_pool.status_ready');
      }
      if (status == 1) {
        return loc.tr('components.solo_pool.status_waiting');
      }
      if (status == -1) {
        return loc.tr('components.solo_pool.status_error');
      }
      return loc.tr('components.solo_pool.status_not_ready');
    }

    final List<String> bindChoices = _bindIpChoices(store);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                  child: Text(loc.tr('components.solo_pool.title'),
                      style: Theme.of(context).textTheme.titleLarge)),
              Chip(
                label: Text(
                  statusLabel(),
                  style: const TextStyle(
                    color: Color(0xFF14110A),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                backgroundColor: _statusChipColor(status),
              ),
            ],
          ),
          if (daemonType == 'remote')
            MaterialBanner(
              content: Text(
                loc.tr('components.solo_pool.remote_warning'),
                style: const TextStyle(color: ArqmaColors.arqmaGreenSolid),
              ),
              backgroundColor: const Color(0xFF2A2418),
              actions: <Widget>[
                TextButton(
                  onPressed: () =>
                      ScaffoldMessenger.of(context).hideCurrentMaterialBanner(),
                  child: Text(loc.tr('receiver.cancel')),
                ),
              ],
            ),
          if (server['enabled'] == true && poolState['desynced'] == true)
            MaterialBanner(
              content: Text(
                loc.tr('components.solo_pool.pool_desync_hint'),
                style: const TextStyle(color: ArqmaColors.arqmaGreenSolid),
              ),
              backgroundColor: const Color(0xFF2A2418),
              actions: <Widget>[
                TextButton(
                  onPressed: () =>
                      ScaffoldMessenger.of(context).hideCurrentMaterialBanner(),
                  child: Text(loc.tr('receiver.cancel')),
                ),
              ],
            ),
          if (server['enabled'] == true &&
              poolState['system_clock_error'] == true)
            MaterialBanner(
              content:
                  Text(loc.tr('components.solo_pool.system_clock_error_hint')),
              backgroundColor: Colors.red.shade700,
              actions: <Widget>[
                TextButton(
                  onPressed: () =>
                      ScaffoldMessenger.of(context).hideCurrentMaterialBanner(),
                  child: Text(loc.tr('receiver.cancel')),
                ),
              ],
            ),
          CheckboxListTile(
            value: server['enabled'] == true,
            onChanged: daemonType == 'remote'
                ? null
                : (bool? v) {
                    setState(() {
                      server['enabled'] = v ?? false;
                      _settings['server'] = server;
                    });
                  },
            title: Text(loc.tr('components.solo_pool.enable')),
          ),
          Builder(
            builder: (BuildContext _) {
              final List<({String label, String value})> miningChoices =
                  _miningAddressChoices(store);
              final String mt = _miningAddress.text.trim();
              final bool inList = miningChoices
                  .any((({String label, String value}) e) => e.value == mt);
              if (miningChoices.isEmpty || !inList) {
                return TextField(
                  controller: _miningAddress,
                  decoration: InputDecoration(
                      labelText: loc.tr('components.solo_pool.mining_address')),
                );
              }
              return DropdownButtonFormField<String>(
                value: mt,
                decoration: InputDecoration(
                    labelText: loc.tr('components.solo_pool.mining_address')),
                items: miningChoices
                    .map(
                      (({String label, String value}) e) =>
                          DropdownMenuItem<String>(
                        value: e.value,
                        child: Text(e.label, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(),
                onChanged: (String? nv) =>
                    setState(() => _miningAddress.text = nv ?? ''),
              );
            },
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<String>(
                  value: bindChoices.contains(_bindIpValue)
                      ? _bindIpValue
                      : bindChoices.first,
                  decoration: InputDecoration(
                      labelText: loc.tr('components.solo_pool.bind_ip')),
                  items: bindChoices
                      .map((String ip) =>
                          DropdownMenuItem<String>(value: ip, child: Text(ip)))
                      .toList(),
                  onChanged: (String? v) =>
                      setState(() => _bindIpValue = v ?? _bindIpValue),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _bindPort,
                  decoration: InputDecoration(
                      labelText: loc.tr('components.solo_pool.port')),
                  keyboardType: TextInputType.number,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(loc.tr('components.solo_pool.net_hashrate'),
              style: Theme.of(context).textTheme.titleSmall),
          _soloEvenStatRow(<MapEntry<String, String>>[
            MapEntry(loc.tr('components.solo_pool.net_hashrate'),
                _shortHashrate(netHr)),
            MapEntry(loc.tr('components.solo_pool.net_difficulty'),
                _commas(diff)),
            MapEntry(loc.tr('components.solo_pool.height'), _commas(height)),
            MapEntry(
                loc.tr('components.solo_pool.workers'), '$activeWorkers'),
          ]),
          const SizedBox(height: 12),
          _soloEvenStatRow(effortCards
              .map((Map<String, dynamic> ec) =>
                  MapEntry<String, String>('${ec['label']}', '${ec['value']}'))
              .toList()),
          const SizedBox(height: 12),
          Text(loc.tr('components.solo_pool.pool_hashrate'),
              style: Theme.of(context).textTheme.titleSmall),
          _soloEvenStatRow(<MapEntry<String, String>>[
            MapEntry(loc.tr('components.solo_pool.hashrate_5m'),
                _shortHashrate(hr5)),
            MapEntry(loc.tr('components.solo_pool.hashrate_1h'),
                _shortHashrate(hr1)),
            MapEntry(loc.tr('components.solo_pool.hashrate_6h'),
                _shortHashrate(hr6)),
            MapEntry(loc.tr('components.solo_pool.hashrate_24h'),
                _shortHashrate(hr24)),
          ]),
          const SizedBox(height: 12),
          Builder(
            builder: (BuildContext chartCtx) {
              final Set<String> workerIds = workers
                  .map((Map<String, dynamic> w) => '${w['miner']}')
                  .toSet();
              String chartWorker = _selectedWorker;
              if (chartWorker != '__all__' &&
                  !workerIds.contains(chartWorker)) {
                chartWorker = '__all__';
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted &&
                      _selectedWorker != '__all__' &&
                      !workerIds.contains(_selectedWorker)) {
                    setState(() => _selectedWorker = '__all__');
                  }
                });
              }
              final List<Offset> aggPts =
                  _soloPoolAggregatePoints(workers, chartWorker, _chartRange);
              final List<_WorkerChartLine> wl = chartWorker == '__all__'
                  ? _soloPoolWorkerLines(workers, _chartRange)
                  : <_WorkerChartLine>[];
              final double chartTop = _soloChartTopLabel(aggPts);
              final double chartMid = (chartTop / 2).roundToDouble();
              String rangeLeft() {
                if (_chartRange == '15m') {
                  return '-15m';
                }
                if (_chartRange == '6h') {
                  return '-6h';
                }
                return '-60m';
              }

              String rangeMid() {
                if (_chartRange == '15m') {
                  return '-7.5m';
                }
                if (_chartRange == '6h') {
                  return '-3h';
                }
                return '-30m';
              }

              return Card(
                color: const Color(0xFF1a1a1a),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: <Widget>[
                            ConstrainedBox(
                              constraints: const BoxConstraints(
                                  minWidth: 120, maxWidth: 220),
                              child: Text(
                                loc.tr('components.solo_pool.hashrate_chart'),
                                style: Theme.of(chartCtx).textTheme.titleSmall,
                              ),
                            ),
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 200,
                              child: DropdownButtonFormField<String>(
                                value: chartWorker,
                                isDense: true,
                                decoration: InputDecoration(
                                  labelText: loc
                                      .tr('components.solo_pool.chart_worker'),
                                  isDense: true,
                                ),
                                items: <DropdownMenuItem<String>>[
                                  DropdownMenuItem<String>(
                                    value: '__all__',
                                    child: Text(loc.tr(
                                        'components.solo_pool.chart_all_workers')),
                                  ),
                                  ...workers.map(
                                    (Map<String, dynamic> w) =>
                                        DropdownMenuItem<String>(
                                      value: '${w['miner']}',
                                      child: Text('${w['miner']}',
                                          overflow: TextOverflow.ellipsis),
                                    ),
                                  ),
                                ],
                                onChanged: (String? v) => setState(
                                    () => _selectedWorker = v ?? '__all__'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            ToggleButtons(
                              isSelected: ['15m', '60m', '6h']
                                  .map((String k) => _chartRange == k)
                                  .toList(),
                              onPressed: (int i) => setState(() => _chartRange =
                                  <String>['15m', '60m', '6h'][i]),
                              borderRadius: BorderRadius.circular(8),
                              constraints: const BoxConstraints(
                                  minHeight: 36, minWidth: 48),
                              children: <Widget>[
                                Text(loc.tr('components.solo_pool.range_15m')),
                                Text(loc.tr('components.solo_pool.range_60m')),
                                Text(loc.tr('components.solo_pool.range_6h')),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: <Widget>[
                          Expanded(
                              child: Text(_shortHashrate(chartTop),
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: ArqmaColors.textSecondary))),
                          Expanded(
                            child: Text(
                              _shortHashrate(chartMid),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: ArqmaColors.textSecondary),
                            ),
                          ),
                          const Expanded(
                            child: Text('0 H/s',
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                    fontSize: 12,
                                    color: ArqmaColors.textSecondary)),
                          ),
                        ],
                      ),
                      SizedBox(
                        height: 120,
                        width: double.infinity,
                        child: CustomPaint(
                          painter: _SoloPoolHashrateChartPainter(
                              aggregate: aggPts, workerLines: wl),
                        ),
                      ),
                      if (chartWorker == '__all__' && wl.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: wl
                                .map(
                                  (_WorkerChartLine line) => Chip(
                                    label: Text(
                                      line.miner,
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: ArqmaColors.black90,
                                      ),
                                    ),
                                    backgroundColor: line.color,
                                    visualDensity: VisualDensity.compact,
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                      const SizedBox(height: 4),
                      Row(
                        children: <Widget>[
                          Expanded(
                              child: Text(rangeLeft(),
                                  style: const TextStyle(
                                      fontSize: 11,
                                      color: ArqmaColors.textMuted))),
                          Expanded(
                            child: Text(
                              rangeMid(),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  fontSize: 11, color: ArqmaColors.textMuted),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              loc.tr('components.solo_pool.now'),
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                  fontSize: 11, color: ArqmaColors.textMuted),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const Divider(height: 32),
          SwitchListTile(
            value: _enableBlockRefresh,
            onChanged: (bool v) => setState(() => _enableBlockRefresh = v),
            title: Text(
                loc.tr('components.solo_pool.block_template_auto_refresh')),
          ),
          TextField(
            controller: _blockRefresh,
            decoration: InputDecoration(
                labelText: loc
                    .tr('components.solo_pool.block_refresh_interval_seconds')),
            keyboardType: TextInputType.number,
          ),
          TextField(
            controller: _minerTimeout,
            decoration: InputDecoration(
                labelText:
                    loc.tr('components.solo_pool.miner_timeout_seconds')),
            keyboardType: TextInputType.number,
          ),
          const Divider(height: 32),
          Text(loc.tr('components.solo_pool.vardiff_section'),
              style: Theme.of(context).textTheme.titleMedium),
          Text(loc.tr('components.solo_pool.vardiff_caption'),
              style: Theme.of(context).textTheme.bodySmall),
          _vdRow(loc.tr('components.solo_pool.vardiff_start_diff'), _vdStart),
          _vdRow(loc.tr('components.solo_pool.vardiff_min'), _vdMin),
          _vdRow(loc.tr('components.solo_pool.vardiff_max'), _vdMax),
          _vdRow(loc.tr('components.solo_pool.vardiff_target_time'), _vdTarget),
          _vdRow(loc.tr('components.solo_pool.vardiff_retarget_time'),
              _vdRetarget),
          _vdRow(loc.tr('components.solo_pool.vardiff_variance'), _vdVariance),
          _vdRow(loc.tr('components.solo_pool.vardiff_max_jump'), _vdMaxJump),
          TextField(
            controller: _vdSeparator,
            decoration: InputDecoration(
                labelText: loc.tr('components.solo_pool.vardiff_separator')),
            maxLength: 2,
          ),
          const SizedBox(height: 16),
          Text(loc.tr('components.solo_pool.worker'),
              style: Theme.of(context).textTheme.titleSmall),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: [
                DataColumn(label: Text(loc.tr('components.solo_pool.worker'))),
                DataColumn(
                    label: Text(loc.tr('components.solo_pool.difficulty'))),
                DataColumn(label: Text(loc.tr('components.solo_pool.rejects'))),
                DataColumn(
                    label: Text(loc.tr('components.solo_pool.last_share'))),
              ],
              rows: workers
                  .map(
                    (Map<String, dynamic> w) => DataRow(
                      cells: [
                        DataCell(Text('${w['miner']}')),
                        DataCell(Text(_commas(
                            num.tryParse('${w['difficulty'] ?? 0}') ?? 0))),
                        DataCell(Text(_commas(
                            num.tryParse('${w['rejects'] ?? 0}') ?? 0))),
                        DataCell(Text(_formatShareTime(w['lastShare']))),
                      ],
                    ),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(height: 16),
          Text(loc.tr('components.solo_pool.blocks_table'),
              style: Theme.of(context).textTheme.titleSmall),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: [
                DataColumn(label: Text(loc.tr('components.solo_pool.height'))),
                DataColumn(label: Text(loc.tr('components.footer.status'))),
                DataColumn(
                    label: Text(loc.tr('components.solo_pool.difficulty'))),
                DataColumn(label: Text(loc.tr('components.solo_pool.worker'))),
                DataColumn(
                    label: Text(
                        loc.tr('components.swap_list_tabular.block_hash'))),
                DataColumn(
                    label: Text(loc.tr('components.solo_pool.last_share'))),
              ],
              rows: blocks
                  .map(
                    (Map<String, dynamic> b) => DataRow(
                      cells: [
                        DataCell(Text(
                            _commas(num.tryParse('${b['height'] ?? 0}') ?? 0))),
                        DataCell(Text(_blockStatusLabel(loc, b['status']))),
                        DataCell(Text(_commas(num.tryParse(
                                '${b['diff'] ?? b['difficulty'] ?? 0}') ??
                            0))),
                        DataCell(Text('${b['miner'] ?? ''}')),
                        DataCell(Text(_formatBlockHash(b['hash']))),
                        DataCell(Text(_formatShareTime(b['timeFound']))),
                      ],
                    ),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(height: 24),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton(
                onPressed: _save,
                child: Text(loc.tr('components.solo_pool.save'))),
          ),
        ],
      ),
    );
  }

  static String _formatShareTime(Object? lastShare) {
    final int? ms =
        (lastShare is num) ? lastShare.toInt() : int.tryParse('$lastShare');
    if (ms == null || ms <= 0) {
      return '—';
    }
    final DateTime dt =
        DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toLocal();
    return dt.toString().substring(0, 19);
  }

  static String _formatBlockHash(Object? hash) {
    final String s = '$hash'.trim();
    if (s.isEmpty) {
      return '—';
    }
    if (s.length <= 18) {
      return s;
    }
    return '${s.substring(0, 18)}...';
  }

  static String _blockStatusLabel(LocaleController loc, Object? status) {
    final int s =
        (status is num) ? status.toInt() : int.tryParse('$status') ?? 0;
    if (s == 2) {
      return 'Unlocked';
    }
    if (s == 1) {
      return 'Orphaned';
    }
    return loc.tr('components.tx_list.pending');
  }

  Widget _vdRow(String label, TextEditingController c) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: c,
        decoration: InputDecoration(labelText: label),
        keyboardType: TextInputType.number,
      ),
    );
  }

  /// Fills row width evenly (replaces fixed-width [Wrap] tiles).
  Widget _soloEvenStatRow(List<MapEntry<String, String>> entries) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (int i = 0; i < entries.length; i++) ...<Widget>[
          if (i > 0) const SizedBox(width: 8),
          Expanded(child: _soloStatTile(entries[i].key, entries[i].value)),
        ],
      ],
    );
  }

  Widget _soloStatTile(String title, String value) {
    return Card(
      color: const Color(0xFF1a1a1a),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                  fontSize: 11, color: ArqmaColors.textSecondary),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              value,
              style: const TextStyle(
                  fontWeight: FontWeight.w600, fontSize: 12),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show FrameTiming, FlutterView;

import 'package:flutter/material.dart';

/// Which level of card detail to render, cycled from the HUD.
///
/// 0 = full card, 1 = no cover image, 2 = no text block, 3 = plain colour box.
/// Used to attribute UI-thread cost to a specific part of a feed card.
final ValueNotifier<int> cardVariant = ValueNotifier<int>(0);

const List<String> _variantLabels = <String>[
  'V0 full',
  'V1 no-img',
  'V2 no-text',
  'V3 plain',
];

// ---------------------------------------------------------------------------
// Slow-callback probe
// ---------------------------------------------------------------------------
//
// Frames that take 200ms on the UI thread cannot be blamed on rendering, so
// record every zone callback that takes longer than the threshold together with
// the stack it started from. The HUD then names the code responsible instead of
// us guessing.

class SlowCallback {
  SlowCallback(this.ms, this.trace);

  final int ms;
  final String trace;
}

final List<SlowCallback> slowCallbacks = <SlowCallback>[];
const int _slowThresholdMs = 40;
int _depth = 0;

String _shortTrace(StackTrace st) {
  final List<String> frames = <String>[];
  for (final String line in st.toString().split('\n')) {
    final String t = line.trim();
    if (!t.startsWith('#')) {
      continue;
    }
    // Skip the harness frames themselves.
    if (t.contains('frame_hud.dart') || t.contains('dart:async')) {
      continue;
    }
    frames.add(t.length > 80 ? '${t.substring(0, 80)}…' : t);
    if (frames.length == 2) {
      break;
    }
  }
  return frames.join('\n');
}

void _record(int ms, StackTrace st) {
  slowCallbacks.add(SlowCallback(ms, _shortTrace(st)));
  if (slowCallbacks.length > 6) {
    slowCallbacks.removeAt(0);
  }
}

T _probe<T>(T Function() body) {
  final bool outer = _depth == 0;
  final Stopwatch sw = Stopwatch()..start();
  final StackTrace st = StackTrace.current;
  _depth++;
  try {
    return body();
  } finally {
    _depth--;
    if (outer && sw.elapsedMilliseconds >= _slowThresholdMs) {
      _record(sw.elapsedMilliseconds, st);
    }
  }
}

ZoneSpecification probeZoneSpecification() => ZoneSpecification(
  run: <R>(Zone self, ZoneDelegate parent, Zone zone, R Function() f) =>
      _probe<R>(() => parent.run<R>(zone, f)),
  runUnary: <R, T>(Zone self, ZoneDelegate parent, Zone zone, R Function(T) f, T arg) =>
      _probe<R>(() => parent.runUnary<R, T>(zone, f, arg)),
  runBinary: <R, T1, T2>(
    Zone self,
    ZoneDelegate parent,
    Zone zone,
    R Function(T1, T2) f,
    T1 arg1,
    T2 arg2,
  ) => _probe<R>(() => parent.runBinary<R, T1, T2>(zone, f, arg1, arg2)),
);

// ---------------------------------------------------------------------------
// HUD
// ---------------------------------------------------------------------------

/// Diagnostic HUD: real frame timings instead of "feels janky".
class FrameHud extends StatefulWidget {
  const FrameHud({super.key});

  @override
  State<FrameHud> createState() => _FrameHudState();
}

class _FrameHudState extends State<FrameHud> {
  static const int _window = 180;

  final List<double> _ui = <double>[];
  final List<double> _raster = <double>[];
  final List<double> _total = <double>[];

  Timer? _timer;
  int _windowFrames = 0;
  double _fps = 0;
  double _refreshRate = 0;
  DateTime _windowStart = DateTime.now();
  int _totalFrames = 0;

  static const TextStyle _mono = TextStyle(
    fontSize: 11,
    height: 1.3,
    color: Colors.white,
  );

  static const TextStyle _monoGreen = TextStyle(
    fontSize: 11,
    height: 1.3,
    color: Color(0xFF7CF6A0),
  );

  static const TextStyle _monoAmber = TextStyle(
    fontSize: 11,
    height: 1.3,
    color: Color(0xFFFFD166),
  );

  static const TextStyle _monoRed = TextStyle(
    fontSize: 10,
    height: 1.25,
    color: Color(0xFFFF8A80),
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addTimingsCallback(_onTimings);
    _timer = Timer.periodic(const Duration(milliseconds: 400), (_) {
      final DateTime now = DateTime.now();
      final double secs = now.difference(_windowStart).inMicroseconds / 1e6;
      if (secs > 0.2) {
        _fps = _windowFrames / secs;
      }
      _windowFrames = 0;
      _windowStart = now;
      final Iterable<FlutterView> views =
          WidgetsBinding.instance.platformDispatcher.views;
      if (views.isNotEmpty) {
        _refreshRate = views.first.display.refreshRate;
      }
      if (mounted) {
        setState(() {});
      }
    });
  }

  void _onTimings(List<FrameTiming> timings) {
    for (final FrameTiming t in timings) {
      final double ui = t.buildDuration.inMicroseconds / 1000.0;
      final double rs = t.rasterDuration.inMicroseconds / 1000.0;
      _ui.add(ui);
      _raster.add(rs);
      _total.add(math.max(ui, rs));
      _windowFrames++;
      _totalFrames++;
    }
    while (_ui.length > _window) {
      _ui.removeAt(0);
      _raster.removeAt(0);
      _total.removeAt(0);
    }
  }

  double _avg(List<double> v) =>
      v.isEmpty ? 0 : v.reduce((double a, double b) => a + b) / v.length;

  double _pct(List<double> v, double p) {
    if (v.isEmpty) {
      return 0;
    }
    final List<double> s = List<double>.of(v)..sort();
    final int i = ((s.length - 1) * p).round().clamp(0, s.length - 1);
    return s[i];
  }

  double _max(List<double> v) =>
      v.isEmpty ? 0 : v.reduce((double a, double b) => math.max(a, b));

  double _share(List<double> v, double threshold) => v.isEmpty
      ? 0
      : v.where((double e) => e > threshold).length / v.length * 100;

  String _fmt(List<double> v) =>
      '${_avg(v).toStringAsFixed(1)} ${_pct(v, 0.95).toStringAsFixed(1)} '
      '${_max(v).toStringAsFixed(1)}';

  void _reset() {
    _ui.clear();
    _raster.clear();
    _total.clear();
    slowCallbacks.clear();
    _totalFrames = 0;
    _fps = 0;
    _windowFrames = 0;
    _windowStart = DateTime.now();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final double budget = _refreshRate > 90 ? 8.33 : 16.7;
    final List<SlowCallback> slow = slowCallbacks.reversed.take(3).toList();
    return Align(
      alignment: Alignment.topLeft,
      child: SafeArea(
        child: Container(
          margin: const EdgeInsets.only(left: 6, top: 4),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xCC000000),
            borderRadius: BorderRadius.circular(6),
          ),
          child: DefaultTextStyle(
            style: _mono,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  '${_refreshRate.toStringAsFixed(0)}Hz ${_fps.toStringAsFixed(0)}fps n=$_totalFrames',
                  style: _monoGreen,
                ),
                IgnorePointer(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text('UI ${_fmt(_ui)}', style: _mono),
                      Text('RS ${_fmt(_raster)}', style: _mono),
                      Text('MX ${_fmt(_total)}', style: _mono),
                      Text(
                        '>${budget.toStringAsFixed(1)} ${_share(_total, budget).toStringAsFixed(0)}%  '
                        '>16.7 ${_share(_total, 16.7).toStringAsFixed(0)}%',
                        style: _monoAmber,
                      ),
                      if (slow.isEmpty)
                        Text('SLOW -', style: _monoRed)
                      else
                        for (final SlowCallback s in slow)
                          Text('SLOW ${s.ms}ms\n${s.trace}', style: _monoRed),
                    ],
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    _chip(
                      _variantLabels[cardVariant.value],
                      () {
                        cardVariant.value = (cardVariant.value + 1) % 4;
                        _reset();
                      },
                    ),
                    const SizedBox(width: 6),
                    _chip('reset', _reset),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _chip(String label, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    behavior: HitTestBehavior.opaque,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 11, color: Color(0xFF8ED6FF)),
      ),
    ),
  );

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeTimingsCallback(_onTimings);
    super.dispose();
  }
}

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Diagnostic HUD: real frame timings instead of "feels janky".
///
/// Shows the refresh rate the engine actually got, frames per second, and the
/// UI / raster thread cost per frame (avg, p95, max), plus how many frames blew
/// the 120Hz (8.33ms) and 60Hz (16.7ms) budgets.
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addTimingsCallback(_onTimings);
    _timer = Timer.periodic(const Duration(milliseconds: 400), (_) {
      final now = DateTime.now();
      final secs = now.difference(_windowStart).inMicroseconds / 1e6;
      if (secs > 0.2) {
        _fps = _windowFrames / secs;
      }
      _windowFrames = 0;
      _windowStart = now;
      final views = WidgetsBinding.instance.platformDispatcher.views;
      if (views.isNotEmpty) {
        _refreshRate = views.first.display.refreshRate;
      }
      if (mounted) setState(() {});
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
      v.isEmpty ? 0 : v.reduce((a, b) => a + b) / v.length;

  double _pct(List<double> v, double p) {
    if (v.isEmpty) return 0;
    final List<double> s = List<double>.of(v)..sort();
    final int i = ((s.length - 1) * p).round().clamp(0, s.length - 1);
    return s[i];
  }

  double _max(List<double> v) => v.isEmpty ? 0 : v.reduce(math.max);

  double _share(List<double> v, double threshold) =>
      v.isEmpty ? 0 : v.where((e) => e > threshold).length / v.length * 100;

  Widget _row(String label, List<double> v) => Text(
    '$label ${_avg(v).toStringAsFixed(1)}'
    ' / ${_pct(v, 0.95).toStringAsFixed(1)}'
    ' / ${_max(v).toStringAsFixed(1)} ms',
    style: const TextStyle(
      fontSize: 11,
      height: 1.25,
      color: Colors.white,
      fontFeatures: [FontFeature.tabularFigures()],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final double budget = _refreshRate > 90 ? 8.33 : 16.7;
    return Positioned(
      left: 6,
      top: MediaQuery.of(context).padding.top + 4,
      child: IgnorePointer(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xCC000000),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                '${_refreshRate.toStringAsFixed(0)}Hz  '
                'fps ${_fps.toStringAsFixed(1)}  '
                'n $_totalFrames',
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF7CF6A0),
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              _row('UI', _ui),
              _row('RS', _raster),
              _row('MX', _total),
              Text(
                '>${budget.toStringAsFixed(1)}ms ${_share(_total, budget).toStringAsFixed(0)}%   '
                '>16.7ms ${_share(_total, 16.7).toStringAsFixed(0)}%',
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFFFFD166),
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeTimingsCallback(_onTimings);
    super.dispose();
  }
}

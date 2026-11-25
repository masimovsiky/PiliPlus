import 'package:flutter/material.dart';

void main() => runApp(const BenchApp());

class BenchApp extends StatelessWidget {
  const BenchApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      // Performance overlay is always on: UI thread / raster thread timings.
      showPerformanceOverlay: true,
      home: const BenchHome(),
    );
  }
}

class BenchHome extends StatelessWidget {
  const BenchHome({super.key});

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scroll bench'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              'refreshRate=${media.devicePixelRatio.toStringAsFixed(2)}x  '
              'size=${media.size.width.toInt()}x${media.size.height.toInt()}',
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ),
        ),
      ),
      body: ListView.builder(
        cacheExtent: 300,
        itemCount: 2000,
        itemBuilder: (context, index) {
          final int hue = (index * 7) % 360;
          final Color a = HSLColor.fromAHSL(1, hue.toDouble(), 0.65, 0.52).toColor();
          final Color b = HSLColor.fromAHSL(1, ((hue + 40) % 360).toDouble(), 0.65, 0.34).toColor();
          return Container(
            height: 120,
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[a, b],
              ),
              boxShadow: const <BoxShadow>[
                BoxShadow(color: Color(0x33000000), blurRadius: 8, offset: Offset(0, 3)),
              ],
            ),
            alignment: Alignment.center,
            child: Text(
              'Item #$index',
              style: const TextStyle(fontSize: 26, color: Colors.white, fontWeight: FontWeight.w600),
            ),
          );
        },
      ),
    );
  }
}

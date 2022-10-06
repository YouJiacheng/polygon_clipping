import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' show Vector2;

import 'algorithm.dart';
import 'ring.dart';
import 'utils.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '多边形裁剪',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});
  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  static const grid = 30.0;
  bool drawingClip = false;
  bool roundingPoint = false;
  bool usingNonzero = false;
  final subject = Polygon(color: Colors.blueAccent, rings: []);
  final clip = Polygon(color: Colors.redAccent, rings: []);
  final result = Polygon(color: Colors.purpleAccent, rings: []);

  void addVertex(Vector2 vertex) {
    if (drawingClip) {
      return clip.addVertex(vertex);
    }
    subject.addVertex(vertex);
  }

  void closeRing() {
    if (drawingClip) {
      return clip.closeRing();
    }
    subject.closeRing();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: <Widget>[
            SizedBox(
              width: 200,
              child: SwitchListTile(
                title: Text(
                  '输入状态',
                  style: Theme.of(context).primaryTextTheme.headline6,
                ),
                subtitle: Text(
                  drawingClip ? '裁剪多边形' : '主多边形',
                  style: Theme.of(context).primaryTextTheme.bodyText1,
                ),
                value: drawingClip,
                activeColor: Colors.red,
                onChanged: (value) {
                  setState(() {
                    drawingClip = value;
                  });
                },
              ),
            ),
            SizedBox(
              width: 190,
              child: SwitchListTile(
                title: Text(
                  '吸附网格',
                  style: Theme.of(context).primaryTextTheme.headline6,
                ),
                value: roundingPoint,
                activeColor: Colors.red,
                onChanged: (value) {
                  setState(() {
                    roundingPoint = value;
                  });
                },
              ),
            ),
            SizedBox(
              width: 230,
              child: SwitchListTile(
                title: Text(
                  '内部判定准则',
                  style: Theme.of(context).primaryTextTheme.headline6,
                ),
                subtitle: Text(
                  usingNonzero ? '非零' : '奇偶',
                  style: Theme.of(context).primaryTextTheme.bodyText1,
                ),
                value: usingNonzero,
                activeColor: Colors.red,
                onChanged: (value) {
                  setState(() {
                    usingNonzero = value;
                    result.clear();
                  });
                },
              ),
            ),
            TextButton(
              style: TextButton.styleFrom(backgroundColor: Colors.white),
              onPressed: () {
                setState(() {
                  subject.clear();
                  clip.clear();
                  result.clear();
                });
              },
              child: const Text('重置'),
            ),
          ],
        ),
      ),
      body: ConstrainedBox(
        constraints: const BoxConstraints.expand(),
        child: GestureDetector(
          onTapDown: (details) {
            setState(() {
              final p = details.localPosition;
              final vertex = roundingPoint
                  ? (Vector2(p.dx / grid, p.dy / grid)
                    ..round()
                    ..scale(grid))
                  : Vector2(p.dx, p.dy);
              addVertex(vertex);
            });
          },
          onSecondaryTap: () {
            setState(() {
              closeRing();
            });
          },
          child: CustomPaint(
            foregroundPainter: PolygonsPainter([subject, clip, result]),
            child: CustomPaint(painter: GridPainter(grid: roundingPoint ? grid : double.infinity)),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          setState(() {
            result.rings.clear();
            result.rings.addAll(clipping(
              subject: subject.rings,
              clip: clip.rings,
              usingNonZero: usingNonzero,
            ));
          });
        },
        tooltip: '裁剪',
        child: const Text('裁剪'),
      ),
    );
  }
}

class Polygon {
  final List<Ring> rings;
  final Color color;
  Polygon({
    required this.color,
    required this.rings,
  });

  bool get closed => rings.isEmpty || rings.last.closed;
  bool get closable => !closed && rings.last.vertices.length > 2;

  void addVertex(Vector2 vertex) {
    if (closed) {
      rings.add(Ring(vertices: [vertex]));
      return;
    }
    if (rings.last.vertices.last == vertex) {
      // NOT add zero length edge
      return;
    }
    rings.last.vertices.add(vertex);
  }

  void closeRing() {
    if (!closable) {
      return;
    }
    rings.last.closed = true;
  }

  void clear() {
    rings.clear();
  }

  Path get path {
    Offset offset(Vector2 v) => Offset(v.x, v.y);
    final path = Path();
    for (final ring in rings) {
      final begin = ring.vertices.first;
      if (ring.vertices.length == 1) {
        path.addOval(Rect.fromCircle(center: offset(begin), radius: 1.5));
      }
      path.moveTo(begin.x, begin.y);
      final vertices = ring.closed ? ring.vertices.followedByFirst() : ring.vertices;
      for (final pair in vertices.mapPair((a, b) => [a, b])) {
        final prev = pair[0];
        final vertex = pair[1];
        final d = (vertex - prev).normalized(); // direction
        final n = Vector2(-d.y, d.x); // normal
        final a = vertex - d * 8 + n * 4;
        final b = vertex - d * 8 - n * 4;
        path.lineTo(vertex.x, vertex.y);
        // 只是用来画箭头，并非直接用来绘制多边形
        path.addPolygon([offset(a), offset(vertex), offset(b)], false);
        path.moveTo(vertex.x, vertex.y);
      }
    }
    return path;
  }
}

class PolygonsPainter extends CustomPainter {
  final List<Polygon> polygons;
  PolygonsPainter(this.polygons);

  @override
  void paint(Canvas canvas, Size size) {
    for (final polygon in polygons) {
      final paint = Paint()
        ..color = polygon.color
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke;
      canvas.drawPath(polygon.path, paint);
    }
  }

  @override
  bool shouldRepaint(PolygonsPainter oldDelegate) => true;
}

class GridPainter extends CustomPainter {
  final double grid;
  GridPainter({required this.grid});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.greenAccent
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    for (int i = 1; i < size.width ~/ grid; ++i) {
      canvas.drawLine(Offset(i * grid, 0), Offset(i * grid, size.height), paint);
    }
    for (int i = 1; i < size.height ~/ grid; ++i) {
      canvas.drawLine(Offset(0, i * grid), Offset(size.width, i * grid), paint);
    }
  }

  @override
  bool shouldRepaint(GridPainter oldDelegate) => grid != oldDelegate.grid;
}

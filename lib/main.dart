import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' show Vector2;

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
  var isClip = false;
  final subject = Polygon(color: Colors.blueAccent, parts: []);
  final clip = Polygon(color: Colors.redAccent, parts: []);
  final result = Polygon(color: Colors.purpleAccent, parts: []);

  void addPoint(Vector2 point) {
    if (isClip) {
      return clip.addPoint(point);
    }
    subject.addPoint(point);
  }

  void closePart() {
    if (isClip) {
      return clip.closePart();
    }
    subject.closePart();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: SwitchListTile(
            title: Text(
              '输入状态：',
              style: Theme.of(context).primaryTextTheme.headline6,
            ),
            subtitle: Text(
              isClip ? '裁剪多边形' : '主多边形',
              style: Theme.of(context).primaryTextTheme.bodyText1,
            ),
            value: isClip,
            activeColor: Colors.red,
            onChanged: (value) {
              setState(() {
                isClip = value;
              });
            }),
      ),
      body: ConstrainedBox(
        constraints: const BoxConstraints.expand(),
        child: GestureDetector(
          onTapDown: (details) {
            setState(() {
              final p = details.localPosition;
              addPoint(Vector2(p.dx, p.dy));
            });
          },
          onSecondaryTap: () {
            setState(() {
              closePart();
            });
          },
          child: CustomPaint(painter: PolygonsPainter([subject, clip, result])),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {},
        tooltip: '裁剪',
        child: const Text('裁剪'),
      ),
    );
  }
}

class PolygonPart {
  final List<Vector2> points;
  bool closed;
  PolygonPart({
    required this.points,
    this.closed = false,
  });
}

class Polygon {
  final List<PolygonPart> parts;
  final Color color;
  Polygon({
    required this.color,
    required this.parts,
  });

  bool get closed => parts.isEmpty || parts.last.closed;
  bool get closable => !closed && parts.last.points.length > 2;

  void addPoint(Vector2 point) {
    if (closed) {
      return parts.add(PolygonPart(points: [point]));
    }
    parts.last.points.add(point);
  }

  void closePart() {
    if (!closable) {
      return;
    }
    parts.last.closed = true;
  }

  Path get path {
    final path = Path();
    for (final part in parts) {
      final begin = part.points.first;
      if (part.points.length == 1) {
        path.addOval(Rect.fromCircle(center: Offset(begin.x, begin.y), radius: 1.5));
      }
      path.moveTo(begin.x, begin.y);
      for (final point in part.points.skip(1)) {
        path.lineTo(point.x, point.y);
      }
      if (part.closed) {
        path.lineTo(begin.x, begin.y);
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

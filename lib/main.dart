import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' show Vector2;
import 'package:collection/collection.dart';

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
  var isClip = false;
  var rounded = false;
  final subject = Polygon(color: Colors.blueAccent, rings: []);
  final clip = Polygon(color: Colors.redAccent, rings: []);
  final result = Polygon(color: Colors.purpleAccent, rings: []);

  void addVertex(Vector2 vertex) {
    if (isClip) {
      return clip.addVertex(vertex);
    }
    subject.addVertex(vertex);
  }

  void closeRing() {
    if (isClip) {
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
              width: 240,
              child: SwitchListTile(
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
                value: rounded,
                activeColor: Colors.red,
                onChanged: (value) {
                  setState(() {
                    rounded = value;
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
              child: const Text('清除'),
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
              final vertex = rounded
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
            child: CustomPaint(painter: GridPainter(grid: rounded ? grid : double.infinity)),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          setState(() {
            result.rings.clear();
            result.rings.addAll(clipping(subject: subject, clip: clip));
          });
        },
        tooltip: '裁剪',
        child: const Text('裁剪'),
      ),
    );
  }
}

class Ring {
  final List<Vector2> vertices;
  bool closed;
  Ring({
    required this.vertices,
    this.closed = false,
  });
  Iterable<Vector2> ringRelativeTo(Vector2 point) =>
      vertices.map((v) => v - point).followedByFirst();
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

class IntersectionInfo {
  double t0; // not in [0, 1) => NOT an intersection
  double t1;
  bool collinear;
  IntersectionInfo(this.t0, this.t1, {this.collinear = false});
  IntersectionInfo.empty() : this(double.infinity, double.infinity);
}

/// 参数区间[0, 1)
bool inRange(double t) => t >= 0 && t < 1;

/// 求交，参数区间[0, 1)
IntersectionInfo intersect({
  required Vector2 p,
  required Vector2 q,
  required Vector2 r,
  required Vector2 s,
}) {
  final pq = q - p;
  final rs = s - r;
  final pr = r - p;
  final cross = pq.cross(rs);
  if (cross == 0) {
    if (pq.cross(pr) != 0) {
      // 平行
      return IntersectionInfo.empty();
    }
    // 共线
    // 因为参数区间是[0, 1)
    // 只需考虑起点
    final t0 = pq.dot(pr) / pq.length2; // r在pq上的位置
    final t1 = rs.dot(-pr) / rs.length2; // p在rs上的位置
    return IntersectionInfo(t0, t1, collinear: true);
  }
  return IntersectionInfo(
    pr.cross(rs) / cross, // (p + pq * t - r).cross(rs) == 0 交点在pq上的位置
    pq.cross(-pr) / cross, // pq.cross(r + rs * t - p) == 0 交点在rs上的位置
  );
}

extension MyIterable<E> on Iterable<E> {
  /// Returns a new lazy iterable with elements that are created by
  /// calling [toElement] on each successive overlapping pair of
  /// this iterable in iteration order.
  Iterable<T> mapPair<T>(T Function(E prev, E elem) toElement) sync* {
    E previousElement = first;
    for (final element in skip(1)) {
      yield toElement(previousElement, element);
      previousElement = element;
    }
  }

  Iterable<E> followedByFirst() {
    return followedBy([first]);
  }
}

int halfPlaneWindingNumber(Vector2 point, Polygon polygon) {
  // 弧长累加法
  // 经典的quadrant/象限方法使用[0, 90), [90, 180), [180, 270), [270, 360)
  // 改进为半平面方法，使用[0, 180), [180, 360)
  // 点不能在多边形的边上
  bool plane(Vector2 p) {
    return p.y > 0 || (p.y == 0 && p.x > 0);
  }

  int windingNumber(Vector2 a, Vector2 b) {
    if (plane(a) == plane(b)) {
      return 0;
    }
    return a.cross(b).sign.toInt();
  }

  assert(polygon.rings.every((ring) => ring.closed));
  int w = polygon.rings.map((ring) => ring.ringRelativeTo(point).mapPair(windingNumber).sum).sum;
  return w ~/ 2;
}

bool onEdge(Vector2 point, Polygon polygon) {
  return polygon.rings.any((ring) =>
      ring.ringRelativeTo(point).mapPair((a, b) => a.cross(b) == 0 && a.dot(b) <= 0).any((e) => e));
}

class AnnotatedPoint {
  int i;
  Vector2? v;
  double t;
  AnnotatedPoint({
    required this.i,
    this.v,
    this.t = double.infinity,
  });
}

class Edge {
  AnnotatedPoint begin;
  AnnotatedPoint end;
  List<AnnotatedPoint> intersections;
  Edge({required this.begin, required this.end}) : intersections = [];
  Vector2 interp(double t) {
    return begin.v! * (1 - t) + end.v! * t;
  }
}

Iterable<Edge> toEdges(Ring ring, int indexBase) {
  return ring.vertices
      .mapIndexed((index, element) => AnnotatedPoint(i: indexBase + index, v: element))
      .followedByFirst()
      .mapPair((prev, elem) => Edge(begin: prev, end: elem));
}

// 求交
void addIntersections({
  required List<Edge> subjectEdges,
  required List<Edge> clipEdges,
  required HashMap<int, int> coincidence,
  required int indexBase,
}) {
  for (final subjectEdge in subjectEdges) {
    for (final clipEdge in clipEdges) {
      final p = subjectEdge.begin;
      final q = subjectEdge.end;
      final r = clipEdge.begin;
      final s = clipEdge.end;
      final x = intersect(p: p.v!, q: q.v!, r: r.v!, s: s.v!);
      if (x.t0 == 0 && x.t1 == 0) {
        // p和r重合，需要被视为同一点
        coincidence.addAll({p.i: r.i, r.i: p.i});
        p.t = 0; // 表明是退化情况，不能判断是交叉还是反弹
        r.t = 0;
        // 无需加入新的点
        continue;
      }
      if (x.collinear) {
        // 处理共线情况
        // 注意起点重合情况已处理
        if (inRange(x.t0)) {
          // r在pq上
          r.t = 0; // 表明是退化情况
          // 在pq上位置为t0
          subjectEdge.intersections.add(AnnotatedPoint(i: r.i, t: x.t0));
        }
        if (inRange(x.t1)) {
          // p在rs上
          p.t = 0;
          // 在rs上位置为t1
          clipEdge.intersections.add(AnnotatedPoint(i: p.i, t: x.t1));
        }
        // 如果r在pq上且p在rs上
        // 即形如s-p-r-q
        // 裁剪结果中会有重边但不影响
        continue;
      }
      // 非共线情况下t0和t1的含义不同
      // 需要同时满足
      if (inRange(x.t0) && inRange(x.t1)) {
        // 处理相交情况
        // 注意起点重合情况已处理
        if (x.t0 == 0) {
          // 交点在pq上位置为0，是p
          p.t = 0;
          // 向clip加入p
          // 其位置是x.t1
          clipEdge.intersections.add(AnnotatedPoint(i: p.i, t: x.t1));
          continue;
        }
        if (x.t1 == 0) {
          // 交点在rs上位置为0，是r
          r.t = 0;
          // 向subject加入r
          // 其位置是x.t0
          subjectEdge.intersections.add(AnnotatedPoint(i: r.i, t: x.t0));
          continue;
        }
        // 非退化正常相交
        // 创建交点
        final i0 = AnnotatedPoint(i: indexBase, t: x.t0);
        final i1 = AnnotatedPoint(i: indexBase, t: x.t1); // 同一点
        indexBase += 1;
        subjectEdge.intersections.add(i0);
        clipEdge.intersections.add(i1);
        continue;
      }
    }
  }
}

List<Edge> split(List<Edge> edges) => [
      for (final edge in edges)
        ...[edge.begin, ...edge.intersections..sortBy<num>((p) => p.t), edge.end]
            .mapPair((prev, elem) => Edge(begin: prev, end: elem))
    ];

void addInterior({
  required List<Edge> edges,
  required Polygon polygon,
  required HashMap<int, Edge> interiorEdges,
}) {
  bool inside = false;
  // var prevoiusEnd = AnnotatedPoint(i: -1); // -1 won't be any begin
  for (final edge in edges) {
    final begin = edge.begin;
    // todo: avoid useless windingNumber computation
    // if (begin.i != prevoiusEnd.i || begin.t == 0) {
    //   // 非连续边，或为退化情况
    //   // 需要计算判断内外
    //   final midpoint = edge.interp(0.5);
    //   // 分割后边的中点在多边形边界上说明该边与多边形边界有重合
    //   // 认为是inside
    //   inside = onEdge(midpoint, polygon) || halfPlaneWindingNumber(midpoint, polygon) != 0;
    // } else {
    //   // 连续边且非退化
    //   // (0, 1)是交叉情况（已排除0）
    //   // 不在[0, 1)则没有穿过边界
    //   inside = inside ^ inRange(begin.t);
    // }
    final midpoint = edge.interp(0.5);
    // 分割后边的中点在多边形边界上说明该边与多边形边界有重合
    // 认为是inside
    inside = onEdge(midpoint, polygon) || halfPlaneWindingNumber(midpoint, polygon) != 0;
    if (inside) {
      assert(!interiorEdges.containsKey(begin.i) || interiorEdges[begin.i]!.end.i == edge.end.i);
      interiorEdges[begin.i] = edge;
    }
    // prevoiusEnd = edge.end;
  }
}

List<Ring> clipping({required Polygon subject, required Polygon clip}) {
  // 将多边形由顶点形式转换为边形式
  // 同时为顶点标号
  int indexBase = 0;
  final subjectEdges = <Edge>[];
  final clipEdges = <Edge>[];
  final coincidence = HashMap<int, int>(); // todo: more degeneracy handling
  for (final ring in subject.rings) {
    subjectEdges.addAll(toEdges(ring, indexBase));
    indexBase += ring.vertices.length;
  }
  for (final ring in clip.rings) {
    clipEdges.addAll(toEdges(ring, indexBase));
    indexBase += ring.vertices.length;
  }
  addIntersections(
    subjectEdges: subjectEdges,
    clipEdges: clipEdges,
    coincidence: coincidence,
    indexBase: indexBase,
  ); // 此后不需要indexBase，因此无需返回增加后的indexBase
  // 计算交点坐标
  for (final edge in [...subjectEdges, ...clipEdges]) {
    for (final p in edge.intersections) {
      p.v = edge.interp(p.t);
    }
  }
  // 重新分割边
  final splitSubjectEdges = split(subjectEdges);
  final splitClipEdges = split(clipEdges);
  final interiorEdges = HashMap<int, Edge>();
  addInterior(edges: splitSubjectEdges, polygon: clip, interiorEdges: interiorEdges);
  addInterior(edges: splitClipEdges, polygon: subject, interiorEdges: interiorEdges);
  final result = <Ring>[];
  while (interiorEdges.isNotEmpty) {
    final ring = Ring(vertices: []);
    var edge = interiorEdges.values.first;
    while (true) {
      ring.vertices.add(edge.begin.v!);
      interiorEdges.remove(edge.begin.i);
      final e = interiorEdges[edge.end.i] ?? interiorEdges[coincidence[edge.end.i]];
      if (e == null) {
        break;
      }
      edge = e;
    }
    ring.closed = true;
    result.add(ring);
  }
  return result;
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

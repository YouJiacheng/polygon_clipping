import 'package:collection/collection.dart';
import 'package:vector_math/vector_math_64.dart' show Vector2;

import 'utils.dart';

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

int halfPlaneWindingNumber(Vector2 point, List<Ring> rings) {
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

  assert(rings.every((ring) => ring.closed));
  int w = rings.map((ring) => ring.ringRelativeTo(point).mapPair(windingNumber).sum).sum;
  return w ~/ 2;
}

bool onEdge(Vector2 point, List<Ring> rings) {
  return rings.any((ring) =>
      ring.ringRelativeTo(point).mapPair((a, b) => a.cross(b) == 0 && a.dot(b) <= 0).any((e) => e));
}

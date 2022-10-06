import 'dart:collection';
import 'package:collection/collection.dart';
import 'package:vector_math/vector_math_64.dart' show Vector2;

import 'ring.dart';
import 'utils.dart';

class IntersectionInfo {
  // 注意共线情况下t0和t1的含义与非共线情况不同
  double t0;
  double t1;
  bool collinear;
  IntersectionInfo(this.t0, this.t1, {this.collinear = false});
  IntersectionInfo.empty() : this(double.infinity, double.infinity);
}

/// 交点参数计算：参数区间[0, 1)
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

class AnnotatedPoint {
  int i;
  Vector2? v;
  double t;
  bool degeneracy;
  AnnotatedPoint({
    required this.i,
    this.v,
    this.t = double.infinity,
    this.degeneracy = true,
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

  Iterable<Edge> split() {
    return [begin, ...intersections..sortBy<num>((p) => p.t), end]
        .mapPair((prev, elem) => Edge(begin: prev, end: elem));
  }
}

/// 参数区间[0, 1)
bool inRange(double t) => t >= 0 && t < 1;

// 求交
void addIntersections({
  required List<Edge> subjectEdges,
  required List<Edge> clipEdges,
  required HashMap<int, int> coincidence,
  required int indexBase,
}) {
  for (final pq in subjectEdges) {
    for (final rs in clipEdges) {
      final p = pq.begin;
      final q = pq.end;
      final r = rs.begin;
      final s = rs.end;
      final x = intersect(p: p.v!, q: q.v!, r: r.v!, s: s.v!);
      if (x.t0 == 0 && x.t1 == 0) {
        // p和r重合，需要被视为同一点
        coincidence.addAll({p.i: r.i, r.i: p.i});
        // 标记为交点，注意退化标记默认为true
        p.t = r.t = 0;
        // 无需加入新的点
        continue;
      }
      if (x.collinear) {
        // 处理共线情况，注意起点重合情况已处理
        if (inRange(x.t0)) {
          r.t = 0;
          // r在pq上位置为t0
          pq.intersections.add(AnnotatedPoint(i: r.i, t: x.t0));
        }
        if (inRange(x.t1)) {
          p.t = 0;
          // p在rs上位置为t1
          rs.intersections.add(AnnotatedPoint(i: p.i, t: x.t1));
        }
        // 如果r在pq上且p在rs上
        // 即形如s-p-r-q
        // 裁剪结果中会有重边但不影响
        continue;
      }
      // 非共线情况下t0和t1的含义不同，需要同时在[0, 1)中
      if (inRange(x.t0) && inRange(x.t1)) {
        // 处理相交情况，注意起点重合情况已处理
        if (x.t0 == 0) {
          p.t = 0;
          // p在rs上位置为t1
          rs.intersections.add(AnnotatedPoint(i: p.i, t: x.t1));
          continue;
        }
        if (x.t1 == 0) {
          r.t = 0;
          // r在pq上位置为t0
          pq.intersections.add(AnnotatedPoint(i: r.i, t: x.t0));
          continue;
        }
        // 非退化正常相交
        // 创建交点
        final i0 = AnnotatedPoint(i: indexBase, t: x.t0, degeneracy: false);
        final i1 = AnnotatedPoint(i: indexBase, t: x.t1, degeneracy: false); // 同一点
        indexBase += 1;
        pq.intersections.add(i0);
        rs.intersections.add(i1);
      }
    }
  }
}

void addInterior({
  required List<Edge> edges,
  required List<Ring> rings,
  required HashMap<int, HashSet<Edge>> begin2InteriorEdges,
  required HashMap<int, HashSet<Edge>> end2InteriorEdges,
}) {
  bool inside = false;
  int prevEndIndex = -1;
  for (final edge in edges) {
    final begin = edge.begin;
    final end = edge.end;
    final intersected = inRange(begin.t);
    if (begin.i != prevEndIndex || (intersected && begin.degeneracy)) {
      // 非连续边或退化相交
      // 需要计算判断内外
      final midpoint = edge.interp(0.5);
      // 分割后边的中点在多边形边界上说明该边与多边形边界有重合
      // 认为是inside
      inside = onEdge(midpoint, rings) || halfPlaneWindingNumber(midpoint, rings) != 0;
    } else {
      // 连续边且(非相交或非退化相交)
      inside = inside ^ intersected;
    }
    if (inside) {
      begin2InteriorEdges.putIfAbsent(begin.i, () => HashSet.identity());
      end2InteriorEdges.putIfAbsent(end.i, () => HashSet.identity());
      begin2InteriorEdges[begin.i]!.add(edge);
      end2InteriorEdges[end.i]!.add(edge);
    }
    prevEndIndex = end.i;
  }
}

List<Ring> clipping({required List<Ring> subject, required List<Ring> clip}) {
  // 将多边形由顶点形式转换为边形式
  // 同时为顶点标号
  int indexBase = 0;
  Iterable<Edge> toEdges(Ring ring) {
    return ring.vertices
        .mapIndexed((index, element) => AnnotatedPoint(i: indexBase + index, v: element))
        .followedByFirst()
        .mapPair((prev, elem) => Edge(begin: prev, end: elem));
  }

  final subjectEdges = <Edge>[];
  final clipEdges = <Edge>[];
  final coincidence = HashMap<int, int>(); // todo: more degeneracy handling
  for (final ring in subject) {
    subjectEdges.addAll(toEdges(ring));
    indexBase += ring.vertices.length;
  }
  for (final ring in clip) {
    clipEdges.addAll(toEdges(ring));
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
  final splitSubjectEdges = [for (final e in subjectEdges) ...e.split()];
  final splitClipEdges = [for (final e in clipEdges) ...e.split()];
  final begin2InteriorEdges = HashMap<int, HashSet<Edge>>();
  final end2InteriorEdges = HashMap<int, HashSet<Edge>>();
  addInterior(
    edges: splitSubjectEdges,
    rings: clip,
    begin2InteriorEdges: begin2InteriorEdges,
    end2InteriorEdges: end2InteriorEdges,
  );
  addInterior(
    edges: splitClipEdges,
    rings: subject,
    begin2InteriorEdges: begin2InteriorEdges,
    end2InteriorEdges: end2InteriorEdges,
  );
  final result = <Ring>[];
  void remove<K, V>({
    required HashMap<K, HashSet<V>> mapToSet,
    required K mapkey,
    required V setValue,
  }) {
    final set = mapToSet[mapkey]!;
    if (set.length == 1) {
      mapToSet.remove(mapkey);
    } else {
      set.remove(setValue);
    }
  }

  while (begin2InteriorEdges.isNotEmpty) {
    final ring = Ring(vertices: []);
    var edge = begin2InteriorEdges.values.first.last;
    bool fromBegin = true;
    while (true) {
      final begin = edge.begin;
      final end = edge.end;
      final p = fromBegin ? begin : end;
      final q = fromBegin ? end : begin;
      ring.vertices.add(p.v!);
      remove<int, Edge>(mapToSet: begin2InteriorEdges, mapkey: begin.i, setValue: edge);
      remove<int, Edge>(mapToSet: end2InteriorEdges, mapkey: end.i, setValue: edge);

      final alternative = coincidence[q.i];
      var e = begin2InteriorEdges[q.i] ?? begin2InteriorEdges[alternative];
      fromBegin = e != null;
      e ??= end2InteriorEdges[q.i] ?? begin2InteriorEdges[alternative];
      if (e == null) {
        break;
      }
      edge = e.last;
    }
    ring.closed = true;
    result.add(ring);
  }
  return result;
}

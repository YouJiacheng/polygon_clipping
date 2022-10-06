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

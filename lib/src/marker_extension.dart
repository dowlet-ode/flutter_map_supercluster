import 'package:flutter_map/flutter_map.dart';
import 'package:flutter/widgets.dart';

extension MarkerExtension on Marker {
  /// Returns the normalized offset of the marker's alignment point.
  ///
  /// For example, [Alignment.center] -> Offset(0.5, 0.5),
  /// [Alignment.bottomCenter] -> Offset(0.5, 1.0)
  Offset get anchorOffset {
    final align = alignment ?? Alignment.center;
    final dx = (align.x + 1) / 2 * width;
    final dy = (align.y + 1) / 2 * height;
    return Offset(dx, dy);
  }
}

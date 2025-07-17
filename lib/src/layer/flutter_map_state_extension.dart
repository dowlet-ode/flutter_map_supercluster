import 'dart:math';
import 'dart:ui';

import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

extension FlutterMapStateExtension on MapController {
  Offset getPixelOffset(LatLng point) => camera.projectAtZoom(point) - camera.getNewPixelOrigin(camera.center);

  LatLngBounds paddedMapBounds(Size clusterWidgetSize) {
    final boundsPixelPadding = Point<double>(
      clusterWidgetSize.width / 2,
      clusterWidgetSize.height / 2,
    );
    final bounds = camera.pixelBounds;
    return LatLngBounds(
      camera.unprojectAtZoom(bounds.topLeft - Offset(boundsPixelPadding.x, boundsPixelPadding.y)),
      camera.unprojectAtZoom(bounds.bottomRight + Offset(boundsPixelPadding.x, boundsPixelPadding.y)),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_supercluster/src/marker_extension.dart';
import 'package:flutter_map_supercluster/src/splay/displaced_marker.dart';

class MarkerWidget extends StatelessWidget {
  final Marker marker;
  final Widget markerChild;
  final VoidCallback onTap;
  final Offset position;
  final double mapRotationRad;

  final AlignmentGeometry? rotateAlignment;
  final bool removeRotateOrigin;

  MarkerWidget({
    super.key,
    required MapController mapController,
    required this.marker,
    required this.markerChild,
    required this.onTap,
  })  : mapRotationRad = mapController.camera.rotationRad,
        position = _getMapPointPixel(mapController, marker),
        rotateAlignment = marker.alignment,
        removeRotateOrigin = false;

  MarkerWidget.displaced({
    super.key,
    required DisplacedMarker displacedMarker,
    required Offset position,
    required this.markerChild,
    required this.onTap,
    required this.mapRotationRad,
  })  : marker = displacedMarker.marker,
        position = Offset(
          position.dx -
              _alignmentOffset(
                      displacedMarker.marker.alignment, displacedMarker.marker.width, displacedMarker.marker.height)
                  .dx,
          position.dy -
              _alignmentOffset(
                      displacedMarker.marker.alignment, displacedMarker.marker.width, displacedMarker.marker.height)
                  .dy,
        ),
        rotateAlignment = DisplacedMarker.rotateAlignment,
        removeRotateOrigin = true;

  @override
  Widget build(BuildContext context) {
    final child = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: markerChild,
    );

    return Positioned(
      key: ObjectKey(marker),
      width: marker.width,
      height: marker.height,
      left: position.dx,
      top: position.dy,
      child: marker.rotate != true
          ? child
          : Transform.rotate(
              angle: -mapRotationRad,
              origin: removeRotateOrigin ? null : marker.anchorOffset,
              alignment: rotateAlignment,
              child: child,
            ),
    );
  }

  static Offset _getMapPointPixel(
    MapController mapController,
    Marker marker,
  ) {
    final base = mapController.camera.projectAtZoom(marker.point);
    final alignmentOffset = _alignmentOffset(marker.alignment, marker.width, marker.height);
    return Offset(
      base.dx - alignmentOffset.dx,
      base.dy - alignmentOffset.dy,
    );
  }

  static Offset _alignmentOffset(AlignmentGeometry? alignment, double width, double height) {
    final align = alignment ?? Alignment.center;
    final resolved = align is Alignment ? align : align.resolve(TextDirection.ltr);

    return Offset(
      (resolved.x + 1) / 2 * width,
      (resolved.y + 1) / 2 * height,
    );
  }
}

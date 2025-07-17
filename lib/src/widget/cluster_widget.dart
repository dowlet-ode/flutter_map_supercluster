import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_supercluster/src/layer/flutter_map_state_extension.dart';
import 'package:flutter_map_supercluster/src/layer_element_extension.dart';
import 'package:supercluster/supercluster.dart';

class ClusterWidget extends StatelessWidget {
  final LayerCluster<Marker> cluster;
  final Widget child;
  final VoidCallback onTap;
  final Size size;
  final Offset position;
  final double mapRotationRad;

  ClusterWidget({
    Key? key,
    required MapController mapController,
    required this.cluster,
    required this.child,
    required this.onTap,
    required this.size,
    required AlignmentGeometry? alignment,
  })  : position = _getClusterPixel(
          mapController,
          cluster,
          alignment,
          size,
        ),
        mapRotationRad = mapController.camera.rotationRad,
        super(key: ValueKey(cluster.uuid));

  @override
  Widget build(BuildContext context) {
    return Positioned(
      width: size.width,
      height: size.height,
      left: position.dx,
      top: position.dy,
      child: Transform.rotate(
        angle: -mapRotationRad,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: child,
        ),
      ),
    );
  }

  static Offset _getClusterPixel(
    MapController mapController,
    LayerCluster<Marker> cluster,
    AlignmentGeometry? alignment,
    Size size,
  ) {
    return mapController.getPixelOffset(cluster.latLng);
  }
}

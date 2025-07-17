import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_popup/extension_api.dart';
import 'package:flutter_map_supercluster/src/layer/flutter_map_state_extension.dart';
import 'package:flutter_map_supercluster/src/layer_element_extension.dart';
import 'package:flutter_map_supercluster/src/splay/popup_spec_builder.dart';
import 'package:flutter_map_supercluster/src/widget/cluster_widget.dart';
import 'package:flutter_map_supercluster/src/widget/expanded_cluster.dart';
import 'package:flutter_map_supercluster/src/widget/marker_widget.dart';

class ExpandableClusterWidget extends StatelessWidget {
  final MapController mapController;
  final ExpandedCluster expandedCluster;
  final Size size;
  final AlignmentGeometry? alignment;
  final Widget child;
  final void Function(PopupSpec popupSpec) onMarkerTap;
  final VoidCallback onCollapse;
  final Offset clusterPixelPosition;

  ExpandableClusterWidget({
    Key? key,
    required this.mapController,
    required this.expandedCluster,
    required this.size,
    required this.alignment,
    required this.child,
    required this.onMarkerTap,
    required this.onCollapse,
  })  : clusterPixelPosition = mapController.getPixelOffset(expandedCluster.layerCluster.latLng),
        super(key: ValueKey('expandable-${expandedCluster.layerCluster.uuid}'));

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: expandedCluster.animation,
      builder: (context, _) {
        final displacedMarkerOffsets = expandedCluster.displacedMarkerOffsets(
          mapController,
          clusterPixelPosition,
        );
        final splayDecoration = expandedCluster.splayDecoration(
          displacedMarkerOffsets,
        );

        return Positioned.fill(
          child: Stack(
            children: [
              if (splayDecoration != null)
                Positioned(
                  left: clusterPixelPosition.dx - expandedCluster.splayDistance,
                  top: clusterPixelPosition.dy - expandedCluster.splayDistance,
                  width: expandedCluster.splayDistance * 2,
                  height: expandedCluster.splayDistance * 2,
                  child: splayDecoration,
                ),
              ...displacedMarkerOffsets.map(
                (offset) => MarkerWidget.displaced(
                  displacedMarker: offset.displacedMarker,
                  position: clusterPixelPosition + offset.displacedOffset,
                  markerChild: child,
                  onTap: () => onMarkerTap(
                    PopupSpecBuilder.forDisplacedMarker(
                      offset.displacedMarker,
                      expandedCluster.minimumVisibleZoom,
                    ),
                  ),
                  mapRotationRad: mapController.camera.rotationRad,
                ),
              ),
              ClusterWidget(
                mapController: mapController,
                cluster: expandedCluster.layerCluster,
                onTap: expandedCluster.isExpanded ? onCollapse : () {},
                size: size,
                alignment: alignment,
                child: child,
              ),
            ],
          ),
        );
      },
    );
  }
}

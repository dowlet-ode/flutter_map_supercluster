import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_supercluster/src/layer/cluster_data.dart';
import 'package:flutter_map_supercluster/src/layer/flutter_map_state_extension.dart';
import 'package:flutter_map_supercluster/src/layer/supercluster_layer.dart';
import 'package:flutter_map_supercluster/src/layer_element_extension.dart';
import 'package:flutter_map_supercluster/src/splay/cluster_splay_delegate.dart';
import 'package:flutter_map_supercluster/src/splay/displaced_marker.dart';
import 'package:flutter_map_supercluster/src/splay/displaced_marker_offset.dart';
import 'package:supercluster/supercluster.dart';

class ExpandedCluster {
  final LayerCluster<Marker> layerCluster;
  final ClusterData clusterData;
  final List<DisplacedMarker> displacedMarkers;
  final Size maxMarkerSize;
  final ClusterSplayDelegate clusterSplayDelegate;
  late final Map<Marker, DisplacedMarker> markersToDisplacedMarkers;

  final AnimationController animation;
  late final CurvedAnimation _splayAnimation;
  late final CurvedAnimation _clusterOpacityAnimation;

  ExpandedCluster({
    required TickerProvider vsync,
    required this.layerCluster,
    required MapController mapController,
    required List<LayerPoint<Marker>> layerPoints,
    required this.clusterSplayDelegate,
  })  : clusterData = layerCluster.clusterData as ClusterData,
        animation = AnimationController(
          vsync: vsync,
          duration: clusterSplayDelegate.duration,
        ),
        displacedMarkers = clusterSplayDelegate.displaceMarkers(
          layerPoints.map((e) => e.originalPoint).toList(),
          clusterPosition: layerCluster.latLng,
          project: (latLng) => mapController.camera.projectAtZoom(latLng, layerCluster.highestZoom.toDouble()),
          unproject: (point) => mapController.camera.unprojectAtZoom(point, layerCluster.highestZoom.toDouble()),
        ),
        maxMarkerSize = layerPoints.fold(
          Size.zero,
          (previous, layerPoint) => Size(
            max(previous.width, layerPoint.originalPoint.width),
            max(previous.height, layerPoint.originalPoint.height),
          ),
        ) {
    markersToDisplacedMarkers = {
      for (final displacedMarker in displacedMarkers) displacedMarker.marker: displacedMarker
    };
    _splayAnimation = CurvedAnimation(
      parent: animation,
      curve: clusterSplayDelegate.curve,
    );
    _clusterOpacityAnimation = CurvedAnimation(
      parent: animation,
      curve: Interval(0.2, 1.0, curve: clusterSplayDelegate.curve),
    );
  }

  int get minimumVisibleZoom => layerCluster.highestZoom;

  List<DisplacedMarkerOffset> displacedMarkerOffsets(
    MapController mapController,
    Offset clusterPosition,
  ) =>
      clusterSplayDelegate.displacedMarkerOffsets(
        displacedMarkers,
        animation.value,
        mapController.getPixelOffset,
        clusterPosition,
      );

  Widget? splayDecoration(List<DisplacedMarkerOffset> displacedMarkerOffsets) =>
      clusterSplayDelegate.splayDecoration(displacedMarkerOffsets);

  Widget buildCluster(
    BuildContext context,
    ClusterWidgetBuilder clusterBuilder,
  ) =>
      clusterSplayDelegate.buildCluster(
        context,
        clusterBuilder,
        layerCluster.latLng,
        clusterData.markerCount,
        clusterData.innerData,
        animation.value,
      );

  double get splay => _splayAnimation.value;

  double get splayDistance => clusterSplayDelegate.distance;

  bool get isExpanded => animation.status == AnimationStatus.completed;

  bool get collapsing => animation.isAnimating && animation.status == AnimationStatus.reverse;

  Iterable<Marker> get markers => displacedMarkers.map((displacedMarker) => displacedMarker.marker);

  void tryCollapse(void Function(TickerFuture collapseTicker) onCollapse) {
    if (!collapsing) onCollapse(animation.reverse());
  }

  void dispose() {
    _splayAnimation.dispose();
    _clusterOpacityAnimation.dispose();
    animation.dispose();
  }
}

import 'dart:async';
import 'dart:math';

import 'package:async/async.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_marker_popup/extension_api.dart';
import 'package:flutter_map_supercluster/src/controller/marker_matcher.dart';
import 'package:flutter_map_supercluster/src/controller/supercluster_event.dart';
import 'package:flutter_map_supercluster/src/controller/supercluster_state.dart';
import 'package:flutter_map_supercluster/src/layer/create_supercluster.dart';
import 'package:flutter_map_supercluster/src/layer/expanded_cluster_manager.dart';
import 'package:flutter_map_supercluster/src/layer/flutter_map_state_extension.dart';
import 'package:flutter_map_supercluster/src/layer/loading_overlay.dart';
import 'package:flutter_map_supercluster/src/layer/supercluster_config.dart';
import 'package:flutter_map_supercluster/src/layer_element_extension.dart';
import 'package:flutter_map_supercluster/src/options/index_builder.dart';
import 'package:flutter_map_supercluster/src/options/popup_options_impl.dart';
import 'package:flutter_map_supercluster/src/splay/cluster_splay_delegate.dart';
import 'package:flutter_map_supercluster/src/splay/popup_spec_builder.dart';
import 'package:flutter_map_supercluster/src/splay/spread_cluster_splay_delegate.dart';
import 'package:flutter_map_supercluster/src/supercluster_extension.dart';
import 'package:flutter_map_supercluster/src/widget/expandable_cluster_widget.dart';
import 'package:flutter_map_supercluster/src/widget/expanded_cluster.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:supercluster/supercluster.dart';

import '../controller/supercluster_controller.dart';
import '../controller/supercluster_controller_impl.dart';
import '../options/popup_options.dart';
import '../widget/cluster_widget.dart';
import '../widget/marker_widget.dart';
import 'cluster_data.dart';

/// Builder for the cluster widget.
typedef ClusterWidgetBuilder = Widget Function(
  BuildContext context,
  LatLng position,
  int markerCount,
  ClusterDataBase? extraClusterData,
);

/// See [SuperclusterLayer.moveMap].
typedef MoveMapCallback = FutureOr<void> Function(LatLng center, double zoom);

class SuperclusterLayer extends StatefulWidget {
  static const popupNamespace = 'flutter_map_supercluster';

  final bool _isMutableSupercluster;

  /// Cluster builder
  // final ClusterWidgetBuilder builder;
  final Widget child;

  /// Controller for managing [Marker]s and listening to changes.
  final SuperclusterControllerImpl controller;

  /// Initial list of markers, additions/removals must be made using the
  /// [controller].
  final List<Marker> initialMarkers;

  /// Builder used to create the supercluster index. See [IndexBuilders] for
  /// predefined builders and guidelines on which one to use.
  final IndexBuilder indexBuilder;

  /// The minimum number of points required to form a cluster, if there is less
  /// than this number of points within the [maxClusterRadius] the markers will
  /// be left unclustered.
  final int? minimumClusterSize;

  /// The maximum radius in pixels that a cluster can cover.
  final int maxClusterRadius;

  /// Implement this function to extract extra data from Markers which can be
  /// used in the [builder].
  ///
  /// Note that if index creation happens in an isolate, code which does not
  /// work on a separate isolate (e.g. riverpod) will fail. In this case either
  /// refactor your clusterDataExtractor to stop using code which does not work
  /// in a separate isolate or see [IndexBuilders] for how to prevent index
  /// creation from occuring in a separate isolate.
  final ClusterDataBase Function(Marker marker)? clusterDataExtractor;

  /// When tapping a cluster or moving to a [Marker] with
  /// [SuperclusterController]'s moveToMarker method this callback controls
  /// if/how the movement is performed. The default is to move with no
  /// animation.
  ///
  /// When moving to a splay cluster (see [clusterSplayDelegate]) or a [Marker]
  /// inside a splay cluster the splaying will start once this callback
  /// completes.
  final MoveMapCallback? moveMap;

  /// Function to call when a Marker is tapped
  final void Function(Marker)? onMarkerTap;

  /// A builder used to override the override which is displayed whilst the
  /// supercluster index is being built.
  final WidgetBuilder? loadingOverlayBuilder;

  /// If provided popups will be enabled for markers. Depending on the provided
  /// options they will appear when markers are tapped or when triggered by a
  /// provided PopupController.
  final PopupOptionsImpl? popupOptions;

  /// Cluster size
  final Size clusterWidgetSize;

  /// Cluster anchor
  final AlignmentGeometry? alignment;

  /// If true then whenever the aggregated cluster data changes (that is, the
  /// combined cluster data of all Markers as calculated by
  /// [clusterDataExtractor]) then the new value will be added to the
  /// [controller]'s [aggregatedClusterDataStream].
  final bool calculateAggregatedClusterData;

  /// Splaying occurs when it is not possible to open a cluster because its
  /// points are visible at a zoom higher than the max zoom. This delegate
  /// controls the animation and style of the cluster splaying.
  final ClusterSplayDelegate clusterSplayDelegate;

  SuperclusterLayer.immutable({
    super.key,
    SuperclusterImmutableController? controller,
    required this.child,
    required this.indexBuilder,
    this.initialMarkers = const [],
    this.moveMap,
    this.onMarkerTap,
    this.minimumClusterSize,
    this.maxClusterRadius = 80,
    this.clusterDataExtractor,
    this.calculateAggregatedClusterData = false,
    this.clusterWidgetSize = const Size(30, 30),
    this.loadingOverlayBuilder,
    PopupOptions? popupOptions,
    this.alignment,
    this.clusterSplayDelegate = const SpreadClusterSplayDelegate(
      duration: Duration(milliseconds: 300),
      splayLineOptions: SplayLineOptions(),
    ),
  })  : _isMutableSupercluster = false,
        controller = controller != null
            ? controller as SuperclusterControllerImpl
            : SuperclusterControllerImpl(createdInternally: true),
        popupOptions = popupOptions == null ? null : popupOptions as PopupOptionsImpl;

  SuperclusterLayer.mutable({
    super.key,
    SuperclusterMutableController? controller,
    required this.child,
    required this.indexBuilder,
    this.initialMarkers = const [],
    this.moveMap,
    this.onMarkerTap,
    this.minimumClusterSize,
    this.maxClusterRadius = 80,
    this.clusterDataExtractor,
    this.calculateAggregatedClusterData = false,
    this.clusterWidgetSize = const Size(30, 30),
    this.loadingOverlayBuilder,
    PopupOptions? popupOptions,
    this.alignment,
    this.clusterSplayDelegate = const SpreadClusterSplayDelegate(
      duration: Duration(milliseconds: 400),
    ),
  })  : _isMutableSupercluster = true,
        controller = controller != null
            ? controller as SuperclusterControllerImpl
            : SuperclusterControllerImpl(createdInternally: true),
        popupOptions = popupOptions == null ? null : popupOptions as PopupOptionsImpl;

  @override
  State<SuperclusterLayer> createState() => _SuperclusterLayerState();
}

class _SuperclusterLayerState extends State<SuperclusterLayer> with TickerProviderStateMixin {
  static const defaultMinZoom = 1;
  static const defaultMaxZoom = 20;

  bool _initialized = false;

  late int minZoom;
  late int maxZoom;

  late MapController _mapController;
  late final ExpandedClusterManager _expandedClusterManager;

  StreamSubscription<SuperclusterEvent>? _controllerSubscription;
  StreamSubscription<void>? _movementStreamSubscription;

  int? _lastMovementZoom;

  PopupState? _popupState;

  CancelableCompleter<Supercluster<Marker>> _superclusterCompleter = CancelableCompleter();

  @override
  void initState() {
    super.initState();
    _expandedClusterManager = ExpandedClusterManager(
      onRemoveStart: (expandedClusters) {
        // The flutter_map_marker_popup package takes care of hiding popups
        // when zooming out but when an ExpandedCluster removal is triggered by
        // SuperclusterController.collapseSplayedClusters we need to remove the
        // popups ourselves.
        widget.popupOptions?.popupController.hidePopupsOnlyFor(
          expandedClusters.expand((expandedCluster) => expandedCluster.markers).toList(),
        );
      },
      onRemoved: (expandedClusters) => setState(() {}),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    _mapController = MapController.maybeOf(context)!;

    final oldMinZoom = !_initialized ? null : minZoom;
    final oldMaxZoom = !_initialized ? null : maxZoom;
    minZoom = _mapController.camera.minZoom?.ceil() ?? defaultMinZoom;
    maxZoom = _mapController.camera.maxZoom?.ceil() ?? defaultMaxZoom;

    bool zoomsChanged = _initialized && oldMinZoom != minZoom || oldMaxZoom != maxZoom;

    if (!_initialized) {
      _lastMovementZoom = _mapController.camera.zoom.ceil();
      _controllerSubscription =
          widget.controller.stream.listen((superclusterEvent) => _onSuperclusterEvent(superclusterEvent));

      _movementStreamSubscription = _mapController.mapEventStream.listen((_) => _onMove(_mapController));
    }

    if (!_initialized || zoomsChanged) {
      if (_initialized) {
        debugPrint('WARNING: Changes to the FlutterMapState have caused a rebuild of '
            'the Supercluster clusters. This can be a slow operation and '
            'should be avoided whenever possible.');
      }
      _initializeClusterManager(
        !_initialized
            ? Future.value(widget.initialMarkers)
            : _superclusterCompleter.operation.value.then((supercluster) => supercluster.getLeaves().toList()),
      );
    }
    _initialized = true;
  }

  @override
  void didUpdateWidget(SuperclusterLayer oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget._isMutableSupercluster != widget._isMutableSupercluster ||
        oldWidget.controller != widget.controller) {
      _onControllerChange(oldWidget.controller, widget.controller);
    }

    if (oldWidget._isMutableSupercluster != widget._isMutableSupercluster ||
        oldWidget.maxClusterRadius != widget.maxClusterRadius ||
        oldWidget.minimumClusterSize != widget.minimumClusterSize ||
        oldWidget.calculateAggregatedClusterData != widget.calculateAggregatedClusterData) {
      debugPrint('WARNING: Changes to the Supercluster options have caused a rebuild '
          'of the Supercluster clusters. This can be a slow operation and '
          'should be avoided whenever possible.');
      _initializeClusterManager(_superclusterCompleter.operation
          .valueOrCancellation()
          .then((supercluster) => supercluster?.getLeaves().toList() ?? []));
    }

    if (widget.popupOptions != oldWidget.popupOptions) {
      oldWidget.popupOptions?.popupController.dispose();
      _movementStreamSubscription?.cancel();
      _movementStreamSubscription = _mapController.mapEventStream.listen((_) => _onMove(_mapController));
    }
  }

  @override
  void dispose() {
    widget.popupOptions?.popupController.dispose();
    if (widget.controller.createdInternally) widget.controller.dispose();
    _movementStreamSubscription?.cancel();
    _controllerSubscription?.cancel();
    super.dispose();
  }

  void _initializeClusterManager(Future<List<Marker>> markersFuture) {
    widget.controller.updateState(
      const SuperclusterState(loading: true, aggregatedClusterData: null),
    );

    final supercluster = markersFuture.catchError((_) => <Marker>[]).then((markers) {
      final superclusterConfig = SuperclusterConfig(
        isMutableSupercluster: widget._isMutableSupercluster,
        markers: markers,
        minZoom: minZoom,
        maxZoom: maxZoom,
        maxClusterRadius: widget.maxClusterRadius,
        minimumClusterSize: widget.minimumClusterSize,
        innerClusterDataExtractor: widget.clusterDataExtractor,
      );

      if (_superclusterCompleter.isCompleted || _superclusterCompleter.isCanceled) {
        setState(() {
          _superclusterCompleter = CancelableCompleter();
        });
      }

      final newSupercluster = widget.indexBuilder.call(createSupercluster, superclusterConfig);

      _superclusterCompleter.complete(newSupercluster);
      _superclusterCompleter.operation.value.then((supercluster) {
        _onMarkersChange();
        _expandedClusterManager.clear();
        widget.popupOptions?.popupController.hidePopupsWhereSpec(
          (popupSpec) => popupSpec.namespace == SuperclusterLayer.popupNamespace,
        );
      });

      return newSupercluster;
    });

    widget.controller.setSupercluster(supercluster);
  }

  @override
  Widget build(BuildContext context) {
    final mapController = MapController.maybeOf(context)!;

    return _wrapWithPopupStateIfPopupsEnabled(
      (popupState) => Stack(
        children: [
          _clustersAndMarkers(mapController),
          if (widget.popupOptions?.popupDisplayOptions != null)
            PopupLayer(
              popupDisplayOptions: widget.popupOptions!.popupDisplayOptions!,
            ),
          LoadingOverlay(
            superclusterFuture: _superclusterCompleter.operation.value,
            loadingOverlayBuilder: widget.loadingOverlayBuilder,
          ),
        ],
      ),
    );
  }

  Widget _wrapWithPopupStateIfPopupsEnabled(Widget Function(PopupState? popupState) builder) {
    if (widget.popupOptions == null) return builder(null);

    return InheritOrCreatePopupScope(
      popupController: widget.popupOptions!.popupController,
      builder: (context, popupState) {
        _popupState = popupState;
        if (widget.popupOptions!.selectedMarkerBuilder != null) {
          context.watch<PopupState>();
        }
        return builder(popupState);
      },
    );
  }

  Widget _clustersAndMarkers(MapController mapController) {
    final paddedBounds = mapController.paddedMapBounds(widget.clusterWidgetSize);

    return FutureBuilder<Supercluster<Marker>>(
      future: _superclusterCompleter.operation.value,
      builder: (context, snapshot) {
        final supercluster = snapshot.data;
        if (supercluster == null) return const SizedBox.shrink();

        return Stack(children: [..._buildClustersAndMarkers(mapController, supercluster, paddedBounds)]);
      },
    );
  }

  Iterable<Widget> _buildClustersAndMarkers(
    MapController mapState,
    Supercluster<Marker> supercluster,
    LatLngBounds paddedBounds,
  ) sync* {
    final selectedMarkerBuilder = widget.popupOptions != null && _popupState!.selectedMarkers.isNotEmpty
        ? widget.popupOptions!.selectedMarkerBuilder
        : null;
    final List<LayerPoint<Marker>> selectedLayerPoints = [];
    final List<LayerCluster<Marker>> clusters = [];

    // Build non-selected markers first, queue the rest to build afterwards
    // so they appear above these markers.
    for (final layerElement in supercluster.search(
      paddedBounds.west,
      paddedBounds.south,
      paddedBounds.east,
      paddedBounds.north,
      mapState.camera.zoom.ceil(),
    )) {
      if (layerElement is LayerCluster<Marker>) {
        clusters.add(layerElement);
        continue;
      }
      layerElement as LayerPoint<Marker>;
      if (selectedMarkerBuilder != null && _popupState!.selectedMarkers.contains(layerElement.originalPoint)) {
        selectedLayerPoints.add(layerElement);
        continue;
      }
      yield _buildMarker(mapState, layerElement);
    }

    // Build selected markers.
    for (final selectedLayerPoint in selectedLayerPoints) {
      yield _buildMarker(mapState, selectedLayerPoint, selected: true);
    }

    // Build non expanded clusters.
    for (final cluster in clusters) {
      if (_expandedClusterManager.contains(cluster)) continue;
      yield _buildCluster(mapState, supercluster, cluster);
    }

    // Build expanded clusters.
    for (final expandedCluster in _expandedClusterManager.all) {
      yield _buildExpandedCluster(mapState, expandedCluster);
    }
  }

  Widget _buildMarker(
    MapController mapController,
    LayerPoint<Marker> mapPoint, {
    bool selected = false,
  }) {
    final marker = mapPoint.originalPoint;

    final markerChild = !selected ? marker.child : widget.popupOptions!.selectedMarkerBuilder!(context, marker);

    return MarkerWidget(
      mapController: mapController,
      marker: marker,
      markerChild: markerChild,
      onTap: () => _onMarkerTap(PopupSpecBuilder.forLayerPoint(mapPoint)),
    );
  }

  Widget _buildCluster(
    MapController mapController,
    Supercluster<Marker> supercluster,
    LayerCluster<Marker> cluster,
  ) {
    return ClusterWidget(
      mapController: _mapController,
      cluster: cluster,
      onTap: () => _onClusterTap(supercluster, cluster),
      size: widget.clusterWidgetSize,
      alignment: widget.alignment,
      child: widget.child,
    );
  }

  Widget _buildExpandedCluster(
    MapController mapController,
    ExpandedCluster expandedCluster,
  ) {
    return ExpandableClusterWidget(
      mapController: mapController,
      expandedCluster: expandedCluster,
      size: widget.clusterWidgetSize,
      alignment: widget.alignment,
      onCollapse: () {
        widget.popupOptions?.popupController.hidePopupsOnlyFor(expandedCluster.markers.toList());
        _expandedClusterManager.collapseThenRemove(expandedCluster.layerCluster);
      },
      onMarkerTap: _onMarkerTap,
      child: widget.child,
    );
  }

  void _onClusterTap(
    Supercluster<Marker> supercluster,
    LayerCluster<Marker> layerCluster,
  ) async {
    if (layerCluster.highestZoom >= maxZoom) {
      await _moveMapIfNotAt(
        layerCluster.latLng,
        layerCluster.highestZoom.toDouble(),
      );

      final splayAnimation = _expandedClusterManager.putIfAbsent(
        layerCluster,
        () => ExpandedCluster(
          vsync: this,
          mapController: _mapController,
          layerPoints: supercluster.childrenOf(layerCluster).cast<LayerPoint<Marker>>(),
          layerCluster: layerCluster,
          clusterSplayDelegate: widget.clusterSplayDelegate,
        ),
      );
      if (splayAnimation != null) setState(() {});
    } else {
      await _moveMapIfNotAt(
        layerCluster.latLng,
        layerCluster.highestZoom + 0.5,
      );
    }
  }

  FutureOr<void> _moveMapIfNotAt(
    LatLng center,
    double zoom, {
    FutureOr<void> Function(LatLng center, double zoom)? moveMapOverride,
  }) {
    if (center == _mapController.camera.center && zoom == _mapController.camera.zoom) {
      return Future.value();
    }

    final moveMap = moveMapOverride ??
        widget.moveMap ??
        (center, zoom) => _mapController.move(
              center,
              zoom,
            );

    return moveMap.call(center, zoom);
  }

  void _onMarkerTap(PopupSpec popupSpec) {
    _selectMarker(popupSpec);
    widget.onMarkerTap?.call(popupSpec.marker);
  }

  void _selectMarker(PopupSpec popupSpec) {
    if (widget.popupOptions != null) {
      assert(_popupState != null);

      final popupOptions = widget.popupOptions!;
      popupOptions.markerTapBehavior.apply(
        popupSpec,
        _popupState!,
        popupOptions.popupController,
      );

      if (popupOptions.selectedMarkerBuilder != null) setState(() {});
    }
  }

  void _onMove(MapController mapController) {
    final zoom = mapController.camera.zoom.ceil();

    if (_lastMovementZoom == null || zoom < _lastMovementZoom!) {
      _expandedClusterManager.removeIfZoomGreaterThan(zoom);
    }

    _lastMovementZoom = zoom;
  }

  void _onMarkersChange() {
    if (!widget.controller.createdInternally) {
      _superclusterCompleter.operation.value.then((supercluster) {
        final aggregatedClusterData =
            widget.calculateAggregatedClusterData ? supercluster.aggregatedClusterData() : null;
        final clusterData = aggregatedClusterData == null ? null : (aggregatedClusterData as ClusterData);
        widget.controller.updateState(
          SuperclusterState(
            loading: false,
            aggregatedClusterData: clusterData,
          ),
        );
      });
    }
  }

  void _onControllerChange(
    SuperclusterControllerImpl oldController,
    SuperclusterControllerImpl newController,
  ) {
    _controllerSubscription?.cancel();
    _controllerSubscription = newController.stream.listen((event) => _onSuperclusterEvent(event));

    oldController.removeSupercluster();
    if (oldController.createdInternally) oldController.dispose();
    newController.setSupercluster(_superclusterCompleter.operation.value);
  }

  void _moveToMarker({
    required MarkerMatcher markerMatcher,
    required bool showPopup,
    required FutureOr<void> Function(LatLng center, double zoom)? moveMap,
  }) async {
    // Create a shorthand for the map movement function.
    move(center, zoom) => _moveMapIfNotAt(center, zoom, moveMapOverride: moveMap);

    /// Find the Marker's LayerPoint.
    final supercluster = await _superclusterCompleter.operation.value;
    LayerPoint<Marker>? foundLayerPoint = supercluster.layerPointMatching(markerMatcher);
    if (foundLayerPoint == null) return;

    final markerInSplayCluster = maxZoom < foundLayerPoint.lowestZoom;
    if (markerInSplayCluster) {
      await _moveToSplayClusterMarker(
        supercluster: supercluster,
        layerPoint: foundLayerPoint,
        move: move,
        showPopup: showPopup,
      );
    } else {
      await move(
        foundLayerPoint.latLng,
        max(foundLayerPoint.lowestZoom.toDouble(), _mapController.camera.zoom),
      );
      if (showPopup) {
        _selectMarker(PopupSpecBuilder.forLayerPoint(foundLayerPoint));
      }
    }
  }

  /// Move to Marker inside splay cluster. There are three possibilities:
  ///  1. There is already an ExpandedCluster containing the Marker and it
  ///     remains expanded during movement.
  ///  2. There is already an ExpandedCluster and it closes during movement so
  ///     we must create a new one once movement finishes.
  ///  3. There is NOT already an ExpandedCluster, we should create one and add
  ///     it once movement finishes.
  Future<void> _moveToSplayClusterMarker({
    required Supercluster<Marker> supercluster,
    required LayerPoint<Marker> layerPoint,
    required FutureOr<void> Function(LatLng center, double zoom) move,
    required bool showPopup,
  }) async {
    // Find the parent.
    final layerCluster = supercluster.parentOf(layerPoint)!;

    // Shorthand for creating an ExpandedCluster.
    createExpandedCluster() => ExpandedCluster(
          vsync: this,
          mapController: _mapController,
          layerPoints: supercluster.childrenOf(layerCluster).cast<LayerPoint<Marker>>(),
          layerCluster: layerCluster,
          clusterSplayDelegate: widget.clusterSplayDelegate,
        );

    // Find or create the marker's ExpandedCluster and use it to find the
    // DisplacedMarker.
    final expandedClusterBeforeMovement = _expandedClusterManager.forLayerCluster(layerCluster);
    final createdExpandedCluster = expandedClusterBeforeMovement != null ? null : createExpandedCluster();
    final displacedMarker =
        (expandedClusterBeforeMovement ?? createdExpandedCluster)!.markersToDisplacedMarkers[layerPoint.originalPoint]!;

    // Move to the DisplacedMarker.
    await move(
      displacedMarker.displacedPoint,
      max(_mapController.camera.zoom, layerPoint.lowestZoom - 0.99999),
    );

    // Determine the ExpandedCluster after movement, either:
    //   1. We created one (without adding it to ExpandedClusterManager)
    //      because there was none before movement.
    //   2. Movement may have caused the ExpandedCluster to be removed in which
    //      case we create a new one.
    final splayAnimation = _expandedClusterManager.putIfAbsent(
      layerCluster,
      () => createdExpandedCluster ?? createExpandedCluster(),
    );
    if (splayAnimation != null) {
      if (!mounted) return;
      setState(() {});
      await splayAnimation;
    }

    if (showPopup) {
      final popupSpec = PopupSpecBuilder.forDisplacedMarker(
        displacedMarker,
        layerCluster.highestZoom,
      );
      _selectMarker(popupSpec);
    }
  }

  void _onSuperclusterEvent(SuperclusterEvent event) async {
    switch (event) {
      case AddMarkerEvent():
        _superclusterCompleter.operation.then((supercluster) {
          (supercluster as SuperclusterMutable<Marker>).insert(event.marker);
          _onMarkersChange();
        });
      case RemoveMarkerEvent():
        _superclusterCompleter.operation.then((supercluster) {
          final removed = (supercluster as SuperclusterMutable<Marker>).remove(event.marker);
          if (removed) _onMarkersChange();
        });
      case ReplaceAllMarkerEvent():
        _initializeClusterManager(Future.value(event.markers));
      case ModifyMarkerEvent():
        _superclusterCompleter.operation.then((supercluster) {
          final modified = (supercluster as SuperclusterMutable<Marker>).modifyPointData(
            event.oldMarker,
            event.newMarker,
            updateParentClusters: event.updateParentClusters,
          );

          if (modified) _onMarkersChange();
        });
      case CollapseSplayedClustersEvent():
        _expandedClusterManager.collapseThenRemoveAll();
      case ShowPopupsAlsoForEvent():
        if (widget.popupOptions == null) return;
        widget.popupOptions?.popupController.showPopupsAlsoForSpecs(
          PopupSpecBuilder.buildList(
            supercluster: await _superclusterCompleter.operation.value,
            zoom: _mapController.camera.zoom.ceil(),
            maxZoom: maxZoom,
            markers: event.markers,
            expandedClusters: _expandedClusterManager.all,
          ),
          disableAnimation: event.disableAnimation,
        );
      case MoveToMarkerEvent():
        _moveToMarker(
          markerMatcher: event.markerMatcher,
          showPopup: event.showPopup,
          moveMap: event.moveMap,
        );
      case ShowPopupsOnlyForEvent():
        if (widget.popupOptions == null) return;
        widget.popupOptions?.popupController.showPopupsOnlyForSpecs(
          PopupSpecBuilder.buildList(
            supercluster: await _superclusterCompleter.operation.value,
            zoom: _mapController.camera.zoom.ceil(),
            maxZoom: maxZoom,
            markers: event.markers,
            expandedClusters: _expandedClusterManager.all,
          ),
          disableAnimation: event.disableAnimation,
        );
      case HideAllPopupsEvent():
        if (widget.popupOptions == null) return;
        widget.popupOptions?.popupController.hideAllPopups(
          disableAnimation: event.disableAnimation,
        );
      case HidePopupsWhereEvent():
        if (widget.popupOptions == null) return;
        widget.popupOptions?.popupController.hidePopupsWhere(
          event.test,
          disableAnimation: event.disableAnimation,
        );
      case HidePopupsOnlyForEvent():
        if (widget.popupOptions == null) return;
        widget.popupOptions?.popupController.hidePopupsOnlyFor(
          event.markers,
          disableAnimation: event.disableAnimation,
        );
      case TogglePopupEvent():
        if (widget.popupOptions == null) return;
        final popupSpec = PopupSpecBuilder.build(
          supercluster: await _superclusterCompleter.operation.value,
          zoom: _mapController.camera.zoom.ceil(),
          maxZoom: maxZoom,
          marker: event.marker,
          expandedClusters: _expandedClusterManager.all,
        );
        if (popupSpec == null) return;
        widget.popupOptions?.popupController.togglePopupSpec(
          popupSpec,
          disableAnimation: event.disableAnimation,
        );
    }

    setState(() {});
  }
}

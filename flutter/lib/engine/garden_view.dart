// The interactive surface for the garden engine: owns the [GardenCamera], runs
// the animation ticker that drives the critters, and turns finger gestures into
// pinch-zoom / pan. Pan is clamped so the garden stays fixed on screen. There is
// no viewing-angle control — the 2.5D depth is fixed (see kVy).
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;

import '../logic.dart';
import 'garden_engine.dart';

class GardenView extends StatefulWidget {
  final Garden garden;
  final SpriteBank sprites;
  final bool customizing;
  final void Function(int tileIndex) onTapTile;
  final int groundColor;
  final int soilColor;
  final int uiColor; // controls tint (theme onSurface)
  final int panelColor; // chip background behind the on-scene controls (#4)
  final String lang;
  final String Function(String key) tr;

  /// Toggle hiding all garden HUD (bottom-left button). Null hides the button.
  final VoidCallback? onPeek;

  /// Enter camera-framing mode (bottom-left button). Null hides the button.
  final VoidCallback? onCamera;

  /// Wraps the painter in a RepaintBoundary so the scene can be screenshot.
  final GlobalKey? captureKey;

  /// In camera mode the corner buttons hide so framing is clean.
  final bool cameraMode;

  /// When false the view ignores gestures (used as a live backdrop).
  final bool interactive;

  /// When provided, the parent owns the camera so it can read the current
  /// framing (yaw/zoom/pan) — used to set the live wallpaper (v15).
  final GardenCamera? camera;

  const GardenView({
    super.key,
    required this.garden,
    required this.sprites,
    required this.customizing,
    required this.onTapTile,
    required this.groundColor,
    required this.soilColor,
    required this.uiColor,
    required this.panelColor,
    required this.lang,
    required this.tr,
    this.onPeek,
    this.onCamera,
    this.captureKey,
    this.cameraMode = false,
    this.interactive = true,
    this.camera,
  });

  @override
  State<GardenView> createState() => _GardenViewState();
}

class _GardenViewState extends State<GardenView> with SingleTickerProviderStateMixin {
  late final GardenCamera _cam = widget.camera ?? GardenCamera();
  final CritterSystem _critters = CritterSystem();
  final ValueNotifier<int> _frame = ValueNotifier(0);

  late final Ticker _ticker;
  Duration _last = Duration.zero;
  double _zoomAtStart = 1;
  double _yawAtStart = 0;
  Size _lastSize = Size.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      final dt = (elapsed - _last).inMicroseconds / 1e6;
      _last = elapsed;
      _critters.step(dt, math.max(widget.garden.cols, widget.garden.rows), _flowerTargets());
      _frame.value++; // nudges the painter to repaint
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }

  /// Garden-coord centres of planted flowers (not roads/fences) — critters live
  /// in garden space so they rotate/zoom with the map.
  List<Offset> _flowerTargets() {
    final cols = widget.garden.cols, rows = widget.garden.rows;
    final out = <Offset>[];
    widget.garden.tiles.forEach((i, _) {
      final prop = widget.garden.propAt(i);
      if (prop != null && Placeables.isFlower(prop)) {
        out.add(Offset(i % cols - (cols - 1) / 2.0, i ~/ cols - (rows - 1) / 2.0));
      }
    });
    return out;
  }

  void _onScaleStart(ScaleStartDetails d) {
    _zoomAtStart = _cam.zoom;
    _yawAtStart = _cam.yaw;
  }

  /// Clamp pan to the plot's roam radius (the forest fills the rest of the screen).
  void _clampWorld() {
    _cam.clamp(widget.garden.cols, widget.garden.rows, _lastSize);
  }

  /// An on-scene control on a themed chip, so it recolors with the theme (#4)
  /// AND stays readable on the dark forest scene in every theme.
  Widget _chip(Color ui, IconData icon, String tip, VoidCallback? onTap, Key? key) {
    return Container(
      decoration: BoxDecoration(
        color: Color(widget.panelColor).withValues(alpha: 0.85),
        border: Border.all(color: ui.withValues(alpha: 0.5), width: 2),
      ),
      child: IconButton(
        key: key,
        icon: Icon(icon, size: 20, color: ui),
        tooltip: tip,
        visualDensity: VisualDensity.compact,
        onPressed: onTap,
      ),
    );
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    setState(() {
      _cam.zoom = (_zoomAtStart * d.scale).clamp(1.0, 4.0);
      _cam.yaw = _yawAtStart + d.rotation; // two-finger twist = look from another side
      _cam.panX += d.focalPointDelta.dx;
      _cam.panY += d.focalPointDelta.dy;
      _clampWorld();
    });
  }

  void _onTapUp(TapUpDetails d) {
    if (!widget.customizing || _lastSize == Size.zero) return;
    // the projector is plot-sized again, so tileAt returns the claimed index
    // directly; taps on the surrounding forest fall outside and are ignored.
    final p = Projector.fit(widget.garden.cols, widget.garden.rows, _cam, _lastSize);
    final index = p.tileAt(d.localPosition);
    if (index >= 0) widget.onTapTile(index);
  }

  GardenPainter _painter() => GardenPainter(
        garden: widget.garden,
        cam: _cam,
        sprites: widget.sprites,
        critterSystem: _critters,
        customizing: widget.customizing,
        groundColor: widget.groundColor,
        soilColor: widget.soilColor,
        repaint: _frame,
      );

  @override
  Widget build(BuildContext context) {
    final ui = Color(widget.uiColor);
    return LayoutBuilder(
      builder: (context, constraints) {
        _lastSize = Size(constraints.maxWidth, constraints.maxHeight);
        _clampWorld();
        final scene = RepaintBoundary(
          key: widget.captureKey,
          child: CustomPaint(painter: _painter(), size: _lastSize),
        );
        // corner controls are hidden while framing a photo (cameraMode) or when
        // the view is a non-interactive backdrop.
        final showControls = widget.interactive && !widget.cameraMode;
        return Stack(
          children: [
            Positioned.fill(
              child: widget.interactive
                  ? GestureDetector(
                      onScaleStart: _onScaleStart,
                      onScaleUpdate: _onScaleUpdate,
                      onTapUp: _onTapUp,
                      child: scene,
                    )
                  : scene,
            ),
            if (showControls) ...[
              // recenter / reset zoom
              Positioned(
                right: 6,
                bottom: 4,
                child: _chip(ui, Icons.center_focus_strong, widget.tr('recenter'),
                    () => setState(_cam.reset), null),
              ),
              // peek — hide all HUD, just the garden
              if (widget.onPeek != null)
                Positioned(
                  left: 6,
                  bottom: 4,
                  child: _chip(ui, Icons.visibility, widget.tr('peek'), widget.onPeek,
                      const Key('peekButton')),
                ),
              // camera — frame & screenshot the garden
              if (widget.onCamera != null)
                Positioned(
                  left: 50,
                  bottom: 4,
                  child: _chip(ui, Icons.photo_camera, widget.tr('camera'), widget.onCamera,
                      const Key('cameraButton')),
                ),
            ],
          ],
        );
      },
    );
  }
}

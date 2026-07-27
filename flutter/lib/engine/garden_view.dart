// The interactive surface for the garden engine: owns the [GardenCamera], runs
// the animation ticker that drives the critters, and turns finger gestures into
// pinch-zoom / pan. Pan is clamped so the garden stays fixed on screen. There is
// no viewing-angle control beyond yaw — the 2.5D depth is fixed (see kVy).
//
// Desktop/web drives the same camera with mouse + keyboard (#v33.8): the wheel
// zooms, WASD/arrows walk the pan, and holding the MIDDLE button while dragging
// turns the yaw — the mouse spelling of the phone's two-finger twist. Touch
// gestures are untouched; on a phone these handlers simply never fire.
import 'dart:math' as math;

import 'package:flutter/gestures.dart'
    show PointerScrollEvent, PointerSignalEvent, kMiddleMouseButton;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/services.dart' show KeyEvent, KeyUpEvent, LogicalKeyboardKey;

import '../logic.dart';
import 'garden_engine.dart';

/// Pure input maths for the desktop/web controls, split out so the unit tests
/// can pin them without pumping widgets.
///
/// One 120-unit wheel notch scales zoom by 1.1x (down-scroll zooms out),
/// clamped to the same 0.5–4.0 range the pinch gesture uses.
double wheelZoom(double zoom, double scrollDy) =>
    (zoom * math.pow(1.1, -scrollDy / 120)).clamp(0.5, 4.0);

/// Pan that keeps the world point under [focal] pinned to that spot while the
/// zoom goes from [fromZoom] to [toZoom] (#v34.15).
///
/// The projector centres the world on `size/2 + pan` and scales the tile size
/// by the zoom, so changing the zoom alone magnifies about the **screen
/// centre** — and the screen centre is where the garden sits. Zooming in
/// anywhere else still flew toward the plot: "ormana dogru yaklastirmak
/// istiyorum, bahceye dogru gidiyor". The bigger the plot grew the more of the
/// centre it occupied, which is why it got worse with EXPAND.
///
/// Derivation: a world point maps to `centre + M(t)·g`, and M scales linearly
/// with the zoom, so holding `g` under `focal` across a zoom ratio `k` gives
/// `centre' = focal - k·(focal - centre)`; in pan terms, with `u` the focal
/// point's offset from the screen centre, `pan' = u·(1 - k) + pan·k`.
Offset zoomAboutFocal(
    Offset pan, Size size, Offset focal, double fromZoom, double toZoom) {
  if (fromZoom <= 0) return pan;
  final k = toZoom / fromZoom;
  final u = focal - Offset(size.width / 2, size.height / 2);
  return u * (1 - k) + pan * k;
}

/// Screen-pixels of pan for one key event; Offset.zero for keys we don't own.
/// Directions read as walking the CAMERA: D looks further right, so the scene
/// slides left — the same sign convention the drag gesture produces.
Offset wasdPan(LogicalKeyboardKey key, {double step = 32}) {
  if (key == LogicalKeyboardKey.keyW || key == LogicalKeyboardKey.arrowUp) {
    return Offset(0, step);
  }
  if (key == LogicalKeyboardKey.keyS || key == LogicalKeyboardKey.arrowDown) {
    return Offset(0, -step);
  }
  if (key == LogicalKeyboardKey.keyA || key == LogicalKeyboardKey.arrowLeft) {
    return Offset(step, 0);
  }
  if (key == LogicalKeyboardKey.keyD || key == LogicalKeyboardKey.arrowRight) {
    return Offset(-step, 0);
  }
  return Offset.zero;
}

/// Radians of yaw for a middle-drag of [dx] screen pixels — 100px turns ~1rad,
/// gentle enough to aim, fast enough to orbit the plot in one swipe.
double middleDragYaw(double dx) => dx * 0.01;

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

  /// Draw the woods only, with no clearing in them — the FOREST home backdrop
  /// (#v35.0).
  final bool forestOnly;

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
    this.forestOnly = false,
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
  bool _middleDrag = false; // mouse middle-button held: drag turns the yaw
  double _middleX = 0;

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

  // ---- mouse + keyboard (desktop/web), see header comment ------------------
  void _onPointerSignal(PointerSignalEvent e) {
    if (e is! PointerScrollEvent) return;
    setState(() {
      final next = wheelZoom(_cam.zoom, e.scrollDelta.dy);
      // zoom at the cursor, same as the pinch does at the fingers (#v34.15)
      final anchored = zoomAboutFocal(
          Offset(_cam.panX, _cam.panY), _lastSize, e.localPosition, _cam.zoom, next);
      _cam.zoom = next;
      _cam.panX = anchored.dx;
      _cam.panY = anchored.dy;
      _clampWorld();
    });
  }

  void _onPointerDown(PointerDownEvent e) {
    if (e.buttons & kMiddleMouseButton != 0) {
      _middleDrag = true;
      _middleX = e.position.dx;
    }
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (!_middleDrag) return;
    setState(() {
      _cam.yaw += middleDragYaw(e.position.dx - _middleX);
      _middleX = e.position.dx;
    });
  }

  void _endMiddleDrag(PointerEvent _) => _middleDrag = false;

  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    final pan = wasdPan(e.logicalKey);
    if (pan == Offset.zero) return KeyEventResult.ignored;
    setState(() {
      _cam.panX += pan.dx;
      _cam.panY += pan.dy;
      _clampWorld();
    });
    return KeyEventResult.handled;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    // The scale recognizer also tracks middle-button drags; while one is
    // turning the yaw, letting it pan too would smear both motions together.
    if (_middleDrag) return;
    setState(() {
      // min 0.5 (was 1.0) so you can zoom out far enough to frame the WHOLE
      // garden from any yaw — a rotated plot's bounding box is larger, so it used
      // to clip at the old 1.0 floor (capture feedback). Max 4.0 (zoom-in fine).
      final next = (_zoomAtStart * d.scale).clamp(0.5, 4.0);
      // Zoom about the fingers, not the screen centre (#v34.15) — otherwise
      // every zoom drifts toward the plot, whatever you were looking at.
      final anchored = zoomAboutFocal(
          Offset(_cam.panX, _cam.panY), _lastSize, d.localFocalPoint, _cam.zoom, next);
      _cam.zoom = next;
      _cam.yaw = _yawAtStart + d.rotation; // two-finger twist = look from another side
      _cam.panX = anchored.dx + d.focalPointDelta.dx;
      _cam.panY = anchored.dy + d.focalPointDelta.dy;
      _clampWorld();
    });
  }

  /// Double-tap steps the zoom in about the tapped point, and snaps back out
  /// once it is already close in (#v34.15). There was no double-tap handler at
  /// all before — "cift tikla yaklastirma sapitiyor" was the pinch's
  /// centre-anchored zoom plus nothing happening on the gesture the user
  /// actually reached for.
  static const double kDoubleTapZoom = 2.0;

  void _onDoubleTapDown(TapDownDetails d) => _doubleTapAt = d.localPosition;
  Offset _doubleTapAt = Offset.zero;

  void _onDoubleTap() {
    setState(() {
      final next = _cam.zoom < kDoubleTapZoom - 0.01 ? kDoubleTapZoom : 1.0;
      final anchored = zoomAboutFocal(
          Offset(_cam.panX, _cam.panY), _lastSize, _doubleTapAt, _cam.zoom, next);
      _cam.zoom = next;
      _cam.panX = anchored.dx;
      _cam.panY = anchored.dy;
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
        forestOnly: widget.forestOnly,
      );

  @override
  Widget build(BuildContext context) {
    final ui = Color(widget.uiColor);
    // Lift the bottom corner controls above the Android nav bar when the garden
    // runs edge-to-edge (peek mode drops the SafeArea); 0 in normal mode since the
    // SafeArea already consumed the inset (#2).
    final navInset = MediaQuery.of(context).padding.bottom;
    return LayoutBuilder(
      builder: (context, constraints) {
        _lastSize = Size(constraints.maxWidth, constraints.maxHeight);
        _clampWorld();
        // clip to the view box so zoomed forest billboards can't paint over the
        // GardenScreen HUD (title/buttons) above and below it (#v19).
        final scene = ClipRect(
          child: RepaintBoundary(
            key: widget.captureKey,
            child: CustomPaint(painter: _painter(), size: _lastSize),
          ),
        );
        // corner controls are hidden while framing a photo (cameraMode) or when
        // the view is a non-interactive backdrop.
        final showControls = widget.interactive && !widget.cameraMode;
        return Stack(
          children: [
            Positioned.fill(
              child: widget.interactive
                  ? Focus(
                      autofocus: true,
                      onKeyEvent: _onKey,
                      child: Listener(
                        onPointerSignal: _onPointerSignal,
                        onPointerDown: _onPointerDown,
                        onPointerMove: _onPointerMove,
                        onPointerUp: _endMiddleDrag,
                        onPointerCancel: _endMiddleDrag,
                        child: GestureDetector(
                          onScaleStart: _onScaleStart,
                          onScaleUpdate: _onScaleUpdate,
                          onTapUp: _onTapUp,
                          // Only outside CUSTOMIZE: with a double-tap callback
                          // attached, every single tap waits out the
                          // double-tap timeout before firing, which would make
                          // planting a tile feel laggy.
                          onDoubleTapDown:
                              widget.customizing ? null : _onDoubleTapDown,
                          onDoubleTap: widget.customizing ? null : _onDoubleTap,
                          child: scene,
                        ),
                      ),
                    )
                  : scene,
            ),
            if (showControls) ...[
              // recenter / reset zoom
              Positioned(
                right: 6,
                bottom: 4 + navInset,
                child: _chip(ui, Icons.center_focus_strong, widget.tr('recenter'),
                    () => setState(_cam.reset), null),
              ),
              // peek — hide all HUD, just the garden
              if (widget.onPeek != null)
                Positioned(
                  left: 6,
                  bottom: 4 + navInset,
                  child: _chip(ui, Icons.visibility, widget.tr('peek'), widget.onPeek,
                      const Key('peekButton')),
                ),
              // camera — frame & screenshot the garden
              if (widget.onCamera != null)
                Positioned(
                  left: 50,
                  bottom: 4 + navInset,
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

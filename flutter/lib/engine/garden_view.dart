// The interactive surface for the garden engine: owns the [GardenCamera], runs
// the animation ticker that drives the critters, and turns finger gestures into
// pinch-zoom / pan. Pan is clamped so the garden stays fixed on screen. There is
// no viewing-angle control — the 2.5D depth is fixed (see kVy).
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
  final int uiColor; // controls (recenter) tint
  final String lang;
  final String Function(String key) tr;

  const GardenView({
    super.key,
    required this.garden,
    required this.sprites,
    required this.customizing,
    required this.onTapTile,
    required this.groundColor,
    required this.soilColor,
    required this.uiColor,
    required this.lang,
    required this.tr,
  });

  @override
  State<GardenView> createState() => _GardenViewState();
}

class _GardenViewState extends State<GardenView> with SingleTickerProviderStateMixin {
  final GardenCamera _cam = GardenCamera();
  final CritterSystem _critters = CritterSystem();
  final ValueNotifier<int> _frame = ValueNotifier(0);

  late final Ticker _ticker;
  Duration _last = Duration.zero;
  double _zoomAtStart = 1;
  Size _lastSize = Size.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      final dt = (elapsed - _last).inMicroseconds / 1e6;
      _last = elapsed;
      _critters.step(dt, _lastSize, _flowerTargets());
      _frame.value++; // nudges the painter to repaint
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }

  /// Screen positions of planted flowers (not roads/fences), aimed a little
  /// above the ground so visitors hover at bloom height.
  List<Offset> _flowerTargets() {
    if (_lastSize == Size.zero) return const [];
    final p = Projector.fit(widget.garden.size, _cam, _lastSize);
    final out = <Offset>[];
    widget.garden.tiles.forEach((i, id) {
      if (!Placeables.isObject(id)) out.add(p.groundIndex(i).translate(0, -p.t * 0.35));
    });
    return out;
  }

  void _onScaleStart(ScaleStartDetails d) => _zoomAtStart = _cam.zoom;

  void _onScaleUpdate(ScaleUpdateDetails d) {
    setState(() {
      _cam.zoom = (_zoomAtStart * d.scale).clamp(1.0, 4.0);
      _cam.panX += d.focalPointDelta.dx;
      _cam.panY += d.focalPointDelta.dy;
      _cam.clamp(widget.garden.size, _lastSize);
    });
  }

  void _onTapUp(TapUpDetails d) {
    if (!widget.customizing || _lastSize == Size.zero) return;
    final p = Projector.fit(widget.garden.size, _cam, _lastSize);
    final index = p.tileAt(d.localPosition);
    if (index >= 0) widget.onTapTile(index);
  }

  GardenPainter _painter() => GardenPainter(
        garden: widget.garden,
        cam: _cam,
        sprites: widget.sprites,
        critterSystem: _critters,
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
        _cam.clamp(widget.garden.size, _lastSize);
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onScaleStart: _onScaleStart,
                onScaleUpdate: _onScaleUpdate,
                onTapUp: _onTapUp,
                child: CustomPaint(painter: _painter(), size: _lastSize),
              ),
            ),
            // recenter / reset zoom
            Positioned(
              right: 6,
              bottom: 4,
              child: IconButton(
                icon: Icon(Icons.center_focus_strong, size: 22, color: ui),
                tooltip: widget.tr('recenter'),
                onPressed: () => setState(_cam.reset),
              ),
            ),
          ],
        );
      },
    );
  }
}

// The interactive surface for the garden engine: owns the [GardenCamera], runs
// the animation ticker that drives the bugs, and turns finger gestures into
// pinch-zoom / pan, plus a tilt slider to change the viewing angle from above.
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
  final int uiColor; // controls (slider / reset) tint
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
  final BugSystem _bugs = BugSystem();
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
      _bugs.step(dt);
      _frame.value++; // nudges the painter to repaint
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _frame.dispose();
    super.dispose();
  }

  void _onScaleStart(ScaleStartDetails d) => _zoomAtStart = _cam.zoom;

  void _onScaleUpdate(ScaleUpdateDetails d) {
    setState(() {
      _cam.zoom = (_zoomAtStart * d.scale).clamp(0.4, 4.0);
      _cam.panX += d.focalPointDelta.dx;
      _cam.panY += d.focalPointDelta.dy;
    });
  }

  void _onTapUp(TapUpDetails d) {
    if (!widget.customizing || _lastSize == Size.zero) return;
    final painter = _painter();
    final index = painter.tileAt(d.localPosition, _lastSize);
    if (index >= 0) widget.onTapTile(index);
  }

  GardenPainter _painter() => GardenPainter(
        garden: widget.garden,
        cam: _cam,
        sprites: widget.sprites,
        bugSystem: _bugs,
        groundColor: widget.groundColor,
        soilColor: widget.soilColor,
        repaint: _frame,
      );

  @override
  Widget build(BuildContext context) {
    final ui = Color(widget.uiColor);
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        _lastSize = size;
        _bugs.configure(size, widget.garden.size);
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                onScaleStart: _onScaleStart,
                onScaleUpdate: _onScaleUpdate,
                onTapUp: _onTapUp,
                child: CustomPaint(painter: _painter(), size: size),
              ),
            ),
            // tilt (viewing angle) slider
            Positioned(
              left: 8,
              right: 56,
              bottom: 4,
              child: Row(
                children: [
                  Icon(Icons.threed_rotation, size: 18, color: ui),
                  Expanded(
                    child: SliderTheme(
                      data: SliderThemeData(
                        activeTrackColor: ui,
                        inactiveTrackColor: ui.withValues(alpha: 0.3),
                        thumbColor: ui,
                        overlayShape: SliderComponentShape.noOverlay,
                        trackHeight: 3,
                      ),
                      child: Slider(
                        value: _cam.pitch,
                        onChanged: (v) => setState(() => _cam.pitch = v),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // recenter / reset zoom
            Positioned(
              right: 6,
              bottom: 2,
              child: IconButton(
                icon: Icon(Icons.center_focus_strong, size: 22, color: ui),
                tooltip: widget.tr('recenter'),
                onPressed: () => setState(() {
                  _cam.zoom = 1;
                  _cam.panX = 0;
                  _cam.panY = 0;
                }),
              ),
            ),
          ],
        );
      },
    );
  }
}

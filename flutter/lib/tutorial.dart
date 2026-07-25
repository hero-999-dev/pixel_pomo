import 'dart:ui' show ClipOp;

import 'package:flutter/material.dart';

import 'logic.dart';
import 'pixel.dart';
import 'strings.dart';

/// The first-run tour (#v34): a dark scrim with a hole cut around one real
/// widget at a time, plus a card saying what that widget is for.
///
/// The steps point at LIVE widgets by [GlobalKey] rather than at hardcoded
/// coordinates, so the tour keeps pointing at the right thing when the layout
/// moves — clean vs garden home mode, a hidden tracker icon, a taller phone.

/// One stop on the tour. [target] null = a plain centred card with no hole
/// (the welcome and the sign-off).
class TutorialStep {
  final GlobalKey? target;
  final String titleKey;
  final String bodyKey;
  const TutorialStep(this.target, this.titleKey, this.bodyKey);
}

class TutorialOverlay extends StatefulWidget {
  final List<TutorialStep> steps;
  final PixelTheme theme;
  final String lang;

  /// Called once, whether the user walked the whole tour or hit SKIP.
  final VoidCallback onDone;

  const TutorialOverlay({
    super.key,
    required this.steps,
    required this.theme,
    required this.lang,
    required this.onDone,
  });

  @override
  State<TutorialOverlay> createState() => _TutorialOverlayState();
}

class _TutorialOverlayState extends State<TutorialOverlay> {
  int _i = 0;

  @override
  void initState() {
    super.initState();
    // On the very first frame the targets are mounted but not laid out yet, so
    // measuring them returns nothing. Re-measure once the frame is done — that
    // second build is the one that gets real rectangles.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  void _next() {
    if (_i >= widget.steps.length - 1) {
      widget.onDone();
    } else {
      setState(() => _i++);
    }
  }

  /// The target's box in THIS overlay's coordinates, or null when there is
  /// nothing to spotlight (no target, or not laid out yet).
  Rect? _spotlight(GlobalKey? key) {
    final target = key?.currentContext?.findRenderObject();
    final self = context.findRenderObject();
    if (target is! RenderBox || self is! RenderBox) return null;
    if (!target.hasSize || !self.hasSize) return null;
    final topLeft = self.globalToLocal(target.localToGlobal(Offset.zero));
    return (topLeft & target.size).inflate(6);
  }

  @override
  Widget build(BuildContext context) {
    final th = widget.theme;
    final lang = widget.lang;
    final step = widget.steps[_i];
    final hole = _spotlight(step.target);
    final last = _i == widget.steps.length - 1;
    final size = MediaQuery.of(context).size;
    final card = _card(th, lang, step, last);

    return Material(
      type: MaterialType.transparency,
      child: Stack(children: [
        // opaque: the tour owns every tap while it is up, so a spotlighted
        // button can't be pressed for real mid-explanation
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _next,
            child: CustomPaint(painter: SpotlightPainter(hole, col(th.accent))),
          ),
        ),
        if (hole == null)
          Center(child: Padding(padding: const EdgeInsets.all(24), child: card))
        else
          _place(hole, size, card),
      ]),
    );
  }

  /// Room the card needs beside a spotlight before it is worth anchoring there.
  /// Generous on purpose: the body text wraps to three lines in the longer
  /// languages, and this number only decides *where* the card goes.
  static const _cardRoom = 200.0;

  /// Sit the card next to the highlighted box when there is space, and dock it
  /// to the screen edge with the most room when there isn't. Anchoring blindly
  /// to a tall target — the whole timer block, centred in CLEAN mode — pushed
  /// the card, and with it SKIP and NEXT, off the top of the screen.
  Widget _place(Rect hole, Size size, Widget card) {
    final gapBelow = size.height - hole.bottom;
    final gapAbove = hole.top;
    double? top, bottom;
    if (gapBelow >= _cardRoom) {
      top = hole.bottom + 14;
    } else if (gapAbove >= _cardRoom) {
      bottom = size.height - hole.top + 14;
    } else if (gapBelow >= gapAbove) {
      bottom = 16; // no room either side — dock, and overlap the spotlight
    } else {
      top = 16;
    }
    return Positioned(left: 16, right: 16, top: top, bottom: bottom, child: card);
  }

  Widget _card(PixelTheme th, String lang, TutorialStep step, bool last) {
    final title = t(lang, step.titleKey);
    final body = t(lang, step.bodyKey);
    final next = t(lang, last ? 'tutFinish' : 'tutNext');
    final skip = t(lang, 'tutSkip');
    return Container(
      key: const Key('tutorialCard'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: col(th.panel),
        border: Border.all(color: col(th.onSurface), width: 2),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('${_i + 1}/${widget.steps.length}',
            style: pixelStyle(lang, 8, col(th.onSurfaceDim), text: '${_i + 1}/${widget.steps.length}')),
        const SizedBox(height: 8),
        Text(title, style: pixelStyle(lang, 13, col(th.accent), text: title)),
        const SizedBox(height: 10),
        Text(body, style: pixelStyle(lang, 10, col(th.onSurface), text: body)),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: PixelButton(
              key: const Key('tutorialSkip'),
              text: skip,
              fill: th.panel,
              border: th.onSurfaceDim,
              textColor: th.onSurface,
              shadow: th.shadow,
              lang: lang,
              fontSize: 10,
              padding: const EdgeInsets.all(12),
              onTap: widget.onDone,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: PixelButton(
              key: const Key('tutorialNext'),
              text: next,
              fill: th.accent,
              border: th.onSurface,
              textColor: th.onAccent,
              shadow: th.shadow,
              lang: lang,
              fontSize: 10,
              padding: const EdgeInsets.all(12),
              onTap: _next,
            ),
          ),
        ]),
      ]),
    );
  }
}

/// Public so a test can read [hole] back and prove the tour is measuring the
/// real widget, not just drawing a card over a flat scrim.
class SpotlightPainter extends CustomPainter {
  final Rect? hole;
  final Color frame;
  const SpotlightPainter(this.hole, this.frame);

  @override
  void paint(Canvas canvas, Size size) {
    final scrim = Paint()..color = const Color(0xD0000000);
    final full = Offset.zero & size;
    if (hole == null) {
      canvas.drawRect(full, scrim);
      return;
    }
    // Everything EXCEPT the hole gets darkened — one clip, no path algebra.
    canvas.save();
    canvas.clipRect(hole!, clipOp: ClipOp.difference);
    canvas.drawRect(full, scrim);
    canvas.restore();
    canvas.drawRect(
        hole!,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = frame);
  }

  @override
  bool shouldRepaint(SpotlightPainter old) => old.hole != hole || old.frame != frame;
}

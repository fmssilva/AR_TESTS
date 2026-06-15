import 'package:flutter/material.dart';
import '../../../core/ar/models/overlay_data.dart';

// AR heads-up display.
// Renders two layers:
//   1. A status chip at the top (anchor tracking state).
//   2. A CustomPaint fullscreen canvas with:
//        - World-coordinate gizmo: 3 coloured 1-metre axis arrows at the origin.
//        - A labelled circle for each POI at its projected screen position.
class AROverlay extends StatelessWidget {
  final String? activeAnchorId;
  final int detectedCount;
  final OverlayData? overlayData;

  const AROverlay({
    super.key,
    required this.activeAnchorId,
    required this.detectedCount,
    this.overlayData,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // --- Fullscreen canvas (gizmo + POI dots) ---
        if (overlayData != null)
          Positioned.fill(
            child: CustomPaint(
              painter: _AROverlayPainter(overlayData!),
            ),
          ),

        // --- Status chip ---
        SafeArea(
          child: Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.only(top: 12.0),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  activeAnchorId != null
                      ? 'Tracking: $activeAnchorId  |  $detectedCount anchors found'
                      : 'Scanning for anchors...',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Painter
// ---------------------------------------------------------------------------

class _AROverlayPainter extends CustomPainter {
  final OverlayData data;
  _AROverlayPainter(this.data);

  @override
  void paint(Canvas canvas, Size size) {
    final origin = viewportToCanvasPoint(size, data.originX, data.originY);
    final axisX  = viewportToCanvasPoint(size, data.axisXx, data.axisXy);
    final axisY  = viewportToCanvasPoint(size, data.axisYx, data.axisYy);
    final axisZ  = viewportToCanvasPoint(size, data.axisZx, data.axisZy);

    if (data.originVisible && data.axisXVisible) {
      _drawAxis(canvas, origin, axisX, Colors.red, 'X');
    }
    if (data.originVisible && data.axisYVisible) {
      _drawAxis(canvas, origin, axisY, Colors.green, 'Y');
    }
    if (data.originVisible && data.axisZVisible) {
      _drawAxis(canvas, origin, axisZ, Colors.blue, 'Z');
    }
    if (data.originVisible) {
      _drawOriginDot(canvas, origin);
    }

    for (final poi in data.pois) {
      _drawPOI(canvas, poi.toCanvasOffset(size), poi.label);
    }
  }

  void _drawAxis(
      Canvas canvas, Offset from, Offset to, Color color, String label) {
    // Shaft
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(from, to, paint);

    // Arrow head — small filled triangle at the end
    _drawArrowHead(canvas, from, to, color);

    // Label at end
    _drawText(canvas, label, to, color, fontSize: 14, bold: true, offset: const Offset(6, -6));
  }

  void _drawArrowHead(Canvas canvas, Offset from, Offset to, Color color) {
    final dir = (to - from);
    final len = dir.distance;
    if (len < 1) return;
    final unit = dir / len;
    final perp  = Offset(-unit.dy, unit.dx);
    const arrowSize = 10.0;

    final p1 = to;
    final p2 = to - unit * arrowSize + perp * (arrowSize * 0.4);
    final p3 = to - unit * arrowSize - perp * (arrowSize * 0.4);

    final path = Path()
      ..moveTo(p1.dx, p1.dy)
      ..lineTo(p2.dx, p2.dy)
      ..lineTo(p3.dx, p3.dy)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  void _drawOriginDot(Canvas canvas, Offset pos) {
    canvas.drawCircle(
        pos, 6, Paint()..color = Colors.white.withAlpha(230));
    canvas.drawCircle(
        pos, 6, Paint()..color = Colors.black..style = PaintingStyle.stroke..strokeWidth = 1.5);
    _drawText(canvas, 'O', pos, Colors.white, fontSize: 10, offset: const Offset(8, -8));
  }

  void _drawPOI(Canvas canvas, Offset pos, String label) {
    // Orange filled circle
    canvas.drawCircle(pos, 18, Paint()..color = const Color(0xFFFF6D00));
    // White border
    canvas.drawCircle(pos, 18,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
    // Label centred inside
    _drawTextCentered(canvas, label, pos, Colors.white, fontSize: 11, bold: true);
  }

  void _drawText(Canvas canvas, String text, Offset pos, Color color,
      {double fontSize = 12, bool bold = false, Offset offset = Offset.zero}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
            color: color,
            fontSize: fontSize,
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            shadows: const [Shadow(blurRadius: 3)]),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, pos + offset);
  }

  void _drawTextCentered(Canvas canvas, String text, Offset center, Color color,
      {double fontSize = 12, bool bold = false}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
            color: color,
            fontSize: fontSize,
            fontWeight: bold ? FontWeight.bold : FontWeight.normal),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(_AROverlayPainter old) => old.data != data;
}

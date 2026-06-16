import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/ar/models/anchor_blueprint.dart';
import '../../../core/ar/models/overlay_data.dart';

// AR heads-up display.
// Renders two layers:
//   1. A status chip at the top (anchor tracking state).
//   2. A CustomPaint fullscreen canvas with:
//        - World-coordinate gizmo: 3 coloured 1-metre axis arrows at the origin.
//        - A labelled circle for each POI at its projected screen position.
class AROverlay extends StatefulWidget {
  final String? activeAnchorId;
  final int detectedCount;
  final OverlayData? overlayData;
  final List<AnchorBlueprint> anchors;
  final bool isCalibrating;
  final bool isCorrectionFrozen;
  final String? referenceAnchorId;
  final String? editedAnchorId;
  final String? selectedPoiId;
  final Set<String> highlightedPoiIds;
  final double referenceImageOpacity;

  const AROverlay({
    super.key,
    required this.activeAnchorId,
    required this.detectedCount,
    this.overlayData,
    this.anchors = const [],
    this.isCalibrating = false,
    this.isCorrectionFrozen = false,
    this.referenceAnchorId,
    this.editedAnchorId,
    this.selectedPoiId,
    this.highlightedPoiIds = const {},
    this.referenceImageOpacity = 0.0,
  });

  @override
  State<AROverlay> createState() => _AROverlayState();
}

class _AROverlayState extends State<AROverlay> {
  final Map<String, ui.Image> _anchorImagesById = <String, ui.Image>{};
  int? _lastLoggedAnchorCount;
  double? _lastLoggedOpacity;

  @override
  void initState() {
    super.initState();
    _syncAnchorImages();
  }

  @override
  void didUpdateWidget(covariant AROverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.anchors != widget.anchors) {
      _syncAnchorImages();
    }

    final anchorCount = widget.overlayData?.anchors.length ?? 0;
    final opacity = widget.referenceImageOpacity;
    if (_lastLoggedAnchorCount != anchorCount ||
        _lastLoggedOpacity != opacity ||
        oldWidget.referenceAnchorId != widget.referenceAnchorId ||
        oldWidget.editedAnchorId != widget.editedAnchorId) {
      _lastLoggedAnchorCount = anchorCount;
      _lastLoggedOpacity = opacity;
      final firstAnchor = widget.overlayData != null && widget.overlayData!.anchors.isNotEmpty
          ? widget.overlayData!.anchors.first
          : null;
      debugPrint(
        '[CALIBRATION_OVERLAY] anchors=$anchorCount images=${_anchorImagesById.length} opacity=${opacity.toStringAsFixed(2)} reference=${widget.referenceAnchorId} edited=${widget.editedAnchorId} first=${firstAnchor == null ? 'none' : '${firstAnchor.id} tl=(${firstAnchor.tlx.toStringAsFixed(3)},${firstAnchor.tly.toStringAsFixed(3)}) br=(${firstAnchor.brx.toStringAsFixed(3)},${firstAnchor.bry.toStringAsFixed(3)})'}',
      );
    }
  }

  Future<void> _syncAnchorImages() async {
    final images = <String, ui.Image>{};
    for (final anchor in widget.anchors) {
      try {
        final data = await rootBundle.load(
          'assets/ar_anchors/${anchor.imageAssetName}.jpg',
        );
        final codec = await ui.instantiateImageCodec(
          data.buffer.asUint8List(),
        );
        final frame = await codec.getNextFrame();
        images[anchor.id] = frame.image;
        debugPrint(
          '[CALIBRATION_OVERLAY_IMAGE] loaded id=${anchor.id} asset=${anchor.imageAssetName}.jpg size=${frame.image.width}x${frame.image.height}',
        );
      } catch (error) {
        debugPrint(
          '[CALIBRATION_OVERLAY_IMAGE] failed id=${anchor.id} asset=${anchor.imageAssetName}.jpg error=$error',
        );
      }
    }
    if (mounted) {
      setState(() {
        _anchorImagesById
          ..clear()
          ..addAll(images);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // --- Fullscreen canvas (gizmo + POI dots) ---
        if (widget.overlayData != null)
          Positioned.fill(
            child: CustomPaint(
              painter: _AROverlayPainter(
                widget.overlayData!,
                anchorImagesById: _anchorImagesById,
                referenceImageOpacity: widget.referenceImageOpacity,
                isCalibrating: widget.isCalibrating,
                isCorrectionFrozen: widget.isCorrectionFrozen,
                referenceAnchorId: widget.referenceAnchorId,
                editedAnchorId: widget.editedAnchorId,
                selectedPoiId: widget.selectedPoiId,
                highlightedPoiIds: widget.highlightedPoiIds,
              ),
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
                  widget.activeAnchorId != null
                      ? 'Tracking: ${widget.activeAnchorId}  |  ${widget.detectedCount} anchors found'
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
  final Map<String, ui.Image> anchorImagesById;
  final double referenceImageOpacity;
  final bool isCalibrating;
  final bool isCorrectionFrozen;
  final String? referenceAnchorId;
  final String? editedAnchorId;
  final String? selectedPoiId;
  final Set<String> highlightedPoiIds;

  _AROverlayPainter(
    this.data, {
    this.anchorImagesById = const {},
    this.referenceImageOpacity = 0.0,
    this.isCalibrating = false,
    this.isCorrectionFrozen = false,
    this.referenceAnchorId,
    this.editedAnchorId,
    this.selectedPoiId,
    this.highlightedPoiIds = const {},
  });

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
      _drawOriginDot(
        canvas,
        origin,
        wallDistanceMeters: data.originWallDistanceMeters,
        showWallFeedback: isCalibrating,
      );
    }

    for (final anchor in data.anchors) {
      final corners = anchor.toCanvasOffsets(size);
      final anchorImage = anchorImagesById[anchor.id];
      if (anchorImage != null && referenceImageOpacity > 0.0) {
        _drawAnchorImage(
          canvas,
          corners,
          anchorImage,
          referenceImageOpacity,
        );
      }
      _drawAnchorQuad(
        canvas,
        corners,
        anchor: anchor,
        isEdited: anchor.id == editedAnchorId,
        isFrozenReference: isCorrectionFrozen && anchor.id == referenceAnchorId,
        showWallFeedback: isCalibrating,
      );
    }

    for (final poi in data.pois) {
      _drawPOI(
        canvas,
        poi.toCanvasOffset(size),
        poi.label,
        isSelected: poi.id == selectedPoiId || highlightedPoiIds.contains(poi.id),
        wallDistanceMeters: poi.wallDistanceMeters,
        showWallFeedback: isCalibrating,
      );
    }
  }

  void _drawAnchorImage(
    Canvas canvas,
    List<Offset> corners,
    ui.Image image,
    double opacity,
  ) {
    if (corners.length != 4) return;
    final vertices = ui.Vertices.raw(
      ui.VertexMode.triangles,
      Float32List.fromList([
        corners[0].dx,
        corners[0].dy,
        corners[1].dx,
        corners[1].dy,
        corners[2].dx,
        corners[2].dy,
        corners[0].dx,
        corners[0].dy,
        corners[2].dx,
        corners[2].dy,
        corners[3].dx,
        corners[3].dy,
      ]),
      textureCoordinates: Float32List.fromList([
        0,
        0,
        image.width.toDouble(),
        0,
        image.width.toDouble(),
        image.height.toDouble(),
        0,
        0,
        image.width.toDouble(),
        image.height.toDouble(),
        0,
        image.height.toDouble(),
      ]),
    );
    final paint = Paint()
      ..shader = ImageShader(
        image,
        TileMode.clamp,
        TileMode.clamp,
        Float64List.fromList(const <double>[
          1, 0, 0, 0,
          0, 1, 0, 0,
          0, 0, 1, 0,
          0, 0, 0, 1,
        ]),
      )
      ..color = Colors.white.withValues(alpha: opacity);
    canvas.drawVertices(vertices, BlendMode.modulate, paint);
  }

  void _drawAnchorQuad(
    Canvas canvas,
    List<Offset> corners, {
    required AnchorScreenQuad anchor,
    required bool isEdited,
    required bool isFrozenReference,
    required bool showWallFeedback,
  }) {
    if (corners.length != 4) return;
    final strokeWidth = isFrozenReference ? 2.8 : isEdited ? 2.2 : 1.3;
    final segments = <(Offset, Offset, double, double)>[
      (corners[0], corners[1], anchor.tlWallDistanceMeters, anchor.trWallDistanceMeters),
      (corners[1], corners[2], anchor.trWallDistanceMeters, anchor.brWallDistanceMeters),
      (corners[2], corners[3], anchor.brWallDistanceMeters, anchor.blWallDistanceMeters),
      (corners[3], corners[0], anchor.blWallDistanceMeters, anchor.tlWallDistanceMeters),
    ];
    for (final segment in segments) {
      _drawInterpolatedAnchorEdge(
        canvas,
        start: segment.$1,
        end: segment.$2,
        startDistance: segment.$3,
        endDistance: segment.$4,
        strokeWidth: strokeWidth,
        showWallFeedback: showWallFeedback,
      );
    }
  }

  void _drawInterpolatedAnchorEdge(
    Canvas canvas, {
    required Offset start,
    required Offset end,
    required double startDistance,
    required double endDistance,
    required double strokeWidth,
    required bool showWallFeedback,
  }) {
    if (!showWallFeedback) {
      canvas.drawLine(
        start,
        end,
        Paint()
          ..color = const Color(0xFF4FC3F7)
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = strokeWidth,
      );
      return;
    }

    final edge = end - start;
    final segmentCount = (edge.distance / 8.0).clamp(6.0, 48.0).round();
    for (var index = 0; index < segmentCount; index++) {
      final t0 = index / segmentCount;
      final t1 = (index + 1) / segmentCount;
      final p0 = Offset.lerp(start, end, t0)!;
      final p1 = Offset.lerp(start, end, t1)!;
      final midT = (t0 + t1) * 0.5;
      final interpolatedDistance =
          startDistance + ((endDistance - startDistance) * midT);
      canvas.drawLine(
        p0,
        p1,
        Paint()
          ..color = _wallDistanceColor(interpolatedDistance)
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = strokeWidth,
      );
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

  void _drawOriginDot(
    Canvas canvas,
    Offset pos, {
    required double wallDistanceMeters,
    required bool showWallFeedback,
  }) {
    final color = showWallFeedback
        ? _wallDistanceColor(wallDistanceMeters)
        : Colors.white;
    canvas.drawCircle(
        pos, 7, Paint()..color = color.withAlpha(230));
    canvas.drawCircle(
        pos, 6, Paint()..color = Colors.black..style = PaintingStyle.stroke..strokeWidth = 1.5);
    _drawText(canvas, 'O', pos, Colors.white, fontSize: 10, offset: const Offset(8, -8));
    if (showWallFeedback) {
      _drawText(
        canvas,
        '${(wallDistanceMeters * 100).toStringAsFixed(1)}cm',
        pos,
        color,
        fontSize: 10,
        offset: const Offset(12, 8),
      );
    }
  }

  void _drawPOI(
    Canvas canvas,
    Offset pos,
    String label, {
    required bool isSelected,
    required double wallDistanceMeters,
    required bool showWallFeedback,
  }) {
    final fillColor = showWallFeedback
        ? _wallDistanceColor(wallDistanceMeters)
        : isSelected
            ? const Color(0xFFD50000)
            : const Color(0xFFFF6D00);
    // Orange filled circle
    canvas.drawCircle(
      pos,
      18,
      Paint()..color = fillColor,
    );
    // White border
    canvas.drawCircle(pos, 18,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
    // Label centred inside
    _drawTextCentered(canvas, label, pos, Colors.white, fontSize: 11, bold: true);
    if (showWallFeedback) {
      _drawText(
        canvas,
        '${(wallDistanceMeters * 100).toStringAsFixed(1)}cm',
        pos,
        fillColor,
        fontSize: 10,
        offset: const Offset(22, -6),
      );
    }
  }

  Color _wallDistanceColor(double wallDistanceMeters) {
    const tolerance = 0.02;
    if (wallDistanceMeters.abs() <= tolerance) {
      return const Color(0xFF34C759);
    }
    return wallDistanceMeters < 0
        ? const Color(0xFFFF3B30)
        : const Color(0xFFFFCC00);
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
  bool shouldRepaint(_AROverlayPainter old) =>
      old.data != data ||
      old.referenceImageOpacity != referenceImageOpacity ||
      old.isCalibrating != isCalibrating ||
      old.isCorrectionFrozen != isCorrectionFrozen ||
      old.anchorImagesById.length != anchorImagesById.length ||
      old.referenceAnchorId != referenceAnchorId ||
      old.editedAnchorId != editedAnchorId ||
      old.selectedPoiId != selectedPoiId ||
      old.highlightedPoiIds.length != highlightedPoiIds.length ||
      !old.highlightedPoiIds.containsAll(highlightedPoiIds);
}

// lib/barcode_painter.dart

import 'dart:math' as math;
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A [CustomPainter] that draws the barcode as an outlined barcode box.
class BarcodePainter extends CustomPainter {
  /// Construct a new [BarcodePainter] instance.
  const BarcodePainter({
    required this.barcodeCorners,
    required this.barcodeSize,
    required this.boxFit,
    required this.cameraPreviewSize,
    required this.color,
    required this.style,
    required this.deviceOrientation,
    this.strokeWidth = 3.0,
  });

  /// The corners of the barcode.
  final List<Offset> barcodeCorners;

  /// The size of the barcode.
  final Size barcodeSize;

  /// The BoxFit mode for scaling the barcode bounding box.
  final BoxFit boxFit;

  /// The camera preview size.
  final Size cameraPreviewSize;

  /// The color of the outline.
  final Color color;

  /// The drawing style (stroke/fill).
  final PaintingStyle style;

  /// The width of the border.
  final double strokeWidth;

  /// The orientation of the device.
  final DeviceOrientation deviceOrientation;

  @override
  void paint(Canvas canvas, Size size) {
    if (barcodeCorners.length < 4 ||
        barcodeSize.isEmpty ||
        cameraPreviewSize.isEmpty) {
      return;
    }

    // Cihaz yönüne göre camera preview boyutunu ayarla
    final isLandscape =
        deviceOrientation == DeviceOrientation.landscapeLeft ||
            deviceOrientation == DeviceOrientation.landscapeRight;

    final adjustedCameraPreviewSize =
        isLandscape ? cameraPreviewSize.flipped : cameraPreviewSize;

    final ratios = calculateBoxFitRatio(
      boxFit,
      adjustedCameraPreviewSize,
      size,
    );

    final horizontalPadding =
        (adjustedCameraPreviewSize.width * ratios.widthRatio - size.width) / 2;
    final verticalPadding =
        (adjustedCameraPreviewSize.height * ratios.heightRatio - size.height) /
            2;

    final adjustedOffset = <Offset>[
      for (final offset in barcodeCorners)
        Offset(
          offset.dx * ratios.widthRatio - horizontalPadding,
          offset.dy * ratios.heightRatio - verticalPadding,
        ),
    ];

    if (adjustedOffset.length < 4) return;

    // Draw the rotated rectangle
    final path = Path()..addPolygon(adjustedOffset, true);

    final paint = Paint()
      ..color = color
      ..style = style
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawPath(path, paint);

    // Köşelere küçük işaretler ekle
    _drawCornerMarkers(canvas, adjustedOffset, paint);
  }

  void _drawCornerMarkers(Canvas canvas, List<Offset> corners, Paint paint) {
    final markerPaint = Paint()
      ..color = paint.color
      ..style = PaintingStyle.fill;

    const double markerRadius = 3.0;

    for (final corner in corners) {
      canvas.drawCircle(corner, markerRadius, markerPaint);
    }
  }

  @override
  bool shouldRepaint(BarcodePainter oldDelegate) {
    const listEquality = ListEquality<Offset>();

    return !listEquality.equals(oldDelegate.barcodeCorners, barcodeCorners) ||
        oldDelegate.barcodeSize != barcodeSize ||
        oldDelegate.boxFit != boxFit ||
        oldDelegate.cameraPreviewSize != cameraPreviewSize ||
        oldDelegate.color != color ||
        oldDelegate.style != style ||
        oldDelegate.deviceOrientation != deviceOrientation;
  }
}

/// Calculate the scaling ratios for width and height to fit the small box
/// (cameraPreviewSize) into the large box (size) based on the specified BoxFit
/// mode. Returns a record containing the width and height scaling ratios.
({double widthRatio, double heightRatio}) calculateBoxFitRatio(
  BoxFit boxFit,
  Size cameraPreviewSize,
  Size size,
) {
  // If the width or height of cameraPreviewSize or size is 0, return (1.0, 1.0)
  if (cameraPreviewSize.width <= 0 ||
      cameraPreviewSize.height <= 0 ||
      size.width <= 0 ||
      size.height <= 0) {
    return (widthRatio: 1.0, heightRatio: 1.0);
  }

  // Calculate the scaling ratios for width and height
  final double widthRatio = size.width / cameraPreviewSize.width;
  final double heightRatio = size.height / cameraPreviewSize.height;

  switch (boxFit) {
    case BoxFit.fill:
      return (widthRatio: widthRatio, heightRatio: heightRatio);

    case BoxFit.contain:
      final double ratio = math.min(widthRatio, heightRatio);
      return (widthRatio: ratio, heightRatio: ratio);

    case BoxFit.cover:
      final double ratio = math.max(widthRatio, heightRatio);
      return (widthRatio: ratio, heightRatio: ratio);

    case BoxFit.fitWidth:
      return (widthRatio: widthRatio, heightRatio: widthRatio);

    case BoxFit.fitHeight:
      return (widthRatio: heightRatio, heightRatio: heightRatio);

    case BoxFit.none:
      return (widthRatio: 1.0, heightRatio: 1.0);

    case BoxFit.scaleDown:
      final double ratio =
          math.min(1, math.min(widthRatio, heightRatio)).toDouble();
      return (widthRatio: ratio, heightRatio: ratio);
  }
}

import 'package:flutter/material.dart';

class DetectionPainter extends CustomPainter {
  final List<Map<String, dynamic>> detections;
  final Size imageSize;
  final Size canvasSize;

  DetectionPainter(this.detections, this.imageSize, this.canvasSize);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final double scaleX = canvasSize.width / imageSize.width;
    final double scaleY = canvasSize.height / imageSize.height;
    final double scale = scaleX < scaleY ? scaleX : scaleY;

    final double offsetX = (canvasSize.width - imageSize.width * scale) / 2;
    final double offsetY = (canvasSize.height - imageSize.height * scale) / 2;

    print('Số lượng detections: ${detections.length}');
    for (var i = 0; i < detections.length; i++) {
      final detection = detections[i];
      print('Detection $i: $detection');

      // Kiểm tra tính hợp lệ của detection
      if (!detection.containsKey('class') ||
          !detection.containsKey('confidence') ||
          !detection.containsKey('box')) {
        print('Bỏ qua detection không đầy đủ: $detection');
        continue;
      }

      final box = detection['box'] as List<dynamic>?;
      if (box == null || box.length < 4) {
        print('Bỏ qua hộp không hợp lệ (box null hoặc thiếu): $box');
        continue;
      }

      final double x = (box[0] as num?)?.toDouble() ?? 0.0;
      final double y = (box[1] as num?)?.toDouble() ?? 0.0;
      final double width = (box[2] as num?)?.toDouble() ?? 0.0;
      final double height = (box[3] as num?)?.toDouble() ?? 0.0;

      if (width <= 0 ||
          height <= 0 ||
          x.isNaN ||
          y.isNaN ||
          width.isNaN ||
          height.isNaN) {
        print('Bỏ qua hộp không hợp lệ (kích thước hoặc tọa độ lỗi): $box');
        continue;
      }

      final rect = Rect.fromLTWH(
        offsetX + x * scale,
        offsetY + y * scale,
        width * scale,
        height * scale,
      );

      print(
          'Vẽ hộp: x=${rect.left}, y=${rect.top}, w=${rect.width}, h=${rect.height}');
      canvas.drawRect(rect, paint);

      final className = detection['class']?.toString() ?? 'Không xác định';
      final confidence = (detection['confidence'] as num?)?.toDouble() ?? 0.0;
      final text = '$className ${(confidence * 100).toStringAsFixed(1)}%';

      final textPainter = TextPainter(
        text: TextSpan(
          text: text,
          style: const TextStyle(color: Colors.red, fontSize: 14),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(
          canvas, Offset(offsetX + x * scale, offsetY + y * scale - 20));
    }
  }

  @override
  bool shouldRepaint(covariant DetectionPainter oldDelegate) {
    return detections != oldDelegate.detections ||
        imageSize != oldDelegate.imageSize ||
        canvasSize != oldDelegate.canvasSize;
  }
}

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

Future<File> createImageWithBoxes(
    File originalImage, List<Map<String, dynamic>> detections) async {
  final bytes = await originalImage.readAsBytes();
  final image = img.decodeImage(bytes);
  if (image == null) {
    throw Exception('Không thể giải mã ảnh: ${originalImage.path}');
  }
  print('Kích thước ảnh gốc: ${image.width}x${image.height}');

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()));

  // Vẽ ảnh gốc
  final uiImage = await _toUiImage(image);
  canvas.drawImage(uiImage, Offset.zero, Paint());

  // Vẽ bounding box
  final paint = Paint()
    ..color = Colors.green
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.0;

  final textStyle = TextStyle(
    color: Colors.green,
    fontSize: 14,
    backgroundColor: Colors.black.withOpacity(0.5),
  );

  for (var detection in detections) {
    final box = detection['box'] as List<dynamic>;
    final x = (box[0] as num).toDouble();
    final y = (box[1] as num).toDouble();
    final w = (box[2] as num).toDouble();
    final h = (box[3] as num).toDouble();
    print('Vẽ box: x=$x, y=$y, w=$w, h=$h');

    canvas.drawRect(Rect.fromLTWH(x, y, w, h), paint);

    final className = detection['class'] as String;
    final confidence = (detection['confidence'] as double) * 100;
    final text = '$className ${confidence.toStringAsFixed(1)}%';
    final textSpan = TextSpan(text: text, style: textStyle);
    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(x, y - 20));
  }

  final picture = recorder.endRecording();
  final uiImg = await picture.toImage(image.width, image.height);
  final byteData = await uiImg.toByteData(format: ui.ImageByteFormat.png);
  final buffer = byteData!.buffer.asUint8List();

  final outputPath = originalImage.path.replaceAll('.jpg', '_boxed.png');
  print('Lưu ảnh với box tại: $outputPath');
  return await File(outputPath).writeAsBytes(buffer);
}

Future<ui.Image> _toUiImage(img.Image image) async {
  final byteData = img.encodePng(image);
  final completer = Completer<ui.Image>();
  ui.decodeImageFromList(byteData, completer.complete);
  return completer.future;
}

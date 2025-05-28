import 'dart:convert';
import 'dart:io';

import 'package:animate_do/animate_do.dart';
import 'package:flutter/material.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../config.dart';
import '../utils/image_utils.dart';

class DetectionDetailScreen extends StatefulWidget {
  final String imageUrl;
  final List<Map<String, dynamic>> detections;
  final Map<String, double>? imageSize;
  final DateTime timestamp;

  const DetectionDetailScreen({
    super.key,
    required this.imageUrl,
    required this.detections,
    required this.imageSize,
    required this.timestamp,
  });

  @override
  _DetectionDetailScreenState createState() => _DetectionDetailScreenState();
}

class _DetectionDetailScreenState extends State<DetectionDetailScreen> {
  List<Map<String, dynamic>> _insectData = [];
  Map<int, Map<String, dynamic>> _classIdMap = {};
  Map<String, double>? _imageSize;

  @override
  void initState() {
    super.initState();
    _imageSize = widget.imageSize;
    _loadInsectData();
    if (_imageSize == null ||
        _imageSize!['width'] == 0.0 ||
        _imageSize!['height'] == 0.0) {
      _fetchImageSize();
    }
  }

  Future<void> _loadInsectData() async {
    try {
      final String response = await DefaultAssetBundle.of(context)
          .loadString('assets/insects.json');
      setState(() {
        _insectData = List<Map<String, dynamic>>.from(jsonDecode(response));
        _classIdMap = {
          for (var insect in _insectData) insect['class_id']: insect
        };
        print('Loaded insect data: $_insectData');
        print('Class ID map: $_classIdMap');
      });
    } catch (e) {
      print('Lỗi khi đọc insects.json: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lỗi khi đọc dữ liệu côn trùng')),
        );
      }
    }
  }

  Future<void> _fetchImageSize() async {
    try {
      print('Gửi yêu cầu get_image_size với image_url: ${widget.imageUrl}');
      final response = await http.get(
          Uri.parse('$apiBaseUrl/get_image_size?image_url=${widget.imageUrl}'));
      print(
          'Phản hồi từ get_image_size: ${response.statusCode} - ${response.body}');
      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(response.body);
        setState(() {
          _imageSize = {
            'width': (jsonResponse['image_size']['width'] as num).toDouble(),
            'height': (jsonResponse['image_size']['height'] as num).toDouble(),
          };
        });
        print('Cập nhật _imageSize: $_imageSize');
      } else {
        print('Lỗi lấy kích thước ảnh: ${response.body}');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Lỗi lấy kích thước ảnh: ${response.body}')),
          );
        }
      }
    } catch (e) {
      print('Lỗi khi lấy kích thước ảnh: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi khi lấy kích thước ảnh: $e')),
        );
      }
    }
  }

  Map<String, dynamic> _getInsectDetails(Map<String, dynamic> detection) {
    try {
      final classId = detection['class_id'] as int?;
      if (classId != null && _classIdMap.containsKey(classId)) {
        print('Khớp class_id: $classId, chi tiết: ${_classIdMap[classId]}');
        return _classIdMap[classId]!;
      }

      final className = detection['class']?.toString() ?? '';
      final insect = _insectData.firstWhere(
        (insect) =>
            insect['class'].toString().toLowerCase().trim() ==
                className.toLowerCase().trim() ||
            insect['scientific_name'].toString().toLowerCase().trim() ==
                className.toLowerCase().trim(),
        orElse: () => {},
      );
      if (insect.isNotEmpty) {
        print('Khớp tên lớp: $className, chi tiết: $insect');
        return insect;
      }

      print('Không tìm thấy chi tiết cho detection: $detection');
      return {};
    } catch (e) {
      print('Lỗi khi tìm thông tin côn trùng: $detection, lỗi: $e');
      return {};
    }
  }

  String _getObjectSummary() {
    if (widget.detections.isEmpty) return '';
    final classCounts = <String, int>{};
    for (var detection in widget.detections) {
      final className = detection['class'] as String? ?? 'Không xác định';
      classCounts[className] = (classCounts[className] ?? 0) + 1;
    }
    return classCounts.entries.map((e) => '${e.key}: ${e.value}').join(', ');
  }

  Future<File> _downloadImage(String url) async {
    final response = await http.get(Uri.parse(url));
    if (response.statusCode == 200) {
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/${url.split('/').last}');
      await file.writeAsBytes(response.bodyBytes);
      return file;
    } else {
      throw Exception('Lỗi tải ảnh: ${response.statusCode}');
    }
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    bool gradient = false,
  }) {
    return FadeIn(
      child: Column(
        children: [
          Material(
            elevation: 4,
            shape: const CircleBorder(),
            child: InkWell(
              borderRadius: BorderRadius.circular(28),
              onTap: onPressed,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: gradient
                      ? const LinearGradient(
                          colors: [Colors.blue, Colors.blueAccent],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : null,
                  color: gradient ? null : Colors.white,
                ),
                child: Icon(
                  icon,
                  size: 28,
                  color: gradient ? Colors.white : Colors.grey[600],
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 12,
              color: Theme.of(context).textTheme.bodyLarge!.color,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    print('DetectionDetailScreen - Detections: ${widget.detections}');
    print('DetectionDetailScreen - ImageSize: $_imageSize');
    print('DetectionDetailScreen - ImageUrl: ${widget.imageUrl}');
    print('Detections trước CustomPaint: ${widget.detections.map((d) => {
          'class': d['class'],
          'confidence': d['confidence'],
          'box': d['box']
        }).toList()}');

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'CHI TIẾT PHÁT HIỆN',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.white
                : Colors.black87,
          ),
        ),
        centerTitle: true,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.blue, Colors.blueAccent],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
      ),
      body: _imageSize == null ||
              _imageSize!['width'] == 0.0 ||
              _imageSize!['height'] == 0.0
          ? const Center(child: SpinKitFadingCircle(color: Colors.blue))
          : SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Card(
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final aspectRatio =
                              _imageSize!['width']! / _imageSize!['height']!;
                          final displayWidth = constraints.maxWidth;
                          final displayHeight = displayWidth / aspectRatio;

                          return ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: InteractiveViewer(
                              minScale: 0.5,
                              maxScale: 4.0,
                              child: Container(
                                width: displayWidth,
                                height: displayHeight,
                                child: Stack(
                                  alignment: Alignment.center,
                                  children: [
                                    Image.network(
                                      widget.imageUrl,
                                      fit: BoxFit.fill,
                                      width: displayWidth,
                                      height: displayHeight,
                                      alignment: Alignment.center,
                                      loadingBuilder:
                                          (context, child, loadingProgress) {
                                        if (loadingProgress == null)
                                          return child;
                                        return const SizedBox(
                                          height: 300,
                                          child: Center(
                                              child:
                                                  CircularProgressIndicator()),
                                        );
                                      },
                                      errorBuilder:
                                          (context, error, stackTrace) {
                                        print(
                                            'Lỗi tải ảnh chi tiết: ${widget.imageUrl}, lỗi: $error');
                                        return const SizedBox(
                                          height: 300,
                                          child: Center(
                                            child: Icon(
                                              Icons.broken_image,
                                              size: 100,
                                              color: Colors.grey,
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                    // Positioned.fill(
                                    //   child: CustomPaint(
                                    //     key: ValueKey(widget.imageUrl),
                                    //     painter: DetectionPainter(
                                    //       widget.detections,
                                    //       Size(_imageSize!['width']!,
                                    //           _imageSize!['height']!),
                                    //       Size(displayWidth, displayHeight),
                                    //     ),
                                    //   ),
                                    // ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Thời gian: ${widget.timestamp.toLocal().toString().substring(0, 16)}',
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).textTheme.bodyLarge!.color,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Card(
                      elevation: 4,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Số lượng đối tượng: ${widget.detections.length}',
                              style: GoogleFonts.poppins(
                                fontSize: 16,
                                color: Theme.of(context)
                                    .textTheme
                                    .bodyLarge!
                                    .color,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            Text(
                              'Độ chính xác trung bình: ${(widget.detections.isEmpty ? 0 : widget.detections.map((d) => d['confidence'] as double).reduce((a, b) => a + b) / widget.detections.length * 100).toStringAsFixed(1)}%',
                              style: GoogleFonts.poppins(
                                fontSize: 16,
                                color: Theme.of(context)
                                    .textTheme
                                    .bodyLarge!
                                    .color,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            Text(
                              'Đối tượng: ${_getObjectSummary()}',
                              style: GoogleFonts.poppins(
                                fontSize: 16,
                                color: Theme.of(context)
                                    .textTheme
                                    .bodyLarge!
                                    .color,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            // Nút chia sẻ được đặt ở giữa Card
                            Center(
                              child: _buildActionButton(
                                icon: Icons.share,
                                label: 'Chia sẻ kết quả',
                                onPressed: () async {
                                  try {
                                    final imageFile =
                                        await _downloadImage(widget.imageUrl);
                                    final boxedImage =
                                        await createImageWithBoxes(
                                            imageFile, widget.detections);
                                    final text = 'Phát hiện côn trùng:\n'
                                        'Số lượng: ${widget.detections.length}\n'
                                        'Đối tượng: ${_getObjectSummary()}\n'
                                        'Độ chính xác trung bình: ${(widget.detections.isEmpty ? 0 : widget.detections.map((d) => d['confidence'] as double).reduce((a, b) => a + b) / widget.detections.length * 100).toStringAsFixed(1)}%';
                                    await Share.shareXFiles(
                                        [XFile(boxedImage.path)],
                                        text: text);
                                  } catch (e) {
                                    if (mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                            content: Text('Lỗi chia sẻ: $e')),
                                      );
                                    }
                                  }
                                },
                                gradient: true,
                              ),
                            ),
                            const SizedBox(height: 16),
                            if (widget.detections.isNotEmpty)
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: widget.detections.map((detection) {
                                  final insectDetails =
                                      _getInsectDetails(detection);
                                  return FadeIn(
                                    child: ExpansionTile(
                                      title: Text(
                                        insectDetails['vietnamese_name']
                                                ?.toString() ??
                                            detection['class']?.toString() ??
                                            'Không xác định',
                                        style: GoogleFonts.poppins(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: Theme.of(context)
                                              .textTheme
                                              .bodyLarge!
                                              .color,
                                        ),
                                      ),
                                      children: [
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 16.0, vertical: 8.0),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Tên khoa học: ${insectDetails['scientific_name']?.toString() ?? 'Không có thông tin'}',
                                                style: GoogleFonts.poppins(
                                                  fontSize: 14,
                                                  color: Theme.of(context)
                                                      .textTheme
                                                      .bodyLarge!
                                                      .color,
                                                ),
                                              ),
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                    top: 8.0),
                                                child: Text(
                                                  'Mô tả: ${insectDetails['description']?.toString() ?? 'Không có thông tin'}',
                                                  style: GoogleFonts.poppins(
                                                    fontSize: 14,
                                                    color: Theme.of(context)
                                                        .textTheme
                                                        .bodyLarge!
                                                        .color,
                                                  ),
                                                ),
                                              ),
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                    top: 8.0),
                                                child: Text(
                                                  'Mức độ nguy hiểm: ${insectDetails['danger_level']?.toString() ?? 'Không có thông tin'}',
                                                  style: GoogleFonts.poppins(
                                                    fontSize: 14,
                                                    color: Theme.of(context)
                                                        .textTheme
                                                        .bodyLarge!
                                                        .color,
                                                  ),
                                                ),
                                              ),
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                    top: 8.0),
                                                child: Text(
                                                  'Cách xử lý: ${insectDetails['handling']?.toString() ?? 'Không có thông tin'}',
                                                  style: GoogleFonts.poppins(
                                                    fontSize: 14,
                                                    color: Theme.of(context)
                                                        .textTheme
                                                        .bodyLarge!
                                                        .color,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                }).toList(),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

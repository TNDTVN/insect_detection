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
  bool _isPickingImage = false;

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
      final String data = await DefaultAssetBundle.of(context)
          .loadString('assets/insects.json');
      setState(() {
        _insectData = List<Map<String, dynamic>>.from(jsonDecode(data));
        _classIdMap = {
          for (var insect in _insectData) insect['class_id']: insect
        };
      });
    } catch (e) {
      print('Error loading insects.json: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lỗi tải dữ liệu côn trùng')),
        );
      }
    }
  }

  Future<void> _fetchImageSize() async {
    try {
      final response = await http.get(
        Uri.parse('$apiBaseUrl/get_image_size?image_url=${widget.imageUrl}'),
      );
      if (response.statusCode == 200) {
        final jsonResponse = jsonDecode(response.body);
        setState(() {
          _imageSize = {
            'width': (jsonResponse['image_size']['width'] as num).toDouble(),
            'height': (jsonResponse['image_size']['height'] as num).toDouble(),
          };
        });
      } else {
        print('Error fetching image size: ${response.body}');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('Lỗi khi lấy kích thước ảnh: ${response.body}')),
          );
        }
      }
    } catch (e) {
      print('Error fetching image size: $e');
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
      return insect.isNotEmpty ? insect : {};
    } catch (e) {
      print('Error finding insect details: $detection, error: $e');
      return {};
    }
  }

  String _getObjectSummary() {
    if (widget.detections.isEmpty) return 'Không có đối tượng';
    final classCounts = <String, int>{};
    for (var detection in widget.detections) {
      final className = detection['class'] as String? ?? 'Không xác định';
      classCounts[className] = (classCounts[className] ?? 0) + 1;
    }
    return classCounts.entries.map((e) => '${e.key}: ${e.value}').join('\n');
  }

  Future<File> _downloadImage(String url) async {
    final response = await http.get(Uri.parse(url));
    if (response.statusCode == 200) {
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/${url.split('/').last}');
      await file.writeAsBytes(response.bodyBytes);
      return file;
    } else {
      throw Exception('Error downloading image: ${response.statusCode}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final cardTextColor = isDarkMode ? Colors.grey[200] : Colors.black87;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Chi tiết nhận diện',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            color: isDarkMode ? Colors.white : Colors.black87,
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
          : SafeArea(
              child: SingleChildScrollView(
                child: FadeIn(
                  child: Column(
                    children: [
                      Card(
                        elevation: 4,
                        color: isDarkMode ? Colors.grey[850] : Colors.grey[100],
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
                                  child: Image.network(
                                    widget.imageUrl,
                                    fit: BoxFit.contain,
                                    width: displayWidth,
                                    height: displayHeight,
                                    alignment: Alignment.center,
                                    loadingBuilder:
                                        (context, child, loadingProgress) {
                                      if (loadingProgress == null) return child;
                                      return const SizedBox(
                                        height: 200,
                                        child: Center(
                                            child: CircularProgressIndicator()),
                                      );
                                    },
                                    errorBuilder: (context, error, stackTrace) {
                                      print(
                                          'Error loading detail image: ${widget.imageUrl}, error: $error');
                                      return const SizedBox(
                                        height: 200,
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
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16.0, vertical: 8.0),
                        child: Text(
                          'Thời gian: ${widget.timestamp.toLocal().toString().substring(0, 16)}',
                          style: GoogleFonts.poppins(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: cardTextColor,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          children: [
                            GridView.count(
                              crossAxisCount: 2,
                              crossAxisSpacing: 10,
                              mainAxisSpacing: 10,
                              childAspectRatio: 4 / 3,
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              children: [
                                Card(
                                  elevation: 4,
                                  color: isDarkMode
                                      ? Colors.blueGrey[800]
                                      : Colors.blue[200],
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(12.0),
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          'Số lượng',
                                          style: GoogleFonts.poppins(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                            color: cardTextColor,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          widget.detections.length.toString(),
                                          style: GoogleFonts.poppins(
                                            fontSize: 14,
                                            color: cardTextColor,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                Card(
                                  elevation: 4,
                                  color: isDarkMode
                                      ? Colors.deepOrange[900]
                                      : Colors.orange[200],
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(12.0),
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          'Độ chính xác',
                                          style: GoogleFonts.poppins(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                            color: cardTextColor,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          '${(widget.detections.isEmpty ? 0 : widget.detections.map((d) => d['confidence'] as double).reduce((a, b) => a + b) / widget.detections.length * 100).toStringAsFixed(1)}%',
                                          style: GoogleFonts.poppins(
                                            fontSize: 14,
                                            color: cardTextColor,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Card(
                              elevation: 4,
                              color: isDarkMode
                                  ? Colors.grey[850]
                                  : Colors.grey[100],
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(12.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Đối tượng',
                                      style: GoogleFonts.poppins(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: cardTextColor,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      _getObjectSummary(),
                                      style: GoogleFonts.poppins(
                                        fontSize: 14,
                                        color: cardTextColor,
                                      ),
                                      maxLines: 10,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Card(
                              elevation: 4,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: InkWell(
                                onTap: () async {
                                  try {
                                    final imageFile =
                                        await _downloadImage(widget.imageUrl);
                                    final boxedImage =
                                        await createImageWithBoxes(
                                            imageFile, widget.detections);
                                    final text = 'Nhận diện côn trùng:\n'
                                        'Số lượng: ${widget.detections.length}\n'
                                        'Đối tượng:\n${_getObjectSummary()}\n'
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
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(12),
                                    gradient: const LinearGradient(
                                      colors: [Colors.blue, Colors.blueAccent],
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 16.0),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(
                                        Icons.share,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Chia sẻ',
                                        style: GoogleFonts.poppins(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (widget.detections.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16.0, vertical: 8.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: widget.detections.map((detection) {
                              final insectDetails =
                                  _getInsectDetails(detection);
                              return FadeIn(
                                child: Card(
                                  elevation: 4,
                                  color: isDarkMode
                                      ? Colors.grey[850]
                                      : Colors.grey[100],
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  margin:
                                      const EdgeInsets.symmetric(vertical: 4.0),
                                  child: ExpansionTile(
                                    title: Text(
                                      insectDetails['vietnamese_name']
                                              ?.toString() ??
                                          detection['class']?.toString() ??
                                          'Không xác định',
                                      style: GoogleFonts.poppins(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w600,
                                        color: cardTextColor,
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
                                                fontSize: 16,
                                                color: cardTextColor,
                                              ),
                                            ),
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                  top: 8.0),
                                              child: Text(
                                                'Mô tả: ${insectDetails['description']?.toString() ?? 'Không có thông tin'}',
                                                style: GoogleFonts.poppins(
                                                  fontSize: 16,
                                                  color: cardTextColor,
                                                ),
                                              ),
                                            ),
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                  top: 8.0),
                                              child: Text(
                                                'Mức độ nguy hiểm: ${insectDetails['danger_level']?.toString() ?? 'Không có thông tin'}',
                                                style: GoogleFonts.poppins(
                                                  fontSize: 16,
                                                  color: cardTextColor,
                                                ),
                                              ),
                                            ),
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                  top: 8.0),
                                              child: Text(
                                                'Cách xử lý: ${insectDetails['handling']?.toString() ?? 'Không có thông tin'}',
                                                style: GoogleFonts.poppins(
                                                  fontSize: 16,
                                                  color: cardTextColor,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

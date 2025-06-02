import 'dart:io';

import 'package:animate_do/animate_do.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';

import '../utils/image_utils.dart';
import '../widgets/full_screen_camera.dart';

class DetectionResultScreen extends StatefulWidget {
  final File image;
  final List<Map<String, dynamic>> detections;
  final Size imageSize;
  final int userId;
  final List<Map<String, dynamic>> insectData;
  final List<CameraDescription> cameras;
  final Function(File) onCaptureNew;
  final VoidCallback onPickImage;
  final VoidCallback onRefresh;

  const DetectionResultScreen({
    super.key,
    required this.image,
    required this.detections,
    required this.imageSize,
    required this.userId,
    required this.insectData,
    required this.cameras,
    required this.onCaptureNew,
    required this.onPickImage,
    required this.onRefresh,
  });

  @override
  _DetectionResultScreenState createState() => _DetectionResultScreenState();
}

class _DetectionResultScreenState extends State<DetectionResultScreen> {
  CameraController? _controller;
  bool _isFlashOn = false;
  bool _isCameraReady = false;
  bool _isCapturing = false;
  bool _showCamera = false;
  bool _isPickingImage = false;

  @override
  void initState() {
    super.initState();
  }

  Future<void> _initializeCamera() async {
    if (widget.cameras.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Không tìm thấy camera')),
        );
      }
      return;
    }
    await _closeCamera();
    _controller = CameraController(
      widget.cameras[0],
      ResolutionPreset.medium,
      enableAudio: false,
    );
    try {
      print('Initializing camera in DetectionResultScreen');
      await _controller!.initialize();
      if (!mounted) return;
      setState(() {
        _isCameraReady = true;
        _showCamera = true;
      });
    } catch (e) {
      print('Error initializing camera: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi khi khởi tạo camera: $e')),
        );
      }
      if (mounted) {
        setState(() {
          _isCameraReady = false;
          _showCamera = false;
        });
      }
    }
  }

  Future<void> _closeCamera() async {
    if (_controller != null && _controller!.value.isInitialized) {
      try {
        print('Disposing camera in DetectionResultScreen');
        await _controller!.dispose();
        _controller = null;
      } catch (e) {
        print('Error disposing camera: $e');
      }
    }
    if (mounted) {
      setState(() {
        _isCameraReady = false;
        _showCamera = false;
        _isFlashOn = false;
      });
    }
  }

  Future<void> _toggleFlash() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    setState(() {
      _isFlashOn = !_isFlashOn;
    });
    try {
      await _controller!.setFlashMode(
        _isFlashOn ? FlashMode.torch : FlashMode.off,
      );
    } catch (e) {
      print('Error toggling flash: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi khi bật/tắt flash: $e')),
        );
      }
    }
  }

  Future<void> _pickImageWithLoading() async {
    if (_isPickingImage) return;
    setState(() {
      _isPickingImage = true;
    });
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: SpinKitFadingCircle(color: Colors.blue, size: 60.0),
      ),
    );
    try {
      widget.onPickImage();
    } finally {
      if (mounted) {
        setState(() {
          _isPickingImage = false;
        });
        Navigator.of(context).pop();
      }
    }
  }

  Future<File?> _captureImage() async {
    if (_controller == null || !_controller!.value.isInitialized) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Camera chưa sẵn sàng')),
        );
      }
      return null;
    }
    try {
      print('Capturing image in DetectionResultScreen');
      final image = await _controller!.takePicture();
      final fixedImage = await fixImageOrientation(File(image.path));
      return fixedImage;
    } catch (e) {
      print('Error capturing image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi khi chụp ảnh: $e')),
        );
      }
      return null;
    }
  }

  Map<String, dynamic> getInsectDetails(Map<String, dynamic> detection) {
    try {
      final classId = detection['class_id'] as int?;
      final classIdMap = {
        for (var insect in widget.insectData) insect['class_id']: insect
      };
      if (classId != null && classIdMap.containsKey(classId)) {
        return classIdMap[classId]!;
      }

      final className = detection['class'].toString();
      final insect = widget.insectData.firstWhere(
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

  Widget _buildActionButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    Color? color,
    bool gradient = false,
  }) {
    return FadeIn(
      child: Column(
        mainAxisSize: MainAxisSize.min,
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
                  size: 24,
                  color: gradient ? Colors.white : (color ?? Colors.black87),
                ),
              ),
            ),
          ),
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 12,
              color: Theme.of(context).textTheme.bodyLarge?.color ??
                  Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _closeCamera();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    print(
        'Building DetectionResultScreen: _showCamera=$_showCamera, _isCameraReady=$_isCameraReady, _controller=$_controller');
    if (_showCamera && _isCameraReady && _controller != null) {
      return FullScreenCamera(
        controller: _controller!,
        isFlashOn: _isFlashOn,
        isCapturing: _isCapturing,
        onCapture: () async {
          setState(() {
            _isCapturing = true;
          });
          try {
            final image = await _captureImage();
            if (image != null && mounted) {
              widget.onCaptureNew(image);
              await _closeCamera();
            }
          } finally {
            if (mounted) {
              setState(() {
                _isCapturing = false;
              });
            }
          }
        },
        onToggleFlash: _toggleFlash,
        onClose: () async {
          await _closeCamera();
          if (mounted) {
            setState(() {
              _showCamera = false;
            });
          }
        },
      );
    }

    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final cardTextColor = isDarkMode ? Colors.grey[200] : Colors.black87;

    return WillPopScope(
      onWillPop: () async {
        await _closeCamera();
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            'Kết quả nhận diện',
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w600,
              color: isDarkMode ? Colors.white : Colors.black87,
            ),
          ),
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () async {
              await _closeCamera();
              Navigator.pop(context);
            },
          ),
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
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: FadeIn(
                    child: Column(
                      children: [
                        if (widget.imageSize.width > 0 &&
                            widget.imageSize.height > 0)
                          Card(
                            elevation: 4,
                            color: isDarkMode
                                ? Colors.grey[850]
                                : Colors.grey[100],
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                final aspectRatio = widget.imageSize.width /
                                    widget.imageSize.height;
                                final displayWidth = constraints.maxWidth;
                                final displayHeight =
                                    displayWidth / aspectRatio;

                                return ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: InteractiveViewer(
                                    minScale: 0.5,
                                    maxScale: 4.0,
                                    child: Container(
                                      width: displayWidth,
                                      height: displayHeight,
                                      child: Image.file(
                                        widget.image,
                                        fit: BoxFit.contain,
                                        width: displayWidth,
                                        height: displayHeight,
                                        alignment: Alignment.center,
                                        errorBuilder:
                                            (context, error, stackTrace) {
                                          print(
                                              'Error displaying image: $error');
                                          return const Icon(Icons.broken_image,
                                              size: 100);
                                        },
                                      ),
                                    ),
                                  ),
                                );
                              },
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
                                      final boxedImage =
                                          await createImageWithBoxes(
                                              widget.image, widget.detections);
                                      final text = 'Nhận diện côn trùng:\n'
                                          'Số lượng: ${widget.detections.length}\n'
                                          'Đối tượng:\n${_getObjectSummary()}\n'
                                          'Độ chính xác trung bình: ${(widget.detections.isEmpty ? 0 : widget.detections.map((d) => d['confidence'] as double).reduce((a, b) => a + b) / widget.detections.length * 100).toStringAsFixed(1)}%';
                                      await Share.shareXFiles(
                                          [XFile(boxedImage.path)],
                                          text: text);
                                    } catch (e) {
                                      if (!mounted) return;
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                            content: Text('Lỗi chia sẻ: $e')),
                                      );
                                    }
                                  },
                                  borderRadius: BorderRadius.circular(12),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(12),
                                      gradient: const LinearGradient(
                                        colors: [
                                          Colors.blue,
                                          Colors.blueAccent
                                        ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 16.0),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
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
                                    getInsectDetails(detection);
                                return FadeIn(
                                  child: Card(
                                    elevation: 4,
                                    color: isDarkMode
                                        ? Colors.grey[850]
                                        : Colors.grey[100],
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    margin: const EdgeInsets.symmetric(
                                        vertical: 4.0),
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
              Padding(
                padding: const EdgeInsets.fromLTRB(8.0, 8.0, 8.0, 24.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildActionButton(
                      context,
                      icon: Icons.camera_alt,
                      label: 'Chụp ảnh mới',
                      onPressed: () async {
                        setState(() {
                          _isCapturing = true;
                        });
                        try {
                          await _initializeCamera();
                        } finally {
                          if (mounted) {
                            setState(() {
                              _isCapturing = false;
                            });
                          }
                        }
                      },
                      gradient: true,
                    ),
                    _buildActionButton(
                      context,
                      icon: Icons.photo_library,
                      label: 'Chọn ảnh',
                      onPressed: _pickImageWithLoading,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

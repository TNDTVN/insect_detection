import 'dart:async';
import 'dart:convert';

import 'package:animate_do/animate_do.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;

import '../config.dart';
import '../database/detection_history.dart';
import 'detection_detail_screen.dart';

class HistoryScreen extends StatefulWidget {
  final int userId;
  const HistoryScreen({super.key, required this.userId});

  @override
  _HistoryScreenState createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<Map<String, dynamic>> _histories = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHistories();
  }

  Future<void> _loadHistories() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final history = DetectionHistory();
      List<Map<String, dynamic>> localHistories =
          await history.getDetections(widget.userId);

      if (widget.userId != 0) {
        final response = await http
            .get(Uri.parse('$apiBaseUrl/get_history?userId=${widget.userId}'))
            .timeout(
          const Duration(seconds: 15),
          onTimeout: () {
            throw TimeoutException('Yêu cầu tải lịch sử quá thời gian');
          },
        );
        print(
            'Phản hồi từ get_history: ${response.statusCode} - ${response.body}');
        if (response.statusCode == 200) {
          final jsonResponse = jsonDecode(response.body);
          final serverHistories =
              List<Map<String, dynamic>>.from(jsonResponse['histories']);

          print(
              'Server history IDs: ${serverHistories.map((h) => h['id']).toList()}');

          if (serverHistories.isEmpty) {
            await history.clearDetectionsForUser(widget.userId);
            localHistories = [];
          } else {
            await history.clearDetectionsForUser(widget.userId);
            for (var serverHistory in serverHistories) {
              final imageSizeRaw = serverHistory['image_size'];
              Map<String, double> imageSize = {'width': 0.0, 'height': 0.0};
              if (imageSizeRaw != null) {
                imageSize = {
                  'width': (imageSizeRaw['width'] as num?)?.toDouble() ?? 0.0,
                  'height': (imageSizeRaw['height'] as num?)?.toDouble() ?? 0.0,
                };
              }
              await history.saveDetection(
                widget.userId,
                serverHistory['image_url'],
                List<Map<String, dynamic>>.from(serverHistory['detections']),
                imageSize,
                serverId: serverHistory['id'],
                timestamp: serverHistory['timestamp'],
              );
            }
            localHistories = await history.getDetections(widget.userId);
            print(
                'Local history IDs: ${localHistories.map((h) => h['id']).toList()}');
          }
        } else {
          print('Lỗi lấy lịch sử từ server: ${response.body}');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content: Text('Lỗi lấy lịch sử từ server: ${response.body}')),
            );
          }
        }
      }

      setState(() {
        _histories = localHistories;
        _isLoading = false;
      });
    } on TimeoutException catch (e) {
      print('Lỗi timeout: $e');
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hết thời gian tải lịch sử: $e')),
        );
      }
    } catch (e) {
      print('Lỗi khi tải lịch sử: $e');
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi khi tải lịch sử: $e')),
        );
      }
    }
  }

  Future<void> _deleteHistory(int detectionId) async {
    try {
      print('Gửi xóa: detectionId=$detectionId, userId=${widget.userId}');

      if (widget.userId != 0) {
        final response = await http
            .post(
          Uri.parse('$apiBaseUrl/delete_detection'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'detectionId': detectionId,
            'userId': widget.userId,
          }),
        )
            .timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            throw TimeoutException('Yêu cầu xóa bản ghi quá thời gian');
          },
        );

        print(
            'Phản hồi từ delete_detection: ${response.statusCode} - ${response.body}');

        if (response.statusCode != 200 && response.statusCode != 404) {
          print('Lỗi xóa trên server: ${response.body}');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Lỗi xóa trên server: ${response.body}')),
            );
          }
          return;
        }
      }

      final history = DetectionHistory();
      await history.deleteDetection(detectionId);

      setState(() {
        _histories.removeWhere((h) => h['id'] == detectionId);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Đã xóa bản ghi')),
        );
      }
    } on TimeoutException catch (e) {
      print('Lỗi timeout khi xóa: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hết thời gian xóa: $e')),
        );
      }
    } catch (e) {
      print('Lỗi khi xóa bản ghi: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi khi xóa bản ghi: $e')),
        );
      }
    }
  }

  String _getFullImageUrl(String imageUrl) {
    if (imageUrl.startsWith('http')) {
      return imageUrl.replaceAll(
          'http://192.168.1.100:8000', 'http://msi.local:8000');
    }
    return 'http://msi.local:8000$imageUrl';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: Text(
            'LỊCH SỬ PHÁT HIỆN',
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
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Làm mới lịch sử',
              onPressed: _loadHistories,
            ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _histories.isEmpty
                ? Center(
                    child: Text(
                      'Chưa có lịch sử phát hiện',
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        color: Theme.of(context).textTheme.bodyLarge!.color,
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: _histories.length,
                    itemBuilder: (context, index) {
                      final history = _histories[index];
                      final detections = List<Map<String, dynamic>>.from(
                          history['detections']);
                      final timestamp = DateTime.parse(history['timestamp']);
                      final imageUrl = _getFullImageUrl(history['image_url']);
                      final imageSizeRaw = history['image_size'];
                      Map<String, double>? imageSize;
                      if (imageSizeRaw != null) {
                        imageSize = {
                          'width':
                              (imageSizeRaw['width'] as num?)?.toDouble() ??
                                  0.0,
                          'height':
                              (imageSizeRaw['height'] as num?)?.toDouble() ??
                                  0.0,
                        };
                      }

                      print('History item $index - Detections: $detections');
                      print('History item $index - ImageUrl: $imageUrl');
                      print('History item $index - ImageSize: $imageSize');

                      return FadeIn(
                        child: Card(
                          elevation: 4,
                          margin: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: ListTile(
                            leading: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(
                                imageUrl,
                                width: 60,
                                height: 60,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  print(
                                      'Lỗi tải ảnh lịch sử: $imageUrl, lỗi: $error');
                                  return const Icon(Icons.broken_image,
                                      size: 60);
                                },
                              ),
                            ),
                            title: Text(
                              'Phát hiện: ${detections.length} đối tượng',
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context)
                                    .textTheme
                                    .bodyLarge!
                                    .color,
                              ),
                            ),
                            subtitle: Text(
                              'Thời gian: ${timestamp.toLocal().toString().substring(0, 16)}',
                              style: GoogleFonts.poppins(
                                color: Theme.of(context)
                                    .textTheme
                                    .bodyLarge!
                                    .color,
                              ),
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () => _deleteHistory(history['id']),
                              tooltip: 'Xóa bản ghi',
                            ),
                            onTap: () {
                              print(
                                  'Chuyển đến DetectionDetailScreen với detections: $detections');
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => DetectionDetailScreen(
                                    imageUrl: imageUrl,
                                    detections: detections,
                                    imageSize: imageSize,
                                    timestamp: timestamp,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      );
                    },
                  ));
  }
}

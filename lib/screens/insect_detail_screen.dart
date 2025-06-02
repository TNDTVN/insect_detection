import 'package:animate_do/animate_do.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class InsectDetailScreen extends StatelessWidget {
  final Map<String, dynamic> insect;

  const InsectDetailScreen({super.key, required this.insect});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          insect['vietnamese_name']?.toString() ??
              insect['class']?.toString() ??
              'Không xác định',
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
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: FadeIn(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Hình ảnh côn trùng
                  Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.asset(
                        insect['image_path'] ?? 'assets/profile.jpg',
                        height: 200,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          print(
                              'Lỗi tải ảnh côn trùng: ${insect['image_path']}');
                          return const Icon(Icons.broken_image, size: 100);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Thông tin chi tiết
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
                            'Tên: ${insect['vietnamese_name']?.toString() ?? insect['class']?.toString() ?? 'Không xác định'}',
                            style: GoogleFonts.poppins(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color:
                                  Theme.of(context).textTheme.bodyLarge!.color,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Tên khoa học: ${insect['scientific_name']?.toString() ?? 'Không có thông tin'}',
                            style: GoogleFonts.poppins(
                              fontSize: 16,
                              color:
                                  Theme.of(context).textTheme.bodyLarge!.color,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Mô tả: ${insect['description']?.toString() ?? 'Không có thông tin'}',
                            style: GoogleFonts.poppins(
                              fontSize: 16,
                              color:
                                  Theme.of(context).textTheme.bodyLarge!.color,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Mức độ nguy hiểm: ${insect['danger_level']?.toString() ?? 'Không có thông tin'}',
                            style: GoogleFonts.poppins(
                              fontSize: 16,
                              color:
                                  Theme.of(context).textTheme.bodyLarge!.color,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Cách xử lý: ${insect['handling']?.toString() ?? 'Không có thông tin'}',
                            style: GoogleFonts.poppins(
                              fontSize: 16,
                              color:
                                  Theme.of(context).textTheme.bodyLarge!.color,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

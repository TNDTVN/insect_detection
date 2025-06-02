import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:google_fonts/google_fonts.dart';

class FullScreenCamera extends StatelessWidget {
  final CameraController controller;
  final bool isFlashOn;
  final bool isCapturing;
  final VoidCallback? onCapture;
  final VoidCallback? onToggleFlash;
  final VoidCallback onClose;

  const FullScreenCamera({
    super.key,
    required this.controller,
    required this.isFlashOn,
    required this.isCapturing,
    this.onCapture,
    this.onToggleFlash,
    required this.onClose,
  });

  Widget _buildCameraActionButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    Color? color,
    bool gradient = false,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          elevation: 8,
          shape: const CircleBorder(),
          child: InkWell(
            borderRadius: BorderRadius.circular(32),
            onTap: onPressed,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: gradient
                    ? const LinearGradient(
                        colors: [Colors.blue, Colors.blueAccent],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : null,
                color: gradient ? null : Colors.black.withOpacity(0.7),
              ),
              child: Icon(
                icon,
                size: 24,
                color: gradient ? Colors.white : (color ?? Colors.white),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 12,
            color: Colors.white,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: AspectRatio(
              aspectRatio: controller.value.aspectRatio,
              child: CameraPreview(controller),
            ),
          ),
          if (isCapturing)
            Container(
              color: Colors.black.withOpacity(0.5),
              child: const Center(
                child: SpinKitFadingCircle(
                  color: Colors.blue,
                  size: 60.0,
                ),
              ),
            ),
          SafeArea(
            child: Stack(
              children: [
                Positioned(
                  top: 8,
                  left: 8,
                  child: Material(
                    color: Colors.black.withOpacity(0.7),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(32),
                      onTap: onClose,
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(
                          Icons.close,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 16.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _buildCameraActionButton(
                          icon: Icons.camera,
                          label: 'Chụp ảnh',
                          onPressed: isCapturing ? null : onCapture,
                          gradient: true,
                        ),
                        _buildCameraActionButton(
                          icon: isFlashOn ? Icons.flash_on : Icons.flash_off,
                          label: isFlashOn ? 'Tắt Flash' : 'Bật Flash',
                          onPressed: onToggleFlash,
                          color: Colors.black,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

import 'package:camera/camera.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:insect_detection/main.dart';

void main() {
  testWidgets('MyApp builds without crashing', (WidgetTester tester) async {
    // Tạo danh sách CameraDescription giả lập
    final mockCamera = CameraDescription(
      name: 'mock_camera',
      lensDirection: CameraLensDirection.back,
      sensorOrientation: 90,
    );

    // Build MyApp với danh sách camera giả lập
    await tester.pumpWidget(MyApp(cameras: [mockCamera]));

    // Đợi SplashScreen hiển thị
    await tester.pump(const Duration(seconds: 2));

    // Kiểm tra văn bản trên SplashScreen
    expect(find.text('Phát hiện côn trùng'), findsOneWidget);

    // Đợi chuyển sang InsectDetectionScreen (sau 2 giây)
    await tester.pumpAndSettle();

    // Kiểm tra văn bản trên InsectDetectionScreen
    expect(find.text('Phát hiện côn trùng'), findsOneWidget);
  });
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:animate_do/animate_do.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import './config.dart';
import './database/detection_history.dart';
import './screens/auth_screen.dart';
import './screens/history_screen.dart';
import './screens/profile_screen.dart';
import './screens/splash_screen.dart';
import './utils/image_utils.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cameras = await availableCameras();
  runApp(MyApp(cameras: cameras));
}

class MyApp extends StatelessWidget {
  final List<CameraDescription> cameras;
  const MyApp({super.key, required this.cameras});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => UserModel(),
      child: MaterialApp(
        theme: ThemeData.light().copyWith(
          primaryColor: Colors.blue,
          scaffoldBackgroundColor: Colors.grey[100],
          cardTheme: const CardTheme(elevation: 4, margin: EdgeInsets.all(8)),
          textTheme: GoogleFonts.poppinsTextTheme().apply(
            bodyColor: Colors.black87,
            displayColor: Colors.black87,
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        darkTheme: ThemeData.dark().copyWith(
          primaryColor: Colors.blue,
          scaffoldBackgroundColor: Colors.grey[900],
          cardTheme: const CardTheme(elevation: 4, margin: EdgeInsets.all(8)),
          textTheme: GoogleFonts.poppinsTextTheme().apply(
            bodyColor: Colors.white,
            displayColor: Colors.white,
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        themeMode: ThemeMode.system,
        home: SplashScreen(cameras: cameras),
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}

class UserModel extends ChangeNotifier {
  String _email = 'Chưa đăng nhập';
  String _profilePicture = 'assets/profile.jpg';

  String get email => _email;
  String get profilePicture => _profilePicture;

  void updateUser(String email, String profilePicture) {
    _email = email;
    _profilePicture = profilePicture;
    notifyListeners();
  }
}

class InsectDetectionScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  final int userId;
  const InsectDetectionScreen(
      {super.key, required this.cameras, required this.userId});

  @override
  InsectDetectionScreenState createState() => InsectDetectionScreenState();
}

class InsectDetectionScreenState extends State<InsectDetectionScreen> {
  CameraController? _controller;
  File? _image;
  List<Map<String, dynamic>>? _detections;
  Size _imageSize = Size.zero;
  bool _isFlashOn = false;
  bool _isCameraReady = false;
  bool _isCapturing = false;
  bool _isCameraOpen = false;
  String _predictionMessage = '';
  final int _cameraIndex = 0;
  List<Map<String, dynamic>> _insectData = [];
  String? _profilePicture;
  String? _email;

  @override
  void initState() {
    super.initState();
    _requestCameraPermission();
    _loadInsectData();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final userModel = Provider.of<UserModel>(context, listen: false);
    final savedEmail = prefs.getString('email') ?? 'Chưa đăng nhập';
    final savedPassword = prefs.getString('password') ?? '';
    final savedProfilePicture =
        prefs.getString('profilePicture') ?? 'assets/profile.jpg';

    if (widget.userId != 0 &&
        savedEmail != 'Chưa đăng nhập' &&
        savedPassword.isNotEmpty) {
      try {
        final response = await http.post(
          Uri.parse('$apiBaseUrl/login'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'email': savedEmail,
            'password': savedPassword,
          }),
        );
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          await prefs.setString('email', data['email'] ?? savedEmail);
          await prefs.setString('profilePicture', data['profile_picture']);
          userModel.updateUser(
              data['email'] ?? savedEmail, data['profile_picture']);
        } else {
          print(
              'Lỗi đăng nhập tự động: ${response.statusCode} - ${response.body}');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text(
                      'Phiên đăng nhập không hợp lệ, vui lòng đăng nhập lại')),
            );
          }
          await _logout();
        }
      } catch (e) {
        print('Lỗi kiểm tra thông tin từ server: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Không thể kết nối đến server')),
          );
        }
      }
    } else {
      // Trường hợp userId == 0 hoặc không có thông tin đăng nhập
      userModel.updateUser(savedEmail, savedProfilePicture);
    }
    setState(() {
      _profilePicture = userModel.profilePicture;
      _email = userModel.email;
    });
  }

  Map<int, Map<String, dynamic>> _classIdMap = {};

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

  Map<String, dynamic> getInsectDetails(Map<String, dynamic> detection) {
    try {
      final classId = detection['class_id'] as int?;
      if (classId != null && _classIdMap.containsKey(classId)) {
        print('Khớp class_id: $classId, chi tiết: ${_classIdMap[classId]}');
        return _classIdMap[classId]!;
      }

      final className = detection['class'].toString();
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

  Future<void> _requestCameraPermission() async {
    var status = await Permission.camera.status;
    if (!status.isGranted) {
      status = await Permission.camera.request();
      if (!status.isGranted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Cần cấp quyền camera để tiếp tục')),
          );
        }
        return;
      }
    }
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
    if (_controller != null) {
      await _controller!.dispose();
      _controller = null;
    }
    _controller = CameraController(
      widget.cameras[_cameraIndex],
      ResolutionPreset.medium,
      enableAudio: false,
    );
    try {
      await _controller!.initialize();
      if (!mounted) return;
      setState(() {
        _isCameraReady = true;
        _isCameraOpen = true;
        _image = null;
        _detections = null;
        _imageSize = Size.zero;
        _predictionMessage = '';
      });
    } catch (e) {
      print('Lỗi khởi tạo camera: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi khởi tạo camera: $e')),
        );
      }
      setState(() {
        _isCameraReady = false;
        _isCameraOpen = false;
      });
    }
  }

  Future<void> _closeCamera() async {
    if (_controller != null && _controller!.value.isInitialized) {
      await _controller!.dispose();
      _controller = null;
      if (mounted) {
        setState(() {
          _isCameraReady = false;
          _isCameraOpen = false;
          _isFlashOn = false;
          _image = null;
          _detections = null;
          _imageSize = Size.zero;
          _predictionMessage = '';
        });
      }
    }
  }

  Future<void> _refreshCamera() async {
    if (_isCameraOpen &&
        _controller != null &&
        _controller!.value.isInitialized) {
      if (mounted) {
        setState(() {
          _image = null;
          _detections = null;
          _imageSize = Size.zero;
          _predictionMessage = '';
        });
      }
    }
  }

  Future<File> _fixImageOrientation(File imageFile) async {
    final bytes = await imageFile.readAsBytes();
    final image = img.decodeImage(bytes);
    if (image == null) return imageFile;
    final orientedImage = img.bakeOrientation(image);
    final newPath = imageFile.path.replaceAll('.jpg', '_fixed.jpg');
    await File(newPath).writeAsBytes(img.encodeJpg(orientedImage));
    return File(newPath);
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
      print('Lỗi khi bật/tắt flash: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi khi bật/tắt flash: $e')),
        );
      }
    }
  }

  Future<void> _captureImage() async {
    if (_controller == null || !_controller!.value.isInitialized) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Camera chưa sẵn sàng')),
        );
      }
      return;
    }
    if (_isCapturing) {
      print('Đang chụp ảnh, vui lòng chờ...');
      return;
    }

    setState(() {
      _isCapturing = true;
    });

    try {
      final image = await _controller!.takePicture();
      final fixedImage = await _fixImageOrientation(File(image.path));
      if (mounted) {
        setState(() {
          _image = fixedImage;
          _detections = null;
          _imageSize = Size.zero;
          _predictionMessage = '';
        });
      }
      await _sendToApi();
    } catch (e) {
      print('Lỗi khi chụp ảnh: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi khi chụp ảnh: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCapturing = false;
        });
      }
    }
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      final fixedImage = await _fixImageOrientation(File(pickedFile.path));
      if (mounted) {
        setState(() {
          _image = fixedImage;
          _detections = null;
          _imageSize = Size.zero;
          _predictionMessage = '';
        });
      }
      await _sendToApi();
    }
  }

  Future<String?> _uploadImageToServer(File image) async {
    try {
      print('Tải ảnh lên server: ${image.path}');
      var request =
          http.MultipartRequest('POST', Uri.parse('$apiBaseUrl/upload_image'));
      var fileStream = await http.MultipartFile.fromPath(
        'file',
        image.path,
        contentType: MediaType('image', 'jpeg'),
      );
      request.files.add(fileStream);
      var response = await request.send();
      var responseBody = await response.stream.bytesToString();
      if (response.statusCode == 200) {
        var jsonResponse = jsonDecode(responseBody);
        print('Ảnh tải lên thành công: ${jsonResponse['image_url']}');
        return jsonResponse['image_url'];
      } else {
        print('Lỗi tải ảnh: $responseBody');
        return null;
      }
    } catch (e) {
      print('Lỗi khi tải ảnh lên server: $e');
      return null;
    }
  }

  Future<void> _sendToApi() async {
    if (_image == null || !(_image!.existsSync())) {
      print('File không tồn tại: ${_image?.path}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File ảnh không hợp lệ')),
        );
      }
      return;
    }

    try {
      print('Thử gửi request đến: $apiBaseUrl/predict');
      var request =
          http.MultipartRequest('POST', Uri.parse('$apiBaseUrl/predict'));

      String contentType = 'image/jpeg';
      if (_image!.path.toLowerCase().endsWith('.png')) {
        contentType = 'image/png';
      } else if (_image!.path.toLowerCase().endsWith('.webp')) {
        contentType = 'image/webp';
      }

      var fileStream = await http.MultipartFile.fromPath(
        'file',
        _image!.path,
        contentType: MediaType('image', contentType.split('/')[1]),
      );

      request.files.add(fileStream);

      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw TimeoutException('Yêu cầu kết nối hết thời gian');
        },
      );

      var responseBody = await streamedResponse.stream.bytesToString();
      print('Phản hồi từ API: $responseBody');
      var jsonResponse = jsonDecode(responseBody);

      if (streamedResponse.statusCode == 200 &&
          jsonResponse.containsKey('detections') &&
          jsonResponse.containsKey('image_size')) {
        print('Detections thô từ API: ${jsonResponse['detections']}');
        if (mounted) {
          setState(() {
            _detections =
                List<Map<String, dynamic>>.from(jsonResponse['detections'])
                    .where((detection) {
              if (!detection.containsKey('class') ||
                  !detection.containsKey('confidence') ||
                  !detection.containsKey('box')) {
                print('Bỏ qua detection không đầy đủ: $detection');
                return false;
              }
              final box = detection['box'] as List<dynamic>?;
              if (box == null || box.length < 4) {
                print('Bỏ qua hộp không hợp lệ: $box');
                return false;
              }
              final x = (box[0] as num?)?.toDouble() ?? 0.0;
              final y = (box[1] as num?)?.toDouble() ?? 0.0;
              final width = (box[2] as num?)?.toDouble() ?? 0.0;
              final height = (box[3] as num?)?.toDouble() ?? 0.0;
              if (width <= 0 ||
                  height <= 0 ||
                  x.isNaN ||
                  y.isNaN ||
                  width.isNaN ||
                  height.isNaN) {
                print('Bỏ qua hộp không hợp lệ: $box');
                return false;
              }
              return true;
            }).toList();
            _imageSize = Size(
              jsonResponse['image_size']['width'].toDouble(),
              jsonResponse['image_size']['height'].toDouble(),
            );
            _predictionMessage =
                'Dự đoán thành công: ${_detections!.length} đối tượng';
            print('Detections hợp lệ: $_detections');
            print('Image Size: ${_imageSize.width}x${_imageSize.height}');
          });
          if (_detections!.isNotEmpty) {
            try {
              final boxedImage =
                  await createImageWithBoxes(_image!, _detections!);
              if (mounted) {
                setState(() {
                  _image = boxedImage;
                  print('Đã tạo ảnh với hộp: ${_image!.path}');
                });
              }
            } catch (e) {
              print('Lỗi khi vẽ hộp: $e');
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Lỗi khi vẽ hộp: $e')),
                );
              }
            }
          }

          final imageUrl = await _uploadImageToServer(_image!);
          if (imageUrl == null) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Lỗi khi tải ảnh lên server')),
              );
            }
            return;
          }

          final history = DetectionHistory();
          await history.saveDetection(
            widget.userId,
            imageUrl,
            _detections!,
            {'width': _imageSize.width, 'height': _imageSize.height},
          );

          if (widget.userId != 0) {
            final uri = Uri.parse('$apiBaseUrl/sync_history');
            final historyData = {
              'userId': widget.userId,
              'histories': [
                {
                  'image_url': imageUrl,
                  'detections': _detections,
                  'image_size': {
                    'width': _imageSize.width,
                    'height': _imageSize.height
                  },
                  'timestamp': DateTime.now().toIso8601String(),
                }
              ],
            };
            print('Dữ liệu gửi lên /sync_history: ${jsonEncode(historyData)}');
            final response = await http
                .post(
              uri,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(historyData),
            )
                .timeout(
              const Duration(seconds: 15),
              onTimeout: () {
                throw TimeoutException('Yêu cầu đồng bộ lịch sử quá thời gian');
              },
            );
            print(
                'Phản hồi từ /sync_history: ${response.statusCode} - ${response.body}');
            if (response.statusCode != 200) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content: Text(
                          'Lỗi đồng bộ lịch sử: ${response.statusCode} - ${response.body}')),
                );
              }
            }
          }
        }
      } else {
        print('Lỗi từ API: $jsonResponse');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(
                    'Lỗi từ API: ${jsonResponse['detail'] ?? 'Không xác định'}')),
          );
        }
      }
    } on TimeoutException catch (e) {
      print('Lỗi timeout: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hết thời gian chờ: $e')),
        );
      }
    } catch (e) {
      print('Lỗi khi gửi đến server: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi kết nối server: $e')),
        );
      }
    }
  }

  String _getObjectSummary() {
    if (_detections == null || _detections!.isEmpty) return '';
    final classCounts = <String, int>{};
    for (var detection in _detections!) {
      final className = detection['class'] as String;
      classCounts[className] = (classCounts[className] ?? 0) + 1;
    }
    return classCounts.entries.map((e) => '${e.key}: ${e.value}').join(', ');
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('userId', 0);
    await prefs.remove('email');
    await prefs.remove('password');
    await prefs.remove('profilePicture');
    final userModel = Provider.of<UserModel>(context, listen: false);
    userModel.updateUser('Chưa đăng nhập', 'assets/profile.jpg');
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => InsectDetectionScreen(
            cameras: widget.cameras,
            userId: 0,
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<UserModel>(
      builder: (context, user, child) {
        _profilePicture = user.profilePicture;
        _email = user.email;
        return Scaffold(
          appBar: AppBar(
            title: Text(
              'INSECT IDENTIFICATION',
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
            leading: _profilePicture != null
                ? GestureDetector(
                    onTap: () {
                      if (widget.userId != 0 && _email != null) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ProfileScreen(
                              userId: widget.userId,
                              initialEmail: _email!,
                              initialProfilePicture: _profilePicture!,
                            ),
                          ),
                        ).then((_) =>
                            _loadUserData()); // Tải lại dữ liệu sau khi quay lại từ ProfileScreen
                      }
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: CircleAvatar(
                        backgroundImage: _profilePicture!.startsWith('http')
                            ? NetworkImage(_profilePicture!)
                            : AssetImage(_profilePicture!) as ImageProvider,
                        radius: 20,
                        onBackgroundImageError: (error, stackTrace) {
                          print('Lỗi tải ảnh đại diện: $error');
                        },
                      ),
                    ),
                  )
                : null,
            actions: [
              IconButton(
                icon: const Icon(Icons.history),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => HistoryScreen(userId: widget.userId),
                  ),
                ),
                tooltip: 'Xem lịch sử',
              ),
              IconButton(
                icon: Icon(widget.userId == 0 ? Icons.login : Icons.logout),
                onPressed: () {
                  if (widget.userId == 0) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AuthScreen(cameras: widget.cameras),
                      ),
                    );
                  } else {
                    _logout();
                  }
                },
                tooltip: widget.userId == 0 ? 'Đăng nhập/Đăng ký' : 'Đăng xuất',
              ),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: [
                if (_predictionMessage.isNotEmpty)
                  FadeIn(
                    child: Container(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? Colors.blue[900]
                          : Colors.blue[50],
                      padding: const EdgeInsets.all(12.0),
                      width: double.infinity,
                      child: Text(
                        _predictionMessage,
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.white
                              : Colors.blue[800],
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                Expanded(
                  child: _image == null
                      ? (_isCameraOpen && _isCameraReady && _controller != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: CameraPreview(_controller!),
                            )
                          : Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    'Chưa mở camera',
                                    style: GoogleFonts.poppins(
                                      fontSize: 16,
                                      color: Theme.of(context)
                                          .textTheme
                                          .bodyLarge!
                                          .color,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  _buildActionButton(
                                    icon: Icons.camera_alt,
                                    label: 'Mở Camera',
                                    onPressed: _initializeCamera,
                                  ),
                                ],
                              ),
                            ))
                      : SingleChildScrollView(
                          child: FadeIn(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (_imageSize.width > 0 &&
                                    _imageSize.height > 0)
                                  Card(
                                    elevation: 4,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: LayoutBuilder(
                                      builder: (context, constraints) {
                                        final aspectRatio = _imageSize.width /
                                            _imageSize.height;
                                        final displayWidth =
                                            constraints.maxWidth;
                                        final displayHeight =
                                            displayWidth / aspectRatio;

                                        return ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          child: InteractiveViewer(
                                            minScale: 0.5,
                                            maxScale: 4.0,
                                            child: Container(
                                              width: displayWidth,
                                              height: displayHeight,
                                              child: Stack(
                                                alignment: Alignment.center,
                                                children: [
                                                  Image.file(
                                                    _image!,
                                                    fit: BoxFit.fill,
                                                    width: displayWidth,
                                                    height: displayHeight,
                                                    alignment: Alignment.center,
                                                    errorBuilder: (context,
                                                        error, stackTrace) {
                                                      print(
                                                          'Lỗi hiển thị ảnh: $error');
                                                      return const Icon(
                                                          Icons.broken_image,
                                                          size: 100);
                                                    },
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  )
                                else
                                  const Center(
                                    child:
                                        SpinKitFadingCircle(color: Colors.blue),
                                  ),
                                if (_detections != null)
                                  Padding(
                                    padding: const EdgeInsets.all(16.0),
                                    child: Card(
                                      elevation: 4,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Padding(
                                        padding: const EdgeInsets.all(16.0),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Số lượng đối tượng: ${_detections!.length}',
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
                                              'Độ chính xác trung bình: ${(_detections!.isEmpty ? 0 : _detections!.map((d) => d['confidence'] as double).reduce((a, b) => a + b) / _detections!.length * 100).toStringAsFixed(1)}%',
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
                                            Center(
                                              child: _buildActionButton(
                                                icon: Icons.share,
                                                label: 'Chia sẻ kết quả',
                                                onPressed: () async {
                                                  try {
                                                    final boxedImage =
                                                        await createImageWithBoxes(
                                                            _image!,
                                                            _detections!);
                                                    final text =
                                                        'Phát hiện côn trùng:\n'
                                                        'Số lượng: ${_detections!.length}\n'
                                                        'Đối tượng: ${_getObjectSummary()}\n'
                                                        'Độ chính xác trung bình: ${(_detections!.isEmpty ? 0 : _detections!.map((d) => d['confidence'] as double).reduce((a, b) => a + b) / _detections!.length * 100).toStringAsFixed(1)}%';
                                                    await Share.shareXFiles([
                                                      XFile(boxedImage.path)
                                                    ], text: text);
                                                  } catch (e) {
                                                    if (mounted) {
                                                      ScaffoldMessenger.of(
                                                              context)
                                                          .showSnackBar(
                                                        SnackBar(
                                                            content: Text(
                                                                'Lỗi chia sẻ: $e')),
                                                      );
                                                    }
                                                  }
                                                },
                                                gradient: true,
                                              ),
                                            ),
                                            const SizedBox(height: 16),
                                            if (_detections!.isNotEmpty)
                                              Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: _detections!
                                                    .map((detection) {
                                                  final insectDetails =
                                                      getInsectDetails(
                                                          detection);
                                                  return FadeIn(
                                                    child: ExpansionTile(
                                                      title: Text(
                                                        insectDetails[
                                                                    'vietnamese_name']
                                                                ?.toString() ??
                                                            detection['class'],
                                                        style:
                                                            GoogleFonts.poppins(
                                                          fontSize: 16,
                                                          fontWeight:
                                                              FontWeight.w600,
                                                          color:
                                                              Theme.of(context)
                                                                  .textTheme
                                                                  .bodyLarge!
                                                                  .color,
                                                        ),
                                                      ),
                                                      children: [
                                                        Padding(
                                                          padding:
                                                              const EdgeInsets
                                                                  .symmetric(
                                                                  horizontal:
                                                                      16.0,
                                                                  vertical:
                                                                      8.0),
                                                          child: Column(
                                                            crossAxisAlignment:
                                                                CrossAxisAlignment
                                                                    .start,
                                                            children: [
                                                              Text(
                                                                'Tên khoa học: ${insectDetails['scientific_name']?.toString() ?? 'Không có thông tin'}',
                                                                style:
                                                                    GoogleFonts
                                                                        .poppins(
                                                                  fontSize: 14,
                                                                  color: Theme.of(
                                                                          context)
                                                                      .textTheme
                                                                      .bodyLarge!
                                                                      .color,
                                                                ),
                                                              ),
                                                              Padding(
                                                                padding:
                                                                    const EdgeInsets
                                                                        .only(
                                                                        top:
                                                                            8.0),
                                                                child: Text(
                                                                  'Mô tả: ${insectDetails['description']?.toString() ?? 'Không có thông tin'}',
                                                                  style: GoogleFonts
                                                                      .poppins(
                                                                    fontSize:
                                                                        14,
                                                                    color: Theme.of(
                                                                            context)
                                                                        .textTheme
                                                                        .bodyLarge!
                                                                        .color,
                                                                  ),
                                                                ),
                                                              ),
                                                              Padding(
                                                                padding:
                                                                    const EdgeInsets
                                                                        .only(
                                                                        top:
                                                                            8.0),
                                                                child: Text(
                                                                  'Mức độ nguy hiểm: ${insectDetails['danger_level']?.toString() ?? 'Không có thông tin'}',
                                                                  style: GoogleFonts
                                                                      .poppins(
                                                                    fontSize:
                                                                        14,
                                                                    color: Theme.of(
                                                                            context)
                                                                        .textTheme
                                                                        .bodyLarge!
                                                                        .color,
                                                                  ),
                                                                ),
                                                              ),
                                                              Padding(
                                                                padding:
                                                                    const EdgeInsets
                                                                        .only(
                                                                        top:
                                                                            8.0),
                                                                child: Text(
                                                                  'Cách xử lý: ${insectDetails['handling']?.toString() ?? 'Không có thông tin'}',
                                                                  style: GoogleFonts
                                                                      .poppins(
                                                                    fontSize:
                                                                        14,
                                                                    color: Theme.of(
                                                                            context)
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
                      if (_isCameraOpen)
                        _buildActionButton(
                          icon: Icons.camera,
                          label: 'Chụp ảnh',
                          onPressed: _isCapturing ? null : _captureImage,
                        ),
                      if (!_isCameraOpen)
                        _buildActionButton(
                          icon: Icons.photo_library,
                          label: 'Chọn ảnh',
                          onPressed: _pickImage,
                        ),
                      if (_isCameraOpen && _image != null)
                        _buildActionButton(
                          icon: Icons.refresh,
                          label: 'Làm mới',
                          onPressed: _refreshCamera,
                          color: Colors.orange,
                        ),
                      _buildActionButton(
                        icon: _isFlashOn ? Icons.flash_on : Icons.flash_off,
                        label: _isFlashOn ? 'Tắt Flash' : 'Bật Flash',
                        onPressed: _isCameraOpen ? _toggleFlash : null,
                        color: Colors.blue,
                      ),
                      _buildActionButton(
                        icon: _isCameraOpen ? Icons.power_off : Icons.power,
                        label: _isCameraOpen ? 'Đóng Camera' : 'Mở Camera',
                        onPressed:
                            _isCameraOpen ? _closeCamera : _initializeCamera,
                        color: _isCameraOpen ? Colors.red : Colors.green,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    Color? color,
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
                  color: gradient ? Colors.white : (color ?? Colors.grey[600]),
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
}

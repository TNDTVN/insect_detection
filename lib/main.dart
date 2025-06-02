import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:animate_do/animate_do.dart';
import 'package:camera/camera.dart';
import 'package:carousel_slider/carousel_slider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import './config.dart';
import './database/detection_history.dart';
import './screens/auth_screen.dart';
import './screens/detection_result_screen.dart';
import './screens/history_screen.dart';
import './screens/insect_detail_screen.dart';
import './screens/profile_screen.dart';
import './screens/splash_screen.dart';
import './utils/image_utils.dart';
import './widgets/full_screen_camera.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cameras = await availableCameras();
  runApp(MyApp(cameras: cameras));
}

class MyApp extends StatelessWidget {
  final List<CameraDescription> cameras;
  final RouteObserver<ModalRoute> routeObserver = RouteObserver<ModalRoute>();
  MyApp({super.key, required this.cameras});

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
        navigatorObservers: [routeObserver], // Thêm RouteObserver
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

class InsectDetectionScreenState extends State<InsectDetectionScreen>
    with RouteAware {
  CameraController? _controller;
  File? _image;
  List<Map<String, dynamic>>? _detections;
  Size _imageSize = Size.zero;
  bool _isFlashOn = false;
  bool _isCameraReady = false;
  bool _isCapturing = false;
  bool _isCameraOpen = false;
  bool _isInsectListExpanded = false;
  String _predictionMessage = '';
  final int _cameraIndex = 0;
  List<Map<String, dynamic>> _insectData = [];
  String? _profilePicture;
  String? _email;
  bool _isLoadingUserData = true;
  final RouteObserver<ModalRoute> routeObserver = RouteObserver<ModalRoute>();

  @override
  void initState() {
    super.initState();
    _loadInsectData();
    _loadUserData();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ModalRoute? route = ModalRoute.of(context);
    if (route != null) {
      routeObserver.subscribe(this, route);
    }
  }

  @override
  void didPopNext() {
    // Không reset trạng thái ở đây để tránh race condition
    if (mounted && !_isCameraOpen) {
      _startDetection(); // Chỉ khởi tạo camera nếu cần
    }
    super.didPopNext();
  }

  @override
  void dispose() {
    routeObserver.unsubscribe(this);
    _closeCamera();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final userModel = Provider.of<UserModel>(context, listen: false);
    final savedEmail = prefs.getString('email') ?? 'Chưa đăng nhập';
    final savedProfilePicture =
        prefs.getString('profilePicture') ?? 'assets/profile.jpg';

    setState(() {
      _profilePicture = savedProfilePicture;
      _email = savedEmail;
      userModel.updateUser(savedEmail, savedProfilePicture);
    });

    if (widget.userId != 0 && savedEmail != 'Chưa đăng nhập') {
      final savedPassword = prefs.getString('password') ?? '';
      if (savedPassword.isNotEmpty) {
        try {
          final response = await http
              .post(
                Uri.parse('$apiBaseUrl/login'),
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode({
                  'email': savedEmail,
                  'password': savedPassword,
                }),
              )
              .timeout(const Duration(seconds: 5));
          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            await prefs.setString('email', data['email'] ?? savedEmail);
            await prefs.setString('profilePicture',
                data['profile_picture'] ?? savedProfilePicture);
            userModel.updateUser(data['email'] ?? savedEmail,
                data['profile_picture'] ?? savedProfilePicture);
            setState(() {
              _profilePicture = data['profile_picture'] ?? savedProfilePicture;
              _email = data['email'] ?? savedEmail;
            });
          } else {
            print(
                'Auto-login error: ${response.statusCode} - ${response.body}');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                    content: Text(
                        'Phiên làm việc không hợp lệ, vui lòng đăng nhập lại')),
              );
            }
            await _logout();
          }
        } catch (e) {
          print('Error checking server: $e');
        }
      }
    }
    setState(() {
      _isLoadingUserData = false;
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
      });
    } catch (e) {
      print('Error loading insects.json: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lỗi khi tải dữ liệu côn trùng')),
        );
      }
    }
  }

  Future<void> _requestCameraPermission() async {
    var status = await Permission.camera.status;
    if (!status.isGranted) {
      status = await Permission.camera.request();
      if (!status.isGranted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Cần quyền truy cập camera')),
          );
        }
        return;
      }
    }
  }

  Future<void> _initializeCamera() async {
    await _requestCameraPermission();
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
      print('Error initializing camera: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi khi khởi tạo camera: $e')),
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
      try {
        await _controller!.dispose();
        _controller = null;
      } catch (e) {
        print('Error disposing camera: $e');
      }
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
    if (mounted) {
      setState(() {
        _image = null;
        _detections = null;
        _imageSize = Size.zero;
        _predictionMessage = '';
        _isCameraOpen = true;
        _isCameraReady = false;
      });
      await _closeCamera();
      await _initializeCamera();
      if (_controller == null || !_controller!.value.isInitialized) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Không thể khởi động lại camera')),
          );
        }
        setState(() {
          _isCameraOpen = false;
          _isCameraReady = false;
        });
      }
    }
  }

  Future<File> _fixImageOrientation(File imageFile) async {
    return await compute(_fixImageOrientationIsolate, imageFile.path);
  }

  static Future<File> _fixImageOrientationIsolate(String path) async {
    final bytes = await File(path).readAsBytes();
    final image = img.decodeImage(bytes);
    if (image == null) return File(path);
    final orientedImage = img.bakeOrientation(image);
    final newPath = path.replaceAll('.jpg', '_fixed.jpg');
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
      print('Error toggling flash: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi khi bật/tắt flash: $e')),
        );
      }
    }
  }

  Future<void> _captureImage() async {
    if (_controller == null || !_controller!.value.isInitialized) {
      await _initializeCamera();
      if (_controller == null || !_controller!.value.isInitialized) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Camera chưa sẵn sàng')),
          );
        }
        return;
      }
    }
    if (_isCapturing) {
      print('Đang chụp ảnh, vui lòng đợi...');
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
      print('Error capturing image: $e');
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

  Future<void> _startDetection() async {
    if (!_isCameraOpen) {
      await _initializeCamera();
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
        return jsonResponse['image_url'];
      } else {
        print('Error uploading image: $responseBody');
        return null;
      }
    } catch (e) {
      print('Error uploading image to server: $e');
      return null;
    }
  }

  Future<void> _sendToApi() async {
    // Lưu _image vào biến cục bộ để tránh thay đổi bất ngờ
    final File? currentImage = _image;
    if (currentImage == null || !(await currentImage.exists())) {
      print('File does not exist: ${currentImage?.path}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File ảnh không hợp lệ')),
        );
      }
      if (mounted) {
        setState(() {
          _isCapturing = false;
        });
      }
      return;
    }

    try {
      var request =
          http.MultipartRequest('POST', Uri.parse('$apiBaseUrl/predict'));

      String contentType = 'image/jpeg';
      if (currentImage.path.toLowerCase().endsWith('.png')) {
        contentType = 'image/png';
      } else if (currentImage.path.toLowerCase().endsWith('.webp')) {
        contentType = 'image/webp';
      }

      var fileStream = await http.MultipartFile.fromPath(
        'file',
        currentImage.path,
        contentType: MediaType('image', contentType.split('/')[1]),
      );

      request.files.add(fileStream);

      final streamedResponse = await request.send().timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw TimeoutException('Request timed out');
        },
      );

      var responseBody = await streamedResponse.stream.bytesToString();
      var jsonResponse = jsonDecode(responseBody);

      if (streamedResponse.statusCode == 200 &&
          jsonResponse.containsKey('detections') &&
          jsonResponse.containsKey('image_size')) {
        List<Map<String, dynamic>> detections =
            List<Map<String, dynamic>>.from(jsonResponse['detections'])
                .where((detection) {
          if (!detection.containsKey('class') ||
              !detection.containsKey('confidence') ||
              !detection.containsKey('box')) {
            print('Skipping incomplete detection: $detection');
            return false;
          }
          final box = detection['box'] as List<dynamic>?;
          if (box == null || box.length < 4) {
            print('Skipping invalid box: $box');
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
            print('Skipping invalid box: $box');
            return false;
          }
          return true;
        }).toList();
        Size imageSize = Size(
          (jsonResponse['image_size']['width'] as num?)?.toDouble() ?? 0.0,
          (jsonResponse['image_size']['height'] as num?)?.toDouble() ?? 0.0,
        );

        File? processedImage = currentImage;
        if (detections.isNotEmpty) {
          try {
            processedImage =
                await createImageWithBoxes(currentImage, detections);
            if (mounted) {
              setState(() {
                _image = processedImage;
              });
            }
          } catch (e) {
            print('Error drawing boxes: $e');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Lỗi khi vẽ khung hình: $e')),
              );
            }
          }
        }

        if (processedImage == null || !(await processedImage.exists())) {
          print('Processed image is invalid: ${processedImage?.path}');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Ảnh đã xử lý không hợp lệ')),
            );
          }
          return;
        }

        final imageUrl = await _uploadImageToServer(processedImage);
        if (imageUrl == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Lỗi khi tải ảnh lên server')),
            );
          }
          return;
        }

        final history = await DetectionHistory();
        await history.saveDetection(
          widget.userId,
          imageUrl,
          detections,
          {'width': imageSize.width, 'height': imageSize.height},
        );

        if (widget.userId != 0) {
          final uri = Uri.parse('$apiBaseUrl/sync_history');
          final historyData = {
            'userId': widget.userId,
            'histories': [
              {
                'image_url': imageUrl,
                'detections': detections,
                'image_size': {
                  'width': imageSize.width,
                  'height': imageSize.height
                },
                'timestamp': DateTime.now().toIso8601String(),
              }
            ],
          };
          final response = await http
              .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(historyData),
          )
              .timeout(
            const Duration(seconds: 15),
            onTimeout: () {
              throw TimeoutException('History sync timed out');
            },
          );
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

        if (_controller != null && _controller!.value.isInitialized) {
          await _controller!.pausePreview();
        }

        if (mounted) {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => DetectionResultScreen(
                image: processedImage!,
                detections: detections,
                imageSize: imageSize,
                userId: widget.userId,
                insectData: _insectData,
                cameras: widget.cameras,
                onCaptureNew: (File image) {
                  if (mounted) {
                    setState(() {
                      _image = image;
                      _detections = null;
                      _imageSize = Size.zero;
                      _predictionMessage = '';
                      _isCapturing = false;
                      _isCameraOpen = false;
                    });
                    _sendToApi();
                  }
                },
                onPickImage: _pickImage,
                onRefresh: _refreshCamera,
              ),
            ),
          );
          // Reset trạng thái sau khi quay lại
          if (mounted) {
            setState(() {
              _image = null;
              _detections = null;
              _imageSize = Size.zero;
              _predictionMessage = '';
              _isCameraOpen = false;
              _isCameraReady = false;
            });
          }
        }
      } else {
        print('API error: $jsonResponse');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(
                    'Lỗi API: ${jsonResponse['detail'] ?? 'Không xác định'}')),
          );
        }
      }
    } on TimeoutException catch (e) {
      print('Timeout error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Yêu cầu hết thời gian: $e')),
        );
      }
    } catch (e, stackTrace) {
      print('Error sending to server: $e\n$stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi kết nối server: $e')),
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

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
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
                  color: gradient ? Colors.white : Colors.black87,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
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
  Widget build(BuildContext context) {
    return Consumer<UserModel>(
      builder: (context, user, child) {
        return Scaffold(
          appBar: AppBar(
            title: Text(
              'NHẬN DIỆN CÔN TRÙNG',
              style: GoogleFonts.poppins(
                fontWeight: FontWeight.w600,
                fontSize: 18, // Giảm kích thước chữ từ mặc định xuống 16
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
            leading: _isLoadingUserData
                ? const Padding(
                    padding: EdgeInsets.all(8.0),
                    child: CircularProgressIndicator(),
                  )
                : _profilePicture != null
                    ? GestureDetector(
                        onTap: () {
                          if (widget.userId != 0 && _email != null) {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => ProfileScreen(
                                  userId: widget.userId,
                                  initialEmail: _email ?? 'Chưa đăng nhập',
                                  initialProfilePicture:
                                      _profilePicture ?? 'assets/profile.jpg',
                                ),
                              ),
                            ).then((_) => _loadUserData());
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
                              print('Error loading profile picture: $error');
                            },
                          ),
                        ),
                      )
                    : const Icon(Icons.account_circle),
            actions: [
              IconButton(
                icon: const Icon(Icons.history),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => HistoryScreen(userId: widget.userId),
                  ),
                ),
                tooltip: 'Lịch sử',
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
                tooltip: widget.userId == 0 ? 'Đăng nhập' : 'Đăng xuất',
              ),
            ],
          ),
          body: _isLoadingUserData
              ? const Center(child: SpinKitFadingCircle(color: Colors.blue))
              : _isCameraOpen && _isCameraReady && _controller != null
                  ? FullScreenCamera(
                      controller: _controller!,
                      isFlashOn: _isFlashOn,
                      isCapturing: _isCapturing,
                      onCapture: _captureImage,
                      onToggleFlash: _toggleFlash,
                      onClose: _closeCamera,
                    )
                  : SafeArea(
                      child: Column(
                        children: [
                          if (_predictionMessage.isNotEmpty)
                            FadeIn(
                              child: Container(
                                color: Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? Colors.blue[900]
                                    : Colors.blue[50],
                                padding: const EdgeInsets.all(12.0),
                                width: double.infinity,
                                child: Text(
                                  _predictionMessage,
                                  style: GoogleFonts.poppins(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                    color: Theme.of(context).brightness ==
                                            Brightness.dark
                                        ? Colors.white
                                        : Colors.black87,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                          Expanded(
                            child: _image == null
                                ? SingleChildScrollView(
                                    child: Column(
                                      children: [
                                        FadeIn(
                                          child: CarouselSlider(
                                            options: CarouselOptions(
                                              height: 200.0,
                                              autoPlay: true,
                                              autoPlayInterval:
                                                  const Duration(seconds: 3),
                                              enlargeCenterPage: true,
                                              aspectRatio: 16 / 9,
                                              viewportFraction: 0.8,
                                            ),
                                            items: [
                                              'assets/images/carousel1.jpg',
                                              'assets/images/carousel2.png',
                                              'assets/images/carousel3.png',
                                            ].map((imagePath) {
                                              return Builder(
                                                builder:
                                                    (BuildContext context) {
                                                  return Container(
                                                    margin: const EdgeInsets
                                                        .symmetric(
                                                      horizontal: 8.0,
                                                      vertical: 4.0,
                                                    ),
                                                    decoration: BoxDecoration(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              12),
                                                      image: DecorationImage(
                                                        image: AssetImage(
                                                            imagePath),
                                                        fit: BoxFit.cover,
                                                      ),
                                                    ),
                                                  );
                                                },
                                              );
                                            }).toList(),
                                          ),
                                        ),
                                        FadeIn(
                                          child: Card(
                                            elevation: 4,
                                            margin: const EdgeInsets.symmetric(
                                                horizontal: 16, vertical: 8.0),
                                            shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(12)),
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.all(16.0),
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    'Chào mừng bạn đến với Nhận diện Côn trùng',
                                                    style: GoogleFonts.poppins(
                                                      fontSize: 18,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: Theme.of(context)
                                                              .textTheme
                                                              .bodyLarge
                                                              ?.color ??
                                                          Colors.black87,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 8),
                                                  Text(
                                                    'Nhanh chóng nhận diện các côn trùng có hại cho cây trồng với công nghệ AI tiên tiến. Tải ảnh lên hoặc chụp ảnh để bắt đầu!',
                                                    style: GoogleFonts.poppins(
                                                      fontSize: 14,
                                                      color: Theme.of(context)
                                                              .textTheme
                                                              .bodyLarge
                                                              ?.color ??
                                                          Colors.black87,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 16),
                                                  Center(
                                                    child: _buildActionButton(
                                                      icon: Icons.camera_alt,
                                                      label:
                                                          'Bắt đầu nhận diện',
                                                      onPressed:
                                                          _startDetection,
                                                      gradient: true,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                        FadeIn(
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 16, vertical: 8.0),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment
                                                          .spaceBetween,
                                                  children: [
                                                    Text(
                                                      'Danh sách côn trùng',
                                                      style:
                                                          GoogleFonts.poppins(
                                                        fontSize: 16,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        color: Theme.of(context)
                                                                .textTheme
                                                                .bodyLarge
                                                                ?.color ??
                                                            Colors.black87,
                                                      ),
                                                    ),
                                                    TextButton(
                                                      onPressed: () {
                                                        setState(() {
                                                          _isInsectListExpanded =
                                                              !_isInsectListExpanded;
                                                        });
                                                      },
                                                      child: Text(
                                                        _isInsectListExpanded
                                                            ? 'Thu gọn'
                                                            : 'Xem thêm',
                                                        style:
                                                            GoogleFonts.poppins(
                                                          fontSize: 14,
                                                          color: Colors.blue,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 8),
                                                GridView.builder(
                                                  shrinkWrap: true,
                                                  physics:
                                                      const NeverScrollableScrollPhysics(),
                                                  gridDelegate:
                                                      const SliverGridDelegateWithFixedCrossAxisCount(
                                                    crossAxisCount: 2,
                                                    crossAxisSpacing: 8,
                                                    mainAxisSpacing: 8,
                                                    childAspectRatio: 0.75,
                                                  ),
                                                  itemCount: _isInsectListExpanded
                                                      ? _insectData.length
                                                      : 4, // Hiển thị 2 mục khi rút gọn
                                                  itemBuilder:
                                                      (context, index) {
                                                    final insect =
                                                        _insectData[index];
                                                    return Card(
                                                      elevation: 4,
                                                      shape:
                                                          RoundedRectangleBorder(
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(12),
                                                      ),
                                                      child: InkWell(
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(12),
                                                        onTap: () =>
                                                            Navigator.push(
                                                          context,
                                                          MaterialPageRoute(
                                                            builder: (_) =>
                                                                InsectDetailScreen(
                                                                    insect:
                                                                        insect),
                                                          ),
                                                        ),
                                                        child: Column(
                                                          children: [
                                                            ClipRRect(
                                                              borderRadius:
                                                                  const BorderRadius
                                                                      .vertical(
                                                                top: Radius
                                                                    .circular(
                                                                        12),
                                                              ),
                                                              child:
                                                                  Image.asset(
                                                                insect['image_path'] ??
                                                                    'assets/images/default_insect.png',
                                                                height: 120,
                                                                width: double
                                                                    .infinity,
                                                                fit: BoxFit
                                                                    .cover,
                                                                errorBuilder:
                                                                    (context,
                                                                        error,
                                                                        stackTrace) {
                                                                  print(
                                                                      'Error loading insect image: ${insect['image_path']}');
                                                                  return const Icon(
                                                                      Icons
                                                                          .error,
                                                                      size: 60);
                                                                },
                                                              ),
                                                            ),
                                                            Padding(
                                                              padding:
                                                                  const EdgeInsets
                                                                      .all(8.0),
                                                              child: Column(
                                                                crossAxisAlignment:
                                                                    CrossAxisAlignment
                                                                        .start,
                                                                children: [
                                                                  Text(
                                                                    insect['vietnamese_name'] ??
                                                                        insect[
                                                                            'name'] ??
                                                                        'Không xác định',
                                                                    style: GoogleFonts
                                                                        .poppins(
                                                                      fontSize:
                                                                          14,
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .w600,
                                                                      color: Theme.of(context)
                                                                              .textTheme
                                                                              .bodyLarge
                                                                              ?.color ??
                                                                          Colors
                                                                              .black87,
                                                                    ),
                                                                    maxLines: 1,
                                                                    overflow:
                                                                        TextOverflow
                                                                            .ellipsis,
                                                                  ),
                                                                  const SizedBox(
                                                                      height:
                                                                          4),
                                                                  Text(
                                                                    insect['scientific_name'] ??
                                                                        'Không có thông tin',
                                                                    style: GoogleFonts
                                                                        .poppins(
                                                                      fontSize:
                                                                          12,
                                                                      color: Theme.of(context)
                                                                              .textTheme
                                                                              .bodySmall
                                                                              ?.color ??
                                                                          Colors
                                                                              .grey[600],
                                                                    ),
                                                                    maxLines: 1,
                                                                    overflow:
                                                                        TextOverflow
                                                                            .ellipsis,
                                                                  ),
                                                                  const SizedBox(
                                                                      height:
                                                                          4),
                                                                  Text(
                                                                    insect['description'] ??
                                                                        'Không có mô tả',
                                                                    style: GoogleFonts
                                                                        .poppins(
                                                                      fontSize:
                                                                          12,
                                                                      color: Theme.of(context)
                                                                              .textTheme
                                                                              .bodyLarge
                                                                              ?.color ??
                                                                          Colors
                                                                              .black87,
                                                                    ),
                                                                    maxLines: 2,
                                                                    overflow:
                                                                        TextOverflow
                                                                            .ellipsis,
                                                                  ),
                                                                ],
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    );
                                                  },
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                : SingleChildScrollView(
                                    child: FadeIn(
                                      child: Column(
                                        children: [
                                          if (_image != null &&
                                              _imageSize.width > 0 &&
                                              _imageSize.height > 0)
                                            Card(
                                              elevation: 4,
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                              ),
                                              child: LayoutBuilder(
                                                builder:
                                                    (context, constraints) {
                                                  final aspectRatio =
                                                      _imageSize.width /
                                                          _imageSize.height;
                                                  final displayWidth =
                                                      constraints.maxWidth;
                                                  final displayHeight =
                                                      displayWidth /
                                                          aspectRatio;

                                                  return ClipRRect(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            12),
                                                    child: InteractiveViewer(
                                                      minScale: 0.5,
                                                      maxScale: 4.0,
                                                      child: Container(
                                                        width: displayWidth,
                                                        height: displayHeight,
                                                        child: Image.file(
                                                          _image!,
                                                          fit: BoxFit.contain,
                                                          width: displayWidth,
                                                          height: displayHeight,
                                                          alignment:
                                                              Alignment.center,
                                                          errorBuilder:
                                                              (context, error,
                                                                  stackTrace) {
                                                            print(
                                                                'Error loading image: $error');
                                                            return const Icon(
                                                              Icons.error,
                                                              size: 100,
                                                            );
                                                          },
                                                        ),
                                                      ),
                                                    ),
                                                  );
                                                },
                                              ),
                                            )
                                          else
                                            const Center(
                                              child: SpinKitFadingCircle(
                                                  color: Colors.blue),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                          ),
                          Padding(
                            padding:
                                const EdgeInsets.fromLTRB(8.0, 8.0, 8.0, 24.0),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                              children: [
                                _buildActionButton(
                                  icon: Icons.camera_alt,
                                  label: 'Chụp ảnh',
                                  onPressed: _startDetection,
                                  gradient: true,
                                ),
                                _buildActionButton(
                                  icon: Icons.photo_library,
                                  label: 'Chọn ảnh',
                                  onPressed: _pickImage,
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
}

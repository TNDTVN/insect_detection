import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';

class ProfileScreen extends StatefulWidget {
  final int userId;
  final String initialEmail;
  final String initialProfilePicture;
  const ProfileScreen({
    super.key,
    required this.userId,
    required this.initialEmail,
    required this.initialProfilePicture,
  });

  @override
  _ProfileScreenState createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _codeController = TextEditingController();
  String _profilePicture = '';
  bool _isLoading = false;
  bool _isChangingEmail = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadUserData();
    _profilePicture = widget.initialProfilePicture;
  }

  Future<void> _loadUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final savedEmail = prefs.getString('email') ?? 'Chưa đăng nhập';
    setState(() {
      _emailController.text =
          widget.initialEmail == 'Chưa đăng nhập' || widget.initialEmail.isEmpty
              ? savedEmail
              : widget.initialEmail;
      _profilePicture = widget.initialProfilePicture;
    });
  }

  Future<void> _requestEmailCode() async {
    final prefs = await SharedPreferences.getInstance();
    final currentEmail = prefs.getString('email') ?? 'Chưa đăng nhập';
    final newEmail = _emailController.text.trim();

    if (newEmail.isEmpty || newEmail == currentEmail) {
      setState(
          () => _errorMessage = 'Vui lòng nhập email mới khác email hiện tại');
      return;
    }
    setState(() => _isLoading = true);
    try {
      final response = await http.post(
        Uri.parse('$apiBaseUrl/request_email_code'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'userId': widget.userId,
          'email': newEmail,
        }),
      );
      final data = jsonDecode(response.body);
      print('Phản hồi từ /request_email_code: ${response.statusCode} - $data');
      if (response.statusCode == 200) {
        setState(() {
          _isChangingEmail = true;
          _errorMessage = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text(data['message'] ?? 'Mã đã được gửi đến email hiện tại')),
        );
      } else {
        setState(() => _errorMessage = data['detail'] ?? 'Lỗi không xác định');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['detail'] ?? 'Lỗi không xác định')),
        );
      }
    } catch (e) {
      print('Lỗi kết nối server trong _requestEmailCode: $e');
      setState(() => _errorMessage = 'Không thể kết nối đến server');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không thể kết nối đến server')),
      );
    }
    setState(() => _isLoading = false);
  }

  Future<void> _updateEmail() async {
    final prefs = await SharedPreferences.getInstance();
    final newEmail = _emailController.text.trim();

    if (_codeController.text.trim().isEmpty) {
      setState(() => _errorMessage = 'Vui lòng nhập mã xác nhận');
      return;
    }
    setState(() => _isLoading = true);
    try {
      final response = await http.post(
        Uri.parse('$apiBaseUrl/update_email'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'userId': widget.userId,
          'email': newEmail,
          'code': _codeController.text.trim(),
        }),
      );
      final data = jsonDecode(response.body);
      print('Phản hồi từ /update_email: ${response.statusCode} - $data');
      if (response.statusCode == 200) {
        await prefs.setString('email', newEmail);
        setState(() {
          _isChangingEmail = false;
          _codeController.clear();
          _errorMessage = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['message'] ?? 'Email đã được cập nhật')),
        );
      } else {
        String errorMessage = 'Lỗi không xác định';
        if (data['detail'] is List) {
          errorMessage = (data['detail'] as List)
              .map((e) => e['msg'] as String)
              .join(', ');
        } else if (data['detail'] is String) {
          errorMessage = data['detail'];
        }
        setState(() => _errorMessage = errorMessage);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMessage)),
        );
      }
    } catch (e) {
      print('Lỗi kết nối server trong _updateEmail: $e');
      setState(() => _errorMessage = 'Không thể kết nối đến server');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không thể kết nối đến server')),
      );
    }
    setState(() => _isLoading = false);
  }

  Future<void> _updatePassword() async {
    if (_passwordController.text.trim().isEmpty ||
        _newPasswordController.text.trim().isEmpty) {
      setState(() => _errorMessage = 'Vui lòng nhập mật khẩu hiện tại và mới');
      return;
    }
    setState(() => _isLoading = true);
    try {
      final response = await http.post(
        Uri.parse('$apiBaseUrl/update_password'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'userId': widget.userId,
          'currentPassword': _passwordController.text.trim(),
          'newPassword': _newPasswordController.text.trim(),
        }),
      );
      final data = jsonDecode(response.body);
      print('Phản hồi từ /update_password: ${response.statusCode} - $data');
      if (response.statusCode == 200) {
        setState(() {
          _passwordController.clear();
          _newPasswordController.clear();
          _errorMessage = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(data['message'] ?? 'Mật khẩu đã được cập nhật')),
        );
      } else {
        setState(() => _errorMessage = data['detail'] ?? 'Lỗi không xác định');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['detail'] ?? 'Lỗi không xác định')),
        );
      }
    } catch (e) {
      print('Lỗi kết nối server trong _updatePassword: $e');
      setState(() => _errorMessage = 'Không thể kết nối đến server');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không thể kết nối đến server')),
      );
    }
    setState(() => _isLoading = false);
  }

  Future<void> _updateProfilePicture() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile == null) return;

    setState(() => _isLoading = true);
    try {
      // Tải ảnh lên server
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$apiBaseUrl/upload_image'),
      );
      request.files.add(await http.MultipartFile.fromPath(
        'file',
        pickedFile.path,
      ));
      final response = await request.send();
      final responseData = await response.stream.bytesToString();
      final data = jsonDecode(responseData);
      print(
          'Phản hồi từ /upload_image: ${response.statusCode} - $responseData');

      if (response.statusCode == 200) {
        final newImageUrl = data['image_url'];
        final prefs = await SharedPreferences.getInstance();
        final oldProfilePicture = prefs.getString('profilePicture') ??
            'http://msi.local:8000/uploads/profile.jpg';

        // Xóa ảnh đại diện cũ nếu không phải ảnh mặc định
        if (oldProfilePicture != 'http://msi.local:8000/uploads/profile.jpg' &&
            oldProfilePicture.isNotEmpty) {
          final oldImagePath = oldProfilePicture.replaceAll(
              'http://msi.local:8000/uploads/', '');
          final deleteResponse = await http.delete(
            Uri.parse('$apiBaseUrl/delete_image/$oldImagePath'),
          );
          print(
              'Phản hồi từ /delete_image: ${deleteResponse.statusCode} - ${deleteResponse.body}');
        }

        // Cập nhật profile_picture trong cơ sở dữ liệu
        final updateResponse = await http.post(
          Uri.parse('$apiBaseUrl/update_profile_picture'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'userId': widget.userId,
            'image_url': newImageUrl,
          }),
        );
        final updateData = jsonDecode(updateResponse.body);
        print(
            'Phản hồi từ /update_profile_picture: ${updateResponse.statusCode} - ${updateData}');

        if (updateResponse.statusCode == 200) {
          // Cập nhật SharedPreferences và trạng thái giao diện
          await prefs.setString('profilePicture', newImageUrl);
          setState(() {
            _profilePicture = newImageUrl;
            _errorMessage = null;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Đã cập nhật ảnh đại diện')),
          );
        } else {
          setState(() =>
              _errorMessage = updateData['detail'] ?? 'Lỗi không xác định');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(updateData['detail'] ??
                    'Lỗi khi cập nhật ảnh đại diện trong cơ sở dữ liệu')),
          );
        }
      } else {
        setState(
            () => _errorMessage = data['detail'] ?? 'Lỗi tải ảnh lên server');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(data['detail'] ?? 'Lỗi tải ảnh lên server')),
        );
      }
    } catch (e) {
      print('Lỗi kết nối server trong _updateProfilePicture: $e');
      setState(() => _errorMessage = 'Không thể kết nối đến server');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Không thể kết nối đến server')),
      );
    }
    setState(() => _isLoading = false);
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _newPasswordController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'TRANG CÁ NHÂN',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.white
                : Colors.black87,
          ),
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
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Card(
              elevation: 8,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: GestureDetector(
                        onTap: _updateProfilePicture,
                        child: CircleAvatar(
                          radius: 60,
                          backgroundImage: _profilePicture.isNotEmpty
                              ? NetworkImage(_profilePicture)
                              : const AssetImage('assets/default_profile.png')
                                  as ImageProvider,
                          child:
                              const Icon(Icons.camera_alt, color: Colors.white),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _emailController,
                      decoration: InputDecoration(
                        labelText: 'Email',
                        errorText: _errorMessage,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (!_isChangingEmail) ...[
                      ElevatedButton(
                        onPressed: _isLoading ? null : _requestEmailCode,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 16,
                          ),
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [Colors.blue, Colors.blueAccent],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.all(Radius.circular(12)),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: Text(
                            'Thay đổi email',
                            style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ] else ...[
                      const SizedBox(height: 16),
                      TextField(
                        controller: _codeController,
                        decoration: InputDecoration(
                          labelText: 'Mã xác nhận',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton(
                              onPressed: _isLoading ? null : _updateEmail,
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 16,
                                ),
                                backgroundColor: Colors.transparent,
                                shadowColor: Colors.transparent,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: Container(
                                decoration: const BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [Colors.blue, Colors.blueAccent],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius:
                                      BorderRadius.all(Radius.circular(12)),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                child: Text(
                                  'Xác nhận email',
                                  style: GoogleFonts.poppins(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: () => setState(() {
                              _isChangingEmail = false;
                              _codeController.clear();
                            }),
                            child: Text(
                              'Hủy',
                              style: GoogleFonts.poppins(
                                color: Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? Colors.white70
                                    : Colors.blue[600],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 16),
                    TextField(
                      controller: _passwordController,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: 'Mật khẩu hiện tại',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _newPasswordController,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: 'Mật khẩu mới',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _isLoading ? null : _updatePassword,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 16,
                        ),
                        backgroundColor: Colors.transparent,
                        shadowColor: Colors.transparent,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Container(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Colors.blue, Colors.blueAccent],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.all(Radius.circular(12)),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: Text(
                          'Thay đổi mật khẩu',
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                    if (_errorMessage != null) const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ),
          if (_isLoading)
            Container(
              color: Colors.black54,
              child: const Center(
                child: CircularProgressIndicator(
                  color: Colors.blue,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

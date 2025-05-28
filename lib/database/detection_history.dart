import 'dart:convert';

import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class DetectionHistory {
  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final path = join(await getDatabasesPath(), 'detection_history.db');
    return openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE detections (
            id INTEGER PRIMARY KEY,
            user_id INTEGER,
            image_url TEXT,
            detections TEXT,
            image_size TEXT,
            timestamp TEXT
          )
        ''');
      },
    );
  }

  Future<void> saveDetection(
    int userId,
    String imageUrl,
    List<Map<String, dynamic>> detections,
    Map<String, double> imageSize, {
    int? serverId,
    String? timestamp,
  }) async {
    // Kiểm tra và lọc detections hợp lệ
    final validDetections = detections.where((d) {
      final isValid = d.containsKey('class') &&
          d.containsKey('confidence') &&
          d.containsKey('box') &&
          (d['box'] as List<dynamic>?)?.length == 4;
      if (!isValid) {
        print('Bỏ qua detection không hợp lệ khi lưu: $d');
      }
      return isValid;
    }).toList();

    print(
        'Lưu detection: userId=$userId, imageUrl=$imageUrl, validDetections=$validDetections');
    final db = await database;
    await db.insert(
      'detections',
      {
        if (serverId != null) 'id': serverId,
        'user_id': userId,
        'image_url': imageUrl,
        'detections': jsonEncode(validDetections),
        'image_size': jsonEncode(imageSize),
        'timestamp': timestamp ?? DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getDetections(int userId) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'detections',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'timestamp DESC',
    );
    final result = maps.map((map) {
      try {
        final detections = jsonDecode(map['detections']);
        // Kiểm tra và lọc detections hợp lệ
        final validDetections = (detections as List<dynamic>)
            .where((d) {
              final isValid = d is Map &&
                  d.containsKey('class') &&
                  d.containsKey('confidence') &&
                  d.containsKey('box') &&
                  (d['box'] as List<dynamic>?)?.length == 4;
              if (!isValid) {
                print('Bỏ qua detection không hợp lệ khi lấy: $d');
              }
              return isValid;
            })
            .cast<Map<String, dynamic>>()
            .toList();
        return {
          'id': map['id'],
          'user_id': map['user_id'],
          'image_url': map['image_url'],
          'detections': validDetections,
          'image_size': jsonDecode(map['image_size']),
          'timestamp': map['timestamp'],
        };
      } catch (e) {
        print('Lỗi giải mã detection: $map, lỗi: $e');
        return {
          'id': map['id'],
          'user_id': map['user_id'],
          'image_url': map['image_url'],
          'detections': [],
          'image_size': jsonDecode(map['image_size']),
          'timestamp': map['timestamp'],
        };
      }
    }).toList();
    print('Lấy detections: $result');
    return result;
  }

  Future<void> deleteDetection(int id) async {
    final db = await database;
    await db.delete(
      'detections',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> clearDetectionsForUser(int userId) async {
    final db = await database;
    await db.delete(
      'detections',
      where: 'user_id = ?',
      whereArgs: [userId],
    );
  }
}

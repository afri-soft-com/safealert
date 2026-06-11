import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class LocalDatabase {
  static final LocalDatabase _instance = LocalDatabase._();
  LocalDatabase._();
  factory LocalDatabase() => _instance;

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _init();
    return _db!;
  }

  Future<Database> _init() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'safealert_cache.db');
    return openDatabase(
      path,
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE cache (
            key TEXT PRIMARY KEY,
            data TEXT NOT NULL,
            cached_at INTEGER NOT NULL
          )
        ''');
      },
    );
  }

  Future<void> put(String key, dynamic data, {int? ttlSeconds}) async {
    final db = await database;
    await db.insert('cache', {
      'key': key,
      'data': jsonEncode(data),
      'cached_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<dynamic> get(String key, {int? maxAgeSeconds}) async {
    final db = await database;
    final rows = await db.query('cache', where: 'key = ?', whereArgs: [key]);
    if (rows.isEmpty) return null;

    final row = rows.first;
    if (maxAgeSeconds != null) {
      final age = DateTime.now().millisecondsSinceEpoch - (row['cached_at'] as int);
      if (age > maxAgeSeconds * 1000) {
        await db.delete('cache', where: 'key = ?', whereArgs: [key]);
        return null;
      }
    }
    return jsonDecode(row['data'] as String);
  }

  Future<void> remove(String key) async {
    final db = await database;
    await db.delete('cache', where: 'key = ?', whereArgs: [key]);
  }

  Future<void> clear() async {
    final db = await database;
    await db.delete('cache');
  }
}
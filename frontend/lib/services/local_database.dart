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
      version: 4,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE cache (
            key TEXT PRIMARY KEY,
            data TEXT NOT NULL,
            cached_at INTEGER NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE pending_queue (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            kind TEXT NOT NULL,
            payload TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            attempts INTEGER NOT NULL DEFAULT 0,
            next_attempt_at INTEGER NOT NULL DEFAULT 0
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS pending_sos (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              payload TEXT NOT NULL,
              created_at INTEGER NOT NULL,
              attempts INTEGER NOT NULL DEFAULT 0
            )
          ''');
        }
        if (oldVersion < 3) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS pending_queue (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              kind TEXT NOT NULL,
              payload TEXT NOT NULL,
              created_at INTEGER NOT NULL,
              attempts INTEGER NOT NULL DEFAULT 0
            )
          ''');
          try {
            final rows = await db.query('pending_sos');
            for (final r in rows) {
              await db.insert('pending_queue', {
                'kind': 'sos',
                'payload': r['payload'],
                'created_at': r['created_at'],
                'attempts': r['attempts'] ?? 0,
              });
            }
          } catch (_) {}
        }
        if (oldVersion < 4) {
          try {
            await db.execute(
              'ALTER TABLE pending_queue ADD COLUMN next_attempt_at INTEGER NOT NULL DEFAULT 0',
            );
          } catch (_) {}
        }
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

  Future<int> enqueuePendingSos(Map<String, dynamic> payload) async {
    return enqueue('sos', payload);
  }

  Future<int> enqueue(String kind, Map<String, dynamic> payload) async {
    final db = await database;
    return db.insert('pending_queue', {
      'kind': kind,
      'payload': jsonEncode(payload),
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'attempts': 0,
      'next_attempt_at': 0,
    });
  }

  Future<List<Map<String, dynamic>>> listPendingSos() async {
    final all = await listPending(kind: 'sos');
    return all;
  }

  Future<List<Map<String, dynamic>>> listPending({String? kind, bool dueOnly = false}) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    final rows = kind == null
        ? await db.query('pending_queue', orderBy: 'created_at ASC')
        : await db.query('pending_queue', where: 'kind = ?', whereArgs: [kind], orderBy: 'created_at ASC');
    return rows
        .where((r) {
          if (!dueOnly) return true;
          final next = (r['next_attempt_at'] as int?) ?? 0;
          return next <= now;
        })
        .map((r) => {
              'id': r['id'],
              'kind': r['kind'],
              'payload': jsonDecode(r['payload'] as String) as Map<String, dynamic>,
              'attempts': r['attempts'],
              'next_attempt_at': r['next_attempt_at'] ?? 0,
            })
        .toList();
  }

  Future<void> removePendingSos(int id) async {
    await removePending(id);
  }

  Future<void> removePending(int id) async {
    final db = await database;
    await db.delete('pending_queue', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> bumpPendingSosAttempt(int id) async {
    await bumpPendingAttempt(id);
  }

  /// Exponential backoff: 30s, 60s, 120s, … capped at 30 min.
  Future<void> bumpPendingAttempt(int id) async {
    final db = await database;
    final rows = await db.query('pending_queue', where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return;
    final attempts = ((rows.first['attempts'] as int?) ?? 0) + 1;
    final delaySec = (30 * (1 << (attempts - 1).clamp(0, 6))).clamp(30, 1800);
    final nextAt = DateTime.now().millisecondsSinceEpoch + delaySec * 1000;
    await db.update(
      'pending_queue',
      {'attempts': attempts, 'next_attempt_at': nextAt},
      where: 'id = ?',
      whereArgs: [id],
    );
  }
}

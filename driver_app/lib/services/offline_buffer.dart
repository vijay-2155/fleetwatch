// lib/services/offline_buffer.dart
// SQLite-based offline GPS buffer.
// When MQTT is disconnected, events are written here.
// On reconnect, events are flushed in order and marked synced.

import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/truck_event.dart';

class OfflineBuffer {
  static Database? _db;
  static const _tableName = 'gps_buffer';
  static const _maxBufferSize = 10000; // ~27 hours of 10s pings

  static Future<Database> get db async {
    if (_db != null) return _db!;
    _db = await _initDb();
    return _db!;
  }

  static Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    return openDatabase(
      join(dbPath, 'fleet_tracker.db'),
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $_tableName (
            id        INTEGER PRIMARY KEY AUTOINCREMENT,
            vid       TEXT NOT NULL,
            did       TEXT NOT NULL,
            tid       TEXT NOT NULL,
            lat       REAL NOT NULL,
            lng       REAL NOT NULL,
            spd       REAL NOT NULL,
            brg       REAL NOT NULL,
            acc       REAL NOT NULL,
            ts        INTEGER NOT NULL,
            bat       INTEGER NOT NULL,
            src       TEXT NOT NULL DEFAULT 'mobile',
            synced    INTEGER NOT NULL DEFAULT 0,
            created_at INTEGER NOT NULL DEFAULT (strftime('%s', 'now'))
          )
        ''');
        // Index for fast unsynced query
        await db.execute(
          'CREATE INDEX idx_synced ON $_tableName(synced, id)',
        );
      },
    );
  }

  /// Write a single event to buffer
  static Future<void> write(TruckEvent event) async {
    final database = await db;

    // Prevent runaway buffer growth (network completely dead for days)
    final count = Sqflite.firstIntValue(
      await database.rawQuery('SELECT COUNT(*) FROM $_tableName WHERE synced = 0'),
    ) ?? 0;

    if (count >= _maxBufferSize) {
      // Drop oldest unsynced event — we prefer recent data
      await database.rawDelete(
        'DELETE FROM $_tableName WHERE id = (SELECT MIN(id) FROM $_tableName WHERE synced = 0)',
      );
    }

    await database.insert(_tableName, event.toDbMap());
  }

  /// Get all unsynced events in order (oldest first)
  static Future<List<Map<String, dynamic>>> getUnsynced({int limit = 500}) async {
    final database = await db;
    return database.query(
      _tableName,
      where: 'synced = 0',
      orderBy: 'id ASC',
      limit: limit,
    );
  }

  /// Mark a batch of events as synced after successful MQTT publish
  static Future<void> markSynced(List<int> ids) async {
    if (ids.isEmpty) return;
    final database = await db;
    final placeholders = ids.map((_) => '?').join(',');
    await database.rawUpdate(
      'UPDATE $_tableName SET synced = 1 WHERE id IN ($placeholders)',
      ids,
    );
  }

  /// Clean up old synced events (run periodically, e.g., every 6 hours)
  static Future<void> cleanup() async {
    final database = await db;
    // Delete synced events older than 24 hours
    final cutoff = DateTime.now()
        .subtract(const Duration(hours: 24))
        .millisecondsSinceEpoch ~/
        1000;
    await database.rawDelete(
      'DELETE FROM $_tableName WHERE synced = 1 AND created_at < ?',
      [cutoff],
    );
  }

  /// How many events are pending sync — for UI display
  static Future<int> pendingCount() async {
    final database = await db;
    return Sqflite.firstIntValue(
          await database.rawQuery(
            'SELECT COUNT(*) FROM $_tableName WHERE synced = 0',
          ),
        ) ??
        0;
  }
}

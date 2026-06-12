import 'package:sqflite/sqflite.dart';

import '../domain/app_models.dart';
import 'app_database.dart';
import 'model_codec.dart';

class ModelRepository {
  ModelRepository(this._database);

  final AppDatabase _database;

  Future<List<AiModelOption>> listModels() async {
    final db = await _database.instance;
    final rows = await db.rawQuery('''
SELECT m.id, m.provider_id, m.name, m.capabilities, m.enabled, p.name AS provider_name
FROM ai_model_options m
JOIN provider_profiles p ON p.id = m.provider_id
WHERE m.enabled = 1 AND p.user_configured = 1
ORDER BY p.name ASC, m.name ASC
''');
    return rows.map(_decodeModel).toList();
  }

  Future<List<AiModelOption>> listModelsForProvider(String providerId) async {
    final db = await _database.instance;
    final rows = await db.rawQuery(
      '''
SELECT m.id, m.provider_id, m.name, m.capabilities, m.enabled, p.name AS provider_name
FROM ai_model_options m
JOIN provider_profiles p ON p.id = m.provider_id
WHERE m.enabled = 1 AND p.user_configured = 1 AND m.provider_id = ?
ORDER BY m.name ASC
''',
      [providerId],
    );
    return rows.map(_decodeModel).toList();
  }

  Future<void> saveModel({
    required String providerId,
    required String name,
    required Set<ModelCapability> capabilities,
  }) async {
    final db = await _database.instance;
    final now = DateTime.now().toUtc().toIso8601String();
    final id = '$providerId:${name.trim()}';
    await db.insert('ai_model_options', {
      'id': id,
      'provider_id': providerId,
      'name': name.trim(),
      'capabilities': capabilities.map(encodeModelCapability).join(','),
      'enabled': encodeBool(true),
      'created_at': now,
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> replaceModelsForProvider({
    required String providerId,
    required Iterable<({String name, Set<ModelCapability> capabilities})>
    models,
  }) async {
    final db = await _database.instance;
    final now = DateTime.now().toUtc().toIso8601String();
    final normalized = [
      for (final model in models)
        if (model.name.trim().isNotEmpty && model.capabilities.isNotEmpty)
          (
            id: '$providerId:${model.name.trim()}',
            name: model.name.trim(),
            capabilities: model.capabilities,
          ),
    ];

    await db.transaction((txn) async {
      if (normalized.isEmpty) {
        await txn.delete(
          'model_assignments',
          where: 'provider_id = ?',
          whereArgs: [providerId],
        );
        await txn.delete(
          'ai_model_options',
          where: 'provider_id = ?',
          whereArgs: [providerId],
        );
        return;
      }

      final ids = normalized.map((model) => model.id).toList();
      final placeholders = List.filled(ids.length, '?').join(', ');
      await txn.delete(
        'model_assignments',
        where: 'provider_id = ? AND model_id NOT IN ($placeholders)',
        whereArgs: [providerId, ...ids],
      );
      await txn.delete(
        'ai_model_options',
        where: 'provider_id = ? AND id NOT IN ($placeholders)',
        whereArgs: [providerId, ...ids],
      );

      for (final model in normalized) {
        await txn.insert('ai_model_options', {
          'id': model.id,
          'provider_id': providerId,
          'name': model.name,
          'capabilities': model.capabilities
              .map(encodeModelCapability)
              .join(','),
          'enabled': encodeBool(true),
          'created_at': now,
          'updated_at': now,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  AiModelOption _decodeModel(Map<String, Object?> row) {
    return AiModelOption(
      id: row['id'] as String,
      providerId: row['provider_id'] as String,
      providerName: row['provider_name'] as String,
      name: row['name'] as String,
      enabled: decodeBool(row['enabled']),
      capabilities: (row['capabilities'] as String)
          .split(',')
          .map((value) => decodeModelCapability(value.trim()))
          .whereType<ModelCapability>()
          .toSet(),
    );
  }
}

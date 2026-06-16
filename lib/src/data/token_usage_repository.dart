import '../domain/app_models.dart';
import 'app_database.dart';
import 'model_codec.dart';

class TokenUsageRepository {
  TokenUsageRepository(this._database);

  final AppDatabase _database;

  Future<List<TokenUsageRecord>> listRecords() async {
    final db = await _database.instance;
    final rows = await db.query('token_usage', orderBy: 'created_at DESC');
    return rows.map(_decode).toList();
  }

  Future<void> insertRecord({
    required String provider,
    required String model,
    required String taskType,
    required TokenUsage? usage,
  }) async {
    final db = await _database.instance;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.insert('token_usage', {
      'id': newLocalId('tu'),
      'created_at': now,
      'provider': provider,
      'model': model,
      'task_type': taskType,
      'prompt_tokens': usage?.promptTokens,
      'completion_tokens': usage?.completionTokens,
      'total_tokens': usage?.totalTokens,
    });
  }

  Future<void> clearAll() async {
    final db = await _database.instance;
    await db.delete('token_usage');
  }

  TokenUsageRecord _decode(Map<String, Object?> row) {
    return TokenUsageRecord(
      id: row['id'] as String,
      createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
      provider: row['provider'] as String,
      model: row['model'] as String,
      taskType: row['task_type'] as String,
      promptTokens: row['prompt_tokens'] as int?,
      completionTokens: row['completion_tokens'] as int?,
      totalTokens: row['total_tokens'] as int?,
    );
  }
}

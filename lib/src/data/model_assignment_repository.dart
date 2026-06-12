import 'package:sqflite/sqflite.dart';

import '../domain/app_models.dart';
import 'app_database.dart';
import 'model_codec.dart';

class ModelAssignmentRepository {
  ModelAssignmentRepository(this._database);

  final AppDatabase _database;

  Future<List<ModelAssignment>> listAssignments() async {
    final db = await _database.instance;
    final rows = await db.query('model_assignments', orderBy: 'task ASC');
    return rows.map(_decodeAssignment).toList();
  }

  Future<void> saveAssignment(ModelAssignment assignment) async {
    final db = await _database.instance;
    await db.insert('model_assignments', {
      'task': encodeModelAssignmentTask(assignment.task),
      'provider_id': assignment.providerId,
      'model_id': assignment.modelId,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  ModelAssignment _decodeAssignment(Map<String, Object?> row) {
    return ModelAssignment(
      task: decodeModelAssignmentTask(row['task'] as String?),
      providerId: row['provider_id'] as String,
      modelId: row['model_id'] as String,
    );
  }
}

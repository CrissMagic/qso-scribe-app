import 'package:flutter_test/flutter_test.dart';
import 'package:qso_scribe_app/src/data/app_database.dart';
import 'package:qso_scribe_app/src/data/export_service.dart';
import 'package:qso_scribe_app/src/data/qso_repository.dart';
import 'package:qso_scribe_app/src/domain/app_models.dart';

void main() {
  test(
    'generated export reports exactly the persisted QSO ids it contains',
    () async {
      final service = ExportService(
        _FakeQsoRepository([
          _qso(id: 'qso-1', callsign: 'BA1ABC'),
          _qso(id: 'qso-2', callsign: 'K1ABC'),
        ]),
      );

      final generated = await service.exportAdif(const ExportFilter());

      expect(generated.qsoIds, ['qso-1', 'qso-2']);
      expect(generated.content, contains('<CALL:6>BA1ABC'));
      expect(generated.content, contains('<CALL:5>K1ABC'));
    },
  );

  for (final format in ['ADIF', 'CSV', 'raw transcript']) {
    test(
      '$format export only makes confirmed QSO versions eligible for status updates',
      () async {
        final version = DateTime.utc(2026, 7, 10, 8, 31);
        final service = ExportService(
          _FakeQsoRepository([
            _qso(id: 'confirmed', callsign: 'BA1ABC', updatedAt: version),
            _qso(
              id: 'needs-review',
              callsign: 'K1ABC',
              status: LogStatus.needsReview,
            ),
            _qso(id: 'failed', callsign: 'JA1ABC', status: LogStatus.failed),
            _qso(id: 'exported', callsign: 'W1ABC', status: LogStatus.exported),
          ]),
        );

        final generated = switch (format) {
          'ADIF' => await service.exportAdif(const ExportFilter()),
          'CSV' => await service.exportCsv(const ExportFilter()),
          _ => await service.exportRawTranscript(const ExportFilter()),
        };

        expect(generated.qsoIds, [
          'confirmed',
          'needs-review',
          'failed',
          'exported',
        ]);
        expect(generated.confirmedQsoVersions, {'confirmed': version});
      },
    );
  }
}

class _FakeQsoRepository extends QsoRepository {
  _FakeQsoRepository(this.qsos) : super(AppDatabase());

  final List<QsoDraft> qsos;

  @override
  Future<List<QsoDraft>> listQsos([QsoQuery query = const QsoQuery()]) async =>
      qsos;
}

QsoDraft _qso({
  required String id,
  required String callsign,
  LogStatus status = LogStatus.confirmed,
  DateTime? updatedAt,
}) {
  return QsoDraft(
    id: id,
    callsign: QsoField(value: callsign),
    dateTime: QsoField(value: DateTime.utc(2026, 7, 10, 8, 30)),
    band: const QsoField(value: '20m'),
    frequency: const QsoField(value: '14.250'),
    mode: const QsoField(value: 'SSB'),
    sentRst: const QsoField(value: '59'),
    receivedRst: const QsoField(value: '57'),
    status: status,
    updatedAt: updatedAt ?? DateTime.utc(2026, 7, 10, 8, 30),
  );
}

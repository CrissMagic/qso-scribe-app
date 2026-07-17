import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qso_scribe_app/l10n/generated/app_localizations.dart';
import 'package:qso_scribe_app/src/data/app_database.dart';
import 'package:qso_scribe_app/src/data/qso_repository.dart';
import 'package:qso_scribe_app/src/domain/app_models.dart';
import 'package:qso_scribe_app/src/state/app_state.dart';
import 'package:qso_scribe_app/src/ui/screens.dart';

void main() {
  testWidgets('低置信度字段显示来源并可显式确认', (tester) async {
    final repository = _CapturingQsoRepository();
    final draft = QsoDraft(
      callsign: const QsoField(
        value: 'K1ABC',
        confidence: 0.6,
        sourceText: 'Kilo One Alpha Bravo Charlie',
      ),
      dateTime: QsoField(value: DateTime(2026, 7, 17, 9, 30)),
      band: const QsoField(value: '20m'),
      frequency: const QsoField(value: '14.250'),
      mode: const QsoField(value: 'SSB'),
      sentRst: const QsoField(value: '59'),
      receivedRst: const QsoField(value: '57'),
      status: LogStatus.needsReview,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appSettingsProvider.overrideWith(_TestAppSettingsNotifier.new),
          stationEquipmentProvider.overrideWith(
            _EmptyStationEquipmentNotifier.new,
          ),
          qsoRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: QsoReviewScreen(draft: draft),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Review required'), findsOneWidget);
    expect(
      find.text('Source excerpt: Kilo One Alpha Bravo Charlie'),
      findsOneWidget,
    );

    await tester.tap(find.text('Confirm correct'));
    await tester.pump();

    expect(find.text('Review required'), findsNothing);
    expect(find.textContaining('Source excerpt:'), findsNothing);

    await tester.tap(find.text('Confirm and save'));
    await tester.pumpAndSettle();

    expect(repository.saved?.callsign.reviewed, isTrue);
    expect(repository.saved?.callsign.userEdited, isFalse);
    expect(repository.saved?.callsign.confidence, 0.6);
    expect(
      repository.saved?.callsign.sourceText,
      'Kilo One Alpha Bravo Charlie',
    );
    expect(repository.saved?.band.userEdited, isFalse);
  });

  testWidgets('人工编辑字段保留原置信度与来源并写入编辑状态', (tester) async {
    final repository = _CapturingQsoRepository();
    final draft = QsoDraft(
      callsign: const QsoField(
        value: 'K1ABC',
        confidence: 0.6,
        sourceText: 'Kilo One Alpha Bravo Charlie',
      ),
      dateTime: QsoField(value: DateTime(2026, 7, 17, 9, 30)),
      band: const QsoField(value: '20m'),
      frequency: const QsoField(value: '14.250'),
      mode: const QsoField(value: 'SSB'),
      sentRst: const QsoField(value: '59'),
      receivedRst: const QsoField(value: '57'),
      status: LogStatus.needsReview,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appSettingsProvider.overrideWith(_TestAppSettingsNotifier.new),
          stationEquipmentProvider.overrideWith(
            _EmptyStationEquipmentNotifier.new,
          ),
          qsoRepositoryProvider.overrideWithValue(repository),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: QsoReviewScreen(draft: draft),
        ),
      ),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextFormField).first, 'N0CALL');
    await tester.tap(find.text('Confirm and save'));
    await tester.pumpAndSettle();

    expect(repository.saved?.callsign.value, 'N0CALL');
    expect(repository.saved?.callsign.userEdited, isTrue);
    expect(repository.saved?.callsign.reviewed, isTrue);
    expect(repository.saved?.callsign.confidence, 0.6);
    expect(
      repository.saved?.callsign.sourceText,
      'Kilo One Alpha Bravo Charlie',
    );
  });

  testWidgets('未复核字段存在时 QRZ 上传不可用', (tester) async {
    final draft = QsoDraft(
      id: 'qso-test',
      callsign: const QsoField(value: 'K1ABC', confidence: 0.6),
      dateTime: QsoField(value: DateTime(2026, 7, 17, 9, 30)),
      band: const QsoField(value: '20m'),
      frequency: const QsoField(value: '14.250'),
      mode: const QsoField(value: 'SSB'),
      sentRst: const QsoField(value: '59'),
      receivedRst: const QsoField(value: '57'),
      status: LogStatus.confirmed,
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appSettingsProvider.overrideWith(_TestAppSettingsNotifier.new),
          stationEquipmentProvider.overrideWith(
            _EmptyStationEquipmentNotifier.new,
          ),
          qrzUploadProvider.overrideWith((ref, id) async => null),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: QsoReviewScreen(draft: draft),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final uploadButton = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Upload'),
    );
    expect(uploadButton.onPressed, isNull);
    expect(
      find.text(
        'Unreviewed fields remain; this QSO cannot be saved as confirmed',
      ),
      findsOneWidget,
    );
  });
}

class _TestAppSettingsNotifier extends AppSettingsNotifier {
  @override
  Future<AppSettings> build() async => const AppSettings.defaults();
}

class _EmptyStationEquipmentNotifier extends StationEquipmentNotifier {
  @override
  Future<List<StationEquipment>> build() async => const [];
}

class _CapturingQsoRepository extends QsoRepository {
  _CapturingQsoRepository() : super(AppDatabase());

  QsoDraft? saved;

  @override
  Future<String> saveQso(QsoDraft qso) async {
    saved = qso.copyWith(id: qso.id ?? 'qso-test');
    return saved!.id!;
  }

  @override
  Future<List<QsoDraft>> listQsos([QsoQuery query = const QsoQuery()]) async =>
      [?saved];
}

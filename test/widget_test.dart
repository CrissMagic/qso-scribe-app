import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:qso_scribe_app/l10n/generated/app_localizations.dart';
import 'package:qso_scribe_app/src/domain/app_models.dart';
import 'package:qso_scribe_app/src/services/release_info_service.dart';
import 'package:qso_scribe_app/src/state/app_state.dart';
import 'package:qso_scribe_app/src/ui/qso_scribe_app.dart';
import 'package:qso_scribe_app/src/ui/screens.dart';
import 'package:qso_scribe_app/src/ui/theme.dart';

void main() {
  testWidgets('shows first-run setup screen', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: QsoScribeApp()));
    await tester.pumpAndSettle();

    expect(find.text('Initial Setup'), findsOneWidget);
  });

  testWidgets('启动更新提示在录音时不会离开记录页', (tester) async {
    PackageInfo.setMockInitialValues(
      appName: 'QSO Scribe',
      packageName: 'com.example.qso_scribe_app',
      version: '0.1.6',
      buildNumber: '7',
      buildSignature: '',
    );
    final releaseInfo = ReleaseInfoService(
      httpClient: MockClient(
        (_) async => http.Response('''
          {
            "tag_name": "v0.1.7+8",
            "html_url": "https://github.com/CrissMagic/qso-scribe-app/releases/tag/v0.1.7+8",
            "assets": [{
              "name": "qso-scribe-app-0.1.7-build8-android.apk",
              "browser_download_url": "https://github.com/CrissMagic/qso-scribe-app/releases/download/v0.1.7+8/qso-scribe-app-0.1.7-build8-android.apk"
            }]
          }
        ''', 200),
      ),
    );
    addTearDown(releaseInfo.close);
    final recorder = RecordingSessionNotifier();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appSettingsProvider.overrideWith(_TestAppSettingsNotifier.new),
          releaseInfoServiceProvider.overrideWithValue(releaseInfo),
          recordingSessionProvider.overrideWith(() => recorder),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: buildAppTheme(Brightness.light),
          home: const MainShell(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('A new version is available'), findsOneWidget);

    recorder.setSession(
      const RecordingSessionState(
        isRecording: true,
        elapsed: Duration(seconds: 8),
        mode: TranscriptionMode.afterQso,
      ),
    );
    await tester.pump();
    await tester.tap(find.text('View'));
    await tester.pumpAndSettle();

    expect(find.byType(SoftwareUpdateScreen), findsNothing);
    expect(find.text('End recording'), findsOneWidget);
  });

  testWidgets('实时页默认折叠结构化草稿并在气泡显示双方呼号', (tester) async {
    final draft = QsoDraft(
      callsign: const QsoField(value: 'K1ABC', confidence: 0.9),
      dateTime: QsoField(value: DateTime(2026, 7, 22, 9, 30)),
      band: const QsoField(value: '20m'),
      frequency: const QsoField(value: '14.250'),
      mode: const QsoField(value: 'SSB'),
      sentRst: const QsoField(value: '59'),
      receivedRst: const QsoField(value: '57'),
      status: LogStatus.needsReview,
    );
    final capture = QsoCaptureState(
      currentDraft: draft,
      transcriptSegments: const [
        TranscriptSegment(
          id: 'self',
          speaker: TranscriptSpeaker.self,
          text: 'CQ CQ',
          isFinal: true,
        ),
        TranscriptSegment(
          id: 'other',
          speaker: TranscriptSpeaker.other,
          text: 'K1ABC returning',
          isFinal: true,
        ),
      ],
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          transcriptionModeProvider.overrideWithValue(
            TranscriptionMode.streaming,
          ),
          callsignProvider.overrideWithValue('BA1SELF'),
          qsoCaptureProvider.overrideWith(
            () => _StaticQsoCaptureNotifier(capture),
          ),
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
          theme: buildAppTheme(Brightness.light),
          home: const RecordScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('My station · BA1SELF'), findsOneWidget);
    expect(find.text('Other station · K1ABC'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(find.text('Current QSO draft'), findsOneWidget);
    expect(find.text('Sent RST'), findsNothing);

    await tester.tap(find.text('Current QSO draft'));
    await tester.pumpAndSettle();

    expect(find.text('Sent RST'), findsOneWidget);
  });

  testWidgets('窄屏放大文字时日志区分选中和待确认', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final log = QsoDraft(
      callsign: const QsoField(value: 'BH8HGF'),
      dateTime: QsoField(value: DateTime(2026, 7, 22, 9, 30)),
      band: const QsoField(value: '20m'),
      frequency: const QsoField(value: '14.250'),
      mode: const QsoField(value: 'SSB'),
      sentRst: const QsoField(value: '59'),
      receivedRst: const QsoField(value: ''),
      status: LogStatus.needsReview,
    );

    for (final brightness in Brightness.values) {
      final theme = buildAppTheme(brightness);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            qsoLogProvider.overrideWith(() => _StaticQsoLogNotifier(log)),
          ],
          child: MaterialApp(
            locale: const Locale('zh'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            theme: theme,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.3)),
              child: child!,
            ),
            home: const LogsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final all = find.widgetWithText(FilterChip, '全部');
      expect(tester.widget<FilterChip>(all).selected, isTrue);
      expect(tester.widget<FilterChip>(all).showCheckmark, isNot(false));
      expect(theme.chipTheme.selectedColor, theme.colorScheme.primaryContainer);
      final pending = tester.widget<Chip>(find.widgetWithText(Chip, '待确认'));
      expect(pending.backgroundColor, theme.colorScheme.secondaryContainer);
      expect(find.text('发送 RST 59'), findsOneWidget);
      expect(find.text('接收 RST —'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('两种转写结束后可选择稍后或现在复核', (tester) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async => null,
        );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null),
    );
    final draft = QsoDraft(
      callsign: const QsoField(value: 'K1ABC', confidence: 0.9),
      dateTime: QsoField(value: DateTime(2026, 7, 23, 9, 30)),
      band: const QsoField(value: '20m'),
      frequency: const QsoField(value: '14.250'),
      mode: const QsoField(value: 'SSB'),
      sentRst: const QsoField(value: ''),
      receivedRst: const QsoField(value: ''),
      status: LogStatus.failed,
      errorMessage: 'recognition_failed',
    );
    final captureNotifier = _CompletedQsoCaptureNotifier(draft);
    final logNotifier = _RecordingQsoLogNotifier();
    final recordingNotifier = _RecordingSessionNotifier();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          transcriptionModeProvider.overrideWithValue(
            TranscriptionMode.afterQso,
          ),
          appSettingsProvider.overrideWith(_TestAppSettingsNotifier.new),
          failureHandlingProvider.overrideWithValue(FailureHandling.alert),
          recordingSessionProvider.overrideWith(() => recordingNotifier),
          qsoCaptureProvider.overrideWith(() => captureNotifier),
          qsoLogProvider.overrideWith(() => logNotifier),
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
          theme: buildAppTheme(Brightness.light),
          home: const RecordScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('FMO'), findsNothing);
    final recordContext = tester.element(find.byType(RecordScreen));
    final providerContainer = ProviderScope.containerOf(recordContext);
    expect(
      identical(
        providerContainer.read(recordingSessionProvider.notifier),
        recordingNotifier,
      ),
      isTrue,
    );
    final endButton = find.ancestor(
      of: find.text('End recording'),
      matching: find.byWidgetPredicate((widget) => widget is FilledButton),
    );
    expect(endButton, findsOneWidget);
    expect(endButton.hitTestable(), findsOneWidget);
    expect(tester.widget<FilledButton>(endButton).onPressed, isNotNull);
    await tester.tap(endButton);
    await tester.pumpAndSettle();

    expect(recordingNotifier.stopCalled, isTrue);
    expect(find.text('Review later'), findsOneWidget);
    expect(find.text('Review now'), findsOneWidget);
    expect(find.byType(QsoReviewScreen), findsNothing);

    await tester.tap(find.text('Review later'));
    await tester.pumpAndSettle();

    expect(find.byType(QsoReviewScreen), findsNothing);
    expect(logNotifier.saved?.status, LogStatus.failed);
    final capture = await providerContainer.read(qsoCaptureProvider.future);
    expect(capture.currentDraft.callsign.value, isEmpty);
    expect(capture.currentDraft.status, LogStatus.draft);
    expect(
      providerContainer.read(qsoSessionProvider).single.status,
      LogStatus.failed,
    );
    expect(find.text('Start recording'), findsOneWidget);

    await tester.tap(find.text('Real-time'));
    await tester.pumpAndSettle();
    recordingNotifier.setSession(
      RecordingSessionState(
        isRecording: true,
        elapsed: const Duration(seconds: 20),
        mode: TranscriptionMode.streaming,
        startedAt: DateTime(2026, 7, 23, 9, 35),
      ),
    );
    await tester.pump();
    final streamingEndButton = find.ancestor(
      of: find.text('End recording'),
      matching: find.byWidgetPredicate((widget) => widget is FilledButton),
    );
    await tester.tap(streamingEndButton);
    await tester.pumpAndSettle();

    expect(find.text('Review later'), findsOneWidget);
    expect(find.text('Review now'), findsOneWidget);
    final saveCount = logNotifier.saveCount;
    await tester.tap(find.text('Review now'));
    await tester.pumpAndSettle();

    expect(find.byType(QsoReviewScreen), findsOneWidget);
    expect(logNotifier.saveCount, saveCount);
  });
}

class _StaticQsoCaptureNotifier extends QsoCaptureNotifier {
  _StaticQsoCaptureNotifier(this.capture);

  final QsoCaptureState capture;

  @override
  Future<QsoCaptureState> build() async => capture;
}

class _StaticQsoLogNotifier extends QsoLogNotifier {
  _StaticQsoLogNotifier(this.log);

  final QsoDraft log;

  @override
  Future<List<QsoDraft>> build() async => [log];
}

class _CompletedQsoCaptureNotifier extends QsoCaptureNotifier {
  _CompletedQsoCaptureNotifier(this.draft);

  final QsoDraft draft;

  @override
  Future<QsoCaptureState> build() async => QsoCaptureState(currentDraft: draft);

  @override
  Future<QsoDraft> finishQso({
    required String? audioPath,
    required DateTime? startedAt,
    required TranscriptionMode mode,
    required FailureHandling failureHandling,
  }) async => draft;

  @override
  Future<QsoDraft> stopQsoStreaming({
    required String? audioPath,
    required DateTime? startedAt,
  }) async => draft;
}

class _RecordingSessionNotifier extends RecordingSessionNotifier {
  bool stopCalled = false;

  @override
  RecordingSessionState build() => RecordingSessionState(
    isRecording: true,
    elapsed: const Duration(seconds: 30),
    mode: TranscriptionMode.afterQso,
    startedAt: DateTime(2026, 7, 23, 9, 30),
  );

  @override
  Future<String?> stop() async {
    stopCalled = true;
    state = state.copyWith(isRecording: false, isProcessing: false);
    return 'test-output.wav';
  }
}

class _RecordingQsoLogNotifier extends QsoLogNotifier {
  QsoDraft? saved;
  int saveCount = 0;

  @override
  Future<List<QsoDraft>> build() async => const [];

  @override
  Future<String> saveAndRecordInSession(QsoDraft qso) async {
    saveCount += 1;
    saved = qso.copyWith(id: 'saved-qso');
    ref.read(qsoSessionProvider.notifier).record(saved!);
    state = AsyncData([saved!]);
    return 'saved-qso';
  }
}

class _TestAppSettingsNotifier extends AppSettingsNotifier {
  @override
  Future<AppSettings> build() async => const AppSettings.defaults();

  @override
  Future<void> updateSettings(AppSettings settings) async {
    state = AsyncData(settings);
  }
}

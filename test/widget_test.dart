import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qso_scribe_app/l10n/generated/app_localizations.dart';
import 'package:qso_scribe_app/src/domain/app_models.dart';
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
    expect(find.text('Current structured draft'), findsOneWidget);
    expect(find.text('Sent RST'), findsNothing);

    await tester.tap(find.text('Current structured draft'));
    await tester.pumpAndSettle();

    expect(find.text('Sent RST'), findsOneWidget);
  });
}

class _StaticQsoCaptureNotifier extends QsoCaptureNotifier {
  _StaticQsoCaptureNotifier(this.capture);

  final QsoCaptureState capture;

  @override
  Future<QsoCaptureState> build() async => capture;
}

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:qso_scribe_app/l10n/generated/app_localizations.dart';
import 'package:qso_scribe_app/src/domain/app_models.dart';
import 'package:qso_scribe_app/src/state/app_state.dart';
import 'package:qso_scribe_app/src/ui/screens.dart';
import 'package:qso_scribe_app/src/ui/theme.dart';

void main() {
  testWidgets('设置总览进入 AI 模型页并保留模型能力标签', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          providerProfilesProvider.overrideWith(
            (ref) async => const [
              ProviderProfile(
                id: 'provider-1',
                name: 'Field AI',
                type: 'openai',
                hasApiKey: true,
                baseUrl: 'https://example.com/v1',
              ),
            ],
          ),
          modelOptionsProvider.overrideWith(
            (ref) async => const [
              AiModelOption(
                id: 'speech-model',
                providerId: 'provider-1',
                providerName: 'Field AI',
                name: 'speech-model',
                capabilities: {ModelCapability.speech},
              ),
              AiModelOption(
                id: 'stream-model',
                providerId: 'provider-1',
                providerName: 'Field AI',
                name: 'stream-model',
                capabilities: {ModelCapability.streaming},
              ),
              AiModelOption(
                id: 'structure-model',
                providerId: 'provider-1',
                providerName: 'Field AI',
                name: 'structure-model',
                capabilities: {
                  ModelCapability.text,
                  ModelCapability.structuring,
                },
              ),
            ],
          ),
          modelAssignmentsProvider.overrideWith(
            _StaticModelAssignmentsNotifier.new,
          ),
        ],
        child: _LocalizedTestApp(home: const SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('管理电台、AI 模型和应用偏好'), findsOneWidget);
    expect(find.text('查看工作流分配、模型能力和服务配置'), findsOneWidget);

    await tester.tap(find.text('查看工作流分配、模型能力和服务配置'));
    await tester.pumpAndSettle();

    expect(find.byType(AiModelSettingsScreen), findsOneWidget);
    expect(find.text('工作流模型'), findsOneWidget);
    final assignedSpeechModel = find.byKey(
      const ValueKey('assigned-model-transcription'),
    );
    final assignedStreamModel = find.byKey(
      const ValueKey('assigned-model-streaming'),
    );
    final assignedStructureModel = find.byKey(
      const ValueKey('assigned-model-structuring'),
    );
    expect(
      find.descendant(of: assignedSpeechModel, matching: find.text('语音')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: assignedSpeechModel, matching: find.text('流式')),
      findsNothing,
    );
    expect(
      find.descendant(of: assignedStreamModel, matching: find.text('流式')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: assignedStreamModel, matching: find.text('语音')),
      findsNothing,
    );
    expect(
      find.descendant(of: assignedStructureModel, matching: find.text('文本')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: assignedStructureModel, matching: find.text('结构化')),
      findsOneWidget,
    );
    await tester.drag(find.byType(ListView), const Offset(0, -520));
    await tester.pumpAndSettle();
    expect(find.text('已配置模型'), findsOneWidget);
    expect(find.text('speech-model'), findsNWidgets(2));
    expect(find.text('stream-model'), findsNWidgets(2));
    expect(find.text('structure-model'), findsNWidgets(2));
    final speechModel = find.byKey(
      const ValueKey('configured-model-provider-1-speech-model'),
    );
    final streamModel = find.byKey(
      const ValueKey('configured-model-provider-1-stream-model'),
    );
    final structureModel = find.byKey(
      const ValueKey('configured-model-provider-1-structure-model'),
    );
    expect(
      find.descendant(of: speechModel, matching: find.text('语音')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: speechModel, matching: find.text('流式')),
      findsNothing,
    );
    expect(
      find.descendant(of: streamModel, matching: find.text('流式')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: streamModel, matching: find.text('语音')),
      findsNothing,
    );
    expect(
      find.descendant(of: structureModel, matching: find.text('文本')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: structureModel, matching: find.text('结构化')),
      findsOneWidget,
    );
  });

  testWidgets('模型数据加载失败时仍可进入供应商管理', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          providerProfilesProvider.overrideWith(
            (ref) async => const <ProviderProfile>[],
          ),
          modelOptionsProvider.overrideWith(
            (ref) async => throw StateError('model load failed'),
          ),
          modelAssignmentsProvider.overrideWith(
            _StaticModelAssignmentsNotifier.new,
          ),
        ],
        child: const _LocalizedTestApp(home: AiModelSettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('失败'), findsOneWidget);
    expect(find.text('管理供应商'), findsOneWidget);

    await tester.tap(find.text('管理供应商'));
    await tester.pumpAndSettle();

    expect(find.byType(ProviderSetupScreen), findsOneWidget);
  });

  testWidgets('供应商入口触控目标至少为 56dp', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          providerProfilesProvider.overrideWith(
            (ref) async => const [
              ProviderProfile(
                id: 'provider-1',
                name: 'Field AI',
                type: 'openai',
                hasApiKey: true,
              ),
            ],
          ),
          modelOptionsProvider.overrideWith(
            (ref) async => const <AiModelOption>[],
          ),
        ],
        child: const _LocalizedTestApp(home: ProviderSetupScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .getSize(find.byKey(const ValueKey('provider-summary-provider-1')))
          .height,
      greaterThanOrEqualTo(56),
    );
  });

  testWidgets('已保存模型能力触控目标至少为 56dp', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: _LocalizedTestApp(home: ProviderFormScreen())),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .getSize(
            find.byKey(const ValueKey('model-capability-whisper-1-speech')),
          )
          .height,
      greaterThanOrEqualTo(56),
    );
  });

  testWidgets('手动添加模型能力触控目标至少为 56dp', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: _LocalizedTestApp(home: ProviderFormScreen())),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .getSize(find.byKey(const ValueKey('manual-model-capability-speech')))
          .height,
      greaterThanOrEqualTo(56),
    );
  });

  testWidgets('关于页显示作者呼号 BH8HGF', (tester) async {
    PackageInfo.setMockInitialValues(
      appName: 'QSO Scribe',
      packageName: 'com.example.qso_scribe_app',
      version: '0.1.5',
      buildNumber: '6',
      buildSignature: '',
    );

    await tester.pumpWidget(
      const ProviderScope(child: _LocalizedTestApp(home: AboutScreen())),
    );
    await tester.pumpAndSettle();

    expect(find.text('作者呼号 · BH8HGF'), findsOneWidget);
  });
}

class _LocalizedTestApp extends StatelessWidget {
  const _LocalizedTestApp({required this.home});

  final Widget home;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      theme: buildAppTheme(Brightness.light),
      darkTheme: buildAppTheme(Brightness.dark),
      home: home,
    );
  }
}

class _StaticModelAssignmentsNotifier extends ModelAssignmentsNotifier {
  @override
  Future<List<ModelAssignment>> build() async => const [
    ModelAssignment(
      task: ModelAssignmentTask.transcription,
      providerId: 'provider-1',
      modelId: 'speech-model',
    ),
    ModelAssignment(
      task: ModelAssignmentTask.transcriptionStreaming,
      providerId: 'provider-1',
      modelId: 'stream-model',
    ),
    ModelAssignment(
      task: ModelAssignmentTask.structuring,
      providerId: 'provider-1',
      modelId: 'structure-model',
    ),
  ];
}

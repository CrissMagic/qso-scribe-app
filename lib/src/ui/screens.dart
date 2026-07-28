import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/generated/app_localizations.dart';
import '../domain/app_models.dart';
import '../domain/filter_helpers.dart';
import '../domain/provider_catalog.dart';
import '../services/release_info_service.dart';
import '../services/qrz_logbook_upload_service.dart';
import '../state/app_state.dart';
import 'band_colors.dart';
import 'theme.dart';

extension L10nX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

enum _ExportFormat { adif, csv, rawTranscript }

class FirstRunSetupScreen extends ConsumerStatefulWidget {
  const FirstRunSetupScreen({super.key});

  @override
  ConsumerState<FirstRunSetupScreen> createState() =>
      _FirstRunSetupScreenState();
}

class _FirstRunSetupScreenState extends ConsumerState<FirstRunSetupScreen> {
  final _callsignController = TextEditingController();
  bool _languageAutoDetected = false;

  @override
  void initState() {
    super.initState();
    // 根据系统语言自动设置默认语言
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoDetectLanguage();
    });
  }

  void _autoDetectLanguage() {
    if (_languageAutoDetected) return;
    _languageAutoDetected = true;
    final systemLocale = PlatformDispatcher.instance.locale;
    if (systemLocale.languageCode == 'zh') {
      ref.read(appSettingsProvider.notifier).setLocaleMode(AppLocaleMode.zh);
    }
  }

  @override
  void dispose() {
    _callsignController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final localeMode = ref.watch(localeModeProvider);
    final transcriptionMode = ref.watch(transcriptionModeProvider);
    final failureHandling = ref.watch(failureHandlingProvider);
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.appTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              l10n.firstRunTitle,
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(l10n.firstRunSubtitle),
            const SizedBox(height: 24),
            _SectionTitle(number: 1, title: l10n.callsignSetup),
            Text(l10n.callsignSetupDesc),
            const SizedBox(height: 12),
            TextField(
              controller: _callsignController,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: l10n.yourCallsign,
                hintText: l10n.yourCallsignHint,
                prefixIcon: const Icon(Icons.badge),
              ),
            ),
            const SizedBox(height: 24),
            _SectionTitle(number: 2, title: l10n.language),
            _ChoiceCard<AppLocaleMode>(
              value: AppLocaleMode.system,
              groupValue: localeMode,
              title: l10n.followSystem,
              subtitle: l10n.followSystemDesc,
              icon: Icons.language,
              onSelected: (value) =>
                  ref.read(appSettingsProvider.notifier).setLocaleMode(value),
            ),
            _ChoiceCard<AppLocaleMode>(
              value: AppLocaleMode.zh,
              groupValue: localeMode,
              title: l10n.simplifiedChinese,
              subtitle: l10n.simplifiedChineseDesc,
              icon: Icons.translate,
              onSelected: (value) =>
                  ref.read(appSettingsProvider.notifier).setLocaleMode(value),
            ),
            _ChoiceCard<AppLocaleMode>(
              value: AppLocaleMode.en,
              groupValue: localeMode,
              title: l10n.english,
              subtitle: l10n.englishDesc,
              icon: Icons.translate,
              onSelected: (value) =>
                  ref.read(appSettingsProvider.notifier).setLocaleMode(value),
            ),
            const SizedBox(height: 24),
            _SectionTitle(number: 3, title: l10n.transcriptionMode),
            _ChoiceCard<TranscriptionMode>(
              value: TranscriptionMode.streaming,
              groupValue: transcriptionMode,
              title: l10n.streamingMode,
              subtitle: l10n.streamingModeDesc,
              icon: Icons.mic,
              onSelected: (value) => ref
                  .read(appSettingsProvider.notifier)
                  .setTranscriptionMode(value),
            ),
            _ChoiceCard<TranscriptionMode>(
              value: TranscriptionMode.afterQso,
              groupValue: transcriptionMode,
              title: l10n.afterQsoMode,
              subtitle: l10n.afterQsoModeDesc,
              icon: Icons.upload_file,
              onSelected: (value) => ref
                  .read(appSettingsProvider.notifier)
                  .setTranscriptionMode(value),
            ),
            const SizedBox(height: 24),
            _SectionTitle(number: 4, title: l10n.failureHandling),
            _ChoiceCard<FailureHandling>(
              value: FailureHandling.alert,
              groupValue: failureHandling,
              title: l10n.showErrors,
              subtitle: l10n.showErrorsDesc,
              icon: Icons.warning_amber,
              onSelected: (value) => ref
                  .read(appSettingsProvider.notifier)
                  .setFailureHandling(value),
            ),
            _ChoiceCard<FailureHandling>(
              value: FailureHandling.silent,
              groupValue: failureHandling,
              title: l10n.degradeSilently,
              subtitle: l10n.degradeSilentlyDesc,
              icon: Icons.visibility_off,
              onSelected: (value) => ref
                  .read(appSettingsProvider.notifier)
                  .setFailureHandling(value),
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: () async {
                final callsign = _callsignController.text.trim();
                if (callsign.isNotEmpty) {
                  await ref
                      .read(appSettingsProvider.notifier)
                      .setCallsign(callsign);
                }
                await ref.read(setupCompletedProvider.notifier).complete();
              },
              icon: const Icon(Icons.check_circle_outline),
              label: Text(l10n.completeSetup),
            ),
          ],
        ),
      ),
    );
  }
}

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  int _index = 0;
  bool _startupUpdateCheckStarted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_checkUpdateOnStartup());
    });
  }

  Future<void> _checkUpdateOnStartup() async {
    if (_startupUpdateCheckStarted || !mounted) {
      return;
    }
    _startupUpdateCheckStarted = true;
    try {
      final settings = await ref.read(appSettingsProvider.future);
      if (!settings.checkUpdatesOnStartup || !mounted) {
        return;
      }

      final info = await PackageInfo.fromPlatform();
      if (_isTestBuild(info)) {
        return;
      }
      final currentVersion = packageVersionForDisplay(
        info.version,
        info.buildNumber,
        development: false,
      );
      final updateState = await ref
          .read(appUpdateProvider.notifier)
          .checkForUpdate(currentVersion: currentVersion, silent: true);
      if (!mounted ||
          updateState.status != AppUpdateStatus.updateAvailable ||
          updateState.release == null) {
        return;
      }

      final l10n = context.l10n;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.newVersionAvailable),
          action: SnackBarAction(
            label: l10n.viewUpdate,
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const SoftwareUpdateScreen(),
                ),
              );
            },
          ),
        ),
      );
    } catch (_) {
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final pages = [
      const RecordScreen(),
      const LogsScreen(),
      const SettingsScreen(),
    ];

    return Scaffold(
      body: pages[_index],
      bottomNavigationBar: NavigationBar(
        height: 64,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.mic),
            label: l10n.record,
          ),
          NavigationDestination(
            icon: const Icon(Icons.history),
            label: l10n.logs,
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings),
            label: l10n.settings,
          ),
        ],
      ),
    );
  }
}

class RecordScreen extends ConsumerStatefulWidget {
  const RecordScreen({super.key});

  @override
  ConsumerState<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends ConsumerState<RecordScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late int _activeTabIndex;

  @override
  void initState() {
    super.initState();
    final currentMode = ref.read(transcriptionModeProvider);
    final initialIndex = currentMode == TranscriptionMode.streaming ? 1 : 0;
    _activeTabIndex = initialIndex;
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: initialIndex,
    );
    _tabController.addListener(_onTabChanged);
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    // 录音/处理中禁止切换转写模式：否则停止按钮会落到错误的 tab，
    // 导致录音模式与停止处理不匹配（如 afterQso 录音被按流式停止）。
    final session = ref.read(recordingSessionProvider);
    if (session.isRecording || session.isProcessing) {
      _tabController.index = _activeTabIndex;
      return;
    }
    _activeTabIndex = _tabController.index;
    final mode = _tabController.index == 0
        ? TranscriptionMode.afterQso
        : TranscriptionMode.streaming;
    ref.read(appSettingsProvider.notifier).setTranscriptionMode(mode);
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final session = ref.watch(recordingSessionProvider);
    final capture = ref
        .watch(qsoCaptureProvider)
        .maybeWhen(
          data: (value) => value,
          orElse: () => QsoCaptureState(
            currentDraft: QsoDraft(
              callsign: const QsoField(value: ''),
              dateTime: const QsoField<DateTime?>(value: null),
              band: const QsoField(value: ''),
              frequency: const QsoField(value: ''),
              mode: const QsoField(value: ''),
              sentRst: const QsoField(value: ''),
              receivedRst: const QsoField(value: ''),
              status: LogStatus.draft,
            ),
          ),
        );
    final transcript = capture.transcriptSegments;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.appTitle),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: l10n.afterTranscribe),
            Tab(text: l10n.realtimeTranscribe),
            // 比赛模式暂时隐藏
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // 后置转写
          _AfterQsoTab(session: session, capture: capture),
          // 实时转写
          _StreamingTab(
            session: session,
            transcript: transcript,
            capture: capture,
          ),
        ],
      ),
    );
  }
}

class _AfterQsoTab extends ConsumerWidget {
  const _AfterQsoTab({required this.session, required this.capture});

  final RecordingSessionState session;
  final QsoCaptureState capture;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final sessionQsos = ref.watch(qsoSessionProvider);
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _StatusPanel(
            title: l10n.afterQsoMode,
            elapsed: session.elapsed,
            active: session.isRecording,
          ),
          if (session.errorMessage != null) ...[
            const SizedBox(height: 8),
            _PlaceholderCard(
              title: l10n.failed,
              text: _errorLabel(context, session.errorMessage!),
              icon: Icons.error_outline,
            ),
          ],
          if (capture.warningMessage != null) ...[
            const SizedBox(height: 8),
            _PlaceholderCard(
              title: l10n.needsReview,
              text: _captureWarningLabel(context, capture.warningMessage!),
              icon: Icons.info_outline,
            ),
          ],
          const SizedBox(height: 16),
          _CurrentSessionCard(qsos: sessionQsos),
        ],
      ),
      bottomNavigationBar: _RecordControls(
        session: session,
        mode: TranscriptionMode.afterQso,
        onStopped: (audioPath) async {
          final generatedDraft = await ref
              .read(qsoCaptureProvider.notifier)
              .finishQso(
                audioPath: audioPath,
                startedAt: session.startedAt,
                mode: TranscriptionMode.afterQso,
                failureHandling: ref.read(failureHandlingProvider),
              );
          if (context.mounted) {
            await _handleCompletedQso(context, ref, generatedDraft);
          }
        },
      ),
    );
  }
}

class _StreamingTab extends ConsumerWidget {
  const _StreamingTab({
    required this.session,
    required this.transcript,
    required this.capture,
  });

  final RecordingSessionState session;
  final List<TranscriptSegment> transcript;
  final QsoCaptureState capture;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final sessionQsos = ref.watch(qsoSessionProvider);
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _StatusPanel(
            title: l10n.streamingMode,
            elapsed: session.elapsed,
            active: session.isRecording,
          ),
          if (session.errorMessage != null) ...[
            const SizedBox(height: 8),
            _PlaceholderCard(
              title: l10n.failed,
              text: _errorLabel(context, session.errorMessage!),
              icon: Icons.error_outline,
            ),
          ],
          if (capture.warningMessage != null) ...[
            const SizedBox(height: 8),
            _PlaceholderCard(
              title: l10n.needsReview,
              text: _captureWarningLabel(context, capture.warningMessage!),
              icon: Icons.info_outline,
            ),
          ],
          const SizedBox(height: 16),
          _TranscriptCard(
            segments: transcript,
            otherCallsign: capture.currentDraft.callsign.value,
          ),
          const SizedBox(height: 16),
          _RealtimeDraftCard(
            draft: capture.currentDraft,
            isStructuring: capture.isStructuring,
          ),
          const SizedBox(height: 16),
          _CurrentSessionCard(qsos: sessionQsos),
        ],
      ),
      bottomNavigationBar: _RecordControls(
        session: session,
        mode: TranscriptionMode.streaming,
        onStopped: (audioPath) async {
          final generatedDraft = await ref
              .read(qsoCaptureProvider.notifier)
              .stopQsoStreaming(
                audioPath: audioPath,
                startedAt: session.startedAt,
              );
          if (context.mounted) {
            await _handleCompletedQso(context, ref, generatedDraft);
          }
        },
      ),
    );
  }
}

Future<void> _handleCompletedQso(
  BuildContext context,
  WidgetRef ref,
  QsoDraft draft,
) async {
  var saving = false;
  String? saveError;
  final reviewNow = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => PopScope(
      canPop: false,
      child: StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final callsign = draft.callsign.value.trim();
          final summary = [
            if (callsign.isNotEmpty) callsign,
            _statusLabel(dialogContext, draft.status),
          ].join(' · ');
          return AlertDialog(
            title: Text(dialogContext.l10n.qsoReview),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(summary),
                if (draft.errorMessage != null) ...[
                  const SizedBox(height: 8),
                  Text(_errorLabel(dialogContext, draft.errorMessage!)),
                ],
                if (saveError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    '${dialogContext.l10n.errorDetail}: $saveError',
                    style: TextStyle(
                      color: Theme.of(dialogContext).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: saving
                    ? null
                    : () async {
                        setDialogState(() {
                          saving = true;
                          saveError = null;
                        });
                        try {
                          await ref
                              .read(qsoLogProvider.notifier)
                              .saveAndRecordInSession(draft);
                          ref
                              .read(qsoCaptureProvider.notifier)
                              .clearCompletedQso();
                          if (dialogContext.mounted) {
                            Navigator.of(dialogContext).pop(false);
                          }
                        } catch (error) {
                          if (dialogContext.mounted) {
                            setDialogState(() {
                              saving = false;
                              saveError = _errorLabel(dialogContext, '$error');
                            });
                          }
                        }
                      },
                child: saving
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(dialogContext.l10n.reviewLater),
              ),
              FilledButton(
                onPressed: saving
                    ? null
                    : () => Navigator.of(dialogContext).pop(true),
                child: Text(dialogContext.l10n.reviewNow),
              ),
            ],
          );
        },
      ),
    ),
  );
  if (reviewNow == true && context.mounted) {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => QsoReviewScreen(draft: draft, recordInSession: true),
      ),
    );
  }
}

class _RealtimeDraftCard extends ConsumerWidget {
  const _RealtimeDraftCard({required this.draft, required this.isStructuring});

  final QsoDraft draft;
  final bool isStructuring;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final bandOrFrequencyMissing =
        draft.band.value.trim().isEmpty && draft.frequency.value.trim().isEmpty;
    final fields = <_RealtimeDraftField>[
      _RealtimeDraftField(
        key: QsoFieldKey.callsign,
        label: l10n.callsign,
        field: draft.callsign,
        requiredMissing: draft.callsign.value.trim().isEmpty,
      ),
      _RealtimeDraftField(
        key: QsoFieldKey.band,
        label: l10n.band,
        field: draft.band,
        requiredMissing: bandOrFrequencyMissing,
      ),
      _RealtimeDraftField(
        key: QsoFieldKey.frequency,
        label: l10n.frequency,
        field: draft.frequency,
        requiredMissing: bandOrFrequencyMissing,
      ),
      _RealtimeDraftField(
        key: QsoFieldKey.mode,
        label: l10n.mode,
        field: draft.mode,
        requiredMissing: draft.mode.value.trim().isEmpty,
      ),
      _RealtimeDraftField(
        key: QsoFieldKey.sentRst,
        label: l10n.sentRst,
        field: draft.sentRst,
        requiredMissing: draft.sentRst.value.trim().isEmpty,
      ),
      _RealtimeDraftField(
        key: QsoFieldKey.receivedRst,
        label: l10n.receivedRst,
        field: draft.receivedRst,
        requiredMissing: draft.receivedRst.value.trim().isEmpty,
      ),
      _RealtimeDraftField(
        key: QsoFieldKey.name,
        label: l10n.name,
        field: draft.name ?? const QsoField(value: ''),
      ),
      _RealtimeDraftField(
        key: QsoFieldKey.qth,
        label: l10n.qth,
        field: draft.qth ?? const QsoField(value: ''),
      ),
      _RealtimeDraftField(
        key: QsoFieldKey.rig,
        label: l10n.rig,
        field: draft.rig ?? const QsoField(value: ''),
      ),
      _RealtimeDraftField(
        key: QsoFieldKey.antenna,
        label: l10n.antenna,
        field: draft.antenna ?? const QsoField(value: ''),
      ),
      _RealtimeDraftField(
        key: QsoFieldKey.power,
        label: l10n.power,
        field: draft.power ?? const QsoField(value: ''),
      ),
      _RealtimeDraftField(
        key: QsoFieldKey.notes,
        label: l10n.notes,
        field: draft.notes ?? const QsoField(value: ''),
      ),
    ];
    final dateTime = draft.dateTime.value == null
        ? '—'
        : _formatDateTime(draft.dateTime.value!);
    final callsign = draft.callsign.value.trim();
    final summary = callsign.isEmpty ? dateTime : '$callsign · $dateTime';

    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: false,
        leading: const Icon(Icons.auto_fix_high),
        title: Text(l10n.currentStructuredDraft),
        subtitle: Text(
          isStructuring ? l10n.structuringInProgress : summary,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          if (isStructuring) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: 8),
          ],
          for (final item in fields)
            _RealtimeDraftFieldTile(
              item: item,
              onEdit: () => _editField(context, ref, item),
              onReview: () => ref
                  .read(qsoCaptureProvider.notifier)
                  .reviewCurrentDraftField(item.key),
            ),
        ],
      ),
    );
  }

  Future<void> _editField(
    BuildContext context,
    WidgetRef ref,
    _RealtimeDraftField item,
  ) async {
    final controller = TextEditingController(text: item.field.value);
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${dialogContext.l10n.editField}: ${item.label}'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(
              MaterialLocalizations.of(dialogContext).cancelButtonLabel,
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: Text(MaterialLocalizations.of(dialogContext).okButtonLabel),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null) {
      return;
    }
    ref
        .read(qsoCaptureProvider.notifier)
        .editCurrentDraftField(item.key, value);
  }
}

class _RealtimeDraftField {
  const _RealtimeDraftField({
    required this.key,
    required this.label,
    required this.field,
    this.requiredMissing = false,
  });

  final QsoFieldKey key;
  final String label;
  final QsoField<String> field;
  final bool requiredMissing;

  bool get needsReview {
    final hasValue = field.value.trim().isNotEmpty;
    return (hasValue && field.needsReview) ||
        (requiredMissing && !field.reviewed && !field.userEdited);
  }
}

class _RealtimeDraftFieldTile extends StatelessWidget {
  const _RealtimeDraftFieldTile({
    required this.item,
    required this.onEdit,
    required this.onReview,
  });

  final _RealtimeDraftField item;
  final VoidCallback onEdit;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final sourceText = item.field.sourceText?.trim();
    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: item.needsReview ? colors.errorContainer : null,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: item.needsReview ? colors.error : colors.outlineVariant,
        ),
      ),
      child: ListTile(
        dense: true,
        title: Text(item.label),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item.field.value.trim().isEmpty ? '—' : item.field.value),
            if (item.needsReview)
              Text(
                context.l10n.reviewRequired,
                style: TextStyle(color: colors.error),
              ),
            if (item.needsReview && sourceText?.isNotEmpty == true)
              Text(
                '${context.l10n.sourceExcerpt}: $sourceText',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (item.needsReview)
              IconButton(
                tooltip: context.l10n.confirmFieldCorrect,
                onPressed: onReview,
                icon: const Icon(Icons.check_circle_outline),
              ),
            IconButton(
              tooltip: context.l10n.editField,
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined),
            ),
          ],
        ),
        onTap: onEdit,
      ),
    );
  }
}

class _CurrentSessionCard extends StatelessWidget {
  const _CurrentSessionCard({required this.qsos});

  final List<QsoDraft> qsos;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.l10n.recentSession,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (qsos.isEmpty)
              Text(context.l10n.noSessionQsos)
            else
              for (final qso in qsos.reversed)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.radio),
                  title: Text(
                    qso.callsign.value.trim().isEmpty
                        ? '—'
                        : qso.callsign.value,
                  ),
                  subtitle: Text(
                    [
                      qso.band.value,
                      qso.frequency.value,
                      qso.mode.value,
                      _statusLabel(context, qso.status),
                    ].where((value) => value.trim().isNotEmpty).join(' · '),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          QsoReviewScreen(draft: qso, recordInSession: true),
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

class _RecordControls extends ConsumerWidget {
  const _RecordControls({
    required this.session,
    required this.mode,
    required this.onStopped,
  });

  final RecordingSessionState session;
  final TranscriptionMode mode;

  /// 停止录音后的回调（参数为录音文件路径）。
  final Future<void> Function(String? audioPath) onStopped;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final stopping = session.isRecording;
    final colors = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(64),
            backgroundColor: stopping ? colors.error : colors.primary,
            foregroundColor: stopping ? colors.onError : colors.onPrimary,
          ),
          onPressed: session.isProcessing
              ? null
              : () async {
                  final recorder = ref.read(recordingSessionProvider.notifier);
                  if (stopping) {
                    await HapticFeedback.mediumImpact();
                    final audioPath = await recorder.stop();
                    await onStopped(audioPath);
                  } else {
                    await HapticFeedback.selectionClick();
                    await ref
                        .read(qsoCaptureProvider.notifier)
                        .startRecordingQso(mode: mode);
                  }
                },
          icon: Icon(stopping ? Icons.stop : Icons.mic),
          label: Text(stopping ? l10n.endQso : l10n.startQso),
        ),
      ),
    );
  }
}

enum _FilterDimension { status, band, mode }

class LogsScreen extends ConsumerStatefulWidget {
  const LogsScreen({super.key});

  @override
  ConsumerState<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends ConsumerState<LogsScreen> {
  final _searchController = TextEditingController();
  Timer? _searchDebounce;
  _FilterDimension _dimension = _FilterDimension.status;
  LogStatus? _status;
  String? _band;
  String? _mode;
  bool _dateDesc = true;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() {});
    });
  }

  String _dimensionLabel(BuildContext context, _FilterDimension dimension) {
    final l10n = context.l10n;
    return switch (dimension) {
      _FilterDimension.status => l10n.filterDimensionStatus,
      _FilterDimension.band => l10n.filterDimensionBand,
      _FilterDimension.mode => l10n.filterDimensionMode,
    };
  }

  void _cycleFilterDimension() {
    final dimensions = _FilterDimension.values;
    final nextIndex = (dimensions.indexOf(_dimension) + 1) % dimensions.length;
    setState(() => _dimension = dimensions[nextIndex]);
  }

  void _clearLogFilters() {
    _searchController.clear();
    setState(() {
      _status = null;
      _band = null;
      _mode = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final logsState = ref.watch(qsoLogProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.logs),
        actions: [
          IconButton(
            tooltip: l10n.import,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const ImportScreen()),
            ),
            icon: const Icon(Icons.file_download),
          ),
          IconButton(
            tooltip: l10n.export,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const ExportScreen()),
            ),
            icon: const Icon(Icons.file_upload),
          ),
        ],
      ),
      body: logsState.when(
        data: (allLogs) {
          final filteredLogs = allLogs.where(_matchesLogFilter).toList();
          filteredLogs.sort((a, b) {
            final ta = a.dateTime.value;
            final tb = b.dateTime.value;
            if (ta == null && tb == null) return 0;
            if (ta == null) return 1;
            if (tb == null) return -1;
            return _dateDesc ? tb.compareTo(ta) : ta.compareTo(tb);
          });
          final dimensionChips = _buildDimensionChips(context, allLogs);
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(qsoLogProvider);
              await ref.read(qsoLogProvider.future);
            },
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      children: [
                        TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.search),
                            hintText: l10n.searchLogs,
                            suffixIcon: _searchController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear),
                                    onPressed: () {
                                      _searchController.clear();
                                      _onSearchChanged('');
                                    },
                                  )
                                : null,
                          ),
                          onChanged: _onSearchChanged,
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 40,
                          child: Row(
                            children: [
                              SizedBox(
                                width: 40,
                                child: IconButton(
                                  tooltip: l10n.filter,
                                  padding: EdgeInsets.zero,
                                  visualDensity: VisualDensity.compact,
                                  icon: const Icon(Icons.filter_list, size: 20),
                                  onPressed: _cycleFilterDimension,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: ListView(
                                  scrollDirection: Axis.horizontal,
                                  children: dimensionChips,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            ActionChip(
                              label: Text(
                                '${l10n.sortDate} ${_dateDesc ? '↓' : '↑'}',
                              ),
                              onPressed: () =>
                                  setState(() => _dateDesc = !_dateDesc),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${_dimensionLabel(context, _dimension)} · '
                                '${filteredLogs.length} ${l10n.qsoCountUnit}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.end,
                                style: Theme.of(context).textTheme.labelMedium
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                if (filteredLogs.isEmpty)
                  SliverPadding(
                    padding: const EdgeInsets.all(16),
                    sliver: SliverToBoxAdapter(
                      child: Column(
                        children: [
                          _PlaceholderCard(
                            title: l10n.logs,
                            text: l10n.noLogsMatchFilters,
                            icon: Icons.info_outline,
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: allLogs.isEmpty
                                ? () => Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => const ImportScreen(),
                                    ),
                                  )
                                : _clearLogFilters,
                            icon: Icon(
                              allLogs.isEmpty
                                  ? Icons.file_download
                                  : Icons.filter_alt_off,
                            ),
                            label: Text(
                              allLogs.isEmpty ? l10n.import : l10n.clearFilters,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    sliver: SliverList.separated(
                      itemCount: filteredLogs.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) =>
                          _LogListItem(log: filteredLogs[index]),
                    ),
                  ),
                const SliverPadding(padding: EdgeInsets.only(bottom: 16)),
              ],
            ),
          );
        },
        error: (error, stackTrace) => Center(
          child: _PlaceholderCard(
            title: l10n.failed,
            text: error.toString(),
            icon: Icons.error_outline,
          ),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
      ),
    );
  }

  bool _matchesLogFilter(QsoDraft log) {
    final search = _searchController.text.trim().toUpperCase();

    final matchesSearch =
        search.isEmpty ||
        log.callsign.value.toUpperCase().contains(search) ||
        (log.notes?.value.toUpperCase().contains(search) ?? false) ||
        (log.rawTranscript?.toUpperCase().contains(search) ?? false) ||
        (log.qth?.value.toUpperCase().contains(search) ?? false);

    return matchesSearch &&
        (_status == null || log.status == _status) &&
        (_band == null ||
            _band!.toLowerCase() == log.band.value.trim().toLowerCase()) &&
        (_mode == null ||
            _mode!.toLowerCase() == log.mode.value.trim().toLowerCase());
  }

  List<Widget> _buildDimensionChips(
    BuildContext context,
    List<QsoDraft> allLogs,
  ) {
    final l10n = context.l10n;
    switch (_dimension) {
      case _FilterDimension.status:
        return [
          _optionChip(context, l10n.all, _status == null, () {
            setState(() => _status = null);
          }),
          for (final s in LogStatus.values)
            _optionChip(context, _statusLabel(context, s), _status == s, () {
              setState(() => _status = s);
            }),
        ];
      case _FilterDimension.band:
        final bands =
            allLogs
                .map((l) => l.band.value.trim())
                .where((b) => b.isNotEmpty)
                .toSet()
                .toList()
              ..sort();
        return [
          _optionChip(context, l10n.all, _band == null, () {
            setState(() => _band = null);
          }),
          for (final b in bands)
            _optionChip(context, b, _band == b, () {
              setState(() => _band = b);
            }),
        ];
      case _FilterDimension.mode:
        final modes =
            allLogs
                .map((l) => l.mode.value.trim())
                .where((m) => m.isNotEmpty)
                .toSet()
                .toList()
              ..sort();
        return [
          _optionChip(context, l10n.all, _mode == null, () {
            setState(() => _mode = null);
          }),
          for (final m in modes)
            _optionChip(context, m, _mode == m, () {
              setState(() => _mode = m);
            }),
        ];
    }
  }

  Widget _optionChip(
    BuildContext context,
    String label,
    bool selected,
    VoidCallback onSelected,
  ) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        showCheckmark: false,
        onSelected: (_) => onSelected(),
      ),
    );
  }
}

class ImportScreen extends ConsumerWidget {
  const ImportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final jobsState = ref.watch(importJobsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.import)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _ActionCard(
            icon: Icons.audio_file,
            title: l10n.importAudio,
            subtitle: l10n.importAudioDesc,
            onTap: () async {
              final result = await FilePicker.platform.pickFiles(
                type: FileType.custom,
                allowedExtensions: [
                  'wav',
                  'm4a',
                  'mp3',
                  'pcm',
                  'flac',
                  'ogg',
                  'opus',
                  'aac',
                  'amr',
                  'webm',
                ],
              );
              final path = result?.files.single.path;
              if (path == null) {
                return;
              }
              if (!context.mounted) {
                return;
              }
              // 校验音频格式是否与当前 ASR 模型兼容
              final formatOk = await _validateImportFormat(context, ref, path);
              if (!formatOk || !context.mounted) {
                return;
              }
              try {
                final importDraft = await ref
                    .read(importJobsProvider.notifier)
                    .prepareAudioImport(path);
                if (context.mounted) {
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => QsoReviewScreen(
                        draft: importDraft.draft,
                        importJobId: importDraft.jobId,
                      ),
                    ),
                  );
                }
              } catch (error) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        '${l10n.failed}: ${_errorLabel(context, '$error')}',
                      ),
                      backgroundColor: Theme.of(context).colorScheme.error,
                    ),
                  );
                }
              } finally {
                ref.invalidate(importJobsProvider);
              }
            },
          ),
          const SizedBox(height: 12),
          _ActionCard(
            icon: Icons.text_snippet,
            title: l10n.importText,
            subtitle: l10n.importTextDesc,
            onTap: () async {
              final text = await _showImportTextDialog(context);
              if (text == null || text.trim().isEmpty) {
                return;
              }
              final importDraft = await ref
                  .read(importJobsProvider.notifier)
                  .prepareTextImport(text);
              if (context.mounted) {
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => QsoReviewScreen(
                      draft: importDraft.draft,
                      importJobId: importDraft.jobId,
                    ),
                  ),
                );
              }
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l10n.importJobCompleted)),
                );
              }
            },
          ),
          const SizedBox(height: 24),
          Text(
            l10n.recentImports,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          ...jobsState.when(
            data: (jobs) => [
              if (jobs.isEmpty)
                _PlaceholderCard(
                  title: l10n.recentImports,
                  text: l10n.noImportJobs,
                  icon: Icons.info_outline,
                ),
              for (final job in jobs) _ImportItem(job: job),
            ],
            error: (error, stackTrace) => [
              _PlaceholderCard(
                title: l10n.failed,
                text: error.toString(),
                icon: Icons.error_outline,
              ),
            ],
            loading: () => const [Center(child: CircularProgressIndicator())],
          ),
        ],
      ),
    );
  }
}

Future<String?> _showImportTextDialog(BuildContext context) async {
  final controller = TextEditingController();
  final l10n = context.l10n;
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.importText),
      content: TextField(
        controller: controller,
        maxLines: 8,
        decoration: InputDecoration(hintText: l10n.rawTranscript),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(controller.text),
          child: Text(l10n.import),
        ),
      ],
    ),
  );
}

class ExportScreen extends ConsumerStatefulWidget {
  const ExportScreen({super.key});

  @override
  ConsumerState<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends ConsumerState<ExportScreen> {
  _ExportFormat _format = _ExportFormat.adif;
  LogStatus? _status = LogStatus.confirmed;
  String? _band;
  String? _mode;
  DateTime? _from;
  DateTime? _to;

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final logs = ref
        .watch(qsoLogProvider)
        .maybeWhen(data: (value) => value, orElse: () => const <QsoDraft>[]);
    final exportHistoryState = ref.watch(exportHistoryProvider);
    final selectedCount = logs.where(_matchesExportFilter).length;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.exportLogs)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _CardSection(
            title: l10n.format,
            children: [
              SegmentedButton<_ExportFormat>(
                segments: [
                  const ButtonSegment(
                    value: _ExportFormat.adif,
                    label: Text('ADIF'),
                  ),
                  const ButtonSegment(
                    value: _ExportFormat.csv,
                    label: Text('CSV'),
                  ),
                  ButtonSegment(
                    value: _ExportFormat.rawTranscript,
                    label: Text(l10n.rawTranscript),
                  ),
                ],
                selected: {_format},
                onSelectionChanged: (selection) {
                  setState(() => _format = selection.first);
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          _CardSection(
            title: l10n.filters,
            children: [
              DropdownButtonFormField<LogStatus?>(
                initialValue: _status,
                decoration: InputDecoration(labelText: l10n.status),
                hint: Text(l10n.all),
                items: [
                  DropdownMenuItem(value: null, child: Text(l10n.all)),
                  for (final status in LogStatus.values)
                    DropdownMenuItem(
                      value: status,
                      child: Text(_statusLabel(context, status)),
                    ),
                ],
                onChanged: (value) => setState(() => _status = value),
              ),
              const SizedBox(height: 12),
              _TwoColumnFields(
                left: _BandDropdown(
                  value: _band,
                  includeAll: true,
                  onChanged: (value) => setState(() => _band = value),
                ),
                right: _ModeDropdown(
                  value: _mode,
                  includeAll: true,
                  onChanged: (value) => setState(() => _mode = value),
                ),
              ),
              _TwoColumnFields(
                left: _DatePickerField(
                  label: l10n.fromDate,
                  value: _from,
                  onPick: (value) => setState(() => _from = value),
                  onClear: _from == null
                      ? null
                      : () => setState(() => _from = null),
                ),
                right: _DatePickerField(
                  label: l10n.toDate,
                  value: _to,
                  onPick: (value) => setState(() => _to = value),
                  onClear: _to == null
                      ? null
                      : () => setState(() => _to = null),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _clearFilters,
                  icon: const Icon(Icons.filter_alt_off),
                  label: Text(l10n.clearFilters),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Center(
            child: Text(
              '$selectedCount ${l10n.selectedForExport}',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: selectedCount == 0 ? null : _exportToFile,
            icon: const Icon(Icons.file_download),
            label: Text(l10n.exportToFile),
          ),
          const SizedBox(height: 24),
          Text(
            l10n.exportHistory,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          ...exportHistoryState.when(
            data: (history) => [
              if (history.isEmpty)
                _PlaceholderCard(
                  title: l10n.exportHistory,
                  text: l10n.noExportHistory,
                  icon: Icons.info_outline,
                ),
              for (final entry in history) _ExportHistoryItem(entry: entry),
            ],
            error: (error, stackTrace) => [
              _PlaceholderCard(
                title: l10n.failed,
                text: error.toString(),
                icon: Icons.error_outline,
              ),
            ],
            loading: () => const [Center(child: CircularProgressIndicator())],
          ),
        ],
      ),
    );
  }

  bool _matchesExportFilter(QsoDraft draft) {
    final filter = _currentFilter();
    final band = filter.band;
    final mode = filter.mode;
    return (filter.status == null || draft.status == filter.status) &&
        (filter.from == null ||
            (draft.dateTime.value != null &&
                !draft.dateTime.value!.isBefore(filter.from!))) &&
        (filter.to == null ||
            (draft.dateTime.value != null &&
                !draft.dateTime.value!.isAfter(filter.to!))) &&
        matchesFilterText(draft.band.value, band) &&
        matchesFilterText(draft.mode.value, mode);
  }

  ExportFilter _currentFilter() {
    return ExportFilter(
      status: _status,
      from: _from,
      to: _inclusiveDateEnd(_to),
      band: _band,
      mode: _mode,
    );
  }

  void _clearFilters() {
    setState(() {
      _status = null;
      _band = null;
      _mode = null;
      _from = null;
      _to = null;
    });
  }

  Future<void> _exportToFile() async {
    final l10n = context.l10n;
    final service = ref.read(exportServiceProvider);
    final filter = _currentFilter();
    final generated = switch (_format) {
      _ExportFormat.adif => await service.exportAdif(filter),
      _ExportFormat.csv => await service.exportCsv(filter),
      _ExportFormat.rawTranscript => await service.exportRawTranscript(filter),
    };
    final extension = switch (_format) {
      _ExportFormat.adif => 'adi',
      _ExportFormat.csv => 'csv',
      _ExportFormat.rawTranscript => 'txt',
    };
    final fileName =
        'qso_export_${DateTime.now().toUtc().millisecondsSinceEpoch}.$extension';
    final exportedPath = await FilePicker.platform.saveFile(
      dialogTitle: l10n.exportLogs,
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: [extension],
      bytes: Uint8List.fromList(utf8.encode(generated.content)),
    );
    if (exportedPath == null) {
      return;
    }
    final repository = ref.read(exportHistoryRepositoryProvider);
    final filterSummary = _filterSummary();
    try {
      await repository.saveExport(
        format: extension,
        filePath: exportedPath,
        qsoCount: generated.qsoIds.length,
        filterSummary: filterSummary,
        confirmedQsoVersions: generated.confirmedQsoVersions,
      );
    } catch (error) {
      if (!mounted) {
        rethrow;
      }
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('${l10n.exportHistory} / ${l10n.status}: ${l10n.failed}'),
          content: SelectableText(
            '${l10n.exportedTo}: $exportedPath\n\n'
            '${l10n.exportHistory} / ${l10n.status}: ${l10n.failed}\n\n'
            '${l10n.errorDetail}: $error',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(
                MaterialLocalizations.of(dialogContext).okButtonLabel,
              ),
            ),
          ],
        ),
      );
      return;
    }
    ref.invalidate(qsoLogProvider);
    ref.invalidate(exportHistoryProvider);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${l10n.exportedTo}: $exportedPath')),
    );
  }

  String _filterSummary() {
    final filter = _currentFilter();
    return [
      'status=${filter.status?.name ?? 'all'}',
      'from=${filter.from?.toIso8601String() ?? ''}',
      'to=${filter.to?.toIso8601String() ?? ''}',
      'band=${filter.band ?? ''}',
      'mode=${filter.mode ?? ''}',
    ].join(';');
  }
}

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settings)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _CardSection(
            title: l10n.stationSettings,
            children: [
              _SettingsTile(
                icon: Icons.badge,
                title: l10n.callsignSetup,
                subtitle: l10n.callsignSetupDesc,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const CallsignSettingsScreen(),
                  ),
                ),
              ),
              _SettingsTile(
                icon: Icons.radio,
                title: l10n.stationEquipment,
                subtitle: l10n.stationEquipmentDesc,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const StationEquipmentScreen(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _CardSection(
            title: l10n.aiModels,
            children: [
              _SettingsTile(
                icon: Icons.hub,
                title: l10n.providerManagement,
                subtitle: l10n.providerManagementDesc,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ProviderSetupScreen(),
                  ),
                ),
              ),
              _SettingsTile(
                icon: Icons.model_training,
                title: l10n.modelAssignment,
                subtitle: l10n.modelAssignmentDesc,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ModelAssignmentScreen(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _CardSection(
            title: l10n.appSettings,
            children: [
              _SettingsTile(
                icon: Icons.cloud_upload_outlined,
                title: l10n.logbookUploads,
                subtitle: l10n.logbookUploadsDesc,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const LogbookIntegrationSettingsScreen(),
                  ),
                ),
              ),
              _SettingsTile(
                icon: Icons.language,
                title: l10n.language,
                subtitle: l10n.followSystemDesc,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const LanguageSettingsScreen(),
                  ),
                ),
              ),
              _SettingsTile(
                icon: Icons.warning_amber,
                title: l10n.failureHandling,
                subtitle: l10n.showErrorsDesc,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const TranscriptionSettingsScreen(),
                  ),
                ),
              ),
              _SettingsTile(
                icon: Icons.audio_file,
                title: l10n.audioRetention,
                subtitle: l10n.audioRetentionDesc,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const AudioRetentionSettingsScreen(),
                  ),
                ),
              ),
              _SettingsTile(
                icon: Icons.storage,
                title: l10n.localDataManagement,
                subtitle: l10n.localDataManagementDesc,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const LocalDataManagementScreen(),
                  ),
                ),
              ),
              _SettingsTile(
                icon: Icons.system_update,
                title: l10n.softwareUpdate,
                subtitle: l10n.softwareUpdateDesc,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const SoftwareUpdateScreen(),
                  ),
                ),
              ),
              _SettingsTile(
                icon: Icons.bolt,
                title: l10n.tokenUsage,
                subtitle: l10n.tokenUsageDesc,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const TokenUsageScreen(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _CardSection(
            title: l10n.about,
            children: [
              _SettingsTile(
                icon: Icons.info_outline,
                title: l10n.about,
                subtitle: l10n.aboutDesc,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const AboutScreen()),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class LogbookIntegrationSettingsScreen extends ConsumerStatefulWidget {
  const LogbookIntegrationSettingsScreen({super.key});

  @override
  ConsumerState<LogbookIntegrationSettingsScreen> createState() =>
      _LogbookIntegrationSettingsScreenState();
}

class _LogbookIntegrationSettingsScreenState
    extends ConsumerState<LogbookIntegrationSettingsScreen> {
  final _qrzApiKeyController = TextEditingController();
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _qrzApiKeyController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final key = await ref.read(settingsRepositoryProvider).loadQrzApiKey();
    if (mounted) {
      setState(() {
        _qrzApiKeyController.text = key;
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref
          .read(settingsRepositoryProvider)
          .saveQrzApiKey(_qrzApiKeyController.text);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.logbookSettingsSaved)),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _pasteApiKey() async {
    final data = await Clipboard.getData('text/plain');
    final text = data?.text?.trim();
    if (text != null && text.isNotEmpty) {
      setState(() => _qrzApiKeyController.text = text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final disabled = _loading || _saving;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.logbookUploads)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_loading) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: 16),
          ],
          _CardSection(
            title: 'QRZ',
            children: [
              TextField(
                controller: _qrzApiKeyController,
                enabled: !disabled,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: l10n.qrzApiKey,
                  helperText: l10n.qrzApiKeyHint,
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.content_paste),
                    tooltip: l10n.paste,
                    onPressed: disabled ? null : _pasteApiKey,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: disabled ? null : _save,
                  icon: _saving
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save),
                  label: Text(l10n.save),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _PlaceholderCard(
            title: 'LoTW',
            text: l10n.lotwTqslRequired,
            icon: Icons.lock_outline,
          ),
        ],
      ),
    );
  }
}

class SoftwareUpdateScreen extends ConsumerStatefulWidget {
  const SoftwareUpdateScreen({super.key});

  @override
  ConsumerState<SoftwareUpdateScreen> createState() =>
      _SoftwareUpdateScreenState();
}

class _SoftwareUpdateScreenState extends ConsumerState<SoftwareUpdateScreen> {
  PackageInfo? _packageInfo;

  @override
  void initState() {
    super.initState();
    _loadPackageInfo();
  }

  Future<void> _loadPackageInfo() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() => _packageInfo = info);
    }
  }

  String get _currentVersion {
    final info = _packageInfo;
    if (info == null) {
      return '-';
    }
    return packageVersionForDisplay(
      info.version,
      info.buildNumber,
      development: _isTestBuild(info),
    );
  }

  Future<void> _checkUpdate() async {
    var info = _packageInfo;
    if (info == null) {
      info = await PackageInfo.fromPlatform();
      if (!mounted) {
        return;
      }
      setState(() => _packageInfo = info);
    }
    await ref
        .read(appUpdateProvider.notifier)
        .checkForUpdate(currentVersion: _currentVersion);
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(url)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final updateState = ref.watch(appUpdateProvider);
    final release = updateState.release;
    final checkUpdatesOnStartup = ref.watch(checkUpdatesOnStartupProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.softwareUpdate)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _versionRow(l10n.currentVersion, _currentVersion),
          if (release != null) _versionRow(l10n.latestVersion, release.version),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: updateState.isBusy || _packageInfo == null
                ? null
                : _checkUpdate,
            icon: updateState.status == AppUpdateStatus.checking
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            label: Text(l10n.checkUpdate),
          ),
          const SizedBox(height: 8),
          if (_packageInfo != null && !_isTestBuild(_packageInfo!))
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.update),
              title: Text(l10n.checkUpdatesOnStartup),
              value: checkUpdatesOnStartup,
              onChanged: (value) => ref
                  .read(appSettingsProvider.notifier)
                  .setCheckUpdatesOnStartup(value),
            ),
          const SizedBox(height: 24),
          ..._resultWidgets(context, updateState),
        ],
      ),
    );
  }

  Widget _versionRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.titleMedium,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _resultWidgets(
    BuildContext context,
    AppUpdateState updateState,
  ) {
    final l10n = context.l10n;
    if (updateState.status == AppUpdateStatus.checking) {
      return const [
        Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: CircularProgressIndicator(),
          ),
        ),
      ];
    }
    if (updateState.status == AppUpdateStatus.noRelease) {
      return [
        Text(l10n.noReleaseAvailable),
        const SizedBox(height: 12),
        OutlinedButton(onPressed: _checkUpdate, child: Text(l10n.retry)),
      ];
    }

    final release = updateState.release;
    if (release == null) {
      if (updateState.status == AppUpdateStatus.failed) {
        return [
          _UpdateStatusRow(
            icon: Icons.error_outline,
            text: _updateErrorLabel(context, updateState.errorCode),
            isError: true,
          ),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: _checkUpdate, child: Text(l10n.retry)),
        ];
      }
      return const [];
    }
    final hasUpdate = compareVersions(release.version, _currentVersion) > 0;
    if (!hasUpdate) {
      return [
        Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green.shade600),
            const SizedBox(width: 8),
            Expanded(child: Text(l10n.upToDate)),
          ],
        ),
      ];
    }

    final widgets = <Widget>[
      if (updateState.status == AppUpdateStatus.failed) ...[
        _UpdateStatusRow(
          icon: Icons.error_outline,
          text: _updateErrorLabel(context, updateState.errorCode),
          isError: true,
        ),
        const SizedBox(height: 12),
      ],
      Text(
        l10n.newVersionAvailable,
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 12),
      ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        title: Text(l10n.updateNotes),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: MarkdownBody(
              data: release.notes.isEmpty ? release.title : release.notes,
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),
    ];
    widgets.addAll(_downloadWidgets(context, release, updateState));
    return widgets;
  }

  List<Widget> _downloadWidgets(
    BuildContext context,
    AppRelease release,
    AppUpdateState updateState,
  ) {
    final l10n = context.l10n;
    final downloading = updateState.status == AppUpdateStatus.downloading;
    final downloaded =
        updateState.localApkPath != null &&
        updateState.status != AppUpdateStatus.downloading &&
        updateState.status != AppUpdateStatus.installing;

    return [
      _UpdateStatusRow(
        icon: downloaded ? Icons.check_circle_outline : Icons.inventory_2,
        text: _packageSummary(context, release),
      ),
      const SizedBox(height: 12),
      if (downloading) ...[
        LinearProgressIndicator(value: updateState.progress),
        const SizedBox(height: 8),
        Text(
          '${l10n.downloadProgress}: '
          '${_formatBytes(updateState.receivedBytes)} / '
          '${updateState.totalBytes == null ? '-' : _formatBytes(updateState.totalBytes!)}',
        ),
        const SizedBox(height: 12),
      ],
      if (!downloading && !downloaded) ...[
        FilledButton.icon(
          onPressed: () => unawaited(
            ref
                .read(appUpdateProvider.notifier)
                .downloadLatest(openInstallerWhenDone: true),
          ),
          icon: const Icon(Icons.system_update_alt),
          label: Text(l10n.downloadAndOpenInstaller),
        ),
      ],
      if (downloaded)
        FilledButton.icon(
          onPressed: () =>
              unawaited(ref.read(appUpdateProvider.notifier).openInstaller()),
          icon: const Icon(Icons.install_mobile),
          label: Text(l10n.openInstaller),
        ),
      const SizedBox(height: 8),
      TextButton.icon(
        onPressed: () => _openUrl(release.htmlUrl),
        icon: const Icon(Icons.open_in_new),
        label: Text(l10n.goToDownload),
      ),
    ];
  }

  String _packageSummary(BuildContext context, AppRelease release) {
    final size = release.apkAsset.size;
    if (size == null) {
      return context.l10n.updatePackage;
    }
    return '${context.l10n.updatePackage} · ${_formatBytes(size)}';
  }

  String _updateErrorLabel(BuildContext context, String? code) {
    final l10n = context.l10n;
    return switch (code) {
      'noRelease' => l10n.noReleaseAvailable,
      'httpError' => l10n.updateCheckFailed,
      'networkError' => l10n.updateNetworkFailed,
      'timeout' => l10n.updateTimeout,
      'badResponse' => l10n.updateBadResponse,
      'fileSystemError' => l10n.updateFileSystemFailed,
      'checksumMismatch' => l10n.updateChecksumMismatch,
      'installPermissionRequired' => l10n.installPermissionRequired,
      'installerUnavailable' => l10n.installerUnavailable,
      'invalidApkPath' => l10n.invalidApkPath,
      'release_missing' => l10n.updateCheckFailed,
      _ => l10n.updateCheckFailed,
    };
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }
    final kb = bytes / 1024;
    if (kb < 1024) {
      return '${kb.toStringAsFixed(1)} KB';
    }
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(1)} MB';
  }
}

bool _isTestBuild(PackageInfo info) {
  return info.packageName.endsWith('.debug') ||
      info.version.toLowerCase().contains('debug');
}

class _UpdateStatusRow extends StatelessWidget {
  const _UpdateStatusRow({
    required this.icon,
    required this.text,
    this.isError = false,
  });

  final IconData icon;
  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, color: isError ? colorScheme.error : null),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: isError ? TextStyle(color: colorScheme.error) : null,
          ),
        ),
      ],
    );
  }
}

class LocalDataManagementScreen extends ConsumerWidget {
  const LocalDataManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final summaryState = ref.watch(localDataSummaryProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.localDataManagement)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ...summaryState.when(
            data: (summary) => [
              _CardSection(
                title: l10n.localDataOverview,
                children: [
                  _DataCountTile(
                    icon: Icons.audio_file,
                    label: l10n.retainedAudioFiles,
                    count: summary.retainedAudioCount,
                  ),
                  _DataCountTile(
                    icon: Icons.notes,
                    label: l10n.rawTranscriptEntries,
                    count: summary.rawTranscriptCount,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: summary.retainedAudioCount == 0
                    ? null
                    : () => _deleteAllRetainedAudio(context, ref),
                icon: const Icon(Icons.delete_outline),
                label: Text(l10n.deleteAllRetainedAudio),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: summary.rawTranscriptCount == 0
                    ? null
                    : () => _clearAllRawContent(context, ref),
                icon: const Icon(Icons.notes),
                label: Text(l10n.clearAllRawTranscripts),
              ),
            ],
            error: (error, stackTrace) => [
              _PlaceholderCard(
                title: l10n.failed,
                text: error.toString(),
                icon: Icons.error_outline,
              ),
            ],
            loading: () => const [Center(child: CircularProgressIndicator())],
          ),
        ],
      ),
    );
  }

  Future<void> _deleteAllRetainedAudio(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final confirmed = await _confirmDestructiveAction(
      context,
      title: context.l10n.deleteAllRetainedAudio,
      message: context.l10n.deleteAllRetainedAudioConfirm,
    );
    if (!confirmed) {
      return;
    }
    await ref.read(qsoLogProvider.notifier).deleteAllRetainedAudio();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.localDataCleanupComplete)),
      );
    }
  }

  Future<void> _clearAllRawContent(BuildContext context, WidgetRef ref) async {
    final confirmed = await _confirmDestructiveAction(
      context,
      title: context.l10n.clearAllRawTranscripts,
      message: context.l10n.clearAllRawTranscriptsConfirm,
    );
    if (!confirmed) {
      return;
    }
    await ref.read(qsoLogProvider.notifier).clearAllRawContent();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.localDataCleanupComplete)),
      );
    }
  }
}

class StationEquipmentScreen extends ConsumerStatefulWidget {
  const StationEquipmentScreen({super.key});

  @override
  ConsumerState<StationEquipmentScreen> createState() =>
      _StationEquipmentScreenState();
}

class _StationEquipmentScreenState
    extends ConsumerState<StationEquipmentScreen> {
  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final equipmentState = ref.watch(stationEquipmentProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.stationEquipment)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showEquipmentDialog(),
        icon: const Icon(Icons.add),
        label: Text(l10n.addEquipment),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ...equipmentState.when(
            data: (equipment) => [
              if (equipment.isEmpty)
                _PlaceholderCard(
                  title: l10n.stationEquipment,
                  text: l10n.noEquipmentSaved,
                  icon: Icons.radio,
                ),
              for (int i = 0; i < equipment.length; i++) ...[
                _EquipmentTile(
                  equipment: equipment[i],
                  onEdit: () =>
                      _showEquipmentDialog(index: i, equipment: equipment[i]),
                  onDelete: () => _deleteEquipment(i),
                ),
                const SizedBox(height: 8),
              ],
            ],
            error: (error, stackTrace) => [
              _PlaceholderCard(
                title: l10n.failed,
                text: error.toString(),
                icon: Icons.error_outline,
              ),
            ],
            loading: () => const [Center(child: CircularProgressIndicator())],
          ),
        ],
      ),
    );
  }

  Future<void> _showEquipmentDialog({
    int? index,
    StationEquipment? equipment,
  }) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => EquipmentFormScreen(equipment: equipment),
      ),
    );
    if (saved == true) {
      ref.invalidate(stationEquipmentProvider);
      if (mounted) {
        showTopNotice(context, context.l10n.equipmentSaved);
      }
    }
  }

  Future<void> _deleteEquipment(int index) async {
    final confirmed = await _confirmDestructiveAction(
      context,
      title: context.l10n.delete,
      message: context.l10n.stationEquipment,
    );
    if (!confirmed) return;
    final current = ref
        .read(stationEquipmentProvider)
        .maybeWhen(data: (v) => v, orElse: () => <StationEquipment>[]);
    final updated = [...current]..removeAt(index);
    await ref.read(stationEquipmentProvider.notifier).save(updated);
  }
}

class EquipmentFormScreen extends ConsumerStatefulWidget {
  const EquipmentFormScreen({super.key, this.equipment});

  final StationEquipment? equipment;

  @override
  ConsumerState<EquipmentFormScreen> createState() =>
      _EquipmentFormScreenState();
}

class _EquipmentFormScreenState extends ConsumerState<EquipmentFormScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _antennaController;
  late final TextEditingController _powerController;

  @override
  void initState() {
    super.initState();
    final eq = widget.equipment;
    _nameController = TextEditingController(text: eq?.name ?? '');
    _antennaController = TextEditingController(text: eq?.antenna ?? '');
    _powerController = TextEditingController(
      text: eq?.powerOptions.join('\n') ?? '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _antennaController.dispose();
    _powerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isEdit = widget.equipment != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? l10n.editProvider : l10n.addEquipment),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _nameController,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    labelText: l10n.equipmentName,
                    hintText: l10n.equipmentNameHint,
                    prefixIcon: const Icon(Icons.radio),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _antennaController,
                  decoration: InputDecoration(
                    labelText: l10n.antennaName,
                    hintText: l10n.antennaNameHint,
                    prefixIcon: const Icon(Icons.cell_tower),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _powerController,
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: l10n.powerOptions,
                    hintText: l10n.powerOptionsHint,
                    prefixIcon: const Icon(Icons.electrical_services),
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.save),
                    label: Text(l10n.confirmAndSave),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.equipmentName)));
      return;
    }
    final powerLines = _powerController.text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    final equipment = StationEquipment(
      name: name,
      antenna: _antennaController.text.trim(),
      powerOptions: powerLines,
    );

    final current = ref
        .read(stationEquipmentProvider)
        .maybeWhen(data: (v) => v, orElse: () => <StationEquipment>[]);
    final List<StationEquipment> updated;
    final existingIndex = current.indexWhere((e) => e.name == name);
    if (existingIndex >= 0) {
      updated = [...current]..[existingIndex] = equipment;
    } else {
      updated = [...current, equipment];
    }
    await ref.read(stationEquipmentProvider.notifier).save(updated);
    if (mounted) {
      Navigator.of(context).pop(true);
    }
  }
}

class _EquipmentTile extends StatelessWidget {
  const _EquipmentTile({
    required this.equipment,
    required this.onEdit,
    required this.onDelete,
  });

  final StationEquipment equipment;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final powerText = equipment.powerOptions.isEmpty
        ? '-'
        : equipment.powerOptions.join(', ');
    return ListTile(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      leading: const Icon(Icons.radio),
      title: Text(equipment.name),
      subtitle: Text(
        [
          '${l10n.antennaName}: ${equipment.antenna.isEmpty ? "-" : equipment.antenna}',
          '${l10n.powerOptions}: $powerText',
        ].join('\n'),
      ),
      isThreeLine: true,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: l10n.editProvider,
            onPressed: onEdit,
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            tooltip: l10n.delete,
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }
}

class CallsignSettingsScreen extends ConsumerStatefulWidget {
  const CallsignSettingsScreen({super.key});

  @override
  ConsumerState<CallsignSettingsScreen> createState() =>
      _CallsignSettingsScreenState();
}

class _CallsignSettingsScreenState
    extends ConsumerState<CallsignSettingsScreen> {
  late final TextEditingController _callsignController;
  late final TextEditingController _qthController;

  @override
  void initState() {
    super.initState();
    _callsignController = TextEditingController(
      text: ref.read(callsignProvider),
    );
    _qthController = TextEditingController(text: ref.read(qthProvider));
  }

  @override
  void dispose() {
    _callsignController.dispose();
    _qthController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.callsignSetup)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _callsignController,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(
              labelText: l10n.yourCallsign,
              hintText: l10n.yourCallsignHint,
              prefixIcon: const Icon(Icons.badge),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _qthController,
            decoration: InputDecoration(
              labelText: l10n.yourQth,
              hintText: l10n.yourQthHint,
              prefixIcon: const Icon(Icons.location_on_outlined),
            ),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save),
            label: Text(l10n.save),
          ),
        ],
      ),
    );
  }

  void _save() {
    ref
        .read(appSettingsProvider.notifier)
        .setCallsign(_callsignController.text.trim());
    ref.read(appSettingsProvider.notifier).setQth(_qthController.text.trim());
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.l10n.equipmentSaved)));
  }
}

class LanguageSettingsScreen extends ConsumerWidget {
  const LanguageSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final localeMode = ref.watch(localeModeProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.language)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _ChoiceCard<AppLocaleMode>(
            value: AppLocaleMode.system,
            groupValue: localeMode,
            title: l10n.followSystem,
            subtitle: l10n.followSystemDesc,
            icon: Icons.language,
            onSelected: (value) =>
                ref.read(appSettingsProvider.notifier).setLocaleMode(value),
          ),
          _ChoiceCard<AppLocaleMode>(
            value: AppLocaleMode.zh,
            groupValue: localeMode,
            title: l10n.simplifiedChinese,
            subtitle: l10n.simplifiedChineseDesc,
            icon: Icons.translate,
            onSelected: (value) =>
                ref.read(appSettingsProvider.notifier).setLocaleMode(value),
          ),
          _ChoiceCard<AppLocaleMode>(
            value: AppLocaleMode.en,
            groupValue: localeMode,
            title: l10n.english,
            subtitle: l10n.englishDesc,
            icon: Icons.translate,
            onSelected: (value) =>
                ref.read(appSettingsProvider.notifier).setLocaleMode(value),
          ),
        ],
      ),
    );
  }
}

class TranscriptionSettingsScreen extends ConsumerWidget {
  const TranscriptionSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final failureHandling = ref.watch(failureHandlingProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.failureHandling)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _ChoiceCard<FailureHandling>(
            value: FailureHandling.alert,
            groupValue: failureHandling,
            title: l10n.showErrors,
            subtitle: l10n.showErrorsDesc,
            icon: Icons.warning_amber,
            onSelected: (value) => ref
                .read(appSettingsProvider.notifier)
                .setFailureHandling(value),
          ),
          _ChoiceCard<FailureHandling>(
            value: FailureHandling.silent,
            groupValue: failureHandling,
            title: l10n.degradeSilently,
            subtitle: l10n.degradeSilentlyDesc,
            icon: Icons.visibility_off,
            onSelected: (value) => ref
                .read(appSettingsProvider.notifier)
                .setFailureHandling(value),
          ),
        ],
      ),
    );
  }
}

class AudioRetentionSettingsScreen extends ConsumerWidget {
  const AudioRetentionSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final audioRetention = ref.watch(audioRetentionPolicyProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.audioRetention)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<AudioRetentionPolicy>(
            initialValue: audioRetention,
            decoration: InputDecoration(labelText: l10n.audioRetention),
            items: [
              DropdownMenuItem(
                value: AudioRetentionPolicy.keep,
                child: Text(l10n.keepAudio),
              ),
              DropdownMenuItem(
                value: AudioRetentionPolicy.deleteAfterRecognition,
                child: Text(l10n.deleteAudioAfterRecognition),
              ),
              DropdownMenuItem(
                value: AudioRetentionPolicy.deleteAfterConfirmation,
                child: Text(l10n.deleteAudioAfterConfirmation),
              ),
            ],
            onChanged: (value) {
              if (value != null) {
                ref
                    .read(appSettingsProvider.notifier)
                    .setAudioRetentionPolicy(value);
              }
            },
          ),
        ],
      ),
    );
  }
}

class TokenUsageScreen extends ConsumerWidget {
  const TokenUsageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final usageState = ref.watch(tokenUsageListProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.tokenUsage),
        actions: [
          IconButton(
            tooltip: l10n.clearRecords,
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: () => _clearAll(context, ref),
          ),
        ],
      ),
      body: usageState.when(
        data: (records) {
          final totalTokens = records.fold<int>(
            0,
            (sum, r) => sum + (r.totalTokens ?? 0),
          );
          if (records.isEmpty) {
            return Center(child: Text(l10n.noTokenRecords));
          }
          return CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      _UsageStat(
                        label: l10n.totalTokens,
                        value: totalTokens.toString(),
                        icon: Icons.bolt,
                      ),
                      const SizedBox(width: 16),
                      _UsageStat(
                        label: l10n.requestCount,
                        value: records.length.toString(),
                        icon: Icons.request_quote,
                      ),
                    ],
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                sliver: SliverList.separated(
                  itemCount: records.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) =>
                      _TokenUsageItem(record: records[index]),
                ),
              ),
            ],
          );
        },
        error: (error, stack) => Center(child: Text('$error')),
        loading: () => const Center(child: CircularProgressIndicator()),
      ),
    );
  }

  Future<void> _clearAll(BuildContext context, WidgetRef ref) async {
    final confirmed = await _confirmDestructiveAction(
      context,
      title: context.l10n.clearRecords,
      message: context.l10n.clearRecordsConfirm,
    );
    if (!confirmed) return;
    await ref.read(tokenUsageRepositoryProvider).clearAll();
    ref.invalidate(tokenUsageListProvider);
  }
}

class _UsageStat extends StatelessWidget {
  const _UsageStat({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final osc = Theme.of(context).extension<OscilloscopeColors>()!;
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 18, color: osc.phosphor),
                  const SizedBox(width: 6),
                  Text(label, style: Theme.of(context).textTheme.labelMedium),
                ],
              ),
              const SizedBox(height: 6),
              Text(value, style: Theme.of(context).textTheme.headlineSmall),
            ],
          ),
        ),
      ),
    );
  }
}

class _TokenUsageItem extends StatelessWidget {
  const _TokenUsageItem({required this.record});

  final TokenUsageRecord record;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final taskLabel = switch (record.taskType) {
      'transcription' => l10n.taskTranscription,
      'structuring' => l10n.taskStructuring,
      'streaming' => l10n.taskStreaming,
      _ => record.taskType,
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${record.provider} · ${record.model}',
                    style: Theme.of(context).textTheme.titleSmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(taskLabel, style: Theme.of(context).textTheme.labelSmall),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              _formatLocalDateTime(record.createdAt),
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              children: [
                _tokenPair(
                  context,
                  l10n.promptTokens,
                  record.promptTokens?.toString(),
                ),
                _tokenPair(
                  context,
                  l10n.completionTokens,
                  record.completionTokens?.toString(),
                ),
                _tokenPair(
                  context,
                  l10n.totalTokens,
                  record.totalTokens?.toString(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

Widget _tokenPair(BuildContext context, String label, String? value) {
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        '$label: ',
        style: TextStyle(
          fontSize: 12,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      Text(
        value ?? '—',
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
      ),
    ],
  );
}

class AboutScreen extends ConsumerStatefulWidget {
  const AboutScreen({super.key});

  @override
  ConsumerState<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends ConsumerState<AboutScreen> {
  PackageInfo? _packageInfo;

  @override
  void initState() {
    super.initState();
    _loadPackageInfo();
  }

  Future<void> _loadPackageInfo() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() => _packageInfo = info);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final osc = Theme.of(context).extension<OscilloscopeColors>()!;
    final version = _packageInfo == null
        ? '-'
        : packageVersionForDisplay(
            _packageInfo!.version,
            _packageInfo!.buildNumber,
            development: _isTestBuild(_packageInfo!),
          );
    return Scaffold(
      appBar: AppBar(title: Text(l10n.about)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: Column(
              children: [
                Icon(Icons.radio, size: 48, color: osc.phosphor),
                const SizedBox(height: 12),
                Text(
                  l10n.appTitle,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.aboutAppVersion(version),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          ExpansionTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: Text(l10n.privacyPolicy),
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(l10n.privacyPolicyBody),
              ),
            ],
          ),
          ExpansionTile(
            leading: const Icon(Icons.code),
            title: Text(l10n.openSourceCredits),
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(l10n.openSourceCreditsBody),
              ),
            ],
          ),
          ExpansionTile(
            leading: const Icon(Icons.link),
            title: Text(l10n.relatedLinks),
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(l10n.relatedLinksBody),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class ProviderSetupScreen extends ConsumerStatefulWidget {
  const ProviderSetupScreen({super.key});

  @override
  ConsumerState<ProviderSetupScreen> createState() =>
      _ProviderSetupScreenState();
}

class _ProviderSetupScreenState extends ConsumerState<ProviderSetupScreen> {
  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final osc = Theme.of(context).extension<OscilloscopeColors>()!;
    final providersState = ref.watch(providerProfilesProvider);
    final models = ref
        .watch(modelOptionsProvider)
        .maybeWhen(
          data: (value) => value,
          orElse: () => const <AiModelOption>[],
        );
    final modelCountByProvider = <String, int>{};
    for (final model in models) {
      modelCountByProvider.update(
        model.providerId,
        (value) => value + 1,
        ifAbsent: () => 1,
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.providerSetup)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddProviderDialog,
        icon: const Icon(Icons.add),
        label: Text(l10n.addProvider),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ...providersState.when(
            data: (providers) => [
              if (providers.isEmpty)
                _PlaceholderCard(
                  title: l10n.providerManagement,
                  text: l10n.noConfiguredProviders,
                  icon: Icons.hub,
                ),
              for (final provider in providers) ...[
                ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                    side: BorderSide(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                  leading: const Icon(Icons.hub),
                  title: Text(provider.name),
                  subtitle: Text(
                    [
                      provider.type,
                      if (provider.baseUrl != null) provider.baseUrl!,
                      '${modelCountByProvider[provider.id] ?? 0} ${l10n.savedModels}',
                    ].join('\n'),
                  ),
                  isThreeLine: true,
                  onTap: () => _showProviderDialog(provider),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Tooltip(
                        message: provider.hasApiKey
                            ? l10n.apiKeySaved
                            : l10n.apiKeyNotSaved,
                        child: Icon(
                          provider.hasApiKey
                              ? Icons.key
                              : Icons.key_off_outlined,
                          color: provider.hasApiKey ? osc.phosphor : null,
                        ),
                      ),
                      IconButton(
                        tooltip: l10n.editProvider,
                        onPressed: () => _showProviderDialog(provider),
                        icon: const Icon(Icons.edit_outlined),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ],
            error: (error, stackTrace) => [
              _PlaceholderCard(
                title: l10n.failed,
                text: error.toString(),
                icon: Icons.error_outline,
              ),
            ],
            loading: () => const [Center(child: CircularProgressIndicator())],
          ),
        ],
      ),
    );
  }

  Future<void> _showAddProviderDialog() async {
    await _showProviderDialog();
  }

  Future<void> _showProviderDialog([ProviderProfile? provider]) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => ProviderFormScreen(provider: provider),
      ),
    );
    if (saved == true) {
      ref.invalidate(providerProfilesProvider);
      ref.invalidate(modelOptionsProvider);
      if (mounted) {
        showTopNotice(context, context.l10n.providerSaved);
      }
    }
  }
}

class ProviderFormScreen extends ConsumerStatefulWidget {
  const ProviderFormScreen({super.key, this.provider});

  final ProviderProfile? provider;

  @override
  ConsumerState<ProviderFormScreen> createState() => _ProviderFormScreenState();
}

class _ProviderFormScreenState extends ConsumerState<ProviderFormScreen> {
  final _nameController = TextEditingController();
  final _baseUrlController = TextEditingController(
    text: descriptorFor(AiProvider.openai).defaultBaseUrl,
  );
  final _apiKeyController = TextEditingController();
  final _manualModelController = TextEditingController();
  AiProvider _providerKey = AiProvider.openai;
  bool _busy = false;
  bool _loadingInitial = false;
  List<FetchedProviderModel> _models = const [];
  final Set<ModelCapability> _manualCapabilities = {
    ModelCapability.text,
    ModelCapability.structuring,
  };

  @override
  void initState() {
    super.initState();
    final provider = widget.provider;
    if (provider == null) {
      _models = _presetModelsFor(descriptorFor(_providerKey));
      return;
    }
    _loadingInitial = true;
    _providerKey = AiProvider.fromKey(provider.type);
    _nameController.text = provider.name;
    _baseUrlController.text =
        provider.baseUrl ?? descriptorFor(_providerKey).defaultBaseUrl;
    Future.microtask(_loadExistingProvider);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    _manualModelController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final disabled = _busy || _loadingInitial;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.provider == null ? l10n.addProvider : l10n.editProvider,
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_loadingInitial) ...[
                  const LinearProgressIndicator(),
                  const SizedBox(height: 12),
                ],
                DropdownButtonFormField<AiProvider>(
                  initialValue: _providerKey,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: l10n.providerType,
                    helperText: l10n.providerTypeHint,
                  ),
                  items: [
                    for (final descriptor in selectableProviders)
                      DropdownMenuItem(
                        value: descriptor.provider,
                        child: Text(
                          descriptor.displayName,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: disabled
                      ? null
                      : (value) {
                          if (value == null) {
                            return;
                          }
                          setState(() {
                            _providerKey = value;
                            final descriptor = descriptorFor(value);
                            _baseUrlController.text = descriptor.defaultBaseUrl;
                            _models = _presetModelsFor(descriptor);
                            if (_nameController.text.trim().isEmpty) {
                              _nameController.text = descriptor.displayName;
                            }
                          });
                        },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _nameController,
                  enabled: !disabled,
                  decoration: InputDecoration(
                    labelText: l10n.displayName,
                    helperText: l10n.displayNameHint,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _baseUrlController,
                  enabled: !disabled,
                  keyboardType: TextInputType.url,
                  decoration: InputDecoration(
                    labelText: l10n.baseUrl,
                    helperText: l10n.baseUrlHint,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _apiKeyController,
                  enabled: !disabled,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: l10n.apiKey,
                    helperText: l10n.apiKeyHint,
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.content_paste),
                      tooltip: l10n.paste,
                      onPressed: disabled ? null : _pasteApiKey,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: disabled ? null : _testConnection,
                    icon: const Icon(Icons.network_check),
                    label: Text(l10n.testConnection),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.savedModels,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                if (_models.isEmpty)
                  Text(l10n.noModelsSaved)
                else
                  for (final model in _models)
                    _FetchedModelTile(
                      model: model,
                      onSelectedChanged: (selected) {
                        setState(
                          () => _models = [
                            for (final item in _models)
                              item.id == model.id
                                  ? item.copyWith(selected: selected)
                                  : item,
                          ],
                        );
                      },
                      onCapabilitiesChanged: (capabilities) {
                        setState(
                          () => _models = [
                            for (final item in _models)
                              item.id == model.id
                                  ? item.copyWith(capabilities: capabilities)
                                  : item,
                          ],
                        );
                      },
                    ),
                const Divider(height: 24),
                Text(
                  l10n.addModel,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _manualModelController,
                  enabled: !disabled,
                  decoration: InputDecoration(
                    labelText: l10n.modelName,
                    helperText: l10n.modelNameHint,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.capabilityHint,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final capability in ModelCapability.values)
                      FilterChip(
                        label: Text(_capabilityLabel(context, capability)),
                        selected: _manualCapabilities.contains(capability),
                        onSelected: disabled
                            ? null
                            : (selected) {
                                setState(() {
                                  if (selected) {
                                    _manualCapabilities.add(capability);
                                  } else {
                                    _manualCapabilities.remove(capability);
                                  }
                                });
                              },
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: disabled ? null : _addManualModel,
                    icon: const Icon(Icons.add),
                    label: Text(l10n.addModel),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: disabled ? null : _saveProvider,
                    icon: _busy
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save),
                    label: Text(l10n.saveProvider),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _loadExistingProvider() async {
    final provider = widget.provider;
    if (provider == null) {
      return;
    }
    try {
      final connection = await ref
          .read(providerRepositoryProvider)
          .findConnection(provider.id);
      final models = await ref
          .read(modelRepositoryProvider)
          .listModelsForProvider(provider.id);
      if (!mounted) {
        return;
      }
      setState(() {
        final descriptor = descriptorFor(
          connection != null
              ? AiProvider.fromKey(connection.type)
              : _providerKey,
        );
        if (connection != null) {
          _providerKey = AiProvider.fromKey(connection.type);
          _nameController.text = connection.name;
          _baseUrlController.text =
              (connection.baseUrl != null && connection.baseUrl!.isNotEmpty)
              ? connection.baseUrl!
              : descriptor.defaultBaseUrl;
          _apiKeyController.text = connection.apiKey ?? '';
        }
        final presets = _presetModelsFor(descriptor);
        final persisted = models
            .map(
              (model) => FetchedProviderModel(
                id: model.name,
                capabilities: model.capabilities,
              ),
            )
            .toList();
        _models = _mergeFetchedModels(presets, persisted);
        _loadingInitial = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _loadingInitial = false);
      _showSnack(_errorLabel(context, '$error'));
    }
  }

  Future<void> _pasteApiKey() async {
    final data = await Clipboard.getData('text/plain');
    final text = data?.text?.trim();
    if (text != null && text.isNotEmpty) {
      setState(() => _apiKeyController.text = text);
    }
  }

  Future<void> _testConnection() async {
    final descriptor = descriptorFor(_providerKey);
    final structuringModel = descriptor.structuringModels.isNotEmpty
        ? descriptor.structuringModels.first.name
        : '';
    if (structuringModel.isEmpty) {
      _showSnack(context.l10n.connectionTestFailed);
      return;
    }
    await _runBusy(() async {
      await ref
          .read(providerStructuringClientProvider)
          .probe(
            descriptor: descriptor,
            baseUrl: _baseUrlController.text.trim().isEmpty
                ? descriptor.defaultBaseUrl
                : _baseUrlController.text.trim(),
            apiKey: _blankToNull(_apiKeyController.text),
            modelName: structuringModel,
          );
      if (mounted) {
        _showSnack(context.l10n.connectionTestSucceeded);
      }
    });
  }

  Future<void> _saveProvider() async {
    final l10n = context.l10n;
    final name = _nameController.text.trim();
    final baseUrl = _baseUrlController.text.trim();
    if (name.isEmpty) {
      _showSnack(l10n.providerRequiredFields);
      return;
    }
    final descriptor = descriptorFor(_providerKey);
    final effectiveBaseUrl = baseUrl.isEmpty
        ? descriptor.defaultBaseUrl
        : baseUrl;
    if (effectiveBaseUrl.isEmpty) {
      _showSnack(l10n.baseUrlRequired);
      return;
    }

    await _runBusy(() async {
      final providerId =
          widget.provider?.id ??
          'provider-${DateTime.now().toUtc().microsecondsSinceEpoch}';
      await ref
          .read(providerRepositoryProvider)
          .saveProvider(
            id: providerId,
            name: name,
            type: _providerKey.name,
            baseUrl: effectiveBaseUrl,
            apiKey: _blankToNull(_apiKeyController.text),
          );
      await ref
          .read(modelRepositoryProvider)
          .replaceModelsForProvider(
            providerId: providerId,
            models: _models
                .where((model) => model.selected)
                .map(
                  (model) => (name: model.id, capabilities: model.capabilities),
                ),
          );
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    });
  }

  void _addManualModel() {
    final name = _manualModelController.text.trim();
    if (name.isEmpty || _manualCapabilities.isEmpty) {
      _showSnack(context.l10n.modelRequiredFields);
      return;
    }
    final model = FetchedProviderModel(
      id: name,
      capabilities: {..._manualCapabilities},
    );
    setState(() {
      _models = _mergeFetchedModels(_models, [model]);
      _manualModelController.clear();
    });
  }

  Future<void> _runBusy(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      if (mounted) {
        _showSnack(_errorLabel(context, '$error'));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class ModelAssignmentScreen extends ConsumerStatefulWidget {
  const ModelAssignmentScreen({super.key});

  @override
  ConsumerState<ModelAssignmentScreen> createState() =>
      _ModelAssignmentScreenState();
}

class _ModelAssignmentScreenState extends ConsumerState<ModelAssignmentScreen> {
  String? _selectedTranscriptionProviderId;
  String? _selectedTranscriptionModelId;
  String? _selectedStreamingProviderId;
  String? _selectedStreamingModelId;
  String? _selectedStructuringProviderId;
  String? _selectedStructuringModelId;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final models = ref
        .watch(modelOptionsProvider)
        .maybeWhen(
          data: (value) => value,
          orElse: () => const <AiModelOption>[],
        );
    final providers = ref
        .watch(providerProfilesProvider)
        .maybeWhen(
          data: (value) => value,
          orElse: () => const <ProviderProfile>[],
        );
    final assignments = ref
        .watch(modelAssignmentsProvider)
        .maybeWhen(
          data: (value) => value,
          orElse: () => const <ModelAssignment>[],
        );
    final transcriptionAssignment = _assignmentFor(
      assignments,
      ModelAssignmentTask.transcription,
    );
    final streamingAssignment = _assignmentFor(
      assignments,
      ModelAssignmentTask.transcriptionStreaming,
    );
    final structuringAssignment = _assignmentFor(
      assignments,
      ModelAssignmentTask.structuring,
    );

    final selectedTranscriptionProvider =
        _selectedTranscriptionProviderId ??
        _validProviderId(providers, transcriptionAssignment?.providerId);
    final selectedStreamingProvider =
        _selectedStreamingProviderId ??
        _validProviderId(providers, streamingAssignment?.providerId);
    final selectedStructuringProvider =
        _selectedStructuringProviderId ??
        _validProviderId(providers, structuringAssignment?.providerId);

    final transcriptionModels = models
        .where(
          (model) =>
              model.providerId == selectedTranscriptionProvider &&
              model.supports(ModelCapability.speech),
        )
        .toList();
    final streamingModels = models
        .where(
          (model) =>
              model.providerId == selectedStreamingProvider &&
              model.supports(ModelCapability.streaming),
        )
        .toList();
    final structuringModels = models
        .where(
          (model) =>
              model.providerId == selectedStructuringProvider &&
              model.supports(ModelCapability.structuring),
        )
        .toList();
    final selectedTranscription = _validModelId(
      transcriptionModels,
      _selectedTranscriptionModelId ?? transcriptionAssignment?.modelId,
    );
    final selectedStreaming = _validModelId(
      streamingModels,
      _selectedStreamingModelId ?? streamingAssignment?.modelId,
    );
    final selectedStructuring = _validModelId(
      structuringModels,
      _selectedStructuringModelId ?? structuringAssignment?.modelId,
    );

    return Scaffold(
      appBar: AppBar(title: Text(l10n.modelAssignment)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (providers.isEmpty)
            _PlaceholderCard(
              title: l10n.providerManagement,
              text: l10n.noConfiguredProviders,
              icon: Icons.hub,
            ),
          _ModelAssignmentSection(
            title: l10n.transcriptionModelAfter,
            providers: providers,
            selectedProviderId: selectedTranscriptionProvider,
            models: transcriptionModels,
            selectedModelId: selectedTranscription,
            onProviderChanged: (value) {
              setState(() {
                _selectedTranscriptionProviderId = value;
                _selectedTranscriptionModelId = null;
              });
            },
            onChanged: (value) {
              setState(() => _selectedTranscriptionModelId = value);
            },
          ),
          const SizedBox(height: 16),
          _ModelAssignmentSection(
            title: l10n.transcriptionModelStreaming,
            providers: providers,
            selectedProviderId: selectedStreamingProvider,
            models: streamingModels,
            selectedModelId: selectedStreaming,
            onProviderChanged: (value) {
              setState(() {
                _selectedStreamingProviderId = value;
                _selectedStreamingModelId = null;
              });
            },
            onChanged: (value) {
              setState(() => _selectedStreamingModelId = value);
            },
          ),
          const SizedBox(height: 16),
          _ModelAssignmentSection(
            title: l10n.structuringModel,
            providers: providers,
            selectedProviderId: selectedStructuringProvider,
            models: structuringModels,
            selectedModelId: selectedStructuring,
            onProviderChanged: (value) {
              setState(() {
                _selectedStructuringProviderId = value;
                _selectedStructuringModelId = null;
              });
            },
            onChanged: (value) {
              setState(() => _selectedStructuringModelId = value);
            },
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () => _saveAssignments(
              models,
              selectedTranscription,
              selectedStreaming,
              selectedStructuring,
            ),
            icon: const Icon(Icons.save),
            label: Text(l10n.confirmAndSave),
          ),
        ],
      ),
    );
  }

  String? _validProviderId(List<ProviderProfile> providers, String? id) {
    if (id != null && providers.any((provider) => provider.id == id)) {
      return id;
    }
    return providers.isEmpty ? null : providers.first.id;
  }

  String? _validModelId(List<AiModelOption> models, String? id) {
    if (id != null && models.any((model) => model.id == id)) {
      return id;
    }
    return null;
  }

  ModelAssignment? _assignmentFor(
    List<ModelAssignment> assignments,
    ModelAssignmentTask task,
  ) {
    for (final assignment in assignments) {
      if (assignment.task == task) {
        return assignment;
      }
    }
    return null;
  }

  Future<void> _saveAssignments(
    List<AiModelOption> models,
    String? selectedTranscription,
    String? selectedStreaming,
    String? selectedStructuring,
  ) async {
    final transcription = _modelById(models, selectedTranscription);
    final structuring = _modelById(models, selectedStructuring);
    final streaming = _modelById(models, selectedStreaming);
    if (transcription == null || structuring == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.modelAssignmentRequired)),
      );
      return;
    }
    final notifier = ref.read(modelAssignmentsProvider.notifier);
    await notifier.save(
      ModelAssignment(
        task: ModelAssignmentTask.transcription,
        providerId: transcription.providerId,
        modelId: transcription.id,
      ),
    );
    if (streaming != null) {
      await notifier.save(
        ModelAssignment(
          task: ModelAssignmentTask.transcriptionStreaming,
          providerId: streaming.providerId,
          modelId: streaming.id,
        ),
      );
    }
    await notifier.save(
      ModelAssignment(
        task: ModelAssignmentTask.structuring,
        providerId: structuring.providerId,
        modelId: structuring.id,
      ),
    );
    if (mounted) {
      showTopNotice(context, context.l10n.modelAssignmentSaved);
    }
  }

  AiModelOption? _modelById(List<AiModelOption> models, String? id) {
    if (id == null) {
      return null;
    }
    for (final model in models) {
      if (model.id == id) {
        return model;
      }
    }
    return null;
  }
}

class QsoReviewScreen extends ConsumerStatefulWidget {
  const QsoReviewScreen({
    super.key,
    required this.draft,
    this.importJobId,
    this.recordInSession = false,
  });

  final QsoDraft draft;
  final String? importJobId;
  final bool recordInSession;

  @override
  ConsumerState<QsoReviewScreen> createState() => _QsoReviewScreenState();
}

class _QsoReviewScreenState extends ConsumerState<QsoReviewScreen> {
  late LogStatus status = widget.draft.status;
  late QsoDraft _baseDraft;
  final Set<QsoFieldKey> _editedFields = {};
  final Set<QsoFieldKey> _reviewedFields = {};
  late final TextEditingController _callsignController;
  late final TextEditingController _frequencyController;
  late final TextEditingController _sentRstController;
  late final TextEditingController _receivedRstController;
  late final TextEditingController _nameController;
  late final TextEditingController _qthController;
  late final TextEditingController _rigController;
  late final TextEditingController _antennaController;
  late final TextEditingController _powerController;
  late final TextEditingController _notesController;
  StationEquipment? _selectedEquipment;
  late DateTime? _dateTime;
  late String? _band;
  late String? _mode;
  bool _bandSuggested = false;
  String? _frequencyError;
  late String? _audioPath;
  late bool _originalAudioDeleted;
  late String? _rawTranscript;
  late List<TranscriptSegment> _transcriptSegments;
  bool _isAudioPlaying = false;
  String? _audioPlaybackError;
  bool _retrying = false;
  bool _qrzUploading = false;
  late final Future<void> Function() _stopAudioPlayback;

  @override
  void initState() {
    super.initState();
    _stopAudioPlayback = ref.read(audioPlaybackServiceProvider).stop;
    final draft = widget.draft;
    _baseDraft = draft;
    _callsignController = TextEditingController(text: draft.callsign.value);
    _frequencyController = TextEditingController(text: draft.frequency.value);
    _sentRstController = TextEditingController(text: draft.sentRst.value);
    _receivedRstController = TextEditingController(
      text: draft.receivedRst.value,
    );
    _nameController = TextEditingController(text: draft.name?.value ?? '');
    _qthController = TextEditingController(text: draft.qth?.value ?? '');
    _rigController = TextEditingController(text: draft.rig?.value ?? '');
    _antennaController = TextEditingController(
      text: draft.antenna?.value ?? '',
    );
    _powerController = TextEditingController(text: draft.power?.value ?? '');
    _notesController = TextEditingController(text: draft.notes?.value ?? '');
    _dateTime = draft.dateTime.value;
    _band = draft.band.value.trim().isEmpty ? null : draft.band.value.trim();
    _mode = draft.mode.value.trim().isEmpty ? null : draft.mode.value.trim();
    _audioPath = draft.audioPath;
    _originalAudioDeleted = draft.originalAudioDeleted;
    _rawTranscript = draft.rawTranscript;
    _transcriptSegments = draft.transcriptSegments;
  }

  @override
  void dispose() {
    _callsignController.dispose();
    _frequencyController.dispose();
    _sentRstController.dispose();
    _receivedRstController.dispose();
    _nameController.dispose();
    _qthController.dispose();
    _rigController.dispose();
    _antennaController.dispose();
    _powerController.dispose();
    _notesController.dispose();
    unawaited(_stopAudioPlayback());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final qsoId = _baseDraft.id;
    final uploadHasUnreviewedFields = _buildDraft().hasUnreviewedFields;
    final uploadHasEligibleStatus =
        status == LogStatus.confirmed || status == LogStatus.exported;
    final bandOrFrequencyMissing =
        _band == null && _frequencyController.text.trim().isEmpty;
    final qrzUploadState = qsoId == null
        ? null
        : ref.watch(qrzUploadProvider(qsoId));

    return Scaffold(
      appBar: AppBar(title: Text(l10n.qsoReview)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          if (status == LogStatus.exported)
            Align(
              alignment: Alignment.centerLeft,
              child: _StatusChip(status: status),
            )
          else
            DropdownButtonFormField<LogStatus>(
              initialValue: status,
              decoration: InputDecoration(labelText: l10n.status),
              items: [
                if (status == LogStatus.failed)
                  DropdownMenuItem(
                    value: LogStatus.failed,
                    enabled: false,
                    child: Text(_statusLabel(context, LogStatus.failed)),
                  ),
                for (final editableStatus in const [
                  LogStatus.draft,
                  LogStatus.needsReview,
                  LogStatus.confirmed,
                ])
                  DropdownMenuItem(
                    value: editableStatus,
                    child: Text(_statusLabel(context, editableStatus)),
                  ),
              ],
              onChanged: (value) {
                if (value != null) {
                  setState(() => status = value);
                }
              },
            ),
          // 失败状态：错误卡片 + 重试按钮
          if (status == LogStatus.failed) ...[
            const SizedBox(height: 12),
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.error_outline,
                          color: Theme.of(context).colorScheme.error,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          l10n.failed,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onErrorContainer,
                              ),
                        ),
                      ],
                    ),
                    if (_baseDraft.errorMessage != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _errorLabel(context, _baseDraft.errorMessage!),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    FilledButton.tonalIcon(
                      onPressed: _retrying ? null : _retryFinishQso,
                      icon: _retrying
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh),
                      label: Text(_retrying ? l10n.retrying : l10n.retry),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (status != LogStatus.failed &&
              _baseDraft.errorMessage != null) ...[
            const SizedBox(height: 12),
            _PlaceholderCard(
              title: l10n.needsReview,
              text: _errorLabel(context, _baseDraft.errorMessage!),
              icon: Icons.info_outline,
            ),
          ],
          if (qsoId != null) ...[
            const SizedBox(height: 16),
            _CardSection(
              title: l10n.logbookUploads,
              children: [
                qrzUploadState!.when(
                  skipLoadingOnRefresh: false,
                  data: (entry) => _LogbookUploadRow(
                    title: 'QRZ',
                    status: entry?.status,
                    detail:
                        entry?.status == LogbookUploadStatus.pending &&
                            !_qrzUploading
                        ? l10n.qrzUploadPendingUnknown
                        : entry?.errorMessage ?? entry?.remoteId,
                    busy: _qrzUploading,
                    enabled:
                        !_qrzUploading &&
                        entry?.status != LogbookUploadStatus.succeeded &&
                        entry?.status != LogbookUploadStatus.stale &&
                        uploadHasEligibleStatus &&
                        !uploadHasUnreviewedFields,
                    disabledReason:
                        entry?.status == LogbookUploadStatus.succeeded
                        ? l10n.uploadSucceeded
                        : entry?.status == LogbookUploadStatus.stale
                        ? l10n.logbookUploadStale
                        : !uploadHasEligibleStatus
                        ? l10n.confirmBeforeUpload
                        : uploadHasUnreviewedFields
                        ? l10n.unreviewedFieldsRemain
                        : null,
                    onUpload: _uploadToQrz,
                  ),
                  error: (error, stackTrace) => _UpdateStatusRow(
                    icon: Icons.error_outline,
                    text: error.toString(),
                    isError: true,
                  ),
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          _CardSection(
            title: l10n.contactInfo,
            children: [
              _ReviewField(
                label: l10n.callsign,
                controller: _callsignController,
                requiredField: true,
                needsReview: _needsStringReview(
                  QsoFieldKey.callsign,
                  _baseDraft.callsign,
                  requiredMissing: _callsignController.text.trim().isEmpty,
                ),
                sourceText: _baseDraft.callsign.sourceText,
                onReviewed: () => _markFieldReviewed(QsoFieldKey.callsign),
                onChanged: (_) => _markFieldEdited(QsoFieldKey.callsign),
              ),
              _FieldReviewFrame(
                needsReview: _needsDateTimeReview(
                  requiredMissing: _dateTime == null,
                ),
                sourceText: _baseDraft.dateTime.sourceText,
                onReviewed: () => _markFieldReviewed(QsoFieldKey.dateTime),
                child: GestureDetector(
                  onTap: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: _dateTime ?? DateTime.now(),
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (date == null || !mounted) return;
                    if (!context.mounted) return;
                    final time = await showTimePicker(
                      context: context,
                      initialTime: TimeOfDay.fromDateTime(
                        _dateTime ?? DateTime.now(),
                      ),
                    );
                    if (!mounted) return;
                    setState(() {
                      _editedFields.add(QsoFieldKey.dateTime);
                      _dateTime = time == null
                          ? date
                          : DateTime(
                              date.year,
                              date.month,
                              date.day,
                              time.hour,
                              time.minute,
                            );
                    });
                  },
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: l10n.dateTime,
                      suffixIcon: const Icon(Icons.event, size: 18),
                    ),
                    child: Text(
                      _dateTime == null ? '—' : _formatDateTime(_dateTime!),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 8),
                child: Text(
                  l10n.bandOrFrequencyRequired,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
              _TwoColumnFields(
                left: _FieldReviewFrame(
                  needsReview: _needsStringReview(
                    QsoFieldKey.band,
                    _baseDraft.band,
                    requiredMissing: bandOrFrequencyMissing,
                  ),
                  sourceText: _baseDraft.band.sourceText,
                  onReviewed: () => _markFieldReviewed(QsoFieldKey.band),
                  child: _BandDropdown(
                    value: _band,
                    helperText: _bandSuggested ? l10n.suggestedBand : null,
                    onChanged: (value) => setState(() {
                      _editedFields.add(QsoFieldKey.band);
                      _band = value;
                      _bandSuggested = false;
                    }),
                  ),
                ),
                right: _FieldReviewFrame(
                  needsReview: _needsStringReview(
                    QsoFieldKey.frequency,
                    _baseDraft.frequency,
                    requiredMissing: bandOrFrequencyMissing,
                  ),
                  sourceText: _baseDraft.frequency.sourceText,
                  onReviewed: () => _markFieldReviewed(QsoFieldKey.frequency),
                  child: TextFormField(
                    controller: _frequencyController,
                    decoration: InputDecoration(
                      labelText: l10n.frequency,
                      errorText: _frequencyError,
                      suffixText: 'MHz',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    onChanged: (value) => _handleFrequencyChanged(value, l10n),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _FieldReviewFrame(
                needsReview: _needsStringReview(
                  QsoFieldKey.mode,
                  _baseDraft.mode,
                  requiredMissing: _mode == null,
                ),
                sourceText: _baseDraft.mode.sourceText,
                onReviewed: () => _markFieldReviewed(QsoFieldKey.mode),
                child: _ModeDropdown(
                  value: _mode,
                  onChanged: (value) => setState(() {
                    _editedFields.add(QsoFieldKey.mode);
                    _mode = value;
                  }),
                ),
              ),
              const SizedBox(height: 12),
              _TwoColumnFields(
                left: _ReviewField(
                  label: l10n.sentRst,
                  controller: _sentRstController,
                  requiredField: true,
                  needsReview: _needsStringReview(
                    QsoFieldKey.sentRst,
                    _baseDraft.sentRst,
                    requiredMissing: _sentRstController.text.trim().isEmpty,
                  ),
                  sourceText: _baseDraft.sentRst.sourceText,
                  onReviewed: () => _markFieldReviewed(QsoFieldKey.sentRst),
                  onChanged: (_) => _markFieldEdited(QsoFieldKey.sentRst),
                ),
                right: _ReviewField(
                  label: l10n.receivedRst,
                  controller: _receivedRstController,
                  requiredField: true,
                  needsReview: _needsStringReview(
                    QsoFieldKey.receivedRst,
                    _baseDraft.receivedRst,
                    requiredMissing: _receivedRstController.text.trim().isEmpty,
                  ),
                  sourceText: _baseDraft.receivedRst.sourceText,
                  onReviewed: () => _markFieldReviewed(QsoFieldKey.receivedRst),
                  onChanged: (_) => _markFieldEdited(QsoFieldKey.receivedRst),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _CardSection(
            title: l10n.operatorInfo,
            children: [
              _TwoColumnFields(
                left: _ReviewField(
                  label: l10n.name,
                  controller: _nameController,
                  needsReview:
                      _baseDraft.name != null &&
                      _needsStringReview(QsoFieldKey.name, _baseDraft.name!),
                  sourceText: _baseDraft.name?.sourceText,
                  onReviewed: () => _markFieldReviewed(QsoFieldKey.name),
                  onChanged: (_) => _markFieldEdited(QsoFieldKey.name),
                ),
                right: _ReviewField(
                  label: l10n.qth,
                  controller: _qthController,
                  needsReview:
                      _baseDraft.qth != null &&
                      _needsStringReview(QsoFieldKey.qth, _baseDraft.qth!),
                  sourceText: _baseDraft.qth?.sourceText,
                  onReviewed: () => _markFieldReviewed(QsoFieldKey.qth),
                  onChanged: (_) => _markFieldEdited(QsoFieldKey.qth),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _CardSection(
            title: l10n.stationInfo,
            children: [
              _ReviewField(
                label: l10n.rig,
                controller: _rigController,
                needsReview:
                    _baseDraft.rig != null &&
                    _needsStringReview(QsoFieldKey.rig, _baseDraft.rig!),
                sourceText: _baseDraft.rig?.sourceText,
                onReviewed: () => _markFieldReviewed(QsoFieldKey.rig),
                onChanged: (_) => _markFieldEdited(QsoFieldKey.rig),
              ),
              _EquipmentSelector(
                selectedEquipment: _selectedEquipment,
                onSelected: (equipment) {
                  setState(() {
                    _selectedEquipment = equipment;
                    if (equipment != null) {
                      _editedFields.addAll(const {
                        QsoFieldKey.rig,
                        QsoFieldKey.antenna,
                        QsoFieldKey.power,
                      });
                      _rigController.text = equipment.name;
                      _antennaController.text = equipment.antenna;
                      if (equipment.powerOptions.isNotEmpty) {
                        _powerController.text = equipment.powerOptions.first;
                      }
                    }
                  });
                },
              ),
              const SizedBox(height: 12),
              _FieldReviewFrame(
                needsReview:
                    _baseDraft.antenna != null &&
                    _needsStringReview(
                      QsoFieldKey.antenna,
                      _baseDraft.antenna!,
                    ),
                sourceText: _baseDraft.antenna?.sourceText,
                onReviewed: () => _markFieldReviewed(QsoFieldKey.antenna),
                child: _AntennaDropdown(
                  controller: _antennaController,
                  onChanged: (_) => _markFieldEdited(QsoFieldKey.antenna),
                ),
              ),
              _FieldReviewFrame(
                needsReview:
                    _baseDraft.power != null &&
                    _needsStringReview(QsoFieldKey.power, _baseDraft.power!),
                sourceText: _baseDraft.power?.sourceText,
                onReviewed: () => _markFieldReviewed(QsoFieldKey.power),
                child: _PowerDropdown(
                  controller: _powerController,
                  powerOptions: _selectedEquipment?.powerOptions ?? const [],
                  onChanged: (_) => _markFieldEdited(QsoFieldKey.power),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _CardSection(
            title: l10n.notesSection,
            children: [
              _ReviewField(
                label: l10n.notes,
                controller: _notesController,
                maxLines: 3,
                needsReview:
                    _baseDraft.notes != null &&
                    _needsStringReview(QsoFieldKey.notes, _baseDraft.notes!),
                sourceText: _baseDraft.notes?.sourceText,
                onReviewed: () => _markFieldReviewed(QsoFieldKey.notes),
                onChanged: (_) => _markFieldEdited(QsoFieldKey.notes),
              ),
              const SizedBox(height: 12),
              _RetainedAudioCard(
                title: l10n.audioLog,
                path: _audioPath,
                missingText: _originalAudioDeleted
                    ? l10n.originalAudioDeleted
                    : l10n.noAudioFile,
                isPlaying: _isAudioPlaying,
                errorText: _audioPlaybackError,
                playLabel: l10n.playAudio,
                stopLabel: l10n.stopAudio,
                deleteLabel: l10n.deleteRetainedAudio,
                onPlayPressed: _audioPath == null ? null : _toggleAudioPlayback,
                onDelete: _audioPath == null ? null : _deleteRetainedAudio,
              ),
              const SizedBox(height: 12),
              if (_transcriptSegments.isNotEmpty)
                _RetainedTranscriptCard(
                  title: l10n.originalTranscript,
                  segments: _transcriptSegments,
                  otherCallsign: _callsignController.text,
                  deleteLabel: l10n.deleteRawTranscript,
                  onDelete: _rawTranscript?.trim().isNotEmpty ?? false
                      ? _deleteRawTranscript
                      : null,
                )
              else
                _RetainedDataCard(
                  title: l10n.originalTranscript,
                  text: _rawTranscript?.trim().isNotEmpty ?? false
                      ? _rawTranscript!
                      : l10n.noRawTranscript,
                  icon: Icons.notes,
                  deleteLabel: l10n.deleteRawTranscript,
                  onDelete: _rawTranscript?.trim().isNotEmpty ?? false
                      ? _deleteRawTranscript
                      : null,
                ),
            ],
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton.icon(
            onPressed: () async {
              if (!_validateFrequency(l10n)) {
                return;
              }
              final updated = _buildDraft();
              if ((status == LogStatus.confirmed ||
                      status == LogStatus.exported) &&
                  !updated.hasRequiredFields) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l10n.requiredFieldsMissing)),
                );
                return;
              }
              if ((status == LogStatus.confirmed ||
                      status == LogStatus.exported) &&
                  updated.hasUnreviewedFields) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l10n.unreviewedFieldsRemain)),
                );
                return;
              }
              final log = ref.read(qsoLogProvider.notifier);
              final id = widget.recordInSession
                  ? await log.saveAndRecordInSession(updated)
                  : await log.save(updated);
              final importJobId = widget.importJobId;
              if (importJobId != null) {
                await ref
                    .read(importJobsProvider.notifier)
                    .attachGeneratedQso(importJobId: importJobId, qsoId: id);
              }
              if (context.mounted) {
                Navigator.of(context).pop();
              }
            },
            icon: const Icon(Icons.save),
            label: Text(l10n.confirmAndSave),
          ),
        ),
      ),
    );
  }

  void _handleFrequencyChanged(String value, AppLocalizations l10n) {
    final parsed = double.tryParse(value.trim());
    final suggestedBand = parsed == null ? null : _suggestBand(parsed);
    setState(() {
      _editedFields.add(QsoFieldKey.frequency);
      _frequencyError = _frequencyErrorText(value, l10n);
      if (suggestedBand != null && _band == null) {
        _editedFields.add(QsoFieldKey.band);
        _band = suggestedBand;
        _bandSuggested = true;
      }
    });
  }

  bool _validateFrequency(AppLocalizations l10n) {
    final error = _frequencyErrorText(_frequencyController.text, l10n);
    setState(() => _frequencyError = error);
    return error == null;
  }

  String? _frequencyErrorText(String value, AppLocalizations l10n) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final parsed = double.tryParse(trimmed);
    if (parsed == null || parsed < 0.1 || parsed > 30000) {
      return l10n.invalidFrequency;
    }
    return null;
  }

  QsoDraft _buildDraft() {
    final draft = _baseDraft;
    return QsoDraft(
      id: draft.id,
      callsign: _buildTextField(
        draft.callsign,
        _callsignController.text,
        QsoFieldKey.callsign,
      ),
      dateTime: _buildDateTimeField(draft.dateTime),
      band: _buildTextField(draft.band, _band ?? '', QsoFieldKey.band),
      frequency: _buildTextField(
        draft.frequency,
        _frequencyController.text,
        QsoFieldKey.frequency,
      ),
      mode: _buildTextField(draft.mode, _mode ?? '', QsoFieldKey.mode),
      sentRst: _buildTextField(
        draft.sentRst,
        _sentRstController.text,
        QsoFieldKey.sentRst,
      ),
      receivedRst: _buildTextField(
        draft.receivedRst,
        _receivedRstController.text,
        QsoFieldKey.receivedRst,
      ),
      status: status == LogStatus.exported ? LogStatus.confirmed : status,
      name: _buildOptionalField(
        draft.name,
        _nameController.text,
        QsoFieldKey.name,
      ),
      qth: _buildOptionalField(draft.qth, _qthController.text, QsoFieldKey.qth),
      notes: _buildOptionalField(
        draft.notes,
        _notesController.text,
        QsoFieldKey.notes,
      ),
      rig: _buildOptionalField(draft.rig, _rigController.text, QsoFieldKey.rig),
      antenna: _buildOptionalField(
        draft.antenna,
        _antennaController.text,
        QsoFieldKey.antenna,
      ),
      power: _buildOptionalField(
        draft.power,
        _powerController.text,
        QsoFieldKey.power,
      ),
      audioPath: _audioPath,
      originalAudioDeleted: _originalAudioDeleted,
      rawTranscript: _rawTranscript,
      transcriptSegments: _transcriptSegments,
      errorMessage: draft.errorMessage,
      updatedAt: draft.updatedAt,
    );
  }

  QsoField<String> _buildTextField(
    QsoField<String> original,
    String value,
    QsoFieldKey key,
  ) {
    if (_editedFields.contains(key)) {
      return original.copyWith(
        value: value.trim(),
        userEdited: true,
        reviewed: true,
      );
    }
    if (_reviewedFields.contains(key)) {
      return original.copyWith(reviewed: true);
    }
    return original;
  }

  QsoField<DateTime?> _buildDateTimeField(QsoField<DateTime?> original) {
    if (_editedFields.contains(QsoFieldKey.dateTime)) {
      return original.copyWith(
        value: _dateTime,
        userEdited: true,
        reviewed: true,
      );
    }
    if (_reviewedFields.contains(QsoFieldKey.dateTime)) {
      return original.copyWith(reviewed: true);
    }
    return original;
  }

  QsoField<String>? _buildOptionalField(
    QsoField<String>? original,
    String value,
    QsoFieldKey key,
  ) {
    if (_editedFields.contains(key)) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) {
        return null;
      }
      return (original ?? const QsoField(value: '')).copyWith(
        value: trimmed,
        userEdited: true,
        reviewed: true,
      );
    }
    if (_reviewedFields.contains(key) && original != null) {
      return original.copyWith(reviewed: true);
    }
    return original;
  }

  void _markFieldEdited(QsoFieldKey key) {
    if (_editedFields.add(key)) {
      setState(() {});
    }
  }

  void _markFieldReviewed(QsoFieldKey key) {
    setState(() => _reviewedFields.add(key));
  }

  bool _needsStringReview(
    QsoFieldKey key,
    QsoField<String> field, {
    bool requiredMissing = false,
  }) {
    if (_editedFields.contains(key) ||
        _reviewedFields.contains(key) ||
        field.userEdited ||
        field.reviewed) {
      return false;
    }
    return (field.value.trim().isNotEmpty && field.confidence < 0.75) ||
        requiredMissing;
  }

  bool _needsDateTimeReview({required bool requiredMissing}) {
    final field = _baseDraft.dateTime;
    if (_editedFields.contains(QsoFieldKey.dateTime) ||
        _reviewedFields.contains(QsoFieldKey.dateTime) ||
        field.userEdited ||
        field.reviewed) {
      return false;
    }
    return (field.value != null && field.confidence < 0.75) || requiredMissing;
  }

  Future<void> _retryFinishQso() async {
    setState(() => _retrying = true);
    try {
      final draft = await ref
          .read(qsoCaptureProvider.notifier)
          .finishQso(
            audioPath: _audioPath,
            startedAt: widget.draft.dateTime.value,
            mode: TranscriptionMode.afterQso,
            failureHandling: ref.read(failureHandlingProvider),
          );
      if (!mounted) return;
      setState(() {
        _baseDraft = draft;
        _editedFields.clear();
        _reviewedFields.clear();
        status = draft.status;
        _retrying = false;
        // 用重试结果更新字段
        _callsignController.text = draft.callsign.value;
        _frequencyController.text = draft.frequency.value;
        _sentRstController.text = draft.sentRst.value;
        _receivedRstController.text = draft.receivedRst.value;
        _nameController.text = draft.name?.value ?? '';
        _qthController.text = draft.qth?.value ?? '';
        _rigController.text = draft.rig?.value ?? '';
        _antennaController.text = draft.antenna?.value ?? '';
        _powerController.text = draft.power?.value ?? '';
        _notesController.text = draft.notes?.value ?? '';
        _dateTime = draft.dateTime.value;
        _band = draft.band.value.trim().isEmpty
            ? null
            : draft.band.value.trim();
        _mode = draft.mode.value.trim().isEmpty
            ? null
            : draft.mode.value.trim();
        _audioPath = draft.audioPath;
        _originalAudioDeleted = draft.originalAudioDeleted;
        _rawTranscript = draft.rawTranscript;
        _transcriptSegments = draft.transcriptSegments;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _retrying = false);
    }
  }

  Future<void> _uploadToQrz() async {
    final qsoId = widget.draft.id;
    if (qsoId == null || _qrzUploading) {
      return;
    }
    final l10n = context.l10n;
    if (!_validateFrequency(l10n)) {
      return;
    }
    final updated = _buildDraft();
    if (updated.status != LogStatus.confirmed &&
        updated.status != LogStatus.exported) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.confirmBeforeUpload)));
      return;
    }
    if (!updated.hasRequiredFields) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.requiredFieldsMissing)));
      return;
    }
    if (updated.hasUnreviewedFields) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.unreviewedFieldsRemain)));
      return;
    }

    setState(() => _qrzUploading = true);
    final repository = ref.read(logbookUploadRepositoryProvider);
    try {
      final existing = await repository.findUpload(
        qsoId: qsoId,
        logbook: ExternalLogbook.qrz,
      );
      if (existing?.status == LogbookUploadStatus.succeeded ||
          existing?.status == LogbookUploadStatus.stale) {
        if (mounted) {
          final message = existing?.status == LogbookUploadStatus.stale
              ? l10n.logbookUploadStale
              : l10n.uploadSucceeded;
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(message)));
        }
        return;
      }

      final retryPending = existing?.status == LogbookUploadStatus.pending;
      if (retryPending) {
        if (!mounted) return;
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(l10n.pending),
            content: Text(l10n.qrzUploadPendingUnknown),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: Text(
                  MaterialLocalizations.of(dialogContext).cancelButtonLabel,
                ),
              ),
              FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                child: Text(l10n.qrzConfirmPendingRetry),
              ),
            ],
          ),
        );
        if (confirmed != true || !mounted) return;
      }

      final savedId = await ref.read(qsoLogProvider.notifier).save(updated);
      final persisted = await ref.read(qsoRepositoryProvider).findQso(savedId);
      if (persisted == null) {
        throw StateError('saved_qso_not_found');
      }
      if (mounted) {
        setState(() => status = persisted.status);
      }
      final apiKey = await ref.read(settingsRepositoryProvider).loadQrzApiKey();
      if (apiKey.trim().isEmpty) {
        throw const QrzUploadException(QrzUploadFailureReason.missingApiKey);
      }
      final started = await repository.saveUpload(
        qsoId: qsoId,
        logbook: ExternalLogbook.qrz,
        status: LogbookUploadStatus.pending,
        allowPendingRetry: retryPending,
      );
      if (!started) {
        final blocked = await repository.findUpload(
          qsoId: qsoId,
          logbook: ExternalLogbook.qrz,
        );
        if (mounted) {
          final message = switch (blocked?.status) {
            LogbookUploadStatus.succeeded => l10n.uploadSucceeded,
            LogbookUploadStatus.stale => l10n.logbookUploadStale,
            LogbookUploadStatus.pending => l10n.qrzUploadPendingUnknown,
            LogbookUploadStatus.failed || null => l10n.qrzUploadFailed,
          };
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(message)));
        }
        return;
      }
      ref.invalidate(qrzUploadProvider(qsoId));

      final result = await ref
          .read(qrzLogbookUploadServiceProvider)
          .upload(apiKey: apiKey, qso: persisted);
      await repository.saveUpload(
        qsoId: qsoId,
        logbook: ExternalLogbook.qrz,
        status: LogbookUploadStatus.succeeded,
        remoteId: result.remoteId,
        uploadedQso: persisted,
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.qrzUploadSucceeded)));
      }
    } on QrzUploadException catch (error) {
      final message = _qrzUploadErrorLabel(l10n, error);
      final definitelyFailed = switch (error.reason) {
        QrzUploadFailureReason.missingApiKey ||
        QrzUploadFailureReason.requiredFieldsMissing ||
        QrzUploadFailureReason.rejected => true,
        QrzUploadFailureReason.httpError ||
        QrzUploadFailureReason.networkError ||
        QrzUploadFailureReason.badResponse => false,
      };
      if (definitelyFailed) {
        await repository.saveUpload(
          qsoId: qsoId,
          logbook: ExternalLogbook.qrz,
          status: LogbookUploadStatus.failed,
          errorMessage: message,
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${l10n.errorDetail}: $error'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      ref.invalidate(qrzUploadProvider(qsoId));
      if (mounted) {
        setState(() => _qrzUploading = false);
      }
    }
  }

  Future<void> _deleteRetainedAudio() async {
    final audioPath = _audioPath;
    if (audioPath == null) {
      return;
    }
    final confirmed = await _confirmDestructiveAction(
      context,
      title: context.l10n.deleteRetainedAudio,
      message: context.l10n.deleteRetainedAudioConfirm,
    );
    if (!confirmed) {
      return;
    }
    await ref.read(audioPlaybackServiceProvider).stop();
    final trashFiles = await ref
        .read(qsoLogProvider.notifier)
        .deleteRetainedAudio(qsoId: widget.draft.id, path: audioPath);
    if (!mounted) {
      return;
    }
    setState(() {
      _audioPath = null;
      _originalAudioDeleted = true;
      _transcriptSegments = [
        for (final segment in _transcriptSegments)
          segment.copyWith(clearAudioPath: true),
      ];
      _isAudioPlaying = false;
      _audioPlaybackError = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.l10n.retainedAudioDeleted),
        action: SnackBarAction(
          label: context.l10n.undo,
          onPressed: () async {
            await ref
                .read(qsoLogProvider.notifier)
                .restoreRetainedAudio(
                  qsoId: widget.draft.id,
                  path: audioPath,
                  trashFiles: trashFiles,
                );
            if (mounted) {
              setState(() {
                _audioPath = audioPath;
                _originalAudioDeleted = false;
                _transcriptSegments = [
                  for (final segment in _transcriptSegments)
                    segment.copyWith(audioPath: audioPath),
                ];
              });
            }
          },
        ),
      ),
    );
  }

  Future<void> _toggleAudioPlayback() async {
    final audioPath = _audioPath;
    if (audioPath == null) {
      return;
    }

    final service = ref.read(audioPlaybackServiceProvider);
    if (_isAudioPlaying) {
      await service.stop();
      if (mounted) {
        setState(() {
          _isAudioPlaying = false;
          _audioPlaybackError = null;
        });
      }
      return;
    }

    setState(() {
      _isAudioPlaying = true;
      _audioPlaybackError = null;
    });
    try {
      await service.play(audioPath);
      if (mounted) {
        setState(() => _isAudioPlaying = false);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _isAudioPlaying = false;
          _audioPlaybackError =
              '${context.l10n.audioPlaybackFailed}: ${_errorLabel(context, '$error')}';
        });
      }
    }
  }

  Future<void> _deleteRawTranscript() async {
    final previousText = _rawTranscript;
    final previousSegments = _transcriptSegments;
    final previousQsoId = widget.draft.id;
    final previousImportId = widget.importJobId;
    final confirmed = await _confirmDestructiveAction(
      context,
      title: context.l10n.deleteRawTranscript,
      message: context.l10n.deleteRawTranscriptConfirm,
    );
    if (!confirmed) {
      return;
    }
    if (!mounted) {
      return;
    }
    final previousImportRawText = previousImportId == null
        ? null
        : await ref
              .read(importJobsProvider.notifier)
              .rawTextForJob(previousImportId);
    await ref.read(qsoLogProvider.notifier).clearRawTranscript(widget.draft.id);
    if (previousImportId != null) {
      await ref
          .read(importJobsProvider.notifier)
          .clearRawText(previousImportId);
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _rawTranscript = null;
      _transcriptSegments = const [];
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.l10n.rawTranscriptDeleted),
        action: SnackBarAction(
          label: context.l10n.undo,
          onPressed: () async {
            if (previousQsoId != null) {
              await ref
                  .read(qsoLogProvider.notifier)
                  .restoreRawTranscript(
                    qsoId: previousQsoId,
                    rawTranscript: previousText,
                    transcriptSegments: previousSegments,
                  );
            }
            if (previousImportId != null) {
              await ref
                  .read(importJobsProvider.notifier)
                  .restoreRawText(previousImportId, previousImportRawText);
            }
            if (mounted) {
              setState(() {
                _rawTranscript = previousText;
                _transcriptSegments = previousSegments;
              });
            }
          },
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.number, required this.title});

  final int number;
  final String title;

  @override
  Widget build(BuildContext context) {
    final osc = Theme.of(context).extension<OscilloscopeColors>()!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 18,
            decoration: BoxDecoration(
              color: osc.phosphor,
              boxShadow: [
                BoxShadow(
                  color: osc.phosphor.withAlpha(80),
                  blurRadius: 6,
                  spreadRadius: 0,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '[${number.toString().padLeft(2, '0')}]',
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: osc.phosphorDim),
          ),
          const SizedBox(width: 10),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
        ],
      ),
    );
  }
}

class _ChoiceCard<T> extends StatelessWidget {
  const _ChoiceCard({
    required this.value,
    required this.groupValue,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onSelected,
  });

  final T value;
  final T groupValue;
  final String title;
  final String subtitle;
  final IconData icon;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final selected = value == groupValue;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => onSelected(value),
        child: Card(
          color: selected
              ? Theme.of(context).colorScheme.primaryContainer
              : null,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Icon(icon),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(subtitle),
                    ],
                  ),
                ),
                if (selected)
                  Icon(
                    Icons.check_circle_outline,
                    color: Theme.of(context).colorScheme.primary,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusPanel extends StatelessWidget {
  const _StatusPanel({
    required this.title,
    required this.elapsed,
    required this.active,
  });

  final String title;
  final Duration elapsed;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final minutes = elapsed.inMinutes.toString().padLeft(2, '0');
    final seconds = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
    final osc = Theme.of(context).extension<OscilloscopeColors>()!;
    final l10n = context.l10n;
    return Semantics(
      label:
          '$title, ${active ? l10n.recording : l10n.startQso}, $minutes:$seconds',
      child: Card(
        color: active
            ? osc.phosphor.withAlpha(20)
            : Theme.of(context).colorScheme.surface,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    active ? Icons.fiber_manual_record : Icons.radio_button_off,
                    size: 14,
                    color: active ? osc.rec : osc.gridLine,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    active ? '${l10n.recording} · $title' : title,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: active ? osc.amber : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '$minutes:$seconds',
                style: Theme.of(context).textTheme.displayMedium?.copyWith(
                  color: active ? osc.phosphor : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TranscriptCard extends ConsumerWidget {
  const _TranscriptCard({required this.segments, required this.otherCallsign});

  final List<TranscriptSegment> segments;
  final String otherCallsign;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ownCallsign = ref.watch(callsignProvider);
    return _CardSection(
      title: context.l10n.liveTranscript,
      children: [
        if (segments.isEmpty)
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest,
                child: Icon(
                  Icons.person,
                  size: 20,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      context.l10n.noStreamingTranscript,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        for (var index = 0; index < segments.length; index += 1)
          _TranscriptBubble(
            key: ValueKey(segments[index].id ?? 'partial_$index'),
            segment: segments[index],
            ownCallsign: ownCallsign,
            otherCallsign: otherCallsign,
            onSpeakerChanged: segments[index].isFinal
                ? (speaker) => ref
                      .read(qsoCaptureProvider.notifier)
                      .updateTranscriptSpeaker(index, speaker)
                : null,
          ),
      ],
    );
  }
}

class _TranscriptBubble extends ConsumerStatefulWidget {
  const _TranscriptBubble({
    super.key,
    required this.segment,
    required this.ownCallsign,
    required this.otherCallsign,
    this.onSpeakerChanged,
  });

  final TranscriptSegment segment;
  final String ownCallsign;
  final String otherCallsign;
  final ValueChanged<TranscriptSpeaker>? onSpeakerChanged;

  @override
  ConsumerState<_TranscriptBubble> createState() => _TranscriptBubbleState();
}

class _TranscriptBubbleState extends ConsumerState<_TranscriptBubble> {
  bool _isPlaying = false;
  String? _playbackError;

  @override
  Widget build(BuildContext context) {
    final segment = widget.segment;
    final isMine = segment.speaker == TranscriptSpeaker.self;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final bubbleColor = isMine
        ? colors.primaryContainer
        : colors.surfaceContainerHighest;
    final textColor = isMine
        ? colors.onPrimaryContainer
        : colors.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: isMine
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isMine) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: colors.surfaceContainerHighest,
              child: Icon(
                Icons.person,
                size: 20,
                color: colors.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: bubbleColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colors.outlineVariant),
              ),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: isMine
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ActionChip(
                          avatar: const Icon(Icons.swap_horiz, size: 16),
                          label: Text(
                            _transcriptSpeakerDisplayLabel(
                              context,
                              segment.speaker,
                              ownCallsign: widget.ownCallsign,
                              otherCallsign: widget.otherCallsign,
                            ),
                          ),
                          onPressed:
                              segment.isFinal && widget.onSpeakerChanged != null
                              ? _toggleSpeaker
                              : null,
                          tooltip: segment.speaker == TranscriptSpeaker.self
                              ? context.l10n.switchToOtherStation
                              : context.l10n.switchToMyStation,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _formatSpeechTimeline(segment),
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: textColor,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        IconButton.filledTonal(
                          tooltip: _isPlaying
                              ? context.l10n.stopAudio
                              : context.l10n.playAudio,
                          onPressed: segment.audioPath == null
                              ? null
                              : _togglePlayback,
                          icon: Icon(_isPlaying ? Icons.stop : Icons.volume_up),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            segment.hasText
                                ? segment.text
                                : context.l10n.unrecognizedSpeech,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: textColor,
                              fontStyle: segment.hasText
                                  ? null
                                  : FontStyle.italic,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (segment.errorMessage != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        _errorLabel(context, segment.errorMessage!),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.error,
                        ),
                      ),
                    ],
                    if (_playbackError != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        _playbackError!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          if (isMine) ...[
            const SizedBox(width: 8),
            CircleAvatar(
              radius: 16,
              backgroundColor: colors.primaryContainer,
              child: Icon(
                Icons.person,
                size: 20,
                color: colors.onPrimaryContainer,
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _toggleSpeaker() {
    final next = switch (widget.segment.speaker) {
      TranscriptSpeaker.unknown => TranscriptSpeaker.self,
      TranscriptSpeaker.self => TranscriptSpeaker.other,
      TranscriptSpeaker.other => TranscriptSpeaker.self,
    };
    widget.onSpeakerChanged?.call(next);
  }

  Future<void> _togglePlayback() async {
    final audioPath = widget.segment.audioPath;
    if (audioPath == null) {
      return;
    }
    final service = ref.read(audioPlaybackServiceProvider);
    if (_isPlaying) {
      await service.stop();
      if (mounted) {
        setState(() {
          _isPlaying = false;
          _playbackError = null;
        });
      }
      return;
    }

    setState(() {
      _isPlaying = true;
      _playbackError = null;
    });
    try {
      await service.play(
        audioPath,
        startOffset: widget.segment.startOffset,
        endOffset: widget.segment.endOffset,
      );
      if (mounted) {
        setState(() => _isPlaying = false);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _isPlaying = false;
          _playbackError =
              '${context.l10n.audioPlaybackFailed}: ${_errorLabel(context, '$error')}';
        });
      }
    }
  }
}

class _LogListItem extends StatelessWidget {
  const _LogListItem({required this.log});

  final QsoDraft log;

  @override
  Widget build(BuildContext context) {
    final strip = bandColor(log.band.value);
    final frequency = log.frequency.value.trim();
    final band = log.band.value.trim();
    final mode = log.mode.value.trim();
    final dateTime = log.dateTime.value;
    final meta = [
      if (frequency.isNotEmpty) '$frequency MHz',
      if (band.isNotEmpty) band,
      if (mode.isNotEmpty) mode,
    ].join(' · ');
    return Semantics(
      label:
          '${log.callsign.value}, ${band.isNotEmpty ? band : "no band"}, '
          '${mode.isNotEmpty ? mode : "no mode"}, '
          'sent ${log.sentRst.value} received ${log.receivedRst.value}, '
          '${_statusLabel(context, log.status)}',
      button: true,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => QsoReviewScreen(draft: log)),
        ),
        child: Card(
          child: IntrinsicHeight(
            child: Row(
              children: [
                Container(width: 4, color: strip),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                log.callsign.value,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                meta.isEmpty ? '—' : meta,
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${log.sentRst.value} / ${log.receivedRst.value}',
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (dateTime != null) const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            _StatusChip(status: log.status),
                            if (dateTime != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                _formatLocalDateTime(dateTime),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LogbookUploadRow extends StatelessWidget {
  const _LogbookUploadRow({
    required this.title,
    required this.status,
    required this.detail,
    required this.busy,
    required this.enabled,
    required this.onUpload,
    this.disabledReason,
  });

  final String title;
  final LogbookUploadStatus? status;
  final String? detail;
  final bool busy;
  final bool enabled;
  final VoidCallback onUpload;
  final String? disabledReason;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isFailed = status == LogbookUploadStatus.failed;
    final detailText = disabledReason ?? detail;
    final details = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          _logbookUploadIcon(status),
          color: isFailed ? colorScheme.error : null,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(
                _logbookUploadStatusLabel(context, status),
                style: TextStyle(color: isFailed ? colorScheme.error : null),
              ),
              if (detailText != null && detailText.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  detailText,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: isFailed
                        ? colorScheme.error
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
    final uploadButton = OutlinedButton.icon(
      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
      onPressed: enabled ? onUpload : null,
      icon: busy
          ? const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.cloud_upload_outlined),
      label: Text(
        status == LogbookUploadStatus.pending
            ? context.l10n.retry
            : context.l10n.upload,
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final stack =
            constraints.maxWidth < 360 ||
            MediaQuery.textScalerOf(context).scale(1) > 1.2;
        if (stack) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [details, const SizedBox(height: 12), uploadButton],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: details),
            const SizedBox(width: 12),
            uploadButton,
          ],
        );
      },
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Icon(icon, size: 32),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }
}

class _ImportItem extends StatelessWidget {
  const _ImportItem({required this.job});

  final ImportJob job;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final fileName = job.sourcePath != null
        ? p.basename(job.sourcePath!)
        : l10n.importedText;
    final details = [
      _importSourceLabel(context, job.sourceType),
      if (job.generatedQsoId != null)
        '${l10n.generatedLog}: ${job.generatedQsoId}',
      if (job.errorMessage != null)
        '${l10n.errorDetail}: ${_errorLabel(context, job.errorMessage!)}',
    ];
    return ListTile(
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      title: Text(fileName),
      subtitle: Text(details.join('\n')),
      isThreeLine: details.length > 1,
      trailing: Chip(label: Text(_importStatusLabel(context, job.status))),
    );
  }
}

class _ExportHistoryItem extends StatelessWidget {
  const _ExportHistoryItem({required this.entry});

  final ExportHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ListTile(
      shape: RoundedRectangleBorder(
        side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      title: Text(
        '${entry.format.toUpperCase()} · ${entry.qsoCount} ${l10n.qsoCountUnit}',
      ),
      subtitle: Text(
        [
          _formatLocalDateTime(entry.createdAt),
          '${l10n.exportPath}: ${entry.filePath}',
          '${l10n.filterSummary}: ${entry.filterSummary}',
        ].join('\n'),
      ),
      isThreeLine: true,
      leading: const Icon(Icons.history),
    );
  }
}

class _FetchedModelTile extends StatelessWidget {
  const _FetchedModelTile({
    required this.model,
    required this.onSelectedChanged,
    required this.onCapabilitiesChanged,
  });

  final FetchedProviderModel model;
  final ValueChanged<bool> onSelectedChanged;
  final ValueChanged<Set<ModelCapability>> onCapabilitiesChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Checkbox(
        value: model.selected,
        onChanged: (value) => onSelectedChanged(value ?? false),
      ),
      title: Text(model.id),
      subtitle: Wrap(
        spacing: 8,
        children: [
          for (final capability in ModelCapability.values)
            FilterChip(
              label: Text(_capabilityLabel(context, capability)),
              selected: model.capabilities.contains(capability),
              onSelected: (selected) {
                final next = {...model.capabilities};
                if (selected) {
                  next.add(capability);
                } else {
                  next.remove(capability);
                }
                onCapabilitiesChanged(next);
              },
            ),
        ],
      ),
    );
  }
}

class _CardSection extends StatelessWidget {
  const _CardSection({
    required this.title,
    required this.children,
    this.trailing,
  });

  final String title;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _PlaceholderCard extends StatelessWidget {
  const _PlaceholderCard({
    required this.title,
    required this.text,
    required this.icon,
  });

  final String title;
  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return _CardSection(
      title: title,
      children: [
        Row(
          children: [
            Icon(icon),
            const SizedBox(width: 12),
            Expanded(child: Text(text)),
          ],
        ),
      ],
    );
  }
}

class _RetainedDataCard extends StatelessWidget {
  const _RetainedDataCard({
    required this.title,
    required this.text,
    required this.icon,
    required this.deleteLabel,
    this.onDelete,
  });

  final String title;
  final String text;
  final IconData icon;
  final String deleteLabel;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return _CardSection(
      title: title,
      trailing: onDelete == null
          ? null
          : IconButton(
              tooltip: deleteLabel,
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline),
            ),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon),
            const SizedBox(width: 12),
            Expanded(child: SelectableText(text)),
          ],
        ),
      ],
    );
  }
}

class _RetainedTranscriptCard extends ConsumerWidget {
  const _RetainedTranscriptCard({
    required this.title,
    required this.segments,
    required this.otherCallsign,
    required this.deleteLabel,
    this.onDelete,
  });

  final String title;
  final List<TranscriptSegment> segments;
  final String otherCallsign;
  final String deleteLabel;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ownCallsign = ref.watch(callsignProvider);
    return Card(
      child: ExpansionTile(
        key: const ValueKey('retained-transcript-expansion'),
        initiallyExpanded: false,
        title: Row(
          children: [
            Expanded(
              child: Text(title, style: Theme.of(context).textTheme.titleLarge),
            ),
            if (onDelete != null)
              IconButton(
                tooltip: deleteLabel,
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline),
              ),
          ],
        ),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        children: [
          for (var index = 0; index < segments.length; index += 1)
            _TranscriptBubble(
              key: ValueKey('retained_${segments[index].id ?? index}'),
              segment: segments[index],
              ownCallsign: ownCallsign,
              otherCallsign: otherCallsign,
            ),
        ],
      ),
    );
  }
}

class _RetainedAudioCard extends StatelessWidget {
  const _RetainedAudioCard({
    required this.title,
    required this.path,
    required this.missingText,
    required this.isPlaying,
    required this.playLabel,
    required this.stopLabel,
    required this.deleteLabel,
    this.errorText,
    this.onPlayPressed,
    this.onDelete,
  });

  final String title;
  final String? path;
  final String missingText;
  final bool isPlaying;
  final String playLabel;
  final String stopLabel;
  final String deleteLabel;
  final String? errorText;
  final VoidCallback? onPlayPressed;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return _CardSection(
      title: title,
      trailing: onDelete == null
          ? null
          : IconButton(
              tooltip: deleteLabel,
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline),
            ),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconButton.filledTonal(
              tooltip: isPlaying ? stopLabel : playLabel,
              onPressed: onPlayPressed,
              icon: Icon(isPlaying ? Icons.stop : Icons.play_arrow),
            ),
            const SizedBox(width: 8),
            Expanded(child: SelectableText(path ?? missingText)),
          ],
        ),
        if (errorText != null) ...[
          const SizedBox(height: 8),
          Text(errorText!, style: TextStyle(color: colorScheme.error)),
        ],
      ],
    );
  }
}

class _DataCountTile extends StatelessWidget {
  const _DataCountTile({
    required this.icon,
    required this.label,
    required this.count,
  });

  final IconData icon;
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(label),
      trailing: Text('$count', style: Theme.of(context).textTheme.titleMedium),
    );
  }
}

class _TwoColumnFields extends StatelessWidget {
  const _TwoColumnFields({required this.left, required this.right});

  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stack =
            constraints.maxWidth < 440 ||
            MediaQuery.textScalerOf(context).scale(1) > 1.2;
        if (stack) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [left, const SizedBox(height: 12), right],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: left),
            const SizedBox(width: 10),
            Expanded(child: right),
          ],
        );
      },
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final LogStatus status;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(context, status);
    return Chip(
      label: Text(_statusLabel(context, status)),
      side: BorderSide(color: color),
      backgroundColor: color.withAlpha(20),
      labelStyle: TextStyle(color: color, fontWeight: FontWeight.bold),
    );
  }
}

class _ModelAssignmentSection extends StatelessWidget {
  const _ModelAssignmentSection({
    required this.title,
    required this.providers,
    required this.selectedProviderId,
    required this.models,
    required this.selectedModelId,
    required this.onProviderChanged,
    required this.onChanged,
  });

  final String title;
  final List<ProviderProfile> providers;
  final String? selectedProviderId;
  final List<AiModelOption> models;
  final String? selectedModelId;
  final ValueChanged<String?> onProviderChanged;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final effectiveModelId = models.any((model) => model.id == selectedModelId)
        ? selectedModelId
        : null;
    return _CardSection(
      title: title,
      children: [
        DropdownButtonFormField<String>(
          initialValue: selectedProviderId,
          decoration: InputDecoration(
            labelText: context.l10n.providerManagement,
          ),
          items: [
            for (final provider in providers)
              DropdownMenuItem(value: provider.id, child: Text(provider.name)),
          ],
          onChanged: providers.isEmpty ? null : onProviderChanged,
        ),
        const SizedBox(height: 12),
        if (models.isEmpty)
          Row(
            children: [
              const Icon(Icons.info_outline),
              const SizedBox(width: 12),
              Expanded(child: Text(context.l10n.noModelsSaved)),
            ],
          ),
        if (models.isNotEmpty)
          DropdownButtonFormField<String>(
            initialValue: effectiveModelId,
            isExpanded: true,
            decoration: InputDecoration(labelText: context.l10n.modelName),
            items: [
              for (final model in models)
                DropdownMenuItem(
                  value: model.id,
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 2,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(model.name),
                      for (final capability in model.capabilities)
                        _CapabilityChip(capability: capability),
                    ],
                  ),
                ),
            ],
            onChanged: onChanged,
          ),
      ],
    );
  }
}

// 顶部短暂提示（替代默认底部 SnackBar）：更短、位置在页面顶部，用于保存成功等确认。
void showTopNotice(
  BuildContext context,
  String message, {
  Duration duration = const Duration(milliseconds: 1500),
}) {
  final overlay = Overlay.of(context, rootOverlay: true);
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _TopNotice(
      message: message,
      duration: duration,
      onDismissed: entry.remove,
    ),
  );
  overlay.insert(entry);
}

class _TopNotice extends StatefulWidget {
  const _TopNotice({
    required this.message,
    required this.duration,
    required this.onDismissed,
  });

  final String message;
  final Duration duration;
  final VoidCallback onDismissed;

  @override
  State<_TopNotice> createState() => _TopNoticeState();
}

class _TopNoticeState extends State<_TopNotice>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
  );
  Timer? _hideTimer;
  bool _removed = false;

  @override
  void initState() {
    super.initState();
    _controller.forward();
    _hideTimer = Timer(widget.duration, () {
      _controller.reverse().whenComplete(() {
        if (!_removed) {
          _removed = true;
          widget.onDismissed();
        }
      });
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: Center(
          child: FadeTransition(
            opacity: _controller,
            child: Padding(
              padding: const EdgeInsets.only(top: 12, left: 16, right: 16),
              child: Material(
                elevation: 6,
                borderRadius: BorderRadius.circular(10),
                color: theme.colorScheme.primaryContainer,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: Text(
                    widget.message,
                    style: TextStyle(
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CapabilityChip extends StatelessWidget {
  const _CapabilityChip({required this.capability});

  final ModelCapability capability;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(_capabilityLabel(context, capability)),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _EquipmentSelector extends ConsumerWidget {
  const _EquipmentSelector({
    required this.selectedEquipment,
    required this.onSelected,
  });

  final StationEquipment? selectedEquipment;
  final ValueChanged<StationEquipment?> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final equipmentState = ref.watch(stationEquipmentProvider);
    final equipment = equipmentState.maybeWhen(
      data: (v) => v,
      orElse: () => const <StationEquipment>[],
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: DropdownButtonFormField<StationEquipment?>(
            initialValue: selectedEquipment,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: l10n.selectEquipment,
              prefixIcon: const Icon(Icons.radio),
            ),
            items: [
              DropdownMenuItem<StationEquipment?>(
                value: null,
                child: Text(l10n.selectEquipment),
              ),
              for (final eq in equipment)
                DropdownMenuItem<StationEquipment?>(
                  value: eq,
                  child: Text(eq.name),
                ),
            ],
            onChanged: onSelected,
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: l10n.addEquipment,
          icon: const Icon(Icons.add_circle_outline),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const StationEquipmentScreen(),
            ),
          ),
        ),
      ],
    );
  }
}

// 天线下拉：选项来自所有已配置设备的天线（去重）；当前值不在选项中则自动并入。
class _AntennaDropdown extends ConsumerWidget {
  const _AntennaDropdown({required this.controller, this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final equipment = ref
        .watch(stationEquipmentProvider)
        .maybeWhen(data: (v) => v, orElse: () => const <StationEquipment>[]);
    final antennas = equipment
        .map((e) => e.antenna)
        .where((a) => a.isNotEmpty)
        .toSet()
        .toList();
    return TextFormField(
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: l10n.antenna,
        prefixIcon: const Icon(Icons.cell_tower),
        suffixIcon: antennas.isEmpty
            ? null
            : PopupMenuButton<String>(
                onSelected: (value) {
                  controller.text = value;
                  onChanged?.call(value);
                },
                itemBuilder: (_) => [
                  for (final antenna in antennas)
                    PopupMenuItem(value: antenna, child: Text(antenna)),
                ],
              ),
      ),
    );
  }
}

class _PowerDropdown extends StatelessWidget {
  const _PowerDropdown({
    required this.controller,
    required this.powerOptions,
    this.onChanged,
  });

  final TextEditingController controller;
  final List<String> powerOptions;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return TextFormField(
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: l10n.power,
        prefixIcon: const Icon(Icons.electrical_services),
        suffixIcon: powerOptions.isEmpty
            ? null
            : PopupMenuButton<String>(
                onSelected: (value) {
                  controller.text = value;
                  onChanged?.call(value);
                },
                itemBuilder: (_) => [
                  for (final option in powerOptions)
                    PopupMenuItem(value: option, child: Text(option)),
                ],
              ),
      ),
    );
  }
}

class _ReviewField extends StatelessWidget {
  const _ReviewField({
    required this.label,
    required this.controller,
    this.requiredField = false,
    this.maxLines = 1,
    this.needsReview = false,
    this.sourceText,
    this.onReviewed,
    this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final bool requiredField;
  final int maxLines;
  final bool needsReview;
  final String? sourceText;
  final VoidCallback? onReviewed;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return _FieldReviewFrame(
      needsReview: needsReview,
      sourceText: sourceText,
      onReviewed: onReviewed,
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: requiredField ? '$label *' : label,
        ),
      ),
    );
  }
}

class _FieldReviewFrame extends StatelessWidget {
  const _FieldReviewFrame({
    required this.child,
    this.needsReview = false,
    this.sourceText,
    this.onReviewed,
  });

  final Widget child;
  final bool needsReview;
  final String? sourceText;
  final VoidCallback? onReviewed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final source = sourceText?.trim();
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: needsReview ? const EdgeInsets.all(12) : EdgeInsets.zero,
      decoration: needsReview
          ? BoxDecoration(
              color: colors.errorContainer,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: colors.error),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          child,
          if (needsReview) ...[
            const SizedBox(height: 8),
            Text(
              context.l10n.reviewRequired,
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(color: colors.error),
            ),
            if (source?.isNotEmpty == true) ...[
              const SizedBox(height: 4),
              Text(
                '${context.l10n.sourceExcerpt}: $source',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: onReviewed,
                icon: const Icon(Icons.check_circle_outline),
                label: Text(context.l10n.confirmFieldCorrect),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

String? _blankToNull(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

List<FetchedProviderModel> _presetModelsFor(ProviderDescriptor descriptor) {
  return [
    for (final model in descriptor.presetModels)
      FetchedProviderModel(
        id: model.name,
        capabilities: {...model.capabilities},
      ),
  ];
}

List<FetchedProviderModel> _mergeFetchedModels(
  List<FetchedProviderModel> existing,
  List<FetchedProviderModel> incoming,
) {
  final byId = {for (final model in existing) model.id: model};
  for (final model in incoming) {
    byId.putIfAbsent(model.id, () => model);
  }
  return byId.values.toList()..sort((a, b) => a.id.compareTo(b.id));
}

String _importStatusLabel(BuildContext context, ImportJobStatus status) {
  final l10n = context.l10n;
  return switch (status) {
    ImportJobStatus.pending => l10n.pending,
    ImportJobStatus.processing => l10n.processing,
    ImportJobStatus.completed => l10n.completed,
    ImportJobStatus.failed => l10n.failed,
  };
}

String _importSourceLabel(BuildContext context, ImportSourceType sourceType) {
  final l10n = context.l10n;
  return switch (sourceType) {
    ImportSourceType.audio => l10n.audioSource,
    ImportSourceType.text => l10n.textSource,
  };
}

Future<bool> _confirmDestructiveAction(
  BuildContext context, {
  required String title,
  required String message,
}) async {
  await HapticFeedback.heavyImpact();
  if (!context.mounted) return false;
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(
            MaterialLocalizations.of(dialogContext).cancelButtonLabel,
          ),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(dialogContext).colorScheme.error,
            foregroundColor: Theme.of(dialogContext).colorScheme.onError,
          ),
          onPressed: () {
            HapticFeedback.selectionClick();
            Navigator.of(dialogContext).pop(true);
          },
          child: Text(context.l10n.delete),
        ),
      ],
    ),
  );
  return result ?? false;
}

String _formatLocalDateTime(DateTime value) {
  return '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')} '
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';
}

String _captureWarningLabel(BuildContext context, String warning) {
  final l10n = context.l10n;
  return switch (warning) {
    'streaming_not_configured' => l10n.streamingAdapterNotConfigured,
    'streaming_connection_failed' => l10n.streamingConnectionFailed,
    'no_streaming_transcript' => l10n.noStreamingTranscriptProduced,
    _ => warning,
  };
}

String _transcriptSpeakerLabel(
  BuildContext context,
  TranscriptSpeaker speaker,
) {
  final l10n = context.l10n;
  return switch (speaker) {
    TranscriptSpeaker.unknown => l10n.unknownStation,
    TranscriptSpeaker.other => l10n.otherStation,
    TranscriptSpeaker.self => l10n.myStation,
  };
}

String _transcriptSpeakerDisplayLabel(
  BuildContext context,
  TranscriptSpeaker speaker, {
  required String ownCallsign,
  required String otherCallsign,
}) {
  final label = _transcriptSpeakerLabel(context, speaker);
  final callsign = switch (speaker) {
    TranscriptSpeaker.unknown => '',
    TranscriptSpeaker.other => otherCallsign.trim().toUpperCase(),
    TranscriptSpeaker.self => ownCallsign.trim().toUpperCase(),
  };
  return callsign.isEmpty ? label : '$label · $callsign';
}

String _formatSpeechDuration(Duration? duration) {
  if (duration == null) {
    return '--"';
  }
  return '${(duration.inMilliseconds / 1000).toStringAsFixed(1)}"';
}

String _formatSpeechTimeline(TranscriptSegment segment) {
  final startOffset = segment.startOffset;
  final endOffset = segment.endOffset;
  if (startOffset == null || endOffset == null) {
    return _formatSpeechDuration(segment.duration);
  }
  final startSeconds = (startOffset.inMilliseconds / 1000).toStringAsFixed(1);
  final endSeconds = (endOffset.inMilliseconds / 1000).toStringAsFixed(1);
  return '$startSeconds–${endSeconds}s';
}

Future<bool> _validateImportFormat(
  BuildContext context,
  WidgetRef ref,
  String audioPath,
) async {
  final ext = p.extension(audioPath).toLowerCase().replaceFirst('.', '');
  if (ext == 'pcm') return true;
  final assignments = await ref
      .read(modelAssignmentRepositoryProvider)
      .listAssignments();
  ModelAssignment? asrAssignment;
  for (final a in assignments) {
    if (a.task == ModelAssignmentTask.transcription) {
      asrAssignment = a;
      break;
    }
  }
  if (asrAssignment == null) return true;
  final connection = await ref
      .read(providerRepositoryProvider)
      .findConnection(asrAssignment.providerId);
  if (connection == null) return true;
  final descriptor = descriptorFor(AiProvider.fromKey(connection.type));
  final supported = descriptor.asr?.supportedFormats ?? const [];
  if (supported.isEmpty || supported.contains(ext)) return true;
  if (!context.mounted) return false;
  // 格式不匹配为硬性阻断：下游 _validateAudioFormat 会无条件抛错，
  // 故此处仅警告并阻止导入（不提供无法兑现的"继续"按钮）。
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(ctx.l10n.audioFormatWarningTitle),
      content: Text(
        ctx.l10n.audioFormatWarningBody(
          descriptor.displayName,
          ext,
          supported.join(', '),
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: Text(MaterialLocalizations.of(ctx).okButtonLabel),
        ),
      ],
    ),
  );
  return false;
}

String _errorLabel(BuildContext context, String error) {
  final l10n = context.l10n;
  final code = error.startsWith('Bad state: ')
      ? error.substring('Bad state: '.length)
      : error;
  if (code.startsWith('transcription_request_failed:')) {
    final statusCode = code.split(':').last.trim();
    return '${l10n.transcriptionRequestFailed}: $statusCode';
  }
  if (code.startsWith('structuring_request_failed:')) {
    final statusCode = code.split(':').last.trim();
    return '${l10n.structuringRequestFailed}: $statusCode';
  }
  if (code.startsWith('model_list_request_failed:')) {
    final parts = code.split(':');
    final statusCode = parts.length > 1 ? parts[1].trim() : '';
    return '${l10n.modelListRequestFailed}: $statusCode';
  }
  if (code.startsWith('model_list_all_candidates_failed:')) {
    return l10n.modelListAllCandidatesFailed;
  }
  if (code.startsWith('provider_without_asr')) {
    return l10n.providerWithoutAsr;
  }
  if (code.startsWith('connection_test_failed')) {
    final statusCode = code.split(':').last.trim();
    return '${l10n.connectionTestFailed}: $statusCode';
  }
  return switch (code) {
    'base_url_required' => l10n.baseUrlRequired,
    'model_list_empty' => l10n.modelListEmpty,
    'microphone_permission_denied' => l10n.microphonePermissionDenied,
    'no_transcription_model_assigned' => l10n.noTranscriptionModelAssigned,
    'assigned_transcription_provider_missing' =>
      l10n.assignedTranscriptionProviderMissing,
    'transcription_model_without_speech' =>
      l10n.transcriptionModelWithoutSpeech,
    'provider_not_openai_compatible_http' =>
      l10n.providerNotOpenAiCompatibleHttp,
    'audio_file_missing' => l10n.audioFileMissing,
    'no_streaming_transcript' => l10n.noStreamingTranscriptProduced,
    'streaming_connection_closed' => l10n.streamingConnectionClosed,
    'transcription_response_missing_text' =>
      l10n.transcriptionResponseMissingText,
    'assigned_structuring_provider_missing' =>
      l10n.assignedStructuringProviderMissing,
    'structuring_model_without_capability' =>
      l10n.structuringModelWithoutCapability,
    'structuring_response_missing_json' => l10n.structuringResponseMissingJson,
    'required_qso_fields_missing' => l10n.requiredFieldsMissing,
    _ => error,
  };
}

String _qrzUploadErrorLabel(AppLocalizations l10n, QrzUploadException error) {
  return switch (error.reason) {
    QrzUploadFailureReason.missingApiKey => l10n.qrzApiKeyRequired,
    QrzUploadFailureReason.requiredFieldsMissing => l10n.requiredFieldsMissing,
    QrzUploadFailureReason.httpError =>
      '${l10n.qrzUploadFailed}: ${error.statusCode ?? ''}',
    QrzUploadFailureReason.networkError => l10n.updateNetworkFailed,
    QrzUploadFailureReason.rejected =>
      '${l10n.qrzUploadRejected}: ${error.message ?? ''}',
    QrzUploadFailureReason.badResponse => l10n.updateBadResponse,
  };
}

IconData _logbookUploadIcon(LogbookUploadStatus? status) {
  return switch (status) {
    LogbookUploadStatus.pending => Icons.hourglass_empty,
    LogbookUploadStatus.succeeded => Icons.check_circle_outline,
    LogbookUploadStatus.failed => Icons.error_outline,
    LogbookUploadStatus.stale => Icons.edit_note,
    null => Icons.cloud_upload_outlined,
  };
}

String _logbookUploadStatusLabel(
  BuildContext context,
  LogbookUploadStatus? status,
) {
  final l10n = context.l10n;
  return switch (status) {
    LogbookUploadStatus.pending => l10n.pending,
    LogbookUploadStatus.succeeded => l10n.uploadSucceeded,
    LogbookUploadStatus.failed => l10n.failed,
    LogbookUploadStatus.stale => l10n.logbookUploadStale,
    null => l10n.notUploaded,
  };
}

String _capabilityLabel(BuildContext context, ModelCapability capability) {
  final l10n = context.l10n;
  return switch (capability) {
    ModelCapability.speech => l10n.speech,
    ModelCapability.streaming => l10n.streaming,
    ModelCapability.text => l10n.text,
    ModelCapability.structuring => l10n.structuring,
  };
}

String _statusLabel(BuildContext context, LogStatus status) {
  final l10n = context.l10n;
  return switch (status) {
    LogStatus.draft => l10n.draft,
    LogStatus.needsReview => l10n.needsReview,
    LogStatus.confirmed => l10n.confirmed,
    LogStatus.exported => l10n.exported,
    LogStatus.failed => l10n.failed,
  };
}

Color _statusColor(BuildContext context, LogStatus status) {
  final osc = Theme.of(context).extension<OscilloscopeColors>()!;
  return switch (status) {
    LogStatus.draft => osc.statusDraft,
    LogStatus.needsReview => osc.statusReview,
    LogStatus.confirmed => osc.statusConfirmed,
    LogStatus.exported => osc.statusExported,
    LogStatus.failed => osc.statusFailed,
  };
}

String _formatDate(DateTime d) {
  final y = d.year.toString();
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '$y-$m-$day';
}

String _formatDateTime(DateTime d) {
  final date = _formatDate(d);
  final hh = d.hour.toString().padLeft(2, '0');
  final mm = d.minute.toString().padLeft(2, '0');
  return '$date $hh:$mm';
}

DateTime? _inclusiveDateEnd(DateTime? date) {
  if (date == null) {
    return null;
  }
  return parseFilterEndDate(_formatDate(date));
}

String? _suggestBand(double mhz) {
  const table = <(double, double, String)>[
    (1.8, 2.0, '160m'),
    (3.5, 4.0, '80m'),
    (5.06, 5.45, '60m'),
    (7.0, 7.3, '40m'),
    (10.1, 10.2, '30m'),
    (14.0, 14.35, '20m'),
    (18.06, 18.17, '17m'),
    (21.0, 21.45, '15m'),
    (24.89, 24.99, '12m'),
    (28.0, 29.7, '10m'),
    (50.0, 54.0, '6m'),
    (70.0, 71.0, '4m'),
    (144.0, 148.0, '2m'),
    (430.0, 440.0, '70cm'),
  ];
  for (final entry in table) {
    if (mhz >= entry.$1 && mhz <= entry.$2) {
      return entry.$3;
    }
  }
  return null;
}

class _DatePickerField extends StatelessWidget {
  const _DatePickerField({
    required this.label,
    required this.value,
    required this.onPick,
    this.onClear,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime> onPick;
  final VoidCallback? onClear;

  Future<void> _open(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: value ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null && context.mounted) {
      onPick(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final clear = onClear;
    return GestureDetector(
      onTap: () => _open(context),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: clear == null
              ? const Icon(Icons.event, size: 18)
              : IconButton(
                  tooltip: l10n.clearFilters,
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: clear,
                ),
        ),
        child: Text(value == null ? l10n.all : _formatDate(value!)),
      ),
    );
  }
}

class _BandDropdown extends StatelessWidget {
  const _BandDropdown({
    required this.value,
    required this.onChanged,
    this.includeAll = false,
    this.helperText,
  });

  final String? value;
  final ValueChanged<String?> onChanged;
  final bool includeAll;
  final String? helperText;

  static const _bands = <String>[
    '160m',
    '80m',
    '60m',
    '40m',
    '30m',
    '20m',
    '17m',
    '15m',
    '12m',
    '10m',
    '6m',
    '4m',
    '2m',
    '1.25m',
    '70cm',
    '33cm',
    '23cm',
  ];

  @override
  Widget build(BuildContext context) {
    final currentValue = _dropdownValue(value);
    final bands = _dropdownOptions(_bands, currentValue);
    return DropdownButtonFormField<String>(
      initialValue: currentValue,
      decoration: InputDecoration(
        labelText: context.l10n.band,
        helperText: helperText,
      ),
      hint: includeAll ? Text(context.l10n.all) : null,
      isExpanded: true,
      items: [
        if (includeAll)
          DropdownMenuItem<String>(value: null, child: Text(context.l10n.all)),
        for (final band in bands)
          DropdownMenuItem(
            value: band,
            child: Text(band, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: onChanged,
    );
  }
}

class _ModeDropdown extends StatelessWidget {
  const _ModeDropdown({
    required this.value,
    required this.onChanged,
    this.includeAll = false,
  });

  final String? value;
  final ValueChanged<String?> onChanged;
  final bool includeAll;

  static const _modes = <String>[
    'CW',
    'SSB',
    'LSB',
    'USB',
    'FM',
    'AM',
    'RTTY',
    'PSK31',
    'FT8',
    'FT4',
    'MFSK16',
    'DV',
  ];

  @override
  Widget build(BuildContext context) {
    final currentValue = _dropdownValue(value);
    final modes = _dropdownOptions(_modes, currentValue);
    return DropdownButtonFormField<String>(
      initialValue: currentValue,
      decoration: InputDecoration(labelText: context.l10n.mode),
      hint: includeAll ? Text(context.l10n.all) : null,
      isExpanded: true,
      items: [
        if (includeAll)
          DropdownMenuItem<String>(value: null, child: Text(context.l10n.all)),
        for (final mode in modes)
          DropdownMenuItem(
            value: mode,
            child: Text(mode, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: onChanged,
    );
  }
}

String? _dropdownValue(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  return trimmed;
}

List<String> _dropdownOptions(List<String> defaults, String? value) {
  if (value == null || defaults.contains(value)) {
    return defaults;
  }
  return [...defaults, value];
}

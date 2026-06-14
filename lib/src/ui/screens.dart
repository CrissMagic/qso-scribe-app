import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../l10n/generated/app_localizations.dart';
import '../domain/app_models.dart';
import '../domain/filter_helpers.dart';
import '../services/provider_model_fetch_service.dart';
import '../state/app_state.dart';

extension L10nX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

enum _ExportFormat { adif, csv, rawTranscript }

class FirstRunSetupScreen extends ConsumerWidget {
  const FirstRunSetupScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
            _SectionTitle(number: 1, title: l10n.language),
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
            _SectionTitle(number: 2, title: l10n.transcriptionMode),
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
            _SectionTitle(number: 3, title: l10n.failureHandling),
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
              onPressed: () =>
                  ref.read(setupCompletedProvider.notifier).complete(),
              icon: const Icon(Icons.check_circle_outline),
              label: Text(l10n.completeSetup),
            ),
          ],
        ),
      ),
    );
  }
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final pages = [
      const RecordScreen(),
      const LogsScreen(),
      const ImportScreen(),
      const ExportScreen(),
      const SettingsScreen(),
    ];

    return Scaffold(
      body: pages[_index],
      bottomNavigationBar: NavigationBar(
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
            icon: const Icon(Icons.upload_file),
            label: l10n.import,
          ),
          NavigationDestination(
            icon: const Icon(Icons.file_download),
            label: l10n.export,
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

class RecordScreen extends ConsumerWidget {
  const RecordScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final session = ref.watch(recordingSessionProvider);
    final mode = ref.watch(transcriptionModeProvider);
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
    final draft = capture.currentDraft;
    final transcript = capture.transcriptSegments;
    final logs = ref
        .watch(qsoLogProvider)
        .maybeWhen(data: (value) => value, orElse: () => const <QsoDraft>[]);
    final isStreaming = mode == TranscriptionMode.streaming;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.appTitle),
        actions: [
          IconButton(
            tooltip: l10n.settings,
            icon: const Icon(Icons.settings),
            onPressed: () {},
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _StatusPanel(
            title: isStreaming ? l10n.streamingMode : l10n.afterQsoMode,
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
          if (isStreaming && transcript.isNotEmpty)
            _TranscriptCard(segments: transcript)
          else
            _PlaceholderCard(
              title: l10n.liveTranscript,
              text: isStreaming
                  ? l10n.noStreamingTranscript
                  : l10n.recordingPlaceholder,
              icon: Icons.audio_file,
            ),
          const SizedBox(height: 16),
          _DraftCard(draft: draft),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: session.isProcessing
                ? null
                : () async {
                    final recorder = ref.read(
                      recordingSessionProvider.notifier,
                    );
                    if (session.isRecording) {
                      final audioPath = await recorder.stop();
                      final generatedDraft = await ref
                          .read(qsoCaptureProvider.notifier)
                          .finishQso(
                            audioPath: audioPath,
                            startedAt: session.startedAt,
                            mode: mode,
                            failureHandling: ref.read(failureHandlingProvider),
                          );
                      if (context.mounted) {
                        await Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                QsoReviewScreen(draft: generatedDraft),
                          ),
                        );
                      }
                    } else {
                      await recorder.start(mode);
                      final updatedSession = ref.read(recordingSessionProvider);
                      final startedAt = updatedSession.startedAt;
                      if (updatedSession.isRecording && startedAt != null) {
                        ref
                            .read(qsoCaptureProvider.notifier)
                            .startQso(mode: mode, startedAt: startedAt);
                      }
                    }
                  },
            icon: Icon(session.isRecording ? Icons.stop : Icons.mic),
            label: Text(session.isRecording ? l10n.endQso : l10n.startQso),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () {
              final qso = draft.copyWith(audioPath: session.audioPath);
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => QsoReviewScreen(draft: qso),
                ),
              );
            },
            icon: const Icon(Icons.edit_note),
            label: Text(l10n.qsoReview),
          ),
          const SizedBox(height: 16),
          _RecentSessionList(logs: logs.take(3).toList()),
        ],
      ),
    );
  }
}

class LogsScreen extends ConsumerStatefulWidget {
  const LogsScreen({super.key});

  @override
  ConsumerState<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends ConsumerState<LogsScreen> {
  LogStatus? _status;
  final _searchController = TextEditingController();
  final _bandController = TextEditingController();
  final _modeController = TextEditingController();
  final _fromController = TextEditingController();
  final _toController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    _bandController.dispose();
    _modeController.dispose();
    _fromController.dispose();
    _toController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final logsState = ref.watch(qsoLogProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.logs)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: l10n.searchLogs,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          _CardSection(
            title: l10n.filters,
            children: [
              DropdownButtonFormField<LogStatus?>(
                initialValue: _status,
                decoration: InputDecoration(labelText: l10n.status),
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
                left: TextField(
                  controller: _bandController,
                  decoration: InputDecoration(labelText: l10n.band),
                  onChanged: (_) => setState(() {}),
                ),
                right: TextField(
                  controller: _modeController,
                  decoration: InputDecoration(labelText: l10n.mode),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              _TwoColumnFields(
                left: TextField(
                  controller: _fromController,
                  decoration: InputDecoration(
                    labelText: l10n.fromDate,
                    hintText: '2026-06-01',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                right: TextField(
                  controller: _toController,
                  decoration: InputDecoration(
                    labelText: l10n.toDate,
                    hintText: '2026-06-30',
                  ),
                  onChanged: (_) => setState(() {}),
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
          const SizedBox(height: 16),
          ...logsState.when(
            data: (logs) {
              final filteredLogs = logs.where(_matchesLogFilter).toList();
              return [
                if (filteredLogs.isEmpty)
                  _PlaceholderCard(
                    title: l10n.logs,
                    text: l10n.noLogsMatchFilters,
                    icon: Icons.info_outline,
                  ),
                for (final log in filteredLogs) ...[
                  _LogListItem(log: log),
                  const SizedBox(height: 8),
                ],
              ];
            },
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

  bool _matchesLogFilter(QsoDraft log) {
    final search = _searchController.text.trim().toUpperCase();
    final band = _blankToNull(_bandController.text);
    final mode = _blankToNull(_modeController.text);
    final from = parseFilterStartDate(_fromController.text);
    final to = parseFilterEndDate(_toController.text);
    final dateTime = log.dateTime.value;

    final matchesSearch =
        search.isEmpty ||
        log.callsign.value.toUpperCase().contains(search) ||
        (log.qth?.value.toUpperCase().contains(search) ?? false) ||
        (log.notes?.value.toUpperCase().contains(search) ?? false);

    return matchesSearch &&
        (_status == null || log.status == _status) &&
        matchesFilterText(log.band.value, band) &&
        matchesFilterText(log.mode.value, mode) &&
        (from == null || (dateTime != null && !dateTime.isBefore(from))) &&
        (to == null || (dateTime != null && !dateTime.isAfter(to)));
  }

  void _clearFilters() {
    setState(() {
      _status = null;
      _searchController.clear();
      _bandController.clear();
      _modeController.clear();
      _fromController.clear();
      _toController.clear();
    });
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
                allowedExtensions: ['wav', 'm4a', 'mp3', 'pcm'],
              );
              final path = result?.files.single.path;
              if (path == null) {
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
                if (context.mounted &&
                    importDraft.draft.status == LogStatus.failed) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(l10n.audioImportManualReview)),
                  );
                }
              } catch (error) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        '${l10n.failed}: ${_errorLabel(context, '$error')}',
                      ),
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
  final _bandController = TextEditingController();
  final _modeController = TextEditingController();
  final _fromController = TextEditingController();
  final _toController = TextEditingController();

  @override
  void dispose() {
    _bandController.dispose();
    _modeController.dispose();
    _fromController.dispose();
    _toController.dispose();
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
          Text(l10n.exportDesc),
          const SizedBox(height: 16),
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
                left: TextField(
                  controller: _bandController,
                  decoration: InputDecoration(labelText: l10n.band),
                  onChanged: (_) => setState(() {}),
                ),
                right: TextField(
                  controller: _modeController,
                  decoration: InputDecoration(labelText: l10n.mode),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              _TwoColumnFields(
                left: TextField(
                  controller: _fromController,
                  decoration: InputDecoration(
                    labelText: l10n.fromDate,
                    hintText: '2026-06-01',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                right: TextField(
                  controller: _toController,
                  decoration: InputDecoration(
                    labelText: l10n.toDate,
                    hintText: '2026-06-30',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Center(
            child: Text(
              '$selectedCount ${l10n.selectedForExport}',
              style: Theme.of(context).textTheme.headlineSmall,
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
      from: parseFilterStartDate(_fromController.text),
      to: parseFilterEndDate(_toController.text),
      band: _blankToNull(_bandController.text),
      mode: _blankToNull(_modeController.text),
    );
  }

  Future<void> _exportToFile() async {
    final service = ref.read(exportServiceProvider);
    final filter = _currentFilter();
    final content = switch (_format) {
      _ExportFormat.adif => await service.exportAdif(filter),
      _ExportFormat.csv => await service.exportCsv(filter),
      _ExportFormat.rawTranscript => await service.exportRawTranscript(filter),
    };
    final dir = await getApplicationDocumentsDirectory();
    final exportDir = Directory(p.join(dir.path, 'exports'));
    if (!exportDir.existsSync()) {
      await exportDir.create(recursive: true);
    }
    final extension = switch (_format) {
      _ExportFormat.adif => 'adi',
      _ExportFormat.csv => 'csv',
      _ExportFormat.rawTranscript => 'txt',
    };
    final path = p.join(
      exportDir.path,
      'qso_export_${DateTime.now().toUtc().millisecondsSinceEpoch}.$extension',
    );
    await File(path).writeAsString(content);
    await ref
        .read(exportHistoryRepositoryProvider)
        .saveExport(
          format: extension,
          filePath: path,
          qsoCount: ref
              .read(qsoLogProvider)
              .maybeWhen(
                data: (logs) => logs.where(_matchesExportFilter).length,
                orElse: () => 0,
              ),
          filterSummary: _filterSummary(),
        );
    ref.invalidate(exportHistoryProvider);
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${context.l10n.exportedTo}: $path')),
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
    final localeMode = ref.watch(localeModeProvider);
    final transcriptionMode = ref.watch(transcriptionModeProvider);
    final failureHandling = ref.watch(failureHandlingProvider);
    final audioRetention = ref.watch(audioRetentionPolicyProvider);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settings)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _CardSection(
            title: l10n.language,
            children: [
              SegmentedButton<AppLocaleMode>(
                segments: [
                  ButtonSegment(
                    value: AppLocaleMode.system,
                    label: Text(l10n.followSystem),
                  ),
                  ButtonSegment(
                    value: AppLocaleMode.zh,
                    label: Text(l10n.simplifiedChinese),
                  ),
                  ButtonSegment(
                    value: AppLocaleMode.en,
                    label: Text(l10n.english),
                  ),
                ],
                selected: {localeMode},
                onSelectionChanged: (selection) {
                  ref
                      .read(appSettingsProvider.notifier)
                      .setLocaleMode(selection.first);
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          _CardSection(
            title: l10n.transcriptionMode,
            children: [
              SegmentedButton<TranscriptionMode>(
                segments: [
                  ButtonSegment(
                    value: TranscriptionMode.streaming,
                    label: Text(l10n.streamingMode),
                  ),
                  ButtonSegment(
                    value: TranscriptionMode.afterQso,
                    label: Text(l10n.afterQsoMode),
                  ),
                ],
                selected: {transcriptionMode},
                onSelectionChanged: (selection) {
                  ref
                      .read(appSettingsProvider.notifier)
                      .setTranscriptionMode(selection.first);
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          _CardSection(
            title: l10n.failureHandling,
            children: [
              SegmentedButton<FailureHandling>(
                segments: [
                  ButtonSegment(
                    value: FailureHandling.alert,
                    label: Text(l10n.showErrors),
                  ),
                  ButtonSegment(
                    value: FailureHandling.silent,
                    label: Text(l10n.degradeSilently),
                  ),
                ],
                selected: {failureHandling},
                onSelectionChanged: (selection) {
                  ref
                      .read(appSettingsProvider.notifier)
                      .setFailureHandling(selection.first);
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          _CardSection(
            title: l10n.audioRetention,
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
          const SizedBox(height: 16),
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
        ],
      ),
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
          Text(l10n.localDataManagementDesc),
          const SizedBox(height: 16),
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
                          color: provider.hasApiKey ? Colors.green : null,
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
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => _ProviderFormDialog(provider: provider),
    );
    if (saved == true) {
      ref.invalidate(providerProfilesProvider);
      ref.invalidate(modelOptionsProvider);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.l10n.providerSaved)));
      }
    }
  }
}

class _ProviderFormDialog extends ConsumerStatefulWidget {
  const _ProviderFormDialog({this.provider});

  final ProviderProfile? provider;

  @override
  ConsumerState<_ProviderFormDialog> createState() =>
      _ProviderFormDialogState();
}

class _ProviderFormDialogState extends ConsumerState<_ProviderFormDialog> {
  final _nameController = TextEditingController();
  final _baseUrlController = TextEditingController(
    text: 'https://api.openai.com/v1',
  );
  final _apiKeyController = TextEditingController();
  final _manualModelController = TextEditingController();
  String _providerType = 'OpenAI';
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
      return;
    }
    _loadingInitial = true;
    _providerType = provider.type;
    _nameController.text = provider.name;
    _baseUrlController.text =
        provider.baseUrl ?? _defaultBaseUrlForType(provider.type) ?? '';
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
    return AlertDialog(
      title: Text(
        widget.provider == null ? l10n.addProvider : l10n.editProvider,
      ),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_loadingInitial) ...[
                const LinearProgressIndicator(),
                const SizedBox(height: 12),
              ],
              DropdownButtonFormField<String>(
                initialValue: _providerType,
                decoration: InputDecoration(labelText: l10n.providerType),
                items: [
                  for (final type in _providerTypes)
                    DropdownMenuItem(value: type, child: Text(type)),
                ],
                onChanged: disabled
                    ? null
                    : (value) {
                        if (value == null) {
                          return;
                        }
                        setState(() {
                          _providerType = value;
                          final defaultBaseUrl = _defaultBaseUrlForType(value);
                          if (defaultBaseUrl != null) {
                            _baseUrlController.text = defaultBaseUrl;
                          }
                        });
                      },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _nameController,
                enabled: !disabled,
                decoration: InputDecoration(labelText: l10n.displayName),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _baseUrlController,
                enabled: !disabled,
                decoration: InputDecoration(labelText: l10n.baseUrl),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _apiKeyController,
                enabled: !disabled,
                obscureText: true,
                decoration: InputDecoration(labelText: l10n.apiKey),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: disabled ? null : _testConnection,
                    icon: const Icon(Icons.network_check),
                    label: Text(l10n.testConnection),
                  ),
                  OutlinedButton.icon(
                    onPressed: disabled ? null : _fetchModels,
                    icon: const Icon(Icons.cloud_download),
                    label: Text(l10n.fetchModels),
                  ),
                ],
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
                decoration: InputDecoration(labelText: l10n.modelName),
              ),
              const SizedBox(height: 8),
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
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: disabled ? null : () => Navigator.of(context).pop(false),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        FilledButton.icon(
          onPressed: disabled ? null : _saveProvider,
          icon: _busy
              ? const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save),
          label: Text(l10n.saveProvider),
        ),
      ],
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
        if (connection != null) {
          _nameController.text = connection.name;
          _providerType = connection.type;
          _baseUrlController.text =
              connection.baseUrl ??
              _defaultBaseUrlForType(connection.type) ??
              '';
          _apiKeyController.text = connection.apiKey ?? '';
        }
        _models =
            models
                .map(
                  (model) => FetchedProviderModel(
                    id: model.name,
                    capabilities: model.capabilities,
                  ),
                )
                .toList()
              ..sort((a, b) => a.id.compareTo(b.id));
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

  Future<void> _testConnection() async {
    await _runBusy(() async {
      await ref
          .read(providerModelFetchServiceProvider)
          .testConnection(
            baseUrl: _baseUrlController.text,
            apiKey: _blankToNull(_apiKeyController.text),
          );
      if (mounted) {
        _showSnack(context.l10n.connectionTestSucceeded);
      }
    });
  }

  Future<void> _fetchModels() async {
    await _runBusy(() async {
      final models = await ref
          .read(providerModelFetchServiceProvider)
          .fetchModels(
            baseUrl: _baseUrlController.text,
            apiKey: _blankToNull(_apiKeyController.text),
          );
      setState(() => _models = _mergeFetchedModels(_models, models));
      if (mounted) {
        _showSnack('${models.length} ${context.l10n.modelsFetched}');
      }
    });
  }

  Future<void> _saveProvider() async {
    final l10n = context.l10n;
    final name = _nameController.text.trim();
    final baseUrl = _baseUrlController.text.trim();
    if (name.isEmpty || _providerType.trim().isEmpty) {
      _showSnack(l10n.providerRequiredFields);
      return;
    }
    if (baseUrl.isEmpty) {
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
            type: _providerType,
            baseUrl: baseUrl,
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
    final transcriptionMode = ref.watch(transcriptionModeProvider);

    final transcriptionAssignment = _assignmentFor(
      assignments,
      ModelAssignmentTask.transcription,
    );
    final structuringAssignment = _assignmentFor(
      assignments,
      ModelAssignmentTask.structuring,
    );

    final selectedTranscriptionProvider =
        _selectedTranscriptionProviderId ??
        _validProviderId(providers, transcriptionAssignment?.providerId);
    final selectedStructuringProvider =
        _selectedStructuringProviderId ??
        _validProviderId(providers, structuringAssignment?.providerId);

    final transcriptionModels = models.where((model) {
      final hasRequiredCapability =
          transcriptionMode == TranscriptionMode.streaming
          ? model.supports(ModelCapability.streaming)
          : model.supports(ModelCapability.speech);
      return model.providerId == selectedTranscriptionProvider &&
          hasRequiredCapability;
    }).toList();
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
            title: l10n.transcriptionModel,
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
    String? selectedStructuring,
  ) async {
    final transcription = _modelById(models, selectedTranscription);
    final structuring = _modelById(models, selectedStructuring);
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
    await notifier.save(
      ModelAssignment(
        task: ModelAssignmentTask.structuring,
        providerId: structuring.providerId,
        modelId: structuring.id,
      ),
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.modelAssignmentSaved)),
      );
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
  const QsoReviewScreen({super.key, required this.draft, this.importJobId});

  final QsoDraft draft;
  final String? importJobId;

  @override
  ConsumerState<QsoReviewScreen> createState() => _QsoReviewScreenState();
}

class _QsoReviewScreenState extends ConsumerState<QsoReviewScreen> {
  late LogStatus status = widget.draft.status;
  late final TextEditingController _callsignController;
  late final TextEditingController _dateTimeController;
  late final TextEditingController _bandController;
  late final TextEditingController _frequencyController;
  late final TextEditingController _modeController;
  late final TextEditingController _sentRstController;
  late final TextEditingController _receivedRstController;
  late final TextEditingController _nameController;
  late final TextEditingController _qthController;
  late final TextEditingController _rigController;
  late final TextEditingController _antennaController;
  late final TextEditingController _notesController;
  late String? _audioPath;
  late String? _rawTranscript;
  bool _isAudioPlaying = false;
  String? _audioPlaybackError;

  @override
  void initState() {
    super.initState();
    final draft = widget.draft;
    _callsignController = TextEditingController(text: draft.callsign.value);
    _dateTimeController = TextEditingController(
      text: draft.dateTime.value?.toIso8601String() ?? '',
    );
    _bandController = TextEditingController(text: draft.band.value);
    _frequencyController = TextEditingController(text: draft.frequency.value);
    _modeController = TextEditingController(text: draft.mode.value);
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
    _notesController = TextEditingController(text: draft.notes?.value ?? '');
    _audioPath = draft.audioPath;
    _rawTranscript = draft.rawTranscript;
  }

  @override
  void dispose() {
    _callsignController.dispose();
    _dateTimeController.dispose();
    _bandController.dispose();
    _frequencyController.dispose();
    _modeController.dispose();
    _sentRstController.dispose();
    _receivedRstController.dispose();
    _nameController.dispose();
    _qthController.dispose();
    _rigController.dispose();
    _antennaController.dispose();
    _notesController.dispose();
    unawaited(ref.read(audioPlaybackServiceProvider).stop());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.qsoReview)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<LogStatus>(
            initialValue: status,
            decoration: InputDecoration(labelText: l10n.status),
            items: LogStatus.values
                .map(
                  (value) => DropdownMenuItem(
                    value: value,
                    child: Text(_statusLabel(context, value)),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() => status = value);
              }
            },
          ),
          const SizedBox(height: 12),
          _ReviewField(
            label: l10n.callsign,
            controller: _callsignController,
            requiredField: true,
          ),
          _ReviewField(
            label: l10n.dateTime,
            controller: _dateTimeController,
            requiredField: true,
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              l10n.bandOrFrequencyRequired,
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
          _TwoColumnFields(
            left: _ReviewField(label: l10n.band, controller: _bandController),
            right: _ReviewField(
              label: l10n.frequency,
              controller: _frequencyController,
            ),
          ),
          _ReviewField(
            label: l10n.mode,
            controller: _modeController,
            requiredField: true,
          ),
          _TwoColumnFields(
            left: _ReviewField(
              label: l10n.sentRst,
              controller: _sentRstController,
              requiredField: true,
            ),
            right: _ReviewField(
              label: l10n.receivedRst,
              controller: _receivedRstController,
              requiredField: true,
            ),
          ),
          _ReviewField(label: l10n.name, controller: _nameController),
          _ReviewField(label: l10n.qth, controller: _qthController),
          _ReviewField(label: l10n.rig, controller: _rigController),
          _ReviewField(label: l10n.antenna, controller: _antennaController),
          _ReviewField(
            label: l10n.notes,
            controller: _notesController,
            maxLines: 3,
          ),
          const SizedBox(height: 12),
          _RetainedAudioCard(
            title: l10n.audioLog,
            path: _audioPath,
            missingText: l10n.noAudioFile,
            isPlaying: _isAudioPlaying,
            errorText: _audioPlaybackError,
            playLabel: l10n.playAudio,
            stopLabel: l10n.stopAudio,
            deleteLabel: l10n.deleteRetainedAudio,
            onPlayPressed: _audioPath == null ? null : _toggleAudioPlayback,
            onDelete: _audioPath == null ? null : _deleteRetainedAudio,
          ),
          const SizedBox(height: 12),
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
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () async {
              final updated = _buildDraft();
              if ((status == LogStatus.confirmed ||
                      status == LogStatus.exported) &&
                  !updated.hasRequiredFields) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l10n.requiredFieldsMissing)),
                );
                return;
              }
              final id = await ref.read(qsoLogProvider.notifier).save(updated);
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
        ],
      ),
    );
  }

  QsoDraft _buildDraft() {
    final draft = widget.draft;
    final parsedDateTime = DateTime.tryParse(_dateTimeController.text.trim());
    return QsoDraft(
      id: draft.id,
      callsign: _editedField(_callsignController.text),
      dateTime: QsoField(value: parsedDateTime, userEdited: true),
      band: _editedField(_bandController.text),
      frequency: _editedField(_frequencyController.text),
      mode: _editedField(_modeController.text),
      sentRst: _editedField(_sentRstController.text),
      receivedRst: _editedField(_receivedRstController.text),
      status: status,
      name: _optionalEditedField(_nameController.text),
      qth: _optionalEditedField(_qthController.text),
      notes: _optionalEditedField(_notesController.text),
      rig: _optionalEditedField(_rigController.text),
      antenna: _optionalEditedField(_antennaController.text),
      audioPath: _audioPath,
      rawTranscript: _rawTranscript,
    );
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
    await ref
        .read(qsoLogProvider.notifier)
        .deleteRetainedAudio(qsoId: widget.draft.id, path: audioPath);
    if (mounted) {
      setState(() {
        _audioPath = null;
        _isAudioPlaying = false;
        _audioPlaybackError = null;
      });
    }
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
    final confirmed = await _confirmDestructiveAction(
      context,
      title: context.l10n.deleteRawTranscript,
      message: context.l10n.deleteRawTranscriptConfirm,
    );
    if (!confirmed) {
      return;
    }
    await ref.read(qsoLogProvider.notifier).clearRawTranscript(widget.draft.id);
    final importJobId = widget.importJobId;
    if (importJobId != null) {
      await ref.read(importJobsProvider.notifier).clearRawText(importJobId);
    }
    if (mounted) {
      setState(() => _rawTranscript = null);
    }
  }

  QsoField<String> _editedField(String value) {
    return QsoField(value: value.trim(), userEdited: true);
  }

  QsoField<String>? _optionalEditedField(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return QsoField(value: trimmed, userEdited: true);
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.number, required this.title});

  final int number;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          CircleAvatar(radius: 16, child: Text('$number')),
          const SizedBox(width: 12),
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
                if (selected) const Icon(Icons.check_circle_outline),
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.circle,
                  size: 12,
                  color: active ? Colors.red : Colors.grey,
                ),
                const SizedBox(width: 8),
                Text(title, style: Theme.of(context).textTheme.labelLarge),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '$minutes:$seconds',
              style: Theme.of(context).textTheme.displayMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _TranscriptCard extends StatelessWidget {
  const _TranscriptCard({required this.segments});

  final List<TranscriptSegment> segments;

  @override
  Widget build(BuildContext context) {
    return _CardSection(
      title: context.l10n.liveTranscript,
      children: [
        for (final segment in segments)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: RichText(
              text: TextSpan(
                style: DefaultTextStyle.of(context).style,
                children: [
                  TextSpan(
                    text: '${segment.speaker}: ',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  TextSpan(text: segment.text),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _DraftCard extends StatelessWidget {
  const _DraftCard({required this.draft});

  final QsoDraft draft;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return _CardSection(
      title: l10n.draftEntry,
      trailing: Wrap(
        spacing: 8,
        children: [
          _LegendDot(color: Colors.blue, label: l10n.aiFilled),
          _LegendDot(color: Colors.grey, label: l10n.userEdited),
        ],
      ),
      children: [
        _FieldTile(
          label: l10n.callsign,
          field: draft.callsign,
          requiredField: true,
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            l10n.bandOrFrequencyRequired,
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ),
        _TwoColumnFields(
          left: _FieldTile(label: l10n.band, field: draft.band),
          right: _FieldTile(label: l10n.frequency, field: draft.frequency),
        ),
        _FieldTile(label: l10n.mode, field: draft.mode, requiredField: true),
        _TwoColumnFields(
          left: _FieldTile(
            label: l10n.sentRst,
            field: draft.sentRst,
            requiredField: true,
          ),
          right: _FieldTile(
            label: l10n.receivedRst,
            field: draft.receivedRst,
            requiredField: true,
          ),
        ),
        _TwoColumnFields(
          left: _FieldTile(label: l10n.qth, field: draft.qth),
          right: _FieldTile(label: l10n.name, field: draft.name),
        ),
        _TwoColumnFields(
          left: _FieldTile(label: l10n.rig, field: draft.rig),
          right: _FieldTile(label: l10n.antenna, field: draft.antenna),
        ),
        _FieldTile(label: l10n.notes, field: draft.notes, maxLines: 3),
      ],
    );
  }
}

class _FieldTile extends StatelessWidget {
  const _FieldTile({
    required this.label,
    required this.field,
    this.requiredField = false,
    this.maxLines = 1,
  });

  final String label;
  final QsoField<String>? field;
  final bool requiredField;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final needsReview = field?.needsReview ?? false;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        initialValue: field?.value ?? '',
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: requiredField ? '$label *' : label,
          helperText: needsReview ? context.l10n.lowConfidence : null,
          helperStyle: needsReview
              ? const TextStyle(color: Colors.orange)
              : null,
          fillColor: needsReview ? Colors.orange.withAlpha(20) : null,
          filled: needsReview,
        ),
      ),
    );
  }
}

class _RecentSessionList extends StatelessWidget {
  const _RecentSessionList({required this.logs});

  final List<QsoDraft> logs;

  @override
  Widget build(BuildContext context) {
    return _CardSection(
      title: context.l10n.recentSession,
      children: [
        for (final log in logs)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              log.callsign.value,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text('${log.band.value} ${log.mode.value}'),
            trailing: Text('${log.sentRst.value} / ${log.receivedRst.value}'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => QsoReviewScreen(draft: log),
              ),
            ),
          ),
      ],
    );
  }
}

class _LogListItem extends StatelessWidget {
  const _LogListItem({required this.log});

  final QsoDraft log;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(log.status);
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => QsoReviewScreen(draft: log)),
      ),
      child: Card(
        child: IntrinsicHeight(
          child: Row(
            children: [
              Container(width: 4, color: color),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              log.callsign.value,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                          _StatusChip(status: log.status),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${log.frequency.value} MHz · ${log.band.value} · ${log.mode.value}',
                      ),
                      const SizedBox(height: 4),
                      Text('${log.sentRst.value} / ${log.receivedRst.value}'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
          side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
        ),
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Icon(icon, size: 42),
              const SizedBox(height: 12),
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(subtitle, textAlign: TextAlign.center),
            ],
          ),
        ),
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: left),
        const SizedBox(width: 10),
        Expanded(child: right),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.circle, color: color, size: 10),
        const SizedBox(width: 4),
        Text(label, style: Theme.of(context).textTheme.labelSmall),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final LogStatus status;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(status);
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
            decoration: InputDecoration(labelText: context.l10n.modelName),
            items: [
              for (final model in models)
                DropdownMenuItem(value: model.id, child: Text(model.name)),
            ],
            onChanged: onChanged,
          ),
        const SizedBox(height: 8),
        for (final model in models)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Wrap(
              spacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  model.name,
                  style: model.id == effectiveModelId
                      ? const TextStyle(fontWeight: FontWeight.bold)
                      : null,
                ),
                for (final capability in model.capabilities)
                  _CapabilityChip(capability: capability),
              ],
            ),
          ),
      ],
    );
  }
}

class _CapabilityChip extends StatelessWidget {
  const _CapabilityChip({required this.capability});

  final ModelCapability capability;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final label = switch (capability) {
      ModelCapability.speech => l10n.speech,
      ModelCapability.streaming => l10n.streaming,
      ModelCapability.text => l10n.text,
      ModelCapability.structuring => l10n.structuring,
    };
    return Chip(label: Text(label), visualDensity: VisualDensity.compact);
  }
}

class _ReviewField extends StatelessWidget {
  const _ReviewField({
    required this.label,
    required this.controller,
    this.requiredField = false,
    this.maxLines = 1,
  });

  final String label;
  final TextEditingController controller;
  final bool requiredField;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: requiredField ? '$label *' : label,
        ),
      ),
    );
  }
}

String? _blankToNull(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

const _providerTypes = [
  'OpenAI',
  'OpenAI-compatible',
  'Local endpoint',
  'DeepSeek',
  'Qwen',
  'Zhipu',
  'Gemini',
];

String? _defaultBaseUrlForType(String type) {
  return switch (type) {
    'OpenAI' => 'https://api.openai.com/v1',
    'Local endpoint' => 'http://10.0.2.2:8000/v1',
    'DeepSeek' => 'https://api.deepseek.com',
    'Qwen' => 'https://dashscope.aliyuncs.com/compatible-mode/v1',
    'Zhipu' => 'https://open.bigmodel.cn/api/paas/v4',
    'Gemini' => 'https://generativelanguage.googleapis.com/v1beta/openai',
    _ => null,
  };
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
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
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
    'no_streaming_transcript' => l10n.noStreamingTranscriptProduced,
    _ => warning,
  };
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

Color _statusColor(LogStatus status) {
  return switch (status) {
    LogStatus.draft => Colors.grey,
    LogStatus.needsReview => Colors.orange,
    LogStatus.confirmed => Colors.green,
    LogStatus.exported => Colors.blue,
    LogStatus.failed => Colors.red,
  };
}

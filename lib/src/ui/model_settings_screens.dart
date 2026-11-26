part of 'screens.dart';

class AiModelSettingsScreen extends ConsumerStatefulWidget {
  const AiModelSettingsScreen({super.key});

  @override
  ConsumerState<AiModelSettingsScreen> createState() =>
      _AiModelSettingsScreenState();
}

class _AiModelSettingsScreenState extends ConsumerState<AiModelSettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final providersState = ref.watch(providerProfilesProvider);
    final modelsState = ref.watch(modelOptionsProvider);
    final assignmentsState = ref.watch(modelAssignmentsProvider);
    final loading =
        providersState.isLoading ||
        modelsState.isLoading ||
        assignmentsState.isLoading;
    final error =
        providersState.error ?? modelsState.error ?? assignmentsState.error;
    final providers = providersState.maybeWhen(
      data: (value) => value,
      orElse: () => const <ProviderProfile>[],
    );
    final models = modelsState.maybeWhen(
      data: (value) => value,
      orElse: () => const <AiModelOption>[],
    );
    final assignments = assignmentsState.maybeWhen(
      data: (value) => value,
      orElse: () => const <ModelAssignment>[],
    );

    return Scaffold(
      appBar: AppBar(title: Text(l10n.aiModels)),
      body: ListView(
        padding: AppLayout.settingsPagePadding,
        children: [
          _SettingsPageHeader(
            title: l10n.aiModels,
            subtitle: l10n.modelSettingsOverviewDesc,
          ),
          const SizedBox(height: 24),
          if (loading)
            const _SettingsPanel(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator(),
                ),
              ),
            )
          else if (error != null)
            _SettingsPanel(title: l10n.failed, child: Text(error.toString()))
          else ...[
            _SettingsPanel(
              title: l10n.workflowModels,
              subtitle: l10n.modelAssignmentDesc,
              trailing: const Icon(Icons.chevron_right),
              onTap: _openModelAssignments,
              child: Column(
                children: [
                  _AssignedModelSummary(
                    key: const ValueKey('assigned-model-transcription'),
                    icon: Icons.graphic_eq,
                    title: l10n.transcriptionModelAfter,
                    model: _assignedModel(
                      models,
                      assignments,
                      ModelAssignmentTask.transcription,
                    ),
                  ),
                  const Divider(height: 24),
                  _AssignedModelSummary(
                    key: const ValueKey('assigned-model-streaming'),
                    icon: Icons.stream,
                    title: l10n.transcriptionModelStreaming,
                    model: _assignedModel(
                      models,
                      assignments,
                      ModelAssignmentTask.transcriptionStreaming,
                    ),
                  ),
                  const Divider(height: 24),
                  _AssignedModelSummary(
                    key: const ValueKey('assigned-model-structuring'),
                    icon: Icons.auto_fix_high,
                    title: l10n.structuringModel,
                    model: _assignedModel(
                      models,
                      assignments,
                      ModelAssignmentTask.structuring,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _SettingsPanel(
              title: l10n.configuredModels,
              subtitle: l10n.capabilityHint,
              child: models.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(l10n.noModelsSaved),
                    )
                  : Column(
                      children: [
                        for (var index = 0; index < models.length; index++) ...[
                          _ConfiguredModelTile(
                            model: models[index],
                            onTap: () {
                              final provider = _providerById(
                                providers,
                                models[index].providerId,
                              );
                              if (provider != null) {
                                _editProvider(provider);
                              }
                            },
                          ),
                          if (index != models.length - 1)
                            const Divider(height: 24),
                        ],
                      ],
                    ),
            ),
          ],
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: _openProviderManagement,
            icon: const Icon(Icons.hub_outlined),
            label: Text(l10n.manageProviders),
          ),
        ],
      ),
    );
  }

  AiModelOption? _assignedModel(
    List<AiModelOption> models,
    List<ModelAssignment> assignments,
    ModelAssignmentTask task,
  ) {
    ModelAssignment? assignment;
    for (final candidate in assignments) {
      if (candidate.task == task) {
        assignment = candidate;
        break;
      }
    }
    if (assignment == null) {
      return null;
    }
    for (final model in models) {
      if (model.id == assignment.modelId &&
          model.providerId == assignment.providerId) {
        return model;
      }
    }
    return null;
  }

  ProviderProfile? _providerById(List<ProviderProfile> providers, String id) {
    for (final provider in providers) {
      if (provider.id == id) {
        return provider;
      }
    }
    return null;
  }

  Future<void> _openModelAssignments() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const ModelAssignmentScreen()),
    );
    ref.invalidate(modelAssignmentsProvider);
  }

  Future<void> _openProviderManagement() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const ProviderSetupScreen()),
    );
    ref.invalidate(providerProfilesProvider);
    ref.invalidate(modelOptionsProvider);
  }

  Future<void> _editProvider(ProviderProfile provider) async {
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
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 96),
        children: [
          _SettingsPageHeader(
            title: l10n.providerSetup,
            subtitle: l10n.providerManagementDesc,
          ),
          const SizedBox(height: 24),
          providersState.when(
            data: (providers) => _SettingsPanel(
              title: l10n.providerManagement,
              child: providers.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(l10n.noConfiguredProviders),
                    )
                  : Column(
                      children: [
                        for (
                          var index = 0;
                          index < providers.length;
                          index++
                        ) ...[
                          _ProviderSummaryTile(
                            provider: providers[index],
                            modelCount:
                                modelCountByProvider[providers[index].id] ?? 0,
                            keyColor: osc.phosphor,
                            onTap: () => _showProviderDialog(providers[index]),
                          ),
                          if (index != providers.length - 1)
                            const Divider(height: 24),
                        ],
                      ],
                    ),
            ),
            error: (error, stackTrace) => _SettingsPanel(
              title: l10n.failed,
              child: Text(error.toString()),
            ),
            loading: () => const _SettingsPanel(
              child: Center(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: CircularProgressIndicator(),
                ),
              ),
            ),
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
      body: _SettingsFormTheme(
        child: SingleChildScrollView(
          padding: AppLayout.settingsPagePadding,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SettingsPageHeader(
                    title: widget.provider == null
                        ? l10n.addProvider
                        : l10n.editProvider,
                    subtitle: l10n.providerManagementDesc,
                  ),
                  if (_loadingInitial) ...[
                    const SizedBox(height: 16),
                    const LinearProgressIndicator(),
                  ],
                  const SizedBox(height: 24),
                  _SettingsPanel(
                    title: l10n.providerManagement,
                    subtitle: l10n.providerManagementDesc,
                    child: Column(
                      children: [
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
                                    _baseUrlController.text =
                                        descriptor.defaultBaseUrl;
                                    _models = _presetModelsFor(descriptor);
                                    if (_nameController.text.trim().isEmpty) {
                                      _nameController.text =
                                          descriptor.displayName;
                                    }
                                  });
                                },
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _nameController,
                          enabled: !disabled,
                          decoration: InputDecoration(
                            labelText: l10n.displayName,
                            helperText: l10n.displayNameHint,
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _baseUrlController,
                          enabled: !disabled,
                          keyboardType: TextInputType.url,
                          decoration: InputDecoration(
                            labelText: l10n.baseUrl,
                            helperText: l10n.baseUrlHint,
                          ),
                        ),
                        const SizedBox(height: 14),
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
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: disabled ? null : _testConnection,
                            icon: const Icon(Icons.network_check),
                            label: Text(l10n.testConnection),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  _SettingsPanel(
                    title: l10n.savedModels,
                    subtitle: l10n.capabilityHint,
                    child: _models.isEmpty
                        ? Text(l10n.noModelsSaved)
                        : Column(
                            children: [
                              for (final model in _models)
                                _FetchedModelTile(
                                  model: model,
                                  onSelectedChanged: (selected) {
                                    setState(
                                      () => _models = [
                                        for (final item in _models)
                                          item.id == model.id
                                              ? item.copyWith(
                                                  selected: selected,
                                                )
                                              : item,
                                      ],
                                    );
                                  },
                                  onCapabilitiesChanged: (capabilities) {
                                    setState(
                                      () => _models = [
                                        for (final item in _models)
                                          item.id == model.id
                                              ? item.copyWith(
                                                  capabilities: capabilities,
                                                )
                                              : item,
                                      ],
                                    );
                                  },
                                ),
                            ],
                          ),
                  ),
                  const SizedBox(height: 20),
                  _SettingsPanel(
                    title: l10n.addModel,
                    subtitle: l10n.modelNameHint,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: _manualModelController,
                          enabled: !disabled,
                          decoration: InputDecoration(
                            labelText: l10n.modelName,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          l10n.capabilityHint,
                          style: Theme.of(context).textTheme.appControlLabel,
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final capability in ModelCapability.values)
                              ConstrainedBox(
                                constraints: const BoxConstraints(
                                  minHeight: AppLayout.primaryActionHeight,
                                ),
                                child: FilterChip(
                                  key: ValueKey(
                                    'manual-model-capability-${capability.name}',
                                  ),
                                  label: Text(
                                    _capabilityLabel(context, capability),
                                  ),
                                  visualDensity: VisualDensity.compact,
                                  selected: _manualCapabilities.contains(
                                    capability,
                                  ),
                                  onSelected: disabled
                                      ? null
                                      : (selected) {
                                          setState(() {
                                            if (selected) {
                                              _manualCapabilities.add(
                                                capability,
                                              );
                                            } else {
                                              _manualCapabilities.remove(
                                                capability,
                                              );
                                            }
                                          });
                                        },
                                ),
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
      body: _SettingsFormTheme(
        child: ListView(
          padding: AppLayout.settingsPagePadding,
          children: [
            _SettingsPageHeader(
              title: l10n.modelAssignment,
              subtitle: l10n.modelAssignmentDesc,
            ),
            const SizedBox(height: 24),
            if (providers.isEmpty) ...[
              _SettingsPanel(
                title: l10n.providerManagement,
                child: Text(l10n.noConfiguredProviders),
              ),
              const SizedBox(height: 20),
            ],
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
            const SizedBox(height: 20),
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
            const SizedBox(height: 20),
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
            const SizedBox(height: 20),
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

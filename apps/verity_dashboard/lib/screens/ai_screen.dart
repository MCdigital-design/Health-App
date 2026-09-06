import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../ai/ai_prefs.dart';
import '../ai/openai_chat_service.dart';
import '../ai/openai_device_auth.dart';
import '../ai/openai_models.dart';
import '../ai/session_brief.dart';
import '../ai/studio_dashboard_store.dart';
import '../ai/studio_spec.dart';
import '../models/recording_session.dart';
import '../widgets/collapsible_hint.dart';
import 'ai_studio_panel.dart';

enum AiWorkspace { chooser, chat, studio }

class AiScreen extends StatefulWidget {
  final RecordingSession? focusSession;
  final AiWorkspace? initialWorkspace;
  final OpenAiDeviceAuth? auth;
  final OpenAiChatService? chat;
  final OpenAiModelCatalog? catalog;
  final AiPrefs? prefs;

  const AiScreen({
    super.key,
    this.focusSession,
    this.initialWorkspace,
    this.auth,
    this.chat,
    this.catalog,
    this.prefs,
  });

  @override
  State<AiScreen> createState() => _AiScreenState();
}

class _AiScreenState extends State<AiScreen> {
  late final OpenAiDeviceAuth _auth;
  late final OpenAiChatService _chat;
  late final OpenAiModelCatalog _catalog;
  late final AiPrefs _prefs;
  final _input = TextEditingController();
  final _turns = <ChatTurn>[];

  OpenAiSession? _session;
  DeviceLoginPending? _pending;
  AiWorkspace _workspace = AiWorkspace.chooser;
  List<LlmModel> _models = const [];
  bool _modelsFromAccount = false;
  String? _modelId;
  ContextDepth _depth = ContextDepth.standard;
  bool _loading = true;
  bool _busy = false;
  bool _cancelled = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _auth = widget.auth ?? OpenAiDeviceAuth();
    _chat = widget.chat ?? OpenAiChatService(auth: _auth);
    _catalog = widget.catalog ?? OpenAiModelCatalog();
    _prefs = widget.prefs ?? AiPrefs();
    _workspace = widget.initialWorkspace ??
        (widget.focusSession != null ? AiWorkspace.chat : AiWorkspace.chooser);
    _restore();
  }

  @override
  void dispose() {
    _cancelled = true;
    _input.dispose();
    super.dispose();
  }

  Future<void> _restore() async {
    final session = await _auth.loadSession();
    final depth = await _prefs.loadDepth();
    if (!mounted) return;
    setState(() {
      _session = session;
      _depth = depth;
      _loading = false;
    });
    if (session != null) {
      await _loadModels(session);
    }
  }

  Future<void> _loadModels(OpenAiSession session) async {
    final previous = await _prefs.loadSelectedModel(accountId: session.accountId);
    final result = await _catalog.fetchForAccount(session);
    final modelId = pickDefaultModel(result.models, previous: previous);
    await _prefs.saveSelectedModel(modelId, accountId: session.accountId);
    if (!mounted) return;
    setState(() {
      _models = result.models;
      _modelsFromAccount = result.fromAccount;
      _modelId = modelId;
    });
  }

  Future<void> _startLogin() async {
    setState(() {
      _busy = true;
      _error = null;
      _cancelled = false;
    });
    try {
      final pending = await _auth.startDeviceLogin();
      if (!mounted) return;
      setState(() {
        _pending = pending;
        _busy = false;
      });
      final session = await _auth.waitForApproval(
        pending,
        isCancelled: () => _cancelled || !mounted,
      );
      if (!mounted) return;
      setState(() {
        _session = session;
        _pending = null;
      });
      await _loadModels(session);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _pending = null;
        _busy = false;
      });
    }
  }

  void _cancelLogin() {
    _cancelled = true;
    setState(() {
      _pending = null;
      _busy = false;
    });
  }

  Future<void> _signOut({bool startAgain = false}) async {
    await _auth.signOut();
    await _prefs.clearAccountModel();
    if (!mounted) return;
    setState(() {
      _session = null;
      _models = const [];
      _modelsFromAccount = false;
      _modelId = null;
      _turns.clear();
      _pending = null;
      if (widget.focusSession == null) {
        _workspace = AiWorkspace.chooser;
      }
    });
    if (startAgain) {
      await _startLogin();
    }
  }

  Future<void> _selectModel(String? id) async {
    if (id == null) return;
    setState(() => _modelId = id);
    await _prefs.saveSelectedModel(id, accountId: _session?.accountId);
  }

  Future<void> _selectDepth(ContextDepth? depth) async {
    if (depth == null) return;
    setState(() => _depth = depth);
    await _prefs.saveDepth(depth);
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _busy || _modelId == null) return;
    _input.clear();
    setState(() {
      _turns.add(ChatTurn(role: 'user', text: text));
      _busy = true;
      _error = null;
    });
    try {
      final history = _turns.length <= 1
          ? const <ChatTurn>[]
          : _turns.sublist(0, _turns.length - 1);
      final reply = await _chat.ask(
        question: text,
        history: history,
        focusSessionId: widget.focusSession?.id,
        model: _modelId,
        depth: _depth,
        accountModels: _models,
      );
      if (!mounted) return;
      setState(() {
        _turns.add(ChatTurn(role: 'assistant', text: reply));
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _busy = false;
      });
    }
  }

  Future<void> _saveSpec(StudioDashboardSpec spec) async {
    await StudioDashboardStore().insert(
      title: spec.title,
      specJson: jsonEncode(spec.toJson()),
      accountHint: _session?.email,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Saved to Studio')),
    );
  }

  Future<void> _openVerification() async {
    final url = Uri.parse(kOpenAiVerificationUrl);
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final title = switch (_workspace) {
      AiWorkspace.chooser => widget.focusSession == null ? 'AI' : 'Ask AI',
      AiWorkspace.chat => widget.focusSession == null ? 'Chat' : 'Ask AI',
      AiWorkspace.studio => 'Studio',
    };
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: _workspace != AiWorkspace.chooser && widget.focusSession == null
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: 'AI home',
                onPressed: () => setState(() => _workspace = AiWorkspace.chooser),
              )
            : null,
        actions: [
          if (_session != null)
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'switch') _signOut(startAgain: true);
                if (value == 'out') _signOut();
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'switch', child: Text('Switch account')),
                PopupMenuItem(value: 'out', child: Text('Sign out')),
              ],
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _session == null
              ? ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (_pending == null) _signInCard(),
                    if (_pending != null) _codeCard(),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(_error!, style: const TextStyle(color: Colors.orangeAccent)),
                      ),
                  ],
                )
              : Column(
                  children: [
                    if (_workspace != AiWorkspace.chooser) _workspaceTabs(),
                    Expanded(child: _signedInBody()),
                  ],
                ),
    );
  }

  Widget _signedInBody() {
    switch (_workspace) {
      case AiWorkspace.chooser:
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _accountCard(),
            const SizedBox(height: 12),
            _chooserCard(
              icon: Icons.chat_bubble_outline,
              title: 'Chat',
              body: 'Ask a question, give a direction, or tell it to make something.',
              onTap: () => setState(() => _workspace = AiWorkspace.chat),
            ),
            const SizedBox(height: 12),
            _chooserCard(
              icon: Icons.dashboard_customize,
              title: 'Studio',
              body: 'AI builds custom dashboards from recordings on this phone.',
              onTap: () => setState(() => _workspace = AiWorkspace.studio),
            ),
          ],
        );
      case AiWorkspace.chat:
        return Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (widget.focusSession != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Chip(
                        avatar: const Icon(Icons.folder, size: 16),
                        label: Text('Using ${widget.focusSession!.name}'),
                      ),
                    ),
                  _accountCard(),
                  const SizedBox(height: 12),
                  _modelAndDepth(),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(_error!, style: const TextStyle(color: Colors.orangeAccent)),
                    ),
                  const SizedBox(height: 12),
                  for (final turn in _turns) _bubble(turn),
                  if (_busy)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('Thinking…'),
                    ),
                ],
              ),
            ),
            _composer(),
          ],
        );
      case AiWorkspace.studio:
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: _modelAndDepth(),
            ),
            Expanded(
              child: AiStudioPanel(
                chat: _chat,
                model: _modelId ?? pickDefaultModel(_models),
                accountModels: _models,
                depth: _depth,
                accountHint: _session?.email,
                focusSessionId: widget.focusSession?.id,
              ),
            ),
          ],
        );
    }
  }

  Widget _workspaceTabs() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: SegmentedButton<AiWorkspace>(
        segments: const [
          ButtonSegment(value: AiWorkspace.chat, label: Text('Chat'), icon: Icon(Icons.chat_bubble_outline)),
          ButtonSegment(value: AiWorkspace.studio, label: Text('Studio'), icon: Icon(Icons.dashboard_customize)),
        ],
        selected: {_workspace},
        onSelectionChanged: (value) {
          setState(() => _workspace = value.first);
        },
      ),
    );
  }

  Widget _chooserCard({
    required IconData icon,
    required String title,
    required String body,
    required VoidCallback onTap,
  }) {
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Icon(icon, size: 32),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(body, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }

  Widget _signInCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Use your ChatGPT account', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            const CollapsibleHint(
              label: 'Any account, that account’s models',
              body:
                  'Opens OpenAI’s device page (auth.openai.com/codex/device) and shows a '
                  'one-time code. Sign in with whatever ChatGPT account you have — Plus, '
                  'Pro, Team, or another plan this login supports. After you approve, '
                  'the app loads the models that account can use and lets you pick one. '
                  'Switch account any time. Tokens stay on this phone. Recordings stay '
                  'on this phone. When you send a message, a session brief goes to '
                  'OpenAI — Compact, Standard, or Full, your choice. Standard is not '
                  '40,000 raw PPG rows; those envelopes keep the shape without flooding '
                  'the model. Nothing is uploaded to GitHub. Not a medical device.',
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: _busy ? null : _startLogin,
              icon: const Icon(Icons.login),
              label: Text(_busy ? 'Starting…' : 'Sign in with ChatGPT'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _codeCard() {
    final code = _pending!.userCode;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Enter this code', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SelectableText(
              code,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    letterSpacing: 2,
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            Text(kOpenAiVerificationUrl, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton(
                  onPressed: _openVerification,
                  child: const Text('Open OpenAI'),
                ),
                OutlinedButton(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: code));
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Code copied')),
                    );
                  },
                  child: const Text('Copy code'),
                ),
                TextButton(onPressed: _cancelLogin, child: const Text('Cancel')),
              ],
            ),
            const SizedBox(height: 8),
            const Text('Waiting for approval in the browser…'),
          ],
        ),
      ),
    );
  }

  Widget _accountCard() {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.verified_user),
        title: Text(_session!.displayName),
        subtitle: Text(
          _modelsFromAccount
              ? 'Models from this ChatGPT account'
              : 'Signed in. Could not load this account’s model list — pick a common model it can use.',
        ),
      ),
    );
  }

  Widget _modelAndDepth() {
    final selected = _models.any((m) => m.id == _modelId) ? _modelId : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              flex: 3,
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Model',
                  isDense: true,
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: selected,
                    isExpanded: true,
                    hint: const Text('Loading models…'),
                    items: [
                      for (final model in _models)
                        DropdownMenuItem(
                          value: model.id,
                          child: Text(model.display, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: _models.isEmpty ? null : _selectModel,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Context',
                  isDense: true,
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<ContextDepth>(
                    value: _depth,
                    isExpanded: true,
                    items: [
                      for (final depth in ContextDepth.values)
                        DropdownMenuItem(value: depth, child: Text(depth.label)),
                    ],
                    onChanged: _selectDepth,
                  ),
                ),
              ),
            ),
          ],
        ),
        CollapsibleHint(
          label: 'Why not dump every PPG sample?',
          body:
              '${_depth.hint} 40k PPG rows is about 1.7 MB, not 40 KB. Sending every '
              'raw value as text is hundreds of thousands of tokens: slower, easier '
              'to overflow, and worse for point-level guesses. Standard keeps full-ish '
              'HR (1 Hz) and PPI, and PPG/motion as min/max envelopes so the model '
              'still sees the shape.',
        ),
      ],
    );
  }

  Widget _bubble(ChatTurn turn) {
    final mine = turn.role == 'user';
    final spec = mine ? null : StudioDashboardSpec.tryParse(turn.text);
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        constraints: const BoxConstraints(maxWidth: 520),
        decoration: BoxDecoration(
          color: mine ? const Color(0xFF6C5CE7).withValues(alpha: 0.35) : const Color(0xFF1A1D2E),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText(turn.text),
            if (spec != null) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => _saveSpec(spec),
                icon: const Icon(Icons.dashboard_customize, size: 16),
                label: const Text('Save to Studio'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _composer() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _input,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration: const InputDecoration(
                  hintText: 'Ask about recovery, HRV, or this session…',
                  isDense: true,
                ),
              ),
            ),
            IconButton(
              onPressed: _busy ? null : _send,
              icon: const Icon(Icons.send),
            ),
          ],
        ),
      ),
    );
  }
}

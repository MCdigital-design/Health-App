import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../ai/openai_chat_service.dart';
import '../ai/openai_device_auth.dart';
import '../models/recording_session.dart';
import '../widgets/collapsible_hint.dart';

class AiScreen extends StatefulWidget {
  final RecordingSession? focusSession;

  const AiScreen({super.key, this.focusSession});

  @override
  State<AiScreen> createState() => _AiScreenState();
}

class _AiScreenState extends State<AiScreen> {
  final _auth = OpenAiDeviceAuth();
  final _chat = OpenAiChatService();
  final _input = TextEditingController();
  final _turns = <ChatTurn>[];

  OpenAiSession? _session;
  DeviceLoginPending? _pending;
  bool _loading = true;
  bool _busy = false;
  bool _cancelled = false;
  String? _error;

  @override
  void initState() {
    super.initState();
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
    if (!mounted) return;
    setState(() {
      _session = session;
      _loading = false;
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

  Future<void> _signOut() async {
    await _auth.signOut();
    if (!mounted) return;
    setState(() {
      _session = null;
      _turns.clear();
    });
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _busy) return;
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

  Future<void> _openVerification() async {
    final url = Uri.parse(kOpenAiVerificationUrl);
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.focusSession == null ? 'AI' : 'Ask AI'),
        actions: [
          if (_session != null)
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'Sign out of ChatGPT',
              onPressed: _signOut,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
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
                      if (_session == null && _pending == null) _signInCard(),
                      if (_pending != null) _codeCard(),
                      if (_session != null) _signedInBanner(),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(_error!, style: const TextStyle(color: Colors.orangeAccent)),
                        ),
                      for (final turn in _turns) _bubble(turn),
                      if (_busy && _session != null && _pending == null)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Text('Thinking…'),
                        ),
                    ],
                  ),
                ),
                if (_session != null) _composer(),
              ],
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
            Text('ChatGPT on this phone', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            const CollapsibleHint(
              label: 'How sign-in works',
              body:
                  'Opens OpenAI’s device page (auth.openai.com/codex/device) and shows a '
                  'one-time code. Sign in with your own ChatGPT account (Plus / Pro / Team). '
                  'This is the same public device-code login Codex uses. Tokens stay on '
                  'this phone. When you send a message, a compact session summary goes to '
                  'OpenAI — not the raw 40,000-row PPG table, and nothing is uploaded to '
                  'GitHub. Not a medical device.',
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

  Widget _signedInBanner() {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.verified_user),
        title: Text(_session!.displayName),
        subtitle: const Text('Your ChatGPT subscription. Compact summaries only.'),
      ),
    );
  }

  Widget _bubble(ChatTurn turn) {
    final mine = turn.role == 'user';
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
        child: SelectableText(turn.text),
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

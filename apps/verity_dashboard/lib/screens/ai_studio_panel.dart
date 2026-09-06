import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../ai/openai_chat_service.dart';
import '../ai/openai_models.dart';
import '../ai/session_brief.dart';
import '../ai/studio_dashboard_store.dart';
import '../ai/studio_spec.dart';
import '../widgets/studio_dashboard_view.dart';

class AiStudioPanel extends StatefulWidget {
  final OpenAiChatService chat;
  final String model;
  final List<LlmModel> accountModels;
  final ContextDepth depth;
  final String? accountHint;
  final String? focusSessionId;

  const AiStudioPanel({
    super.key,
    required this.chat,
    required this.model,
    required this.accountModels,
    required this.depth,
    this.accountHint,
    this.focusSessionId,
  });

  @override
  State<AiStudioPanel> createState() => _AiStudioPanelState();
}

class _AiStudioPanelState extends State<AiStudioPanel> {
  final _store = StudioDashboardStore();
  final _input = TextEditingController();
  List<SavedStudioDashboard> _saved = const [];
  SavedStudioDashboard? _open;
  bool _loading = true;
  bool _busy = false;
  String? _error;
  String? _lastReply;
  StreamSubscription<void>? _sub;

  @override
  void initState() {
    super.initState();
    _reload();
    _sub = StudioDashboardStore.changes.listen((_) => _reload());
  }

  @override
  void dispose() {
    _sub?.cancel();
    _input.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    final rows = await _store.list();
    if (!mounted) return;
    setState(() {
      _saved = rows;
      _loading = false;
      if (_open != null) {
        SavedStudioDashboard? still;
        for (final row in rows) {
          if (row.id == _open!.id) still = row;
        }
        _open = still;
      }
    });
  }

  Future<void> _build() async {
    final text = _input.text.trim();
    if (text.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _lastReply = null;
    });
    try {
      final reply = await widget.chat.ask(
        question: text,
        history: const [],
        focusSessionId: widget.focusSessionId,
        model: widget.model,
        depth: widget.depth,
        accountModels: widget.accountModels,
        studioMode: true,
      );
      final spec = StudioDashboardSpec.tryParse(reply);
      if (spec != null) {
        await _store.insert(
          title: spec.title,
          specJson: jsonEncode(spec.toJson()),
          accountHint: widget.accountHint,
        );
        _input.clear();
      }
      if (!mounted) return;
      setState(() {
        _lastReply = spec == null ? reply : null;
        _busy = false;
        if (spec == null) {
          _error = 'The model replied, but no dashboard JSON was found. Try asking it to build a view.';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _busy = false;
      });
    }
  }

  Future<void> _delete(SavedStudioDashboard row) async {
    await _store.delete(row.id);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_open != null) {
      final spec = _open!.spec;
      return Column(
        children: [
          ListTile(
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => setState(() => _open = null),
            ),
            title: Text(_open!.title),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                final row = _open!;
                setState(() => _open = null);
                await _delete(row);
              },
            ),
          ),
          Expanded(
            child: spec == null
                ? const Center(child: Text('This saved view could not be read.'))
                : StudioDashboardView(spec: spec),
          ),
        ],
      );
    }

    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: [
              Text(
                'Studio builds custom views from recordings on this phone. '
                'They stay here — not on OpenAI’s servers.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(_error!, style: const TextStyle(color: Colors.orangeAccent)),
                ),
              if (_busy) const Padding(
                padding: EdgeInsets.only(bottom: 12),
                child: Text('Building…'),
              ),
              if (_lastReply != null) ...[
                SelectableText(_lastReply!),
                const SizedBox(height: 12),
              ],
              if (_saved.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'No custom dashboards yet. Describe a view below — '
                      'heart rate plus RMSSD for the latest take, for example.',
                    ),
                  ),
                )
              else
                for (final row in _saved)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.dashboard_customize),
                      title: Text(row.title),
                      subtitle: Text(
                        DateTime.fromMillisecondsSinceEpoch(row.createdMs).toString(),
                      ),
                      onTap: () => setState(() => _open = row),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _delete(row),
                      ),
                    ),
                  ),
            ],
          ),
        ),
        SafeArea(
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
                    onSubmitted: (_) => _build(),
                    decoration: const InputDecoration(
                      hintText: 'Describe a dashboard to build…',
                      isDense: true,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _busy ? null : _build,
                  icon: const Icon(Icons.auto_awesome),
                  tooltip: 'Build with AI',
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

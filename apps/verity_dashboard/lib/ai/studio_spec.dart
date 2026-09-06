import 'dart:convert';

class StudioWidget {
  final String type;
  final String title;
  final String? value;
  final String? unit;
  final String? signal;
  final String? sessionId;
  final String? text;

  const StudioWidget({
    required this.type,
    required this.title,
    this.value,
    this.unit,
    this.signal,
    this.sessionId,
    this.text,
  });

  Map<String, dynamic> toJson() => {
        'type': type,
        'title': title,
        if (value != null) 'value': value,
        if (unit != null) 'unit': unit,
        if (signal != null) 'signal': signal,
        if (sessionId != null) 'sessionId': sessionId,
        if (text != null) 'text': text,
      };

  static StudioWidget? fromJson(Map<String, dynamic> json) {
    final type = json['type']?.toString();
    if (type == null || type.isEmpty) return null;
    return StudioWidget(
      type: type,
      title: (json['title'] ?? json['label'] ?? type).toString(),
      value: json['value']?.toString(),
      unit: json['unit']?.toString(),
      signal: json['signal']?.toString(),
      sessionId: (json['sessionId'] ?? json['session_id'])?.toString(),
      text: json['text']?.toString(),
    );
  }
}

class StudioDashboardSpec {
  final String title;
  final List<StudioWidget> widgets;

  const StudioDashboardSpec({required this.title, required this.widgets});

  Map<String, dynamic> toJson() => {
        'title': title,
        'widgets': [for (final w in widgets) w.toJson()],
      };

  static StudioDashboardSpec? tryParse(String raw) {
    final jsonBlock = _extractJson(raw);
    if (jsonBlock == null) return null;
    try {
      final decoded = jsonDecode(jsonBlock);
      if (decoded is! Map) return null;
      final widgetsRaw = decoded['widgets'];
      if (widgetsRaw is! List) return null;
      final widgets = <StudioWidget>[];
      for (final item in widgetsRaw) {
        if (item is Map<String, dynamic>) {
          final w = StudioWidget.fromJson(item);
          if (w != null) widgets.add(w);
        } else if (item is Map) {
          final w = StudioWidget.fromJson(Map<String, dynamic>.from(item));
          if (w != null) widgets.add(w);
        }
      }
      if (widgets.isEmpty) return null;
      final title = (decoded['title'] ?? 'Custom dashboard').toString();
      return StudioDashboardSpec(title: title, widgets: widgets);
    } catch (_) {
      return null;
    }
  }
}

String? _extractJson(String raw) {
  final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)```', caseSensitive: false);
  final match = fence.firstMatch(raw);
  if (match != null) return match.group(1)!.trim();
  final start = raw.indexOf('{');
  final end = raw.lastIndexOf('}');
  if (start >= 0 && end > start) return raw.substring(start, end + 1);
  return null;
}

const kStudioBuildPrompt = '''
If the user asks you to make a dashboard, chart, or custom view, end your reply
with a JSON object (optionally in a ```json fence) of this exact shape:
{
  "title": "short title",
  "widgets": [
    {"type":"metric","title":"RMSSD","value":"42","unit":"ms"},
    {"type":"chart","title":"Heart rate","signal":"hr","sessionId":"<id from the brief>"},
    {"type":"note","title":"Read","text":"one or two sentences"}
  ]
}
Use only session ids that appear in the brief. signal must be one of hr, ppg, ppi, acc, gyro, mag.
Do not invent sample counts. This is not a medical device.
''';

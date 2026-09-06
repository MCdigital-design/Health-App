import 'package:flutter_test/flutter_test.dart';
import 'package:verity_dashboard/ai/studio_signal.dart';
import 'package:verity_dashboard/ai/studio_spec.dart';
import 'package:verity_dashboard/storage/local_db.dart';

void main() {
  test('StudioDashboardSpec reads fenced JSON and ignores chatter', () {
    const raw = '''
Here is a recovery view.

```json
{
  "title": "Recovery",
  "widgets": [
    {"type":"metric","title":"RMSSD","value":"42","unit":"ms"},
    {"type":"chart","title":"Heart rate","signal":"hr","session_id":"abc"},
    {"type":"note","title":"Read","text":"Not medical."}
  ]
}
```
''';
    final spec = StudioDashboardSpec.tryParse(raw);
    expect(spec, isNotNull);
    expect(spec!.title, 'Recovery');
    expect(spec.widgets, hasLength(3));
    expect(spec.widgets[1].sessionId, 'abc');
    expect(spec.widgets[1].signal, 'hr');
  });

  test('StudioDashboardSpec.tryParse returns null without widgets', () {
    expect(StudioDashboardSpec.tryParse('{"title":"x","widgets":[]}'), isNull);
    expect(StudioDashboardSpec.tryParse('no json here'), isNull);
  });

  test('chartSignalFromName maps aliases', () {
    expect(chartSignalFromName('heart_rate'), ChartSignal.hr);
    expect(chartSignalFromName('RR'), ChartSignal.ppi);
    expect(chartSignalFromName('accelerometer'), ChartSignal.acc);
    expect(chartSignalFromName('nope'), isNull);
  });
}

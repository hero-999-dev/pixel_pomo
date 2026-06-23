import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixel_pomo/app_blocker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const ch = MethodChannel('pixel_pomo/blocker');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ch, (c) async {
      calls.add(c);
      if (c.method == 'hasAccessibility') return true;
      if (c.method == 'hasOverlay') return false;
      if (c.method == 'installedApps') {
        return [
          {'package': 'com.b', 'label': 'Beta'},
          {'package': 'com.a', 'label': 'alpha'},
        ];
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ch, null);
  });

  test('installedApps maps + sorts the native payload (case-insensitive)', () async {
    final apps = await installedApps();
    expect(apps.map((a) => a.package).toList(), ['com.a', 'com.b']); // alpha < Beta
    expect(apps.first.label, 'alpha');
  });

  test('permission getters return the channel values', () async {
    expect(await hasAccessibility(), true);
    expect(await hasOverlay(), false);
  });

  test('openers invoke the channel without throwing', () async {
    await openAccessibilitySettings();
    await openOverlaySettings();
    expect(calls.map((c) => c.method), containsAll(['openAccessibilitySettings', 'openOverlaySettings']));
  });
}

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pixel_pomo/store.dart';

/// The ongoing focus-timer notification (#v23 fb): it appears when the app is
/// backgrounded mid-session and is cancelled when the session stops. Native draws
/// it; here we assert the store drives the `pixel_pomo/timer` channel correctly.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const ch = MethodChannel('pixel_pomo/timer');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ch, (c) async {
      calls.add(c);
      return null;
    });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ch, null);
  });

  test('background shows the countdown only while running; stopping cancels it', () async {
    SharedPreferences.setMockInitialValues({});
    final s = AppStore();
    await s.load();

    // idle → backgrounding posts nothing
    s.onBackgrounded();
    await Future<void>.delayed(Duration.zero);
    expect(calls.any((c) => c.method == 'show'), false);

    // running + backgrounded → show, with a deadline in the future
    s.start();
    s.onBackgrounded();
    await Future<void>.delayed(Duration.zero);
    final show = calls.firstWhere((c) => c.method == 'show');
    final deadline = (show.arguments as Map)['deadline'] as int;
    expect(deadline, greaterThan(DateTime.now().millisecondsSinceEpoch));

    // cancel the session in-app → notification cleared
    calls.clear();
    s.reset();
    await Future<void>.delayed(Duration.zero);
    expect(calls.any((c) => c.method == 'cancel'), true);
  });
}

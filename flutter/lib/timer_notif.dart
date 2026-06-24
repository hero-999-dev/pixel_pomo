import 'package:flutter/services.dart';

/// Flutter side of the ongoing focus-timer notification (#v23 fb). The native
/// `MainActivity` posts a lock-screen-visible, ongoing notification whose MM:SS
/// countdown the system ticks on its own (a chronometer), and which auto-clears at
/// the deadline (`setTimeoutAfter`) — so it keeps counting even if Android suspends
/// our isolate in the background, and can't be swiped away until it's done. Every
/// call is wrapped so iOS / a missing plugin is a safe no-op (host-unit-testable).
const _ch = MethodChannel('pixel_pomo/timer');

Future<void> showTimerNotification(int deadlineMs, String title) async {
  try {
    await _ch.invokeMethod('show', {'deadline': deadlineMs, 'title': title});
  } catch (_) {}
}

Future<void> cancelTimerNotification() async {
  try {
    await _ch.invokeMethod('cancel');
  } catch (_) {}
}

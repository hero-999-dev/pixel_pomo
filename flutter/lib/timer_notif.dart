import 'package:flutter/services.dart';

/// Flutter side of the ongoing focus-timer notification (#v23 fb). The native
/// `TimerService` (a foreground service) owns it; we hand it the WHOLE plan up
/// front — this phase's deadline, and the auto-following phase if there is one —
/// because once we're backgrounded our Dart isolate freezes, so the service has
/// to drive the focus→break / focus→done transition itself (the MM:SS is a
/// system-ticked chronometer, so it keeps counting regardless). [nextMs] > 0 means
/// an auto-break follows for that long titled [nextTitle]; when nothing's left the
/// notification settles on [doneTitle] (a static "FOCUS DONE!" / "BREAK OVER!"),
/// no longer counting. Calls are wrapped so iOS / a missing plugin is a safe no-op.
const _ch = MethodChannel('pixel_pomo/timer');

Future<void> showTimerNotification(int deadlineMs, String title,
    {int nextMs = 0, String nextTitle = '', String doneTitle = ''}) async {
  try {
    await _ch.invokeMethod('show', {
      'deadline': deadlineMs,
      'title': title,
      'nextMs': nextMs,
      'nextTitle': nextTitle,
      'doneTitle': doneTitle,
    });
  } catch (_) {}
}

Future<void> cancelTimerNotification() async {
  try {
    await _ch.invokeMethod('cancel');
  } catch (_) {}
}

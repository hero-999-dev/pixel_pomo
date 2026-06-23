import 'package:flutter/services.dart';

/// Flutter side of the native app blocker (#v23). The *state* (active flag,
/// blocked packages, block-until, overlay copy) crosses to the AccessibilityService
/// via SharedPreferences (see `AppStore._publishBlocker`); this channel is only for
/// the installed-app list and the permission checks/openers. Every call is wrapped
/// so iOS / a missing plugin returns a safe default (host-unit-testable).
const _ch = MethodChannel('pixel_pomo/blocker');

class AppInfo {
  final String package;
  final String label;
  final Uint8List? icon;
  const AppInfo(this.package, this.label, this.icon);
}

Future<List<AppInfo>> installedApps() async {
  try {
    final raw = await _ch.invokeMethod<List<dynamic>>('installedApps') ?? [];
    final list = raw.map((e) {
      final m = (e as Map);
      final pkg = m['package'] as String;
      return AppInfo(
        pkg,
        (m['label'] as String?) ?? pkg,
        m['icon'] is Uint8List ? m['icon'] as Uint8List : null,
      );
    }).toList();
    list.sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    return list;
  } catch (_) {
    return [];
  }
}

Future<bool> hasAccessibility() async {
  try {
    return await _ch.invokeMethod<bool>('hasAccessibility') ?? false;
  } catch (_) {
    return false;
  }
}

Future<bool> hasOverlay() async {
  try {
    return await _ch.invokeMethod<bool>('hasOverlay') ?? false;
  } catch (_) {
    return false;
  }
}

Future<void> openAccessibilitySettings() async {
  try {
    await _ch.invokeMethod('openAccessibilitySettings');
  } catch (_) {}
}

Future<void> openOverlaySettings() async {
  try {
    await _ch.invokeMethod('openOverlaySettings');
  } catch (_) {}
}

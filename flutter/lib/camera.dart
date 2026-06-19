import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:wallpaper_manager_flutter/wallpaper_manager_flutter.dart';

/// Camera helpers for the garden section: screenshot the live scene, persist it
/// as a static backdrop, or hand it to the system share sheet. Kept out of
/// main.dart so the UI stays lean.
///
/// Note: capture uses `RenderRepaintBoundary.toImage`, which hangs in headless
/// `flutter test`, so these are verified on-device, not in unit tests.

/// Screenshot the widget subtree behind [key]'s RepaintBoundary as PNG bytes.
Future<Uint8List?> captureBoundary(GlobalKey key) async {
  final ctx = key.currentContext;
  if (ctx == null) return null;
  final boundary = ctx.findRenderObject() as RenderRepaintBoundary?;
  if (boundary == null) return null;
  final image = await boundary.toImage(pixelRatio: 2.0);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data?.buffer.asUint8List();
}

/// Persist the captured PNG as the garden's static backdrop; returns its path.
Future<String> saveBackdropPng(Uint8List bytes) async {
  final dir = await getApplicationDocumentsDirectory();
  final file = File('${dir.path}/garden_backdrop.png');
  await file.writeAsBytes(bytes, flush: true);
  return file.path;
}

/// Open the system share sheet with the captured PNG (the user can save it to
/// Photos / set it as their phone wallpaper from there).
Future<void> sharePng(Uint8List bytes, String filename) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$filename');
  await file.writeAsBytes(bytes, flush: true);
  await Share.shareXFiles([XFile(file.path)]);
}

/// Set the captured PNG as the phone's HOME-screen wallpaper (Android only, #6).
/// Returns false on non-Android (the caller hides the button there). The true
/// *animated* live wallpaper is a future version; this sets the framed still.
Future<bool> setPhoneWallpaper(Uint8List bytes) async {
  if (!Platform.isAndroid) return false;
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/pixel_pomo_wallpaper.png');
  await file.writeAsBytes(bytes, flush: true);
  return WallpaperManagerFlutter().setWallpaper(file, WallpaperManagerFlutter.homeScreen);
}

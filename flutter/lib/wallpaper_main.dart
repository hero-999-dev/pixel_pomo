import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'engine/garden_engine.dart';
import 'engine/garden_view.dart';
import 'logic.dart';

// Garden palette (mirrors the private consts in main.dart).
const int _wGround = 0xFF4E9E3E;
const int _wSoil = 0xFF6B4A2B;

/// Entry point run by the Android live-wallpaper service in its OWN FlutterEngine
/// (see android_overlay/GardenWallpaperService.kt). It renders the **real** garden
/// — the exact same `GardenView` engine as the app (3D fences, real critters, all
/// sprites) — at the framing the user saved, instead of a simplified native re-draw
/// (#v20). `@pragma('vm:entry-point')` keeps it from being tree-shaken away.
@pragma('vm:entry-point')
void wallpaperMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(debugShowCheckedModeBanner: false, home: _WallpaperApp()));
}

class _WallpaperApp extends StatefulWidget {
  const _WallpaperApp();
  @override
  State<_WallpaperApp> createState() => _WallpaperAppState();
}

class _WallpaperAppState extends State<_WallpaperApp> {
  Garden? _garden;
  SpriteBank? _sprites;
  WallpaperCam _wcam = WallpaperCam.none;
  PixelTheme _theme = Themes.dark;
  bool _error = false;
  final GardenCamera _camera = GardenCamera();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final garden = Garden.decode(prefs.getString('garden'))
          .atLeast(Economy.baseGardenCols, Economy.baseGardenRows);
      final sprites = await SpriteBank.load();
      final wcam = WallpaperCam.decode(prefs.getString('wallpaper_cam'));
      final theme = Themes.byId(prefs.getString('theme_id'));
      _camera.yaw = wcam.yaw;
      _camera.zoom = wcam.zoom;
      if (mounted) {
        setState(() {
          _garden = garden;
          _sprites = sprites;
          _wcam = wcam;
          _theme = theme;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Diagnostic colours so a device report pinpoints the failure (#v20):
    //   black  → the Flutter→surface pipeline isn't rendering at all
    //   RED    → pipeline works but loading the garden/sprites failed
    //   INDIGO → pipeline works, still loading
    //   garden → fixed
    final g = _garden, s = _sprites;
    if (_error) return const ColoredBox(color: Color(0xFFD32F2F)); // red
    if (g == null || s == null) return const ColoredBox(color: Color(0xFF3949AB)); // indigo
    return LayoutBuilder(
      builder: (ctx, cons) {
        // reproduce the saved framing: pan was stored as a fraction of the tile size
        // so it lands the same at the wallpaper's surface size.
        final p = Projector.fit(g.cols, g.rows, _camera, Size(cons.maxWidth, cons.maxHeight));
        _camera.panX = _wcam.panXFrac * p.t;
        _camera.panY = _wcam.panYFrac * p.t;
        return GardenView(
          garden: g,
          sprites: s,
          customizing: false,
          onTapTile: (_) {},
          groundColor: _wGround,
          soilColor: _wSoil,
          uiColor: _theme.onSurface,
          panelColor: _theme.panel,
          lang: 'en',
          tr: (k) => k,
          interactive: false, // no gestures/controls, but the ticker still animates critters
          camera: _camera,
        );
      },
    );
  }
}

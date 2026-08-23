import 'dart:convert';
import 'dart:io';

class WindowState {
  const WindowState({
    required this.width,
    required this.height,
    required this.x,
    required this.y,
    this.maximized = false,
  });

  final double width;
  final double height;
  final double x;
  final double y;
  final bool maximized;

  Map<String, dynamic> toJson() => {
    'width': width,
    'height': height,
    'x': x,
    'y': y,
    'maximized': maximized,
  };
}

class WindowStateStore {
  WindowStateStore({String? path}) : _path = path ?? _defaultPath();

  final String _path;

  Future<WindowState?> load() async {
    final file = File(_path);
    if (!await file.exists()) return null;
    try {
      final data = jsonDecode(await file.readAsString()) as Map;
      final width = (data['width'] as num?)?.toDouble();
      final height = (data['height'] as num?)?.toDouble();
      final x = (data['x'] as num?)?.toDouble();
      final y = (data['y'] as num?)?.toDouble();
      if (width == null || height == null || x == null || y == null) {
        return null;
      }
      if (width < 200 || width > 10000 || height < 200 || height > 10000) {
        return null;
      }
      return WindowState(
        width: width,
        height: height,
        x: x,
        y: y,
        maximized: data['maximized'] == true,
      );
    } on FormatException {
      return null;
    } on FileSystemException {
      return null;
    }
  }

  Future<void> save(WindowState state) async {
    final file = File(_path);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode({
        'version': 1,
        ...state.toJson(),
      }),
      flush: true,
    );
  }

  static String _defaultPath() {
    if (Platform.isMacOS) {
      final home = Platform.environment['HOME'] ?? '.';
      return '$home/Library/Application Support/NewChirp/window-state.json';
    }
    if (Platform.isWindows) {
      final appData =
          Platform.environment['APPDATA'] ??
          Platform.environment['USERPROFILE'] ??
          '.';
      return '$appData\\NewChirp\\window-state.json';
    }
    final home = Platform.environment['HOME'] ?? '.';
    final config = Platform.environment['XDG_CONFIG_HOME'] ?? '$home/.config';
    return '$config/newchirp/window-state.json';
  }
}

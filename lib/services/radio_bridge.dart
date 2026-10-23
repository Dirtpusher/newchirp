import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:flutter/services.dart';

import '../models/radio_channel.dart';

const _progressPrefix = '__NEWCHIRP_PROGRESS__ ';

class RadioBridgeException implements Exception {
  RadioBridgeException(this.message);
  final String message;
  @override
  String toString() => message;
}

class RadioInstructions {
  const RadioInstructions({
    required this.info,
    required this.experimental,
    required this.preDownload,
    required this.preUpload,
  });

  final String? info;
  final String? experimental;
  final String? preDownload;
  final String? preUpload;

  Iterable<String> get readMessages => [?experimental, ?info, ?preDownload];
  Iterable<String> get writeMessages => [?experimental, ?info, ?preUpload];
}

class RadioCapabilities {
  const RadioCapabilities({
    required this.duplexes,
    required this.toneModes,
    required this.crossModes,
    required this.modes,
    required this.steps,
    required this.skips,
    required this.powers,
    required this.tones,
    required this.dtcsCodes,
    required this.nameLength,
    required this.validCharacters,
    required this.hasTuningStep,
  });

  final List<String> duplexes;
  final List<String> toneModes;
  final List<String> crossModes;
  final List<String> modes;
  final List<double> steps;
  final List<String> skips;
  final List<String> powers;
  final List<double> tones;
  final List<int> dtcsCodes;
  final int nameLength;
  final String validCharacters;
  final bool hasTuningStep;

  bool get uppercaseNames =>
      validCharacters.isNotEmpty &&
      validCharacters == validCharacters.toUpperCase();

  factory RadioCapabilities.fromJson(Map<String, dynamic> json) {
    List<String> strings(String key) => (json[key] as List? ?? const [])
        .map((item) => item.toString())
        .toList();
    return RadioCapabilities(
      duplexes: strings('duplexes'),
      toneModes: strings('toneModes'),
      crossModes: strings('crossModes'),
      modes: strings('modes'),
      steps: (json['steps'] as List? ?? const [])
          .map((item) => (item as num).toDouble())
          .toList(),
      skips: strings('skips'),
      powers: strings('powers'),
      tones: (json['tones'] as List? ?? const [])
          .map((item) => (item as num).toDouble())
          .toList(),
      dtcsCodes: (json['dtcsCodes'] as List? ?? const [])
          .map((item) => (item as num).toInt())
          .toList(),
      nameLength: (json['nameLength'] as num?)?.toInt() ?? 16,
      validCharacters: '${json['validCharacters'] ?? ''}',
      hasTuningStep: json['hasTuningStep'] as bool? ?? true,
    );
  }
}

class RadioProgress {
  const RadioProgress({required this.label, this.fraction});

  final String label;
  final double? fraction;
}

class RadioSettingNode {
  RadioSettingNode({
    required this.id,
    required this.name,
    required this.shortName,
    required this.kind,
    required this.documentation,
    required this.value,
    required this.options,
    required this.mutable,
    required this.min,
    required this.max,
    required this.step,
    required this.minLength,
    required this.maxLength,
    required this.children,
  });

  final List<int> id;
  final String name;
  final String shortName;
  final String? documentation;
  final String kind;
  final List<String> options;
  final bool mutable;
  final num? min;
  final num? max;
  final num? step;
  final int? minLength;
  final int? maxLength;
  final List<RadioSettingNode> children;
  Object? value;
  bool invalid = false;

  String get label => shortName.isEmpty ? name : shortName;
  bool get isGroup => kind == 'group';

  factory RadioSettingNode.fromJson(Map<String, dynamic> json) {
    return RadioSettingNode(
      id: (json['id'] as List? ?? const [])
          .map((item) => (item as num).toInt())
          .toList(),
      name: '${json['name'] ?? ''}',
      shortName: '${json['shortName'] ?? ''}',
      kind: '${json['kind'] ?? 'string'}',
      documentation: json['documentation'] as String?,
      value: json['value'],
      options: (json['options'] as List? ?? const [])
          .map((item) => '$item')
          .toList(),
      mutable: json['mutable'] as bool? ?? false,
      min: json['min'] as num?,
      max: json['max'] as num?,
      step: json['step'] as num?,
      minLength: (json['minLength'] as num?)?.toInt(),
      maxLength: (json['maxLength'] as num?)?.toInt(),
      children: (json['children'] as List? ?? const [])
          .map(
            (item) => RadioSettingNode.fromJson(
              (item as Map).cast<String, dynamic>(),
            ),
          )
          .toList(),
    );
  }

  Map<String, Object?> toChangeJson() => {'id': id, 'value': value};
}

class RadioSettings {
  const RadioSettings({
    required this.hasSettings,
    required this.items,
    this.imagePath,
  });

  final bool hasSettings;
  final List<RadioSettingNode> items;
  final String? imagePath;

  factory RadioSettings.fromJson(Map<String, dynamic> json) {
    return RadioSettings(
      hasSettings: json['hasSettings'] as bool? ?? false,
      imagePath: json['imagePath'] as String?,
      items: (json['settings'] as List? ?? const [])
          .map(
            (item) => RadioSettingNode.fromJson(
              (item as Map).cast<String, dynamic>(),
            ),
          )
          .toList(),
    );
  }
}

class RadioBridge {
  RadioBridge({this.sourcePath, this.newDriversPath});
  final String? sourcePath;
  final String? newDriversPath;
  Process? _activeProcess;
  bool _cancelRequested = false;

  String get chirpSource => _findChirpSource();

  bool cancelActive() {
    _cancelRequested = true;
    final process = _activeProcess;
    return process == null || process.kill(ProcessSignal.sigterm);
  }

  Future<List<String>> serialPorts() async {
    if (Platform.isWindows) return _windowsSerialPorts();
    final dev = Directory('/dev');
    if (!dev.existsSync()) return [];
    final patterns = Platform.isMacOS
        ? ['cu.usb', 'cu.SLAB', 'cu.wch', 'tty.usb']
        : ['ttyUSB', 'ttyACM'];
    final ports =
        dev
            .listSync()
            .whereType<FileSystemEntity>()
            .map((e) => e.path)
            .where((path) => patterns.any(path.contains))
            .toList()
          ..sort();
    return ports;
  }

  /// Windows: read the live COM ports from the SERIALCOMM registry key, then
  /// fall back to .NET's SerialPort.GetPortNames() so only real ports show up.
  Future<List<String>> _windowsSerialPorts() async {
    try {
      final result = await Process.run('reg', [
        'query',
        r'HKEY_LOCAL_MACHINE\HARDWARE\DEVICEMAP\SERIALCOMM',
      ]);
      if (result.exitCode == 0) {
        final ports = _parseComPorts('${result.stdout}');
        if (ports.isNotEmpty) return ports;
      }
    } on ProcessException {
      // reg.exe unavailable; fall through to the .NET lookup below.
    }
    try {
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-Command',
        '[System.IO.Ports.SerialPort]::GetPortNames()',
      ]);
      if (result.exitCode == 0) return _parseComPorts('${result.stdout}');
    } on ProcessException {
      // Fall through; no ports available.
    }
    return const [];
  }

  List<String> _parseComPorts(String output) {
    final ports = <String>{};
    for (final line in output.split('\n')) {
      final parts = line.trim().split(RegExp(r'\s+'));
      if (parts.isEmpty) continue;
      final last = parts.last;
      if (RegExp(r'^COM\d+$', caseSensitive: false).hasMatch(last)) {
        ports.add(last.toUpperCase());
      }
    }
    final list = ports.toList();
    list.sort((a, b) {
      return int.parse(a.substring(3)).compareTo(int.parse(b.substring(3)));
    });
    return list;
  }

  Future<List<String>> models() async {
    final data = await _run(['list-models']);
    return (data['models'] as List).cast<String>();
  }

  Future<RadioInstructions> instructions(String model) async {
    final data = await _run(['model-info', '--model', model]);
    return RadioInstructions(
      info: data['info'] as String?,
      experimental: data['experimental'] as String?,
      preDownload: data['preDownload'] as String?,
      preUpload: data['preUpload'] as String?,
    );
  }

  Future<
    ({
      List<RadioChannel> channels,
      String model,
      String imagePath,
      RadioCapabilities capabilities,
    })
  >
  readImage(String imagePath) async {
    final data = await _run(['read-image', '--image', imagePath]);
    return (
      channels: (data['channels'] as List)
          .map(
            (entry) =>
                RadioChannel.fromJson((entry as Map).cast<String, dynamic>()),
          )
          .toList(),
      model: '${data['model']}',
      imagePath: '${data['imagePath']}',
      capabilities: RadioCapabilities.fromJson(
        (data['features'] as Map).cast<String, dynamic>(),
      ),
    );
  }

  Future<
    ({
      List<RadioChannel> channels,
      String imagePath,
      RadioCapabilities capabilities,
    })
  >
  download({
    required String model,
    required String port,
    void Function(RadioProgress)? onProgress,
  }) async {
    final data = await _run([
      'download',
      '--model',
      model,
      '--port',
      port,
    ], onProgress: onProgress);
    return (
      channels: (data['channels'] as List)
          .map((e) => RadioChannel.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
      imagePath: data['imagePath'] as String,
      capabilities: RadioCapabilities.fromJson(
        (data['features'] as Map).cast<String, dynamic>(),
      ),
    );
  }

  Future<List<Map<String, dynamic>>> upload({
    required String model,
    required String port,
    required String imagePath,
    required List<RadioChannel> channels,
    required List<int> cleared,
    void Function(RadioProgress)? onProgress,
  }) async {
    final temp = File('${Directory.systemTemp.path}/newchirp-upload.json');
    await temp.writeAsString(
      jsonEncode(channels.map((e) => e.toJson()).toList()),
    );
    final data = await _run([
      'upload',
      '--model',
      model,
      '--port',
      port,
      '--image',
      imagePath,
      '--channels',
      temp.path,
      '--cleared',
      cleared.join(','),
    ], onProgress: onProgress);
    final skipped = (data['skipped'] as List? ?? const [])
        .map((entry) => (entry as Map).cast<String, dynamic>())
        .toList();
    final adjusted = (data['adjusted'] as List? ?? const [])
        .map((entry) => (entry as Map).cast<String, dynamic>())
        .toList();
    return [...skipped, ...adjusted];
  }

  Future<RadioSettings> readSettings({
    required String model,
    String? imagePath,
    String? port,
    void Function(RadioProgress)? onProgress,
  }) async {
    if ((imagePath == null) == (port == null)) {
      throw ArgumentError(
        'Specify exactly one of imagePath or port for readSettings.',
      );
    }
    final data = await _run([
      'read-settings',
      '--model',
      model,
      if (port != null) ...['--port', port] else ...['--image', imagePath!],
    ], onProgress: onProgress);
    return RadioSettings.fromJson(data);
  }

  Future<void> writeSettings({
    required String model,
    required String port,
    required String imagePath,
    required List<Map<String, Object?>> changes,
    void Function(RadioProgress)? onProgress,
  }) async {
    final temp = File(
      '${Directory.systemTemp.path}/newchirp-settings-$pid-'
      '${DateTime.now().microsecondsSinceEpoch}.json',
    );
    try {
      await temp.writeAsString(jsonEncode({'changes': changes}));
      await _run([
        'write-settings',
        '--model',
        model,
        '--port',
        port,
        '--image',
        imagePath,
        '--settings',
        temp.path,
      ], onProgress: onProgress);
    } finally {
      if (await temp.exists()) await temp.delete();
    }
  }

  Future<Map<String, dynamic>> _run(
    List<String> args, {
    void Function(RadioProgress)? onProgress,
  }) async {
    _cancelRequested = false;
    final script = await _materializeBridge();
    final vendor = await _materializePythonDependencies();
    final source = _findChirpSource();
    final newDrivers = _findNewChirpDrivers();
    final python = await _resolvePython();
    late final Process process;
    try {
      process = await Process.start(python, [
        script,
        '--source',
        source,
        '--vendor',
        vendor,
        if (newDrivers != null) ...['--newchirp-driver-dir', newDrivers],
        ...args,
      ]);
    } on ProcessException catch (error) {
      throw RadioBridgeException(
        'NewChirp could not start its CHIRP helper. Python 3 was not found '
        'or could not be launched (${error.message}).',
      );
    }
    _activeProcess = process;
    if (_cancelRequested) process.kill(ProcessSignal.sigterm);
    final stdoutFuture = process.stdout.transform(utf8.decoder).join();
    final stderrLines = <String>[];
    final stderrFuture = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .forEach((line) {
          if (!line.startsWith(_progressPrefix)) {
            stderrLines.add(line);
            return;
          }
          try {
            final data = jsonDecode(line.substring(_progressPrefix.length));
            if (data is! Map) return;
            final rawFraction = data['fraction'];
            final fraction = rawFraction is num
                ? rawFraction.toDouble().clamp(0.0, 1.0).toDouble()
                : null;
            onProgress?.call(
              RadioProgress(
                label: '${data['label'] ?? 'Working...'}',
                fraction: fraction,
              ),
            );
          } on FormatException {
            stderrLines.add(line);
          }
        });
    late final int exitCode;
    late final String stdout;
    late final String stderr;
    try {
      exitCode = await process.exitCode;
      stdout = (await stdoutFuture).trim();
      await stderrFuture;
      stderr = stderrLines.join('\n').trim();
    } finally {
      if (identical(_activeProcess, process)) _activeProcess = null;
    }
    if (exitCode != 0) {
      final details = stderr.isNotEmpty ? stderr : stdout;
      if ((exitCode & 0xFFFFFFFF) == 0xC0000005) {
        throw RadioBridgeException(
          'NewChirp\u2019s radio helper crashed while communicating with the '
          'radio (Windows access violation, exit code 0xC0000005).\n\n'
          'Unplug and reconnect the programming cable, put the radio back in '
          'CLONE mode, and try again. If it keeps happening, restart NewChirp '
          'and the computer before retrying.',
        );
      }
      throw RadioBridgeException(
        details.isEmpty
            ? 'Radio bridge failed with exit code $exitCode.'
            : details,
      );
    }
    final output = stdout;
    try {
      return (jsonDecode(output) as Map).cast<String, dynamic>();
    } on FormatException {
      throw RadioBridgeException(
        output.isEmpty
            ? 'The radio bridge completed without returning data.'
            : 'The radio bridge returned an invalid response: $output',
      );
    }
  }

  /// The bundled CHIRP tree uses Python 3.10+ syntax, so prefer an interpreter
  /// that is new enough even when an older system Python is first on PATH.
  Future<String> _resolvePython() async {
    final configured = Platform.environment['NEWCHIRP_PYTHON'];
    final resources = _bundledResourcesDirectory();
    final macRuntime = switch (Abi.current()) {
      Abi.macosArm64 => 'python-arm64',
      Abi.macosX64 => 'python-x64',
      _ => null,
    };
    final candidates = <String>[
      if (configured != null && configured.isNotEmpty) configured,
      if (resources != null && Platform.isWindows)
        '${resources.path}/python/python.exe',
      if (resources != null && Platform.isMacOS && macRuntime != null)
        '${resources.path}/$macRuntime/bin/python3',
      if (resources != null && !Platform.isWindows && !Platform.isMacOS)
        '${resources.path}/python/bin/python3',
      if (resources != null && Platform.isMacOS)
        '${resources.path}/python/bin/python3',
      if (Platform.isMacOS) '/opt/homebrew/bin/python3',
      if (Platform.isMacOS) '/usr/local/bin/python3',
      if (Platform.isWindows) 'python',
      'python3',
    ];
    for (final candidate in candidates) {
      try {
        final result = await Process.run(candidate, [
          '-c',
          'import sys; print("%d.%d" % sys.version_info[:2])',
        ]);
        if (result.exitCode != 0) continue;
        final parts = '${result.stdout}'.trim().split('.');
        final major = int.tryParse(parts.first);
        final minor = int.tryParse(parts.length > 1 ? parts[1] : '0');
        if (major != null &&
            minor != null &&
            (major > 3 || (major == 3 && minor >= 10))) {
          return candidate;
        }
      } on ProcessException {
        // Candidate is not available; try the next interpreter.
      }
    }
    return 'python3';
  }

  Directory? _bundledResourcesDirectory() {
    final executable = File(Platform.resolvedExecutable);
    if (Platform.isMacOS) {
      final macosDirectory = executable.parent;
      final contentsDirectory = macosDirectory.parent;
      if (!contentsDirectory.path.endsWith('/Contents')) return null;
      return Directory('${contentsDirectory.path}/Resources');
    }
    return executable.parent;
  }

  Future<String> _materializeBridge() async {
    final file = File('${Directory.systemTemp.path}/newchirp-chirp-bridge.py');
    await file.writeAsString(
      await rootBundle.loadString('scripts/chirp_bridge.py'),
    );
    return file.path;
  }

  Future<String> _materializePythonDependencies() async {
    final file = File(
      '${Directory.systemTemp.path}/pyserial-3.5-py2.py3-none-any.whl',
    );
    final data = await rootBundle.load(
      'assets/python/pyserial-3.5-py2.py3-none-any.whl',
    );
    await file.writeAsBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      flush: true,
    );
    return file.path;
  }

  String _findChirpSource() {
    final configured = sourcePath ?? Platform.environment['CHIRP_SOURCE'];
    if (configured != null && Directory(configured).existsSync()) {
      return Directory(configured).absolute.path;
    }

    final resources = _bundledResourcesDirectory();
    if (resources != null &&
        Directory('${resources.path}/chirp').existsSync()) {
      return resources.absolute.path;
    }

    final candidates = <Directory>[Directory('../chirp-20260626')];
    var cursor = File(Platform.resolvedExecutable).parent;
    for (var i = 0; i < 10; i++) {
      candidates.add(Directory('${cursor.path}/chirp-20260626'));
      candidates.add(Directory('${cursor.path}/../chirp-20260626'));
      cursor = cursor.parent;
    }
    for (final candidate in candidates) {
      if (File('${candidate.path}/chirp/chirp_common.py').existsSync()) {
        return candidate.absolute.path;
      }
    }
    throw RadioBridgeException(
      'The CHIRP driver folder was not found. Keep chirp-20260626 beside '
      'NewChirp, or set the CHIRP_SOURCE environment variable.',
    );
  }

  String? _findNewChirpDrivers() {
    final configured =
        newDriversPath ?? Platform.environment['NEWCHIRP_DRIVERS'];
    if (configured == null || configured.isEmpty) return null;
    final directory = Directory(configured);
    if (!directory.existsSync()) return null;
    return directory.absolute.path;
  }
}

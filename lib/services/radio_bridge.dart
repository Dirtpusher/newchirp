import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import '../models/radio_channel.dart';

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
  });

  final String? info;
  final String? experimental;
  final String? preDownload;

  Iterable<String> get readMessages => [?experimental, ?info, ?preDownload];
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
  final bool hasTuningStep;

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
      hasTuningStep: json['hasTuningStep'] as bool? ?? true,
    );
  }
}

class RadioBridge {
  RadioBridge({this.sourcePath});
  final String? sourcePath;
  Process? _activeProcess;
  bool _cancelRequested = false;

  String get chirpSource => _findChirpSource();

  bool cancelActive() {
    _cancelRequested = true;
    final process = _activeProcess;
    return process == null || process.kill(ProcessSignal.sigterm);
  }

  Future<List<String>> serialPorts() async {
    if (Platform.isWindows) return const ['COM1', 'COM2', 'COM3', 'COM4'];
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
    );
  }

  Future<
    ({
      List<RadioChannel> channels,
      String imagePath,
      RadioCapabilities capabilities,
    })
  >
  download({required String model, required String port}) async {
    final data = await _run(['download', '--model', model, '--port', port]);
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
    ]);
    final skipped = (data['skipped'] as List? ?? const [])
        .map((entry) => (entry as Map).cast<String, dynamic>())
        .toList();
    final adjusted = (data['adjusted'] as List? ?? const [])
        .map((entry) => (entry as Map).cast<String, dynamic>())
        .toList();
    return [...skipped, ...adjusted];
  }

  Future<Map<String, dynamic>> _run(List<String> args) async {
    _cancelRequested = false;
    final script = await _materializeBridge();
    final vendor = await _materializePythonDependencies();
    final source = _findChirpSource();
    final python = await _resolvePython();
    late final Process process;
    try {
      process = await Process.start(python, [
        script,
        '--source',
        source,
        '--vendor',
        vendor,
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
    final stderrFuture = process.stderr.transform(utf8.decoder).join();
    late final int exitCode;
    late final String stdout;
    late final String stderr;
    try {
      exitCode = await process.exitCode;
      stdout = (await stdoutFuture).trim();
      stderr = (await stderrFuture).trim();
    } finally {
      if (identical(_activeProcess, process)) _activeProcess = null;
    }
    if (exitCode != 0) {
      final details = stderr.isNotEmpty ? stderr : stdout;
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
    final candidates = <String>[
      if (configured != null && configured.isNotEmpty) configured,
      if (resources != null && Platform.isWindows)
        '${resources.path}\python\python.exe',
      if (resources != null && !Platform.isWindows)
        '${resources.path}/python/bin/python3',
      if (Platform.isMacOS) '/opt/homebrew/bin/python3',
      if (Platform.isMacOS) '/usr/local/bin/python3',
      if (Platform.isWindows) 'python',
      'python3',
    ];
    for (final candidate in candidates) {
      try {
        final result = await Process.run(
          candidate,
          ['-c', 'import sys; print("%d.%d" % sys.version_info[:2])'],
        );
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
    if (resources != null && Directory('${resources.path}/chirp').existsSync()) {
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
}

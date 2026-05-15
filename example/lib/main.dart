import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iwad_runtime/iwad_runtime.dart';
import 'package:path_provider/path_provider.dart';
import 'package:window_manager/window_manager.dart';

import 'browser_fullscreen.dart';

const String _smokeIwadUrl = String.fromEnvironment(
  'IWAD_RUNTIME_SMOKE_IWAD_URL',
);
const String _smokeIwadDocument = String.fromEnvironment(
  'IWAD_RUNTIME_SMOKE_IWAD_DOCUMENT',
);
const String _smokeSaveMode = String.fromEnvironment(
  'IWAD_RUNTIME_SMOKE_SAVE_MODE',
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (_isDesktopPlatform) {
    await windowManager.ensureInitialized();
  }
  runApp(const IwadExampleApp());
}

class IwadExampleApp extends StatelessWidget {
  const IwadExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: const EntryScreen(),
    );
  }
}

class EntryScreen extends StatefulWidget {
  const EntryScreen({super.key});

  @override
  State<EntryScreen> createState() => _EntryScreenState();
}

class _EntryScreenState extends State<EntryScreen> {
  final TextEditingController _pathController = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (_smokeIwadUrl.isNotEmpty) {
      _pathController.text = _smokeIwadUrl;
      WidgetsBinding.instance.addPostFrameCallback((_) => _start(context));
    } else if (_smokeIwadDocument.isNotEmpty) {
      unawaited(_startDocumentSmoke());
    }
  }

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  TextField(
                    controller: _pathController,
                    decoration: const InputDecoration(
                      labelText: 'IWAD path or web URL',
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) => _start(context),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Start runtime'),
                    onPressed: () => _start(context),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _start(BuildContext context) {
    final String path = _pathController.text.trim();
    if (path.isEmpty) {
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => GameScreen(iwadPath: path),
        fullscreenDialog: true,
      ),
    );
  }

  Future<void> _startDocumentSmoke() async {
    _pathController.text = await _documentPath(_smokeIwadDocument);
    if (mounted) {
      _start(context);
    }
  }
}

class GameScreen extends StatefulWidget {
  const GameScreen({required this.iwadPath, super.key});

  final String iwadPath;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late final IwadController _controller;
  bool _allowPop = false;
  bool _hotkeyNoticeShown = false;
  Object? _startError;
  IwadDesktopControlScheme _desktopControlScheme =
      IwadDesktopControlScheme.modern;

  @override
  void initState() {
    super.initState();
    _controller = IwadController();
    unawaited(_startRuntime());
    if (_isMobilePlatform) {
      SystemChrome.setPreferredOrientations(<DeviceOrientation>[
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
    if (_usesDesktopHotkeys) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_showDesktopHotkeyNotice());
      });
    }
  }

  Future<void> _startRuntime() async {
    try {
      final Uri? uri = Uri.tryParse(widget.iwadPath);
      if (!kIsWeb &&
          uri != null &&
          (uri.scheme == 'http' || uri.scheme == 'https')) {
        final ByteData data = await NetworkAssetBundle(
          uri,
        ).load(widget.iwadPath);
        await _controller.startBytes(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          fileName: _fileNameFromUri(uri),
        );
      } else {
        await _controller.start(widget.iwadPath);
      }
      if (_isSmokeMode) {
        if (_smokeSaveMode == 'save') {
          await _controller.startNewGame();
          await _controller.tick();
          await _controller.saveGame(0, description: 'IWAD Runtime Smoke');
          await _writeNativeSmokeMarker('saved');
          debugPrint('iwad_runtime_save_smoke mode=save saved=true');
        } else if (_smokeSaveMode == 'load') {
          await _controller.loadGame(0);
          await _writeNativeSmokeMarker('loaded');
          debugPrint('iwad_runtime_save_smoke mode=load loaded=true');
        } else if (_smokeSaveMode == 'roundtrip') {
          try {
            await _controller.loadGame(0);
            await _writeNativeSmokeMarker('loaded');
            debugPrint('iwad_runtime_save_smoke mode=roundtrip loaded=true');
          } on Object {
            await _controller.startNewGame();
            await _controller.tick();
            await _controller.saveGame(0, description: 'IWAD Runtime Smoke');
            await _writeNativeSmokeMarker('saved');
            debugPrint('iwad_runtime_save_smoke mode=roundtrip saved=true');
          }
        }
        await _controller.tick();
        debugPrint(
          'iwad_runtime_smoke started=${_controller.isStarted} '
          'hasImage=${_controller.image != null} error=${_controller.error}',
        );
      }
      if (mounted) {
        setState(() => _startError = null);
      }
    } on Object catch (error) {
      if (_isSmokeMode) {
        debugPrint('iwad_runtime_smoke error=$error');
      }
      if (mounted) {
        setState(() => _startError = error);
      }
    }
  }

  @override
  void dispose() {
    if (_isMobilePlatform) {
      SystemChrome.setPreferredOrientations(DeviceOrientation.values);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop || _allowPop) {
          return;
        }
        unawaited(_controller.tapKey(IwadInputKey.escape));
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: IwadView(
          controller: _controller,
          desktopControlScheme: _desktopControlScheme,
          fullscreenController: _usesDesktopHotkeys
              ? IwadCallbackFullscreenController(_setPlatformFullscreen)
              : null,
          onDesktopControlSchemeChanged:
              (IwadDesktopControlScheme controlScheme) {
                setState(() => _desktopControlScheme = controlScheme);
              },
          onExitRequested: _leaveAfterRuntimeQuit,
          placeholder: _startError == null
              ? const SizedBox.square(
                  dimension: 32,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(
                  _startError.toString(),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
        ),
      ),
    );
  }

  Future<void> _setPlatformFullscreen(bool enabled) async {
    if (kIsWeb) {
      await setBrowserFullscreen(enabled);
      return;
    }
    if (_isDesktopPlatform) {
      await windowManager.setFullScreen(enabled);
    }
  }

  Future<void> _showDesktopHotkeyNotice() async {
    if (!mounted || _hotkeyNoticeShown) {
      return;
    }
    _hotkeyNoticeShown = true;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Desktop controls'),
          content: const Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Modern controls are enabled by default.'),
              SizedBox(height: 12),
              Text('F11: fullscreen'),
              Text('M or F12: switch Modern / Original controls'),
              Text('Left mouse: fire'),
              Text('Right mouse: use'),
            ],
          ),
          actions: <Widget>[
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  void _leaveAfterRuntimeQuit() {
    if (!mounted || _allowPop) {
      return;
    }
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final NavigatorState navigator = Navigator.of(context);
      if (navigator.canPop()) {
        navigator.pop();
      } else {
        navigator.pushReplacement(
          MaterialPageRoute<void>(builder: (_) => const EntryScreen()),
        );
      }
    });
  }

  bool get _isMobilePlatform {
    if (kIsWeb) {
      return false;
    }
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  bool get _usesDesktopHotkeys => kIsWeb || _isDesktopPlatform;
}

bool get _isSmokeMode =>
    _smokeIwadUrl.isNotEmpty || _smokeIwadDocument.isNotEmpty;

bool get _isDesktopPlatform {
  if (kIsWeb) {
    return false;
  }
  return defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux ||
      defaultTargetPlatform == TargetPlatform.macOS;
}

String _fileNameFromUri(Uri uri) {
  final String lastSegment = uri.pathSegments.isEmpty
      ? ''
      : uri.pathSegments.last;
  return lastSegment.isEmpty ? 'game.wad' : lastSegment;
}

Future<String> _documentPath(String fileName) async {
  if (!kIsWeb) {
    final Directory documentsDirectory =
        await getApplicationDocumentsDirectory();
    return '${documentsDirectory.path}/$fileName';
  }
  return fileName;
}

Future<void> _writeNativeSmokeMarker(String value) async {
  if (kIsWeb) {
    return;
  }
  final Directory documentsDirectory = await getApplicationDocumentsDirectory();
  final File marker = File(
    '${documentsDirectory.path}/iwad_runtime_save_smoke.txt',
  );
  await marker.writeAsString(value, flush: true);
}

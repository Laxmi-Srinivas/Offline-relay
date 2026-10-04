import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() => runApp(const MaterialApp(home: BleDiagnostics()));

/// Disposable controls/log viewer, not chat or a production adapter.
class BleDiagnostics extends StatefulWidget {
  const BleDiagnostics({super.key});

  @override
  State<BleDiagnostics> createState() => _BleDiagnosticsState();
}

class _BleDiagnosticsState extends State<BleDiagnostics> {
  static const _commands = MethodChannel('offlinerelay.poc/commands');
  static const _events = EventChannel('offlinerelay.poc/events');
  final _logs = <String>[];
  StreamSubscription<dynamic>? _subscription;

  @override
  void initState() {
    super.initState();
    _subscription = _events.receiveBroadcastStream().listen(
      (event) => _log('$event'),
      onError: (Object error) => _log('event_error: $error'),
    );
  }

  void _log(String text) {
    if (!mounted) return;
    setState(() {
      _logs.add(text);
      if (_logs.length > 300) _logs.removeAt(0);
    });
  }

  Future<void> _command(String method) async {
    try {
      await _commands.invokeMethod<void>(method);
    } on PlatformException catch (error) {
      _log('${error.code}: ${error.message}');
    } on MissingPluginException {
      _log('unsupported: native BLE implementation unavailable');
    }
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Throwaway BLE diagnostics')),
    body: Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(8),
          child: Text(
            'Foreground BLE diagnostics • one pair at a time\n'
            'iPhone B: PERIPHERAL. iPhone A: CENTRAL.\n'
            'Grant permission, then press the role button again.',
          ),
        ),
        Wrap(
          spacing: 8,
          children: [
            for (final entry in {
              'advertise': defaultTargetPlatform == TargetPlatform.iOS
                  ? 'PERIPHERAL: Advertise'
                  : 'B: Advertise',
              'discover': defaultTargetPlatform == TargetPlatform.iOS
                  ? 'CENTRAL: Discover + connect'
                  : 'A: Discover + connect',
              'hello': 'Send Hello',
              'larger': 'Send 256 bytes',
              'stop': 'Stop',
            }.entries)
              ElevatedButton(
                onPressed: () => _command(entry.key),
                child: Text(entry.value),
              ),
          ],
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _logs.length,
            itemBuilder: (context, index) => SelectableText(_logs[index]),
          ),
        ),
      ],
    ),
  );
}

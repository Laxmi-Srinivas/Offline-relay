import 'package:flutter/material.dart';

void main() => runApp(const OfflineRelayFoundation());

/// Host placeholder only, not the product UI.
class OfflineRelayFoundation extends StatelessWidget {
  const OfflineRelayFoundation({super.key});

  @override
  Widget build(BuildContext context) => const MaterialApp(
    home: Scaffold(
      body: Center(child: Text('OfflineRelay — engineering foundation')),
    ),
  );
}

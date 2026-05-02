import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ConnectivityResult>>(
      stream: Connectivity().onConnectivityChanged,
      builder: (context, snapshot) {
        final connectivityResults = snapshot.data ?? [ConnectivityResult.wifi];
        final isOffline = connectivityResults.contains(ConnectivityResult.none);

        if (!isOffline) {
          return const SizedBox.shrink();
        }

        return Container(
          width: double.infinity,
          color: Colors.redAccent,
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
          child: const Text(
            '⚠ SIN SEÑAL — MODO LOCAL ACTIVO',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontFamily: 'monospace',
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        );
      },
    );
  }
}

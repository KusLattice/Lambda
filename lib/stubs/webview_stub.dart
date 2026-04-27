// Stub de webview_windows para plataformas no-Windows.
// Este archivo se usa en el import condicional de map_screen.dart
// cuando la app compila para Android, iOS o Web.
// Las clases aquí NO hacen nada — son solo para satisfacer al compilador.

import 'package:flutter/widgets.dart';

class WebviewController {
  WebviewController();

  _WebviewValue get value => _WebviewValue();

  Stream<String> get url => const Stream.empty();

  Future<void> initialize() async {}

  Future<void> loadUrl(String url) async {}

  void dispose() {}
}

class _WebviewValue {
  bool get isInitialized => false;
}

class Webview extends StatelessWidget {
  // ignore: avoid_unused_constructor_parameters
  const Webview(WebviewController controller, {super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

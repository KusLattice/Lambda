import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lambda_app/models/message_model.dart';
import 'package:lambda_app/services/admin_service.dart';

/// Proveedor para la búsqueda profunda de mensajes en el panel de administración.
/// Se dispara de forma asíncrona cuando el administrador realiza una búsqueda.
final adminDeepSearchProvider = FutureProvider.family<List<Message>, String>((ref, query) async {
  if (query.trim().length < 3) return []; // Evitar búsquedas muy cortas y costosas
  return ref.read(adminServiceProvider).deepSearchMessages(query);
});

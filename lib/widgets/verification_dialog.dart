import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lambda_app/models/user_model.dart';
import 'package:lambda_app/providers/auth_provider.dart';

class VerificationDialog extends ConsumerStatefulWidget {
  const VerificationDialog({super.key});

  @override
  ConsumerState<VerificationDialog> createState() => _VerificationDialogState();
}

class _VerificationDialogState extends ConsumerState<VerificationDialog> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).valueOrNull;
    if (user == null) return const SizedBox.shrink();

    // Lógica para determinar qué dato pedir
    String labelText = '';
    String hintText = '';
    String? fieldToUpdate;

    if (user.correo == null || user.correo!.isEmpty) {
      labelText = 'Ingresa tu Correo Electrónico';
      hintText = 'ejemplo@correo.com';
      fieldToUpdate = 'correo';
    } else if (user.celular == null || user.celular!.isEmpty) {
      labelText = 'Ingresa tu Número de Teléfono';
      hintText = '+56 9 1234 5678';
      fieldToUpdate = 'celular';
    } else {
      labelText = 'Ingresa tu Apodo / Nombre Público';
      hintText = 'Ej: SebaPro';
      fieldToUpdate = 'apodo';
    }

    return AlertDialog(
      backgroundColor: Colors.grey[900],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text(
        'SOLICITUD DE VERIFICACIÓN',
        style: TextStyle(
          color: Colors.amber,
          fontFamily: 'Courier',
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      ),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Para verificarte como usuario premium, necesitamos completar un dato adicional en tu perfil.',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 20),
            Text(
              labelText,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _controller,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: hintText,
                hintStyle: const TextStyle(color: Colors.white24),
                filled: true,
                fillColor: Colors.black,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Este campo es obligatorio';
                }
                if (fieldToUpdate == 'correo' && !value.contains('@')) {
                  return 'Ingresa un correo válido';
                }
                return null;
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.pop(context),
          child: const Text('CANCELAR', style: TextStyle(color: Colors.white24)),
        ),
        ElevatedButton(
          onPressed: _isSubmitting ? null : () => _submit(user, fieldToUpdate!),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.greenAccent,
            foregroundColor: Colors.black,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: _isSubmitting
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.black,
                  ),
                )
              : const Text('ENVIAR SOLICITUD'),
        ),
      ],
    );
  }

  Future<void> _submit(User user, String field) async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);
    try {
      final value = _controller.text.trim();

      // 1. Actualizar el perfil con el dato nuevo
      if (field == 'correo') {
        await ref.read(authProvider.notifier).updateProfileSettings(correo: value);
      } else if (field == 'celular') {
        await ref.read(authProvider.notifier).updateProfileSettings(celular: value);
      } else if (field == 'apodo') {
        await ref.read(authProvider.notifier).updateProfileSettings(apodo: value);
      }

      // 2. Enviar la solicitud de verificación
      await ref.read(authProvider.notifier).sendVerificationRequest();

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.greenAccent,
            content: Text(
              'Solicitud enviada con éxito. Un administrador revisará tu perfil.',
              style: TextStyle(color: Colors.black),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.redAccent,
            content: Text('Error: $e'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }
}

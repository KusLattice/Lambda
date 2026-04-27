import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lambda_app/models/admin_request_model.dart';
import 'package:lambda_app/providers/auth_provider.dart';
import 'package:lambda_app/services/admin_service.dart';

class ContactFormDialog extends ConsumerStatefulWidget {
  const ContactFormDialog({super.key});

  @override
  ConsumerState<ContactFormDialog> createState() => _ContactFormDialogState();
}

class _ContactFormDialogState extends ConsumerState<ContactFormDialog> {
  final _formKey = GlobalKey<FormState>();
  AdminRequestType _selectedType = AdminRequestType.duda;
  final _subjectController = TextEditingController();
  final _messageController = TextEditingController();
  bool _isSending = false;

  @override
  void dispose() {
    _subjectController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final user = ref.read(authProvider).valueOrNull;
    if (user == null) return;

    setState(() => _isSending = true);

    try {
      await ref
          .read(adminServiceProvider)
          .submitRequest(
            senderId: user.id,
            senderName: user.nombre,
            type: _selectedType,
            subject: _selectedType == AdminRequestType.ascenso
                ? 'SOLICITUD DE ASCENSO DE RANGO'
                : _subjectController.text.trim(),
            body: _messageController.text.trim(),
          );

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Solicitud enviada con éxito. Revisa tu bandeja de entrada para futuras respuestas.',
            ),
            backgroundColor: Colors.greenAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al enviar solicitud: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF111111),
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: Colors.greenAccent, width: 1),
        borderRadius: BorderRadius.circular(8),
      ),
      title: const Text(
        'CONTACTO / SOPORTE',
        style: TextStyle(
          color: Colors.greenAccent,
          fontFamily: 'Courier',
          fontWeight: FontWeight.bold,
        ),
      ),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'TIPO DE SOLICITUD',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 10,
                  fontFamily: 'Courier',
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.white24),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<AdminRequestType>(
                    value: _selectedType,
                    isExpanded: true,
                    dropdownColor: Colors.black,
                    style: const TextStyle(
                      color: Colors.white,
                      fontFamily: 'Courier',
                    ),
                    items: AdminRequestType.values.map((type) {
                      return DropdownMenuItem(
                        value: type,
                        child: Text(type.displayName.toUpperCase()),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) setState(() => _selectedType = value);
                    },
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (_selectedType != AdminRequestType.ascenso) ...[
                _buildTextField(
                  controller: _subjectController,
                  label: 'ASUNTO',
                  hint: 'Ej: Problema con el mapa',
                  validator: (v) => v == null || v.isEmpty ? 'Requerido' : null,
                ),
                const SizedBox(height: 16),
              ],
              _buildTextField(
                controller: _messageController,
                label: _selectedType == AdminRequestType.ascenso
                    ? 'JUSTIFICACIÓN / MOTIVOS'
                    : 'MENSAJE / DETALLES',
                hint: _selectedType == AdminRequestType.ascenso
                    ? '¿Por qué necesitas subir de rango?'
                    : 'Escribe aquí tu duda, sugerencia o reclamo...',
                maxLines: _selectedType == AdminRequestType.ascenso ? 2 : 4,
                validator: _selectedType == AdminRequestType.ascenso
                    ? null
                    : (v) => v == null || v.isEmpty ? 'Requerido' : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSending ? null : () => Navigator.of(context).pop(),
          child: const Text(
            'CANCELAR',
            style: TextStyle(color: Colors.grey, fontFamily: 'Courier'),
          ),
        ),
        ElevatedButton(
          onPressed: _isSending ? null : _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: _selectedType == AdminRequestType.ascenso
                ? Colors.amber
                : Colors.greenAccent,
            foregroundColor: Colors.black,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          child: _isSending
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.black,
                  ),
                )
              : Text(
                  _selectedType == AdminRequestType.ascenso
                      ? 'SOLICITAR ASCENSO'
                      : 'ENVIAR',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Courier',
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white54,
            fontSize: 10,
            fontFamily: 'Courier',
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          validator: validator,
          style: const TextStyle(color: Colors.white, fontFamily: 'Courier'),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(
              color: Colors.white.withOpacity(0.2),
              fontSize: 13,
            ),
            filled: true,
            fillColor: Colors.black,
            border: const OutlineInputBorder(
              borderSide: BorderSide(color: Colors.white24),
            ),
            enabledBorder: const OutlineInputBorder(
              borderSide: BorderSide(color: Colors.white24),
            ),
            focusedBorder: const OutlineInputBorder(
              borderSide: BorderSide(color: Colors.greenAccent),
            ),
          ),
        ),
      ],
    );
  }
}

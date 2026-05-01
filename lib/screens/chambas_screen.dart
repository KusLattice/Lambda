import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lambda_app/models/chamba_model.dart';
import 'package:lambda_app/providers/chamba_provider.dart';
import 'package:lambda_app/models/user_model.dart';
import 'package:lambda_app/providers/auth_provider.dart';
import 'package:lambda_app/screens/public_profile_screen.dart';
import 'package:lambda_app/widgets/grid_background.dart';
import 'package:intl/intl.dart';

class ChambasScreen extends ConsumerStatefulWidget {
  static const String routeName = '/chambas';
  const ChambasScreen({super.key});

  @override
  ConsumerState<ChambasScreen> createState() => _ChambasScreenState();
}

class _ChambasScreenState extends ConsumerState<ChambasScreen> {
  bool _hasOpenedInitialChamba = false;

  @override
  Widget build(BuildContext context) {
    final chambasAsync = ref.watch(chambasStreamProvider);
    final initialChambaId =
        ModalRoute.of(context)!.settings.arguments as String?;
    final currentUser = ref.watch(authProvider).valueOrNull;
    final isGuest = currentUser?.role == UserRole.TecnicoInvitado;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'CHAMBAS',
          style: TextStyle(
            fontFamily: 'Courier',
            color: Colors.greenAccent,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.black,
        elevation: 0,
      ),
      floatingActionButton: isGuest
          ? null
          : FloatingActionButton(
              onPressed: () => _showCreateChambaDialog(context),
              backgroundColor: Colors.greenAccent,
              child: const Icon(Icons.add, color: Colors.black),
            ),
      body: Stack(
        children: [
          const GridBackground(child: SizedBox.expand()),
          chambasAsync.when(
            data: (chambas) => chambas.isEmpty
                ? const Center(
                    child: Text(
                      'No hay chambas registradas.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: chambas.length,
                    itemBuilder: (context, index) {
                      final chamba = chambas[index];

                      // Deep Link
                      if (initialChambaId != null &&
                          !_hasOpenedInitialChamba &&
                          chamba.id == initialChambaId) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted && !_hasOpenedInitialChamba) {
                            setState(() => _hasOpenedInitialChamba = true);
                            _showChambaDetails(context, chamba);
                          }
                        });
                      }

                      return InkWell(
                        onTap: () => _showChambaDetails(context, chamba),
                        child: _ChambaCard(chamba: chamba),
                      );
                    },
                  ),
            loading: () => const Center(
              child: CircularProgressIndicator(color: Colors.greenAccent),
            ),
            error: (e, _) => Center(
              child: Text(
                'Error: $e',
                style: const TextStyle(color: Colors.red),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmDeleteChamba(BuildContext context, ChambaPost chamba) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text(
          '¿Eliminar chamba?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          '¿Estás seguro de que quieres borrar este anuncio de pega?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCELAR', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await ref
                    .read(chambaProvider.notifier) // Changed to chambaProvider
                    .deleteChamba(chamba.id);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Chamba eliminada.')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('Error: $e')));
                }
              }
            },
            child: const Text(
              'ELIMINAR',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
  }

  void _showCreateChambaDialog(
    BuildContext context, {
    ChambaPost? initialChamba,
  }) {
    final formKey = GlobalKey<FormState>(); // Added formKey
    final titleCtrl = TextEditingController(text: initialChamba?.title ?? '');
    final descCtrl = TextEditingController(
      text: initialChamba?.description ?? '',
    );
    final salaryCtrl = TextEditingController(text: initialChamba?.salary ?? '');
    ChambaType selectedType =
        initialChamba?.type ?? ChambaType.ofrece; // Corrected initialization

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 24,
          ),
          backgroundColor: Colors.grey[900],
          title: Text(
            initialChamba != null
                ? 'EDITAR CHAMBA'
                : 'PUBLICAR CHAMBA', // Updated title
            style: const TextStyle(
              color: Colors.greenAccent,
              fontFamily: 'Courier',
            ),
          ),
          content: SingleChildScrollView(
            child: Form(
              // Added Form widget
              key: formKey, // Assigned formKey
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButton<ChambaType>(
                    value: selectedType,
                    dropdownColor: Colors.black,
                    isExpanded: true,
                    items: ChambaType.values
                        .map(
                          (type) => DropdownMenuItem(
                            value: type,
                            child: Text(
                              type == ChambaType.ofrece
                                  ? 'OFREZCO PEGA'
                                  : 'BUSCO PEGA',
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (val) => setState(() => selectedType = val!),
                  ),
                  TextFormField(
                    // Changed to TextFormField
                    controller: titleCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Título corto',
                    ),
                    style: const TextStyle(color: Colors.white),
                    validator: (value) {
                      // Added validator
                      if (value == null || value.isEmpty) {
                        return 'Por favor, ingresa un título.';
                      }
                      return null;
                    },
                  ),
                  TextFormField(
                    // Changed to TextFormField
                    controller: descCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Descripción / Requisitos',
                    ),
                    maxLines: 6,
                    style: const TextStyle(color: Colors.white),
                    validator: (value) {
                      // Added validator
                      if (value == null || value.isEmpty) {
                        return 'Por favor, ingresa una descripción.';
                      }
                      return null;
                    },
                  ),

                  TextField(
                    controller: salaryCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Presupuesto/Sueldo (opcional)',
                    ),
                    style: const TextStyle(color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CANCELAR'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (formKey.currentState!.validate()) {
                  // Used formKey
                  final user = ref
                      .read(authProvider)
                      .valueOrNull; // Get user from authProvider
                  if (user == null) return;

                  final chambaData = ChambaPost(
                    id: initialChamba?.id ?? '',
                    authorId: user.id,
                    authorName: user.apodo ?? user.nombre,
                    title: titleCtrl.text.trim(),
                    description: descCtrl.text.trim(),
                    type: selectedType,
                    salary: salaryCtrl.text.trim(),
                    timestamp: initialChamba?.timestamp ?? DateTime.now(),
                  );

                  try {
                    if (initialChamba != null) {
                      await ref
                          .read(chambaProvider.notifier)
                          .updateChamba(chambaData);
                    } else {
                      await ref
                          .read(chambaProvider.notifier)
                          .createChamba(
                            title: chambaData.title,
                            description: chambaData.description,
                            type: chambaData.type,
                            salary: chambaData.salary,
                          );
                    }
                    if (context.mounted) Navigator.pop(context);
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text('Error: $e')));
                    }
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.greenAccent,
              ),
              child: Text(
                initialChamba != null
                    ? 'ACTUALIZAR'
                    : 'PUBLICAR', // Updated button text
                style: const TextStyle(color: Colors.black),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showChambaDetails(BuildContext context, ChambaPost chamba) {
    final user = ref
        .watch(authProvider)
        .valueOrNull; // Get user from authProvider
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        expand: false,
        builder: (context, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: chamba.type == ChambaType.busca
                      ? Colors.orangeAccent.withValues(alpha: 0.2)
                      : Colors.greenAccent.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  chamba.type == ChambaType.busca
                      ? 'BUSCO TRABAJO'
                      : 'OFERTA TÉCNICA',
                  style: TextStyle(
                    color: chamba.type == ChambaType.busca
                        ? Colors.orangeAccent
                        : Colors.greenAccent,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    fontFamily: 'Courier',
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                chamba.title.toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Courier',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.person, color: Colors.blueAccent, size: 16),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () => Navigator.pushNamed(
                      context,
                      PublicProfileScreen.routeName,
                      arguments: chamba.authorId,
                    ),
                    child: Text(
                      chamba.authorName,
                      style: const TextStyle(
                        color: Colors.blueAccent,
                        decoration: TextDecoration.underline,
                        decorationColor: Colors.blueAccent,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    DateFormat('dd/MM HH:mm').format(chamba.timestamp),
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  ),
                  if (user != null) ...[
                    if (chamba.authorId == user.id ||
                        user.role == UserRole.SuperAdmin)
                      IconButton(
                        icon: const Icon(
                          Icons.edit,
                          color: Colors.blueAccent,
                          size: 20,
                        ),
                        onPressed: () => _showCreateChambaDialog(
                          context,
                          initialChamba: chamba,
                        ),
                      ),
                    if (chamba.authorId == user.id ||
                        user.role == UserRole.Admin ||
                        user.role == UserRole.SuperAdmin)
                      IconButton(
                        icon: const Icon(
                          Icons.delete,
                          color: Colors.redAccent,
                          size: 20,
                        ),
                        onPressed: () => _confirmDeleteChamba(context, chamba),
                      ),
                  ],
                ],
              ),
              const SizedBox(height: 24),
              const Divider(color: Colors.white12),
              const SizedBox(height: 24),
              const Text(
                'DETALLE DEL REQUERIMIENTO',
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                chamba.description,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),

              if (chamba.salary != null && chamba.salary!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(
                      Icons.payments,
                      color: Colors.greenAccent,
                      size: 18,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      chamba.salary!,
                      style: const TextStyle(
                        color: Colors.greenAccent,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 100),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChambaCard extends StatelessWidget {
  final ChambaPost chamba;
  const _ChambaCard({required this.chamba});

  @override
  Widget build(BuildContext context) {
    final isBusqueda = chamba.type == ChambaType.busca;

    return Card(
      color: Colors.black.withValues(alpha: 0.7),
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: isBusqueda
              ? Colors.orangeAccent.withValues(alpha: 0.5)
              : Colors.greenAccent.withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: isBusqueda
                        ? Colors.orangeAccent.withValues(alpha: 0.2)
                        : Colors.greenAccent.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    isBusqueda ? 'BUSCO TRABAJO' : 'OFERTA TÉCNICA',
                    style: TextStyle(
                      color: isBusqueda
                          ? Colors.orangeAccent
                          : Colors.greenAccent,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Text(
                  DateFormat('dd/MM HH:mm').format(chamba.timestamp),
                  style: const TextStyle(color: Colors.grey, fontSize: 10),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              chamba.title.toUpperCase(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.bold,
                fontFamily: 'Courier',
              ),
            ),
            const SizedBox(height: 8),
            Text(
              chamba.description,
              style: const TextStyle(color: Colors.grey, fontSize: 13),
            ),
            const Divider(color: Colors.white10, height: 24),
            Row(
              children: [
                if (chamba.salary != null && chamba.salary!.isNotEmpty) ...[
                  const Icon(
                    Icons.payments_outlined,
                    color: Colors.greenAccent,
                    size: 14,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    chamba.salary!,
                    style: const TextStyle(
                      color: Colors.greenAccent,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(
                  Icons.person_outline,
                  color: Colors.blueAccent,
                  size: 14,
                ),
                const SizedBox(width: 4),
                Text(
                  chamba.authorName,
                  style: const TextStyle(
                    color: Colors.blueAccent,
                    fontSize: 12,
                    decoration: TextDecoration.underline,
                    decorationColor: Colors.blueAccent,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

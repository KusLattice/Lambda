import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lambda_app/models/user_model.dart';
import 'package:lambda_app/models/lat_lng.dart';
import 'package:lambda_app/providers/auth_provider.dart';
import 'package:lambda_app/providers/theme_provider.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:lambda_app/widgets/user_contributions_list.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  static const String routeName = '/profile';
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  Future<void> _showEditNicknameDialog(User user) async {
    final nicknameController = TextEditingController(text: user.apodo);
    bool isLoading = false;

    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Cambiar Apodo'),
              content: SingleChildScrollView(
                child: ListBody(
                  children: <Widget>[
                    const Text(
                      'Tu apodo debe ser único y no puede contener "@".',
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: nicknameController,
                      decoration: const InputDecoration(
                        hintText: 'Nuevo apodo',
                      ),
                    ),
                  ],
                ),
              ),
              actions: <Widget>[
                TextButton(
                  child: const Text('Cancelar'),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                ElevatedButton(
                  onPressed: isLoading
                      ? null
                      : () async {
                          setState(() => isLoading = true);
                          final navigator = Navigator.of(context);
                          final messenger = ScaffoldMessenger.of(context);
                          try {
                            await ref
                                .read(authProvider.notifier)
                                .updateNickname(nicknameController.text);
                            if (mounted) navigator.pop();
                          } catch (e) {
                            if (mounted) {
                              messenger.showSnackBar(
                                SnackBar(
                                  backgroundColor: Colors.redAccent,
                                  content: Text(
                                    e.toString().replaceAll('Exception: ', ''),
                                  ),
                                ),
                              );
                            }
                          } finally {
                            if (mounted) {
                              setState(() => isLoading = false);
                            }
                          }
                        },
                  child: isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Guardar'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showEditProfileDialog(
    User user,
    String field,
    String currentVal,
    String title,
  ) async {
    final controller = TextEditingController(text: currentVal);
    bool isLoading = false;

    return showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: const Color.fromARGB(255, 30, 30, 30),
              title: Text(
                title,
                style: const TextStyle(
                  color: Colors.greenAccent,
                  fontSize: 14,
                  fontFamily: 'Courier',
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (field == 'celular') ...[
                    StatefulBuilder(
                      builder: (context, setDialogState) {
                        final countries = [
                          {'name': 'Chile', 'code': '+56'},
                          {'name': 'Argentina', 'code': '+54'},
                          {'name': 'Perú', 'code': '+51'},
                          {'name': 'Bolivia', 'code': '+591'},
                          {'name': 'Colombia', 'code': '+57'},
                        ];

                        String currentCode = '+56';
                        for (var c in countries) {
                          if (controller.text.startsWith(c['code']!)) {
                            currentCode = c['code']!;
                            break;
                          }
                        }

                        return DropdownButton<String>(
                          value: currentCode,
                          isExpanded: true,
                          dropdownColor: Colors.black,
                          style: const TextStyle(color: Colors.greenAccent),
                          items: countries.map((c) {
                            return DropdownMenuItem<String>(
                              value: c['code'],
                              child: Text('${c['name']} (${c['code']})'),
                            );
                          }).toList(),
                          onChanged: (val) {
                            if (val != null) {
                              setDialogState(() {
                                String cleanNum = controller.text.replaceFirst(
                                  currentCode,
                                  '',
                                );
                                while (cleanNum.startsWith(' ') ||
                                    cleanNum.startsWith('-')) {
                                  cleanNum = cleanNum.substring(1);
                                }
                                controller.text = '$val $cleanNum';
                              });
                            }
                          },
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                  ],
                  TextField(
                    controller: controller,
                    style: const TextStyle(color: Colors.white),
                    keyboardType: field == 'celular'
                        ? TextInputType.phone
                        : TextInputType.text,
                    decoration: InputDecoration(
                      hintText: 'Nuevo $title',
                      hintStyle: const TextStyle(color: Colors.white54),
                      enabledBorder: const UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.white54),
                      ),
                      focusedBorder: const UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.greenAccent),
                      ),
                    ),
                  ),
                ],
              ),
              actions: <Widget>[
                TextButton(
                  child: const Text(
                    'Cancelar',
                    style: TextStyle(color: Colors.white54),
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.greenAccent,
                  ),
                  onPressed: isLoading
                      ? null
                      : () async {
                          setState(() => isLoading = true);
                          final navigator = Navigator.of(context);
                          final messenger = ScaffoldMessenger.of(context);
                          try {
                            final authNotifier = ref.read(
                              authProvider.notifier,
                            );
                            if (field == 'nombre') {
                              await authNotifier.updateProfileSettings(
                                nombre: controller.text,
                              );
                            } else if (field == 'biografia')
                              await authNotifier.updateProfileSettings(
                                biografia: controller.text,
                              );
                            else if (field == 'empresa')
                              await authNotifier.updateProfileSettings(
                                empresa: controller.text,
                              );
                            else if (field == 'celular') {
                              await authNotifier.updateProfileSettings(
                                celular: controller.text,
                              );
                            }

                            if (mounted) navigator.pop();
                          } catch (e) {
                            if (mounted) {
                              messenger.showSnackBar(
                                SnackBar(
                                  backgroundColor: Colors.redAccent,
                                  content: Text(
                                    e.toString().replaceAll('Exception: ', ''),
                                  ),
                                ),
                              );
                            }
                          } finally {
                            if (mounted) setState(() => isLoading = false);
                          }
                        },
                  child: isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.black,
                          ),
                        )
                      : const Text(
                          'Guardar',
                          style: TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showEditDateDialog(User user) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: user.fechaDeNacimiento ?? DateTime(2000),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: ThemeData.dark().copyWith(
            colorScheme: const ColorScheme.dark(
              primary: Colors.greenAccent,
              onPrimary: Colors.black,
              surface: Color.fromARGB(255, 30, 30, 30),
              onSurface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null && picked != user.fechaDeNacimiento) {
      final messenger = ScaffoldMessenger.of(context);
      try {
        await ref
            .read(authProvider.notifier)
            .updateProfileSettings(fechaDeNacimiento: picked);
      } catch (e) {
        if (mounted) {
          messenger.showSnackBar(
            SnackBar(
              backgroundColor: Colors.redAccent,
              content: Text(e.toString().replaceAll('Exception: ', '')),
            ),
          );
        }
      }
    }
  }

  Future<void> _pickAndUploadImage() async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 75,
    );

    if (image != null) {
      final messenger = ScaffoldMessenger.of(context);
      try {
        await ref.read(authProvider.notifier).updateProfilePhoto(image.path);
        if (mounted) {
          messenger.showSnackBar(
            const SnackBar(content: Text('Foto de perfil actualizada')),
          );
        }
      } catch (e) {
        if (mounted) {
          messenger.showSnackBar(
            SnackBar(
              backgroundColor: Colors.redAccent,
              content: Text('Error al subir imagen: $e'),
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments;
    final String? targetUserId = args is String ? args : null;

    final currentUserAsync = ref.watch(authProvider);
    final currentUser = currentUserAsync.valueOrNull;

    AsyncValue<User?> displayUserAsync;
    if (targetUserId != null) {
      final docAsync = ref.watch(userDocumentStreamProvider(targetUserId));
      displayUserAsync = docAsync.when(
        data: (doc) {
          if (!doc.exists) return const AsyncValue.data(null);
          try {
            return AsyncValue.data(
              User.fromMap(doc.data() as Map<String, dynamic>, doc.id),
            );
          } catch (e) {
            return AsyncValue.error(e, StackTrace.current);
          }
        },
        error: (err, stack) => AsyncValue.error(err, stack),
        loading: () => const AsyncValue.loading(),
      );
    } else {
      displayUserAsync = currentUserAsync;
    }

    final user = displayUserAsync.valueOrNull;

    if (displayUserAsync.isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Perfil de Usuario'),
          backgroundColor: Colors.black,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (user == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Perfil de Usuario'),
          backgroundColor: Colors.black,
        ),
        body: const Center(child: Text('Usuario no encontrado.')),
      );
    }

    final isViewingSelf = currentUser?.id == user.id;
    final isAdmin =
        currentUser?.role == UserRole.Admin ||
        currentUser?.role == UserRole.SuperAdmin;
    final isSuperAdmin = currentUser?.role == UserRole.SuperAdmin;
    // ... rest of the build method uses 'user' for display, but editing actions should ideally be blocked or handled if viewing others.
    // For simplicity, we disable edit buttons if not viewing self, unless SuperAdmin.
    final canEdit = isViewingSelf || isSuperAdmin;
    final nombreEdits = 3 - (user.editCounts['nombre'] ?? 0);
    final fechaEdits = 3 - (user.editCounts['fechaDeNacimiento'] ?? 0);
    final strNombreEdits = nombreEdits > 0 ? nombreEdits : 0;
    final strFechaEdits = fechaEdits > 0 ? fechaEdits : 0;

    final firebaseUser = auth.FirebaseAuth.instance.currentUser;
    final isPhoneAuth =
        firebaseUser?.providerData.any((p) => p.providerId == 'phone') ?? false;

    final tooltipNombre = isAdmin
        ? 'Ediciones ilimitadas para Admins y Super Admins.'
        : 'Solo puedes cambiar esto 3 veces. Te quedan $strNombreEdits mediciones.';
    final tooltipFecha = isAdmin
        ? 'Ediciones ilimitadas para Admins y Super Admins.'
        : 'Solo puedes cambiar esto 3 veces. Te quedan $strFechaEdits ediciones.';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Perfil de Usuario'),
        backgroundColor: Colors.black,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: <Widget>[
          _buildProfileHeader(user, canEdit: canEdit),
          if (user.role == UserRole.TecnicoInvitado && isViewingSelf) ...[
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => _requestAdminVerification(context, user),
              icon: const Icon(Icons.verified_user, color: Colors.black),
              label: const Text(
                'SOLICITAR VERIFICACIÓN A ADMIN',
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.greenAccent,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ],
          const SizedBox(height: 24),
          _buildSectionTitle('Información Pública'),
          _buildInfoTile(
            'Apodo',
            user.apodo,
            Icons.person_pin_rounded,
            onEdit: canEdit ? () => _showEditNicknameDialog(user) : null,
            tooltip:
                'El apodo es el único nombre garantizado a ser global. No admite "@".',
          ),
          _buildInfoTile(
            'Biografía',
            user.biografia,
            Icons.book_rounded,
            onEdit: canEdit
                ? () => _showEditProfileDialog(
                    user,
                    'biografia',
                    user.biografia ?? '',
                    'Biografía',
                  )
                : null,
            tooltip:
                'Breve descripción que los demás usuarios verán en tu perfil.',
          ),
          if (user.showCompanyPublicly || canEdit)
            _buildInfoTile(
              'Empresa',
              user.empresa,
              Icons.business_rounded,
              onEdit: canEdit
                  ? () => _showEditProfileDialog(
                      user,
                      'empresa',
                      user.empresa ?? '',
                      'Empresa',
                    )
                  : null,
              tooltip:
                  'Compañía contratista, principal o subcontrata para la que operas.',
            ),
          if (canEdit)
            _buildSwitchTile(
              'Mostrar Empresa Públicamente',
              user.showCompanyPublicly,
              (val) {
                ref
                    .read(authProvider.notifier)
                    .updateProfileSettings(showCompanyPublicly: val);
              },
              tooltip:
                  'Si desactivas esto, nadie salvo un Admin podrá ver tu empresa.',
            ),
          if (user.showWorkAreaPublicly || canEdit)
            _buildInfoTile(
              'Área de Trabajo',
              user.area,
              Icons.work_rounded,
              onEdit: canEdit
                  ? () => _showEditProfileDialog(
                      user,
                      'area',
                      user.area ?? '',
                      'Área de Trabajo',
                    )
                  : null,
              tooltip: 'Tu área principal de operaciones o maestría técnica.',
            ),
          if (canEdit)
            _buildSwitchTile(
              'Mostrar Área Públicamente',
              user.showWorkAreaPublicly,
              (val) {
                ref
                    .read(authProvider.notifier)
                    .updateProfileSettings(showWorkAreaPublicly: val);
              },
              tooltip:
                  'Si desactivas esto, nadie salvo un Admin podrá ver a qué te dedicas.',
            ),
          const Divider(color: Colors.white24, height: 40),
          _buildSectionTitle('Información Privada'),
          _buildInfoTile(
            'Nombre Completo',
            user.nombre,
            Icons.person_rounded,
            onEdit: canEdit
                ? () => _showEditProfileDialog(
                    user,
                    'nombre',
                    user.nombre,
                    'Nombre Completo',
                  )
                : null,
            tooltip: tooltipNombre,
          ),
          _buildInfoTile(
            'Correo Electrónico',
            user.correo,
            Icons.email_rounded,
            tooltip: 'Tu correo de acceso asociado a Lambda App.',
          ),
          if (canEdit)
            _buildInfoTile(
              'Celular',
              user.celular,
              Icons.phone_iphone_rounded,
              onEdit: isPhoneAuth || !canEdit
                  ? null
                  : () => _showEditProfileDialog(
                      user,
                      'celular',
                      user.celular ?? '',
                      'Celular',
                    ),
              tooltip: isPhoneAuth
                  ? 'Tu número de acceso principal. No se puede modificar aquí.'
                  : 'Tu número de contacto. Toca para editar.',
            ),
          _buildInfoTile(
            'Fecha de Nacimiento',
            user.fechaDeNacimiento != null
                ? DateFormat('dd/MM/yyyy').format(user.fechaDeNacimiento!)
                : 'No especificada',
            Icons.cake_rounded,
            onEdit: canEdit ? () => _showEditDateDialog(user) : null,
            tooltip: tooltipFecha,
          ),
          const Divider(color: Colors.white24, height: 40),
          _buildSectionTitle('Ubicación en el Mapa'),
          if (canEdit)
            _buildSwitchTile(
              'Hacer visible en el mapa',
              user.isVisibleOnMap,
              (val) async {
                final messenger = ScaffoldMessenger.of(context);
                try {
                  if (val) {
                    bool serviceEnabled =
                        await Geolocator.isLocationServiceEnabled();
                    if (!serviceEnabled) {
                      throw Exception(
                        'Los servicios de ubicación están deshabilitados.',
                      );
                    }
                    LocationPermission permission =
                        await Geolocator.checkPermission();
                    if (permission == LocationPermission.denied) {
                      permission = await Geolocator.requestPermission();
                      if (permission == LocationPermission.denied) {
                        throw Exception('Permisos de ubicación denegados.');
                      }
                    }
                    if (permission == LocationPermission.deniedForever) {
                      throw Exception(
                        'Permisos de ubicación permanentemente denegados.',
                      );
                    }

                    messenger.showSnackBar(
                      const SnackBar(content: Text('Obteniendo ubicación...')),
                    );

                    final position = await Geolocator.getCurrentPosition(
                      locationSettings: const LocationSettings(
                        accuracy: LocationAccuracy.medium,
                      ),
                    );

                    await ref
                        .read(authProvider.notifier)
                        .updateProfileSettings(
                          isVisibleOnMap: true,
                          lastKnownPosition: LatLng(
                            position.latitude,
                            position.longitude,
                          ),
                        );
                  } else {
                    await ref
                        .read(authProvider.notifier)
                        .updateProfileSettings(isVisibleOnMap: false);
                  }
                } catch (e) {
                  messenger.showSnackBar(
                    SnackBar(
                      backgroundColor: Colors.redAccent,
                      content: Text(e.toString().replaceAll('Exception: ', '')),
                    ),
                  );
                }
              },
              tooltip:
                  'Al activar, tu ubicación será visible para otros usuarios en la aplicación.',
            ),
          const Divider(color: Colors.white24, height: 40),
          if (isViewingSelf) _buildThemeSection(),
          const Divider(color: Colors.white24, height: 40),
          _buildSectionTitle('Metadatos de la Cuenta'),
          _buildInfoTile(
            'Rol',
            user.role.displayName,
            Icons.verified_user_rounded,
          ),
          _buildInfoTile('ID de Usuario', user.id, Icons.vpn_key_rounded),
          _buildInfoTile(
            'Fecha de Ingreso',
            user.fechaDeIngreso != null
                ? DateFormat('dd/MM/yyyy HH:mm').format(user.fechaDeIngreso!)
                : 'N/A',
            Icons.event_available_rounded,
          ),
          _buildInfoTile(
            'Ubicación de Ingreso',
            user.ubicacionDeIngreso,
            Icons.location_on_rounded,
          ),
          // Sección de aportes: visible solo para SuperAdmins viendo a otro usuario.
          // Información privada de auditoría de contenido.
          if (isSuperAdmin && !isViewingSelf) ...[
            const Divider(color: Colors.white24, height: 40),
            UserContributionsList(
              user: user,
              sectionTitle: 'APORTES DEL USUARIO',
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildProfileHeader(User user, {required bool canEdit}) {
    return Center(
      child: Column(
        children: [
          Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.greenAccent.withValues(alpha: 0.5),
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.greenAccent.withValues(alpha: 0.2),
                      blurRadius: 15,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: CircleAvatar(
                  radius: 60,
                  backgroundImage:
                      (user.fotoUrl != null && user.fotoUrl!.isNotEmpty)
                      ? NetworkImage(user.fotoUrl!)
                      : null,
                  backgroundColor: Colors.grey[900],
                  child: (user.fotoUrl == null || user.fotoUrl!.isEmpty)
                      ? const Icon(
                          Icons.person,
                          size: 60,
                          color: Colors.white24,
                        )
                      : null,
                ),
              ),
              if (canEdit)
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: InkWell(
                    onTap: _pickAndUploadImage,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(
                        color: Colors.greenAccent,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.camera_alt,
                        color: Colors.black,
                        size: 20,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            user.nombre,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
            ),
            child: Text(
              user.role.displayName,
              style: const TextStyle(
                color: Colors.amber,
                fontSize: 12,
                fontWeight: FontWeight.bold,
                fontFamily: 'Courier',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.greenAccent,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildInfoTile(
    String title,
    String? value,
    IconData icon, {
    VoidCallback? onEdit,
    String? tooltip,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
            leading: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  color: Colors.greenAccent.withValues(alpha: 0.8),
                  size: 18,
                ),
              ],
            ),
            title: Text(
              title.toUpperCase(),
              style: const TextStyle(
                color: Colors.greenAccent,
                fontSize: 10,
                fontFamily: 'Courier',
                fontWeight: FontWeight.bold,
                letterSpacing: 1.0,
              ),
            ),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 2.0),
              child: Text(
                value ?? '---',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ),
            trailing: (onEdit == null && tooltip == null)
                ? null
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (tooltip != null)
                        Tooltip(
                          message: tooltip,
                          triggerMode: TooltipTriggerMode.tap,
                          margin: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 8,
                          ),
                          padding: const EdgeInsets.all(12),
                          showDuration: const Duration(seconds: 4),
                          decoration: BoxDecoration(
                            color: Colors.grey[850],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Colors.greenAccent.withValues(alpha: 0.2),
                            ),
                          ),
                          textStyle: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                          ),
                          child: const Icon(
                            Icons.info_outline,
                            color: Colors.white24,
                            size: 16,
                          ),
                        ),
                      if (onEdit != null)
                        IconButton(
                          icon: const Icon(
                            Icons.edit_outlined,
                            color: Colors.greenAccent,
                            size: 18,
                          ),
                          onPressed: onEdit,
                        ),
                    ],
                  ),
          ),
          const Divider(color: Colors.white10, height: 1, indent: 50),
        ],
      ),
    );
  }

  Widget _buildSwitchTile(
    String title,
    bool value,
    ValueChanged<bool> onChanged, {
    String? tooltip,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.greenAccent,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (tooltip != null)
                Tooltip(
                  message: tooltip,
                  triggerMode: TooltipTriggerMode.tap,
                  margin: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  padding: const EdgeInsets.all(12),
                  showDuration: const Duration(seconds: 4),
                  decoration: BoxDecoration(
                    color: Colors.grey[850],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.greenAccent.withValues(alpha: 0.2),
                    ),
                  ),
                  textStyle: const TextStyle(color: Colors.white, fontSize: 12),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8.0),
                    child: Icon(
                      Icons.help_outline_rounded,
                      color: Colors.white24,
                      size: 14,
                    ),
                  ),
                ),
              Transform.scale(
                scale: 0.7,
                child: Switch(
                  value: value,
                  onChanged: onChanged,
                  activeThumbColor: Colors.greenAccent,
                  activeTrackColor: Colors.greenAccent.withValues(alpha: 0.3),
                  inactiveThumbColor: Colors.grey,
                  inactiveTrackColor: Colors.white10,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
          const Divider(color: Colors.white10, height: 1),
        ],
      ),
    );
  }

  Widget _buildThemeSection() {
    final currentTheme = ref.watch(themeProvider);
    final accent = currentTheme.accent;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              Icon(Icons.palette_outlined, color: accent, size: 18),
              const SizedBox(width: 8),
              Text(
                'PERSONALIZACIÓN',
                style: TextStyle(
                  color: accent,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'Courier',
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
        ),
        // Grid de temas
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 4,
            mainAxisSpacing: 6,
            crossAxisSpacing: 6,
            childAspectRatio: 0.85,
          ),
          itemCount: kLambdaThemes.length,
          itemBuilder: (context, i) {
            final theme = kLambdaThemes[i];
            final isSelected = theme.id == currentTheme.id;
            return GestureDetector(
              onTap: () {
                ref.read(themeProvider.notifier).setTheme(theme);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut,
                decoration: BoxDecoration(
                  color: theme.background,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isSelected
                        ? theme.accent
                        : Colors.white.withValues(alpha: 0.1),
                    width: isSelected ? 1.5 : 0.5,
                  ),
                  gradient: theme.backgroundGradient != null
                      ? LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: theme.backgroundGradient!,
                        )
                      : null,
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: theme.accent.withValues(alpha: 0.3),
                            blurRadius: 6,
                            spreadRadius: 1,
                          ),
                        ]
                      : [],
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(theme.emoji, style: const TextStyle(fontSize: 18)),
                    const SizedBox(height: 2),
                    Text(
                      theme.name,
                      style: TextStyle(
                        color: theme.accent,
                        fontSize: 8.5,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Courier',
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                    ),
                    if (isSelected)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Icon(
                          Icons.check_circle,
                          color: theme.accent,
                          size: 10,
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 10),
        // Color de accent actual
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: currentTheme.accent,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: currentTheme.accent.withValues(alpha: 0.5),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      currentTheme.name,
                      style: TextStyle(
                        color: currentTheme.accent,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      currentTheme.description,
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        // Toggle de FAB flotante
        _buildFloatFabToggle(),
      ],
    );
  }

  Widget _buildFloatFabToggle() {
    final showFab = ref.watch(themeFabVisibleProvider);
    return _buildSwitchTile(
      'Mostrar selector flotante en Dashboard',
      showFab,
      (val) {
        ref.read(themeFabVisibleProvider.notifier).setVisible(val);
      },
      tooltip:
          'Activa un botón flotante en el Dashboard para cambiar el tema rápidamente.',
    );
  }

  Future<void> _requestAdminVerification(
    BuildContext context,
    User user,
  ) async {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text(
          'Solicitar Verificación',
          style: TextStyle(color: Colors.greenAccent),
        ),
        content: const Text(
          'Se enviará un mensaje interno a los Administradores solicitando la revisión de tu perfil para ascenderte de rango.\n\n¿Deseas continuar?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('CANCELAR', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Enviando solicitud...')),
              );
              try {
                await ref.read(authProvider.notifier).sendVerificationRequest();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Solicitud enviada a los Administradores.'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text(
              'ENVIAR',
              style: TextStyle(color: Colors.greenAccent),
            ),
          ),
        ],
      ),
    );
  }
}

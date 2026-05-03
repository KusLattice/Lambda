import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lambda_app/models/user_model.dart';
import 'package:lambda_app/models/contact_request_model.dart';
import 'package:lambda_app/providers/auth_provider.dart';
import 'package:lambda_app/screens/mail_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class PublicProfileScreen extends ConsumerStatefulWidget {
  static const String routeName = '/public_profile';
  final String userId;

  const PublicProfileScreen({super.key, required this.userId});

  @override
  ConsumerState<PublicProfileScreen> createState() =>
      _PublicProfileScreenState();
}

class _PublicProfileScreenState extends ConsumerState<PublicProfileScreen> {
  bool _isLoading = true;
  User? _targetUser;
  bool _isContact = false;
  ContactRequestStatus? _requestStatus;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final authState = ref.read(authProvider).valueOrNull;
    if (authState == null) return;

    // 1. Registrar visita (Telemetría)
    await ref.read(authProvider.notifier).recordProfileVisit(widget.userId);

    // 2. Cargar datos del usuario objetivo
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.userId)
        .get();
    if (!doc.exists) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    final target = User.fromMap(doc.data()!, doc.id);

    // 3. Verificar si ya son contactos
    final isContact = authState.contactIds.contains(widget.userId);

    // 4. Verificar si hay solicitud pendiente
    ContactRequestStatus? status;
    if (!isContact) {
      final reqs = await FirebaseFirestore.instance
          .collection('contact_requests')
          .where('fromId', isEqualTo: authState.id)
          .where('toId', isEqualTo: widget.userId)
          .where('status', isEqualTo: ContactRequestStatus.pending.name)
          .get();
      if (reqs.docs.isNotEmpty) {
        status = ContactRequestStatus.pending;
      }
    }

    if (mounted) {
      setState(() {
        _targetUser = target;
        _isContact = isContact;
        _requestStatus = status;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Colors.black,
        body: const Center(
          child: CircularProgressIndicator(color: Colors.greenAccent),
        ),
      );
    }

    if (_targetUser == null) {
      return Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(backgroundColor: Colors.black),
        body: const Center(
          child: Text(
            'Usuario no encontrado',
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
    }

    final authUser = ref.watch(authProvider).valueOrNull;
    final isSuperAdmin = authUser?.role == UserRole.SuperAdmin;
    final isAdmin = authUser?.role == UserRole.Admin || isSuperAdmin;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: Text(
            _targetUser!.apodo ?? _targetUser!.nombre,
            style: const TextStyle(color: Colors.greenAccent),
          ),
          backgroundColor: Colors.black,
          iconTheme: const IconThemeData(color: Colors.greenAccent),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              // Cabecera: Avatar y Nombre
              Center(
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 60,
                      backgroundColor: Colors.grey[900],
                      backgroundImage: _targetUser!.fotoUrl != null
                          ? NetworkImage(_targetUser!.fotoUrl!)
                          : null,
                      child: _targetUser!.fotoUrl == null
                          ? const Icon(
                              Icons.person,
                              size: 60,
                              color: Colors.greenAccent,
                            )
                          : null,
                    ),
                    const SizedBox(height: 15),
                    Text(
                      _targetUser!.nombre,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (_targetUser!.apodo != null)
                      Text(
                        '@${_targetUser!.apodo}',
                        style: const TextStyle(
                          color: Colors.greenAccent,
                          fontSize: 16,
                        ),
                      ),
                    if (_targetUser!.customStatus != null &&
                        _targetUser!.customStatus!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        _targetUser!.customStatus!,
                        style: const TextStyle(
                          color: Colors.greenAccent,
                          fontSize: 16,
                          fontWeight: FontWeight.w400,
                          fontStyle: FontStyle.italic,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ] else if (_targetUser!.statusEmoji != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _targetUser!.statusEmoji!,
                        style: const TextStyle(
                          color: Colors.greenAccent,
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.greenAccent.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.greenAccent.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Text(
                        _targetUser!.role.displayName,
                        style: const TextStyle(
                          color: Colors.greenAccent,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.remove_red_eye,
                          color: Colors.white38,
                          size: 14,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          '${_targetUser!.visitCount} visitas',
                          style: const TextStyle(
                            color: Colors.white38,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),

              // Acciones de Red
              if (authUser?.id != widget.userId) _buildNetworkActions(),

              const SizedBox(height: 30),

              // Información Pública
              _buildInfoSection(isAdmin),

              const SizedBox(height: 30),

              // TELEMETRÍA (Solo SuperAdmin)
              if (isSuperAdmin) _buildTelemetrySection(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNetworkActions() {
    if (_isContact) {
      return ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.greenAccent,
          foregroundColor: Colors.black,
          minimumSize: const Size(double.infinity, 50),
        ),
        icon: const Icon(Icons.message),
        label: const Text('ENVIAR MENSAJE (Red Galáctica)'),
        onPressed: () {
          Navigator.pushNamed(context, MailScreen.routeName);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Abriendo Correo Lambda...')),
          );
        },
      );
    }

    if (_requestStatus == ContactRequestStatus.pending) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white10,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Text(
          'Solicitud de red pendiente...',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white70),
        ),
      );
    }

    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.grey[900],
        foregroundColor: Colors.greenAccent,
        side: const BorderSide(color: Colors.greenAccent),
        minimumSize: const Size(double.infinity, 50),
      ),
      icon: const Icon(Icons.person_add),
      label: const Text('AÑADIR A MI RED'),
      onPressed: () async {
        await ref.read(authProvider.notifier).sendContactRequest(widget.userId);
        setState(() => _requestStatus = ContactRequestStatus.pending);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Solicitud enviada. Espera la validación.'),
            ),
          );
        }
      },
    );
  }

  Widget _buildInfoSection(bool isAdmin) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF0F0F0F),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInfoItem(
            Icons.info_outline,
            'Biografía',
            _targetUser!.biografia ?? 'Sin biografía visible.',
          ),
          if (_targetUser!.showCompanyPublicly || isAdmin)
            _buildInfoItem(
              Icons.business,
              'Empresa',
              (_targetUser!.empresa == null || _targetUser!.empresa!.isEmpty)
                  ? ''
                  : _targetUser!.empresa!,
            ),
          if (_targetUser!.showWorkAreaPublicly || isAdmin)
            _buildInfoItem(
              Icons.work_outline,
              'Área',
              (_targetUser!.area == null || _targetUser!.area!.isEmpty)
                  ? ''
                  : _targetUser!.area!,
            ),
          _buildInfoItem(
            Icons.calendar_today,
            'Miembro desde',
            _targetUser!.fechaDeIngreso != null
                ? DateFormat('dd/MM/yyyy').format(_targetUser!.fechaDeIngreso!)
                : 'Desconocido',
          ),
        ],
      ),
    );
  }

  Widget _buildInfoItem(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.greenAccent, size: 20),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
                Text(
                  value,
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTelemetrySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(color: Colors.redAccent, thickness: 0.5),
        const SizedBox(height: 10),
        const Row(
          children: [
            Icon(Icons.analytics, color: Colors.redAccent, size: 20),
            SizedBox(width: 10),
            Text(
              'RADAR DE VISITANTES (SUPERADMIN)',
              style: TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 15),
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(widget.userId)
              .collection('profile_visitors')
              .orderBy('lastVisitAt', descending: true)
              .snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Center(
                child: CircularProgressIndicator(color: Colors.redAccent),
              );
            }
            final visits = snapshot.data!.docs;
            if (visits.isEmpty) {
              return const Text(
                'Nadie ha visto este perfil aún.',
                style: TextStyle(color: Colors.white24),
              );
            }

            return ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: visits.length,
              itemBuilder: (context, index) {
                final visit = visits[index].data() as Map<String, dynamic>;
                final date = (visit['lastVisitAt'] as Timestamp?)?.toDate();
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(
                    Icons.remove_red_eye,
                    color: Colors.white24,
                    size: 16,
                  ),
                  title: Text(
                    visit['visitorNickname'] ?? 'Anónimo',
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                  ),
                  subtitle: Text(
                    date != null
                        ? DateFormat('dd/MM/yyyy HH:mm').format(date)
                        : '...',
                    style: const TextStyle(color: Colors.white24, fontSize: 10),
                  ),
                  trailing: Text(
                    'x${visit['visitCount']}',
                    style: const TextStyle(
                      color: Colors.greenAccent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                );
              },
            );
          },
        ),
      ],
    );
  }
}

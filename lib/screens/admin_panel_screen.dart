import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:lambda_app/providers/auth_provider.dart';
import 'package:lambda_app/config/modules_config.dart';
import 'package:lambda_app/screens/recycle_bin_screen.dart';
import 'package:lambda_app/models/user_model.dart';
import '../models/admin_request_model.dart';
import '../services/admin_service.dart';

class AdminPanelScreen extends ConsumerStatefulWidget {
  static const String routeName = '/admin-panel';
  const AdminPanelScreen({super.key});

  @override
  ConsumerState<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends ConsumerState<AdminPanelScreen> {
  UserRole? _filterRole;
  bool _filterConnected = false;
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Lista de features bloqueables derivada de la config central.
  /// Al agregar un módulo en modules_config.dart aparece solo aquí.
  static List<String> get blockableFeatures =>
      kDashboardModules.map((m) => m.featureKey).toList();

  static String featureDisplayName(String feature) {
    final matches = kDashboardModules.where((m) => m.featureKey == feature);
    return matches.isEmpty ? feature : matches.first.displayName;
  }

  void _showPermissionsDialog(BuildContext context, User user) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return _PermissionsDialog(
          user: user,
          blockableFeatures: blockableFeatures,
        );
      },
    );
  }

  bool _canEditRole(User currentUser, User targetUser) {
    if (currentUser.id == targetUser.id) return false;
    if (currentUser.correo == 'kus4587@gmail.com') {
      return true; // Super bypass para Seba
    }
    if (currentUser.role == UserRole.SuperAdmin) {
      // Un SuperAdmin no puede editar a otro SuperAdmin (excepto Seba)
      return targetUser.role != UserRole.SuperAdmin;
    }
    if (currentUser.role == UserRole.Admin) {
      // Un Admin no puede editar a otros Admins o SuperAdmins
      return targetUser.role != UserRole.SuperAdmin &&
          targetUser.role != UserRole.Admin;
    }
    return false;
  }

  List<UserRole> _getAvailableRoles(User currentUser) {
    if (currentUser.role == UserRole.SuperAdmin) return UserRole.values;
    if (currentUser.role == UserRole.Admin) {
      return [
        UserRole.Admin,
        UserRole.TecnicoVerificado,
        UserRole.TecnicoInvitado,
      ];
    }
    return [];
  }

  Widget _buildPopupMenu(
    BuildContext context,
    WidgetRef ref,
    User currentUser,
    User targetUser,
  ) {
    if (currentUser.id == targetUser.id) {
      return const SizedBox(width: 48);
    }

    final authNotifier = ref.read(authProvider.notifier);
    List<PopupMenuEntry<String>> menuItems = [];

    Future<bool> showConfirmDialog(String title, String content) async {
      return await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              backgroundColor: Colors.grey[900],
              title: Text(title, style: const TextStyle(color: Colors.white)),
              content: Text(
                content,
                style: const TextStyle(color: Colors.white70),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text(
                    'Cancelar',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text(
                    'Confirmar',
                    style: TextStyle(color: Colors.redAccent),
                  ),
                ),
              ],
            ),
          ) ??
          false;
    }

    if (currentUser.role == UserRole.Admin ||
        currentUser.role == UserRole.SuperAdmin) {
      menuItems.add(
        PopupMenuItem<String>(
          value: targetUser.isBanned ? 'unban' : 'ban',
          child: Text(
            targetUser.isBanned ? 'Quitar Baneo' : 'Banear Permanente',
            style: TextStyle(
              color: targetUser.isBanned ? Colors.green : Colors.red,
            ),
          ),
        ),
      );
      menuItems.add(
        PopupMenuItem<String>(
          value: targetUser.isDeleted ? 'untrash' : 'trash',
          child: Text(targetUser.isDeleted ? 'Restaurar' : 'Enviar a Papelera'),
        ),
      );
      menuItems.add(
        const PopupMenuItem<String>(
          value: 'edit_permissions',
          child: Text('Editar Permisos'),
        ),
      );
    }

    if (menuItems.isEmpty) {
      return const SizedBox(width: 48);
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (targetUser.isBanned &&
            (currentUser.role == UserRole.Admin ||
                currentUser.role == UserRole.SuperAdmin))
          TextButton.icon(
            icon: const Icon(Icons.check_circle_outline, color: Colors.green),
            label: const Text(
              'Desbanear',
              style: TextStyle(color: Colors.green),
            ),
            onPressed: () async {
              final confirm = await showConfirmDialog(
                'Desbanear Usuario',
                '¿Estás seguro de que quieres quitar el baneo a este usuario?',
              );
              if (confirm) {
                try {
                  await authNotifier.banUser(targetUser.id, false);
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text('Error: $e')));
                  }
                }
              }
            },
          ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert, color: Colors.white70),
          onSelected: (String value) async {
            final messenger = ScaffoldMessenger.of(context);
            try {
              switch (value) {
                case 'ban':
                  final confirm = await showConfirmDialog(
                    'Banear Usuario',
                    '¿Estás seguro de que deseas banear permanentemente a este usuario?',
                  );
                  if (confirm) {
                    await authNotifier.banUser(targetUser.id, true);
                  }
                  break;
                case 'unban':
                  final confirm = await showConfirmDialog(
                    'Desbanear Usuario',
                    '¿Estás seguro de que quieres quitar el baneo a este usuario?',
                  );
                  if (confirm) {
                    await authNotifier.banUser(targetUser.id, false);
                  }
                  break;
                case 'trash':
                  final confirm = await showConfirmDialog(
                    'Enviar a Papelera',
                    '¿Estás seguro de que deseas enviar a este usuario a la papelera?',
                  );
                  if (confirm) {
                    await authNotifier.trashUser(targetUser.id);
                    if (context.mounted) {
                      messenger.showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Usuario enviado a papelera.',
                            style: TextStyle(color: Colors.white),
                          ),
                          backgroundColor: Colors.amber,
                        ),
                      );
                    }
                  }
                  break;
                case 'untrash':
                  final confirm = await showConfirmDialog(
                    'Restaurar Usuario',
                    '¿Estás seguro de que deseas restaurar a este usuario de la papelera?',
                  );
                  if (confirm) {
                    await authNotifier.restoreUser(targetUser.id);
                    if (context.mounted) {
                      messenger.showSnackBar(
                        const SnackBar(
                          content: Text('Usuario restaurado exitosamente.'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  }
                  break;
                case 'edit_permissions':
                  _showPermissionsDialog(context, targetUser);
                  break;
              }
            } catch (e) {
              if (context.mounted) {
                messenger.showSnackBar(
                  SnackBar(
                    backgroundColor: Colors.redAccent,
                    content: Text(
                      'El servidor bloqueó la acción: ${e.toString().replaceAll('Exception: ', '').split('] ').last}',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                );
              }
            }
          },
          itemBuilder: (BuildContext context) => menuItems,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final authNotifier = ref.read(authProvider.notifier);
    final allUsersAsync = ref.watch(allUsersProvider);
    final currentUser = authState.valueOrNull;

    if (authState.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (currentUser == null) {
      return const Scaffold(body: Center(child: Text('Acceso no autorizado.')));
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: _isSearching
              ? Container(
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.greenAccent.withValues(alpha: 0.2),
                    ),
                  ),
                  child: TextField(
                    controller: _searchController,
                    autofocus: true,
                    style: const TextStyle(
                      color: Colors.white,
                      fontFamily: 'Courier',
                      fontSize: 14,
                    ),
                    decoration: InputDecoration(
                      hintText: 'BUSCAR USUARIO...',
                      hintStyle: const TextStyle(
                        color: Colors.white24,
                        fontSize: 12,
                      ),
                      border: InputBorder.none,
                      prefixIcon: const Icon(
                        Icons.search,
                        color: Colors.greenAccent,
                        size: 18,
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(
                                Icons.close_rounded,
                                color: Colors.white38,
                                size: 16,
                              ),
                              onPressed: () {
                                setState(() {
                                  _searchController.clear();
                                });
                              },
                            )
                          : null,
                    ),
                    onChanged: (val) => setState(() {}),
                  ),
                )
              : const Text(
                  'Admin',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Courier',
                  ),
                ),
          backgroundColor: Colors.grey[900],
          elevation: 0,
          actions: [
            IconButton(
              icon: Icon(
                _isSearching ? Icons.close : Icons.search,
                color: _isSearching ? Colors.redAccent : Colors.white70,
              ),
              onPressed: () {
                setState(() {
                  _isSearching = !_isSearching;
                  if (!_isSearching) _searchController.clear();
                });
              },
            ),
            PopupMenuButton<UserRole?>(
              icon: Icon(
                Icons.filter_list,
                color: _filterRole == null
                    ? Colors.white54
                    : Colors.greenAccent,
              ),
              tooltip: 'Filtrar Segmento',
              onSelected: (UserRole? role) {
                setState(() {
                  _filterRole = role;
                });
              },
              color: Colors.grey[900],
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: null,
                  child: Text(
                    'Todos los segmentos',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
                ...UserRole.values.map(
                  (role) => PopupMenuItem(
                    value: role,
                    child: Text(
                      role.displayName,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
                ),
              ],
            ),
            IconButton(
              icon: Icon(
                Icons.sensors,
                color: _filterConnected ? Colors.greenAccent : Colors.white24,
              ),
              tooltip: 'Filtrar Conectados',
              onPressed: () {
                setState(() {
                  _filterConnected = !_filterConnected;
                });
              },
            ),
            IconButton(
              icon: const Icon(
                Icons.delete_outline,
                color: Colors.orangeAccent,
              ),
              tooltip: 'Papelera',
              onPressed: () {
                Navigator.pushNamed(context, RecycleBinScreen.routeName);
              },
            ),
          ],
          bottom: const TabBar(
            indicatorColor: Colors.greenAccent,
            labelColor: Colors.greenAccent,
            unselectedLabelColor: Colors.white54,
            labelStyle: TextStyle(
              fontFamily: 'Courier',
              fontWeight: FontWeight.bold,
            ),
            tabs: [
              Tab(icon: Icon(Icons.people), text: 'USUARIOS'),
              Tab(icon: Icon(Icons.forum_outlined), text: 'SOLICITUDES'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildUsersTab(
              context,
              allUsersAsync,
              currentUser,
              authNotifier,
              ref,
            ),
            _buildRequestsTab(context, authNotifier, ref, currentUser),
          ],
        ),
      ),
    );
  }

  Widget _buildUsersTab(
    BuildContext context,
    AsyncValue<List<User>> allUsersAsync,
    User currentUser,
    dynamic authNotifier,
    WidgetRef ref,
  ) {
    return allUsersAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => Center(child: Text('Error: $err')),
      data: (users) {
        if (users.isEmpty) {
          return const Center(
            child: Text(
              'No hay usuarios registrados.',
              style: TextStyle(color: Colors.white54),
            ),
          );
        }

        final filteredUsers = users.where((u) {
          bool matchesRole = _filterRole == null || u.role == _filterRole;
          bool matchesConnected = true;
          if (_filterConnected) {
            if (u.lastActiveAt != null) {
              final diff = DateTime.now().difference(u.lastActiveAt!);
              matchesConnected = diff.inMinutes <= 10;
            } else {
              matchesConnected = false;
            }
          }
          bool matchesSearch = true;
          if (_searchController.text.isNotEmpty) {
            final query = _searchController.text.toLowerCase();
            final queryTokens = query
                .split(' ')
                .where((t) => t.isNotEmpty)
                .toList();

            final nombre = (u.nombre).toLowerCase();
            final apodo = (u.apodo ?? '').toLowerCase();
            final correo = (u.correo ?? '').toLowerCase();
            final celular = (u.celular ?? '').toLowerCase();
            final empresa = (u.empresa ?? '').toLowerCase();
            final area = (u.area ?? '').toLowerCase();
            final id = u.id.toLowerCase();

            matchesSearch = queryTokens.every((token) {
              return nombre.contains(token) ||
                  apodo.contains(token) ||
                  correo.contains(token) ||
                  celular.contains(token) ||
                  empresa.contains(token) ||
                  area.contains(token) ||
                  id.contains(token);
            });
          }

          return matchesRole && matchesConnected && matchesSearch;
        }).toList();

        filteredUsers.sort((a, b) {
          const sebaEmail = 'kus4587@gmail.com';
          if (a.correo == sebaEmail) return -1;
          if (b.correo == sebaEmail) return 1;

          if (a.role == UserRole.SuperAdmin && b.role != UserRole.SuperAdmin) {
            return -1;
          }
          if (b.role == UserRole.SuperAdmin && a.role != UserRole.SuperAdmin) {
            return 1;
          }

          if (a.role == UserRole.Admin && b.role != UserRole.Admin) return -1;
          if (b.role == UserRole.Admin && a.role != UserRole.Admin) return 1;

          final dateA = a.fechaDeIngreso ?? DateTime(2000);
          final dateB = b.fechaDeIngreso ?? DateTime(2000);
          return dateA.compareTo(dateB);
        });

        return ListView(
          children: [
            // Listado de Usuarios
            ...filteredUsers.map((user) {
              final isCurrentUser = currentUser.id == user.id;
              Color presenceColor = Colors.grey;
              String presenceMsg = 'Desconectado';

              if (user.lastActiveAt != null) {
                final diff = DateTime.now().difference(user.lastActiveAt!);
                if (diff.inMinutes <= 10) {
                  presenceColor = Colors.greenAccent;
                  presenceMsg = 'En línea';
                } else if (diff.inMinutes <= 30) {
                  presenceColor = Colors.yellowAccent;
                  presenceMsg = 'Ausente (10-30 min)';
                } else if (diff.inMinutes <= 60) {
                  presenceColor = Colors.redAccent;
                  presenceMsg = 'Inactivo (30-60 min)';
                } else {
                  presenceColor = Colors.grey;
                  presenceMsg = 'Desconectado (>1h)';
                }
              }

              return Stack(
                children: [
                  Card(
                    color: Colors.grey[850],
                    margin: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: isCurrentUser
                          ? const BorderSide(
                              color: Colors.greenAccent,
                              width: 1,
                            )
                          : BorderSide.none,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(10.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Tooltip(
                                message: presenceMsg,
                                child: Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: presenceColor,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: InkWell(
                                  onTap: () {
                                    if (currentUser.role ==
                                        UserRole.SuperAdmin) {
                                      Navigator.pushNamed(
                                        context,
                                        '/profile',
                                        arguments: user.id,
                                      );
                                    }
                                  },
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        user.nombre,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15,
                                          decoration: TextDecoration.underline,
                                        ),
                                      ),
                                      if (user.correo != null)
                                        Text(
                                          user.correo!,
                                          style: TextStyle(
                                            color: Colors.grey[400],
                                            fontSize: 12,
                                          ),
                                        ),
                                      Row(
                                        children: [
                                          const Icon(
                                            Icons.remove_red_eye,
                                            color: Colors.white24,
                                            size: 12,
                                          ),
                                          const SizedBox(width: 4),
                                          Text(
                                            '${user.visitCount} visitas',
                                            style: const TextStyle(
                                              color: Colors.white38,
                                              fontSize: 11,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              _buildPopupMenu(context, ref, currentUser, user),
                            ],
                          ),
                          _buildRoleSelector(ref, currentUser, user),
                          if (currentUser.role == UserRole.SuperAdmin ||
                              currentUser.role == UserRole.Admin) ...[
                            const Divider(color: Colors.white24, height: 15),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                _buildVaultSwitch(
                                  label: 'Bóveda λ',
                                  value: user.canAccessVaultLambda,
                                  onChanged: !_canEditRole(currentUser, user)
                                      ? null
                                      : (value) =>
                                            authNotifier.updateVaultAccess(
                                              userId: user.id,
                                              vault: 'lambda',
                                              hasAccess: value,
                                            ),
                                ),
                                _buildVaultSwitch(
                                  label: 'Bóveda 👽',
                                  value: user.canAccessVaultMartian,
                                  onChanged: !_canEditRole(currentUser, user)
                                      ? null
                                      : (value) =>
                                            authNotifier.updateVaultAccess(
                                              userId: user.id,
                                              vault: 'martian',
                                              hasAccess: value,
                                            ),
                                ),
                              ],
                            ),
                          ],
                          if (user.isBanned)
                            Container(
                              padding: const EdgeInsets.all(8),
                              margin: const EdgeInsets.only(top: 8),
                              decoration: BoxDecoration(
                                color: Colors.red.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Row(
                                children: [
                                  Icon(
                                    Icons.gavel,
                                    color: Colors.red,
                                    size: 16,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'USUARIO BANEADO',
                                    style: TextStyle(
                                      color: Colors.red,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (user.isDeleted)
                            Container(
                              margin: const EdgeInsets.only(top: 8),
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.grey.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Row(
                                children: [
                                  Icon(
                                    Icons.delete_outline,
                                    color: Colors.grey,
                                    size: 16,
                                  ),
                                  SizedBox(width: 8),
                                  Text(
                                    'EN PAPELERA',
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (user.isBanned)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: Container(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          color: Colors.red.withValues(alpha: 0.1),
                          child: Center(
                            child: Transform.rotate(
                              angle: -0.2,
                              child: Text(
                                'BANEADO',
                                style: TextStyle(
                                  color: Colors.red.withValues(alpha: 0.8),
                                  fontSize: 32,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 4,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (user.isDeleted && !user.isBanned)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: Container(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          color: Colors.black.withValues(alpha: 0.3),
                          child: Center(
                            child: Transform.rotate(
                              angle: -0.2,
                              child: Text(
                                'PAPELERA',
                                style: TextStyle(
                                  color: Colors.grey.withValues(alpha: 0.7),
                                  fontSize: 28,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 4,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            }),
          ],
        );
      },
    );
  }

  Widget _buildRequestsTab(
    BuildContext context,
    dynamic authNotifier,
    WidgetRef ref,
    User currentUser,
  ) {
    final adminService = ref.watch(adminServiceProvider);
    return StreamBuilder<List<AdminRequest>>(
      stream: adminService.getRequestsStream(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final requests =
            snapshot.data?.where((r) => !r.isResolved).toList() ?? [];

        if (requests.isEmpty) {
          return const Center(
            child: Text(
              'Bandeja limpia, comandante.',
              style: TextStyle(color: Colors.white54, fontFamily: 'Courier'),
            ),
          );
        }

        return ListView.builder(
          itemCount: requests.length,
          itemBuilder: (context, index) {
            final request = requests[index];
            final bool isAttendedByOther =
                request.attendedBy != null &&
                request.attendedBy != currentUser.id;
            final bool isAttendedByMe = request.attendedBy == currentUser.id;

            Color typeColor;
            switch (request.type) {
              case AdminRequestType.duda:
                typeColor = Colors.cyanAccent;
                break;
              case AdminRequestType.sugerencia:
                typeColor = Colors.greenAccent;
                break;
              case AdminRequestType.reclamo:
                typeColor = Colors.redAccent;
                break;
              case AdminRequestType.ascenso:
                typeColor = Colors.purpleAccent;
                break;
            }

            return Card(
              color: Colors.grey[900],
              margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              shape: RoundedRectangleBorder(
                side: BorderSide(
                  color: isAttendedByOther
                      ? Colors.white10
                      : typeColor.withValues(alpha: 0.5),
                  width: isAttendedByMe ? 2 : 1,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Stack(
                children: [
                  Opacity(
                    opacity: isAttendedByOther ? 0.4 : 1.0,
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: typeColor.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  request.type.displayName.toUpperCase(),
                                  style: TextStyle(
                                    color: typeColor,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 10,
                                    fontFamily: 'Courier',
                                  ),
                                ),
                              ),
                              Text(
                                timeago.format(request.createdAt, locale: 'es'),
                                style: const TextStyle(
                                  color: Colors.white24,
                                  fontSize: 10,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            request.subject,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'De: ${request.senderName}',
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 12,
                            ),
                          ),
                          const Divider(color: Colors.white10, height: 20),
                          Text(
                            request.body,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              if (isAttendedByMe)
                                TextButton(
                                  onPressed: () =>
                                      adminService.releaseRequest(request.id),
                                  child: const Text(
                                    'SOLTAR TEMA',
                                    style: TextStyle(color: Colors.grey),
                                  ),
                                ),
                              const SizedBox(width: 8),
                              if (request.type == AdminRequestType.ascenso) ...[
                                // Botones específicos para ASCENSO λ
                                ElevatedButton.icon(
                                  onPressed: isAttendedByOther
                                      ? null
                                      : () async {
                                          if (!isAttendedByMe) {
                                            await adminService.markAsAttending(
                                              request.id,
                                              currentUser.id,
                                              currentUser.nombre,
                                            );
                                          }
                                          if (context.mounted) {
                                            _showPromotionDialog(
                                              context,
                                              request,
                                              currentUser,
                                              true, // Aprobar
                                            );
                                          }
                                        },
                                  icon: const Icon(Icons.upgrade, size: 18),
                                  label: const Text('SUBIR RANGO'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.purpleAccent,
                                    foregroundColor: Colors.black,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                ElevatedButton.icon(
                                  onPressed: isAttendedByOther
                                      ? null
                                      : () async {
                                          if (!isAttendedByMe) {
                                            await adminService.markAsAttending(
                                              request.id,
                                              currentUser.id,
                                              currentUser.nombre,
                                            );
                                          }
                                          if (context.mounted) {
                                            _showPromotionDialog(
                                              context,
                                              request,
                                              currentUser,
                                              false, // Denegar
                                            );
                                          }
                                        },
                                  icon: const Icon(Icons.block, size: 18),
                                  label: const Text('DENEGAR'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.red[900],
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                              ] else
                                ElevatedButton.icon(
                                  onPressed: isAttendedByOther
                                      ? null
                                      : () async {
                                          if (!isAttendedByMe) {
                                            await adminService.markAsAttending(
                                              request.id,
                                              currentUser.id,
                                              currentUser.nombre,
                                            );
                                          }
                                          if (context.mounted) {
                                            _showResponseDialog(
                                              context,
                                              request,
                                              currentUser,
                                            );
                                          }
                                        },
                                  icon: const Icon(Icons.reply, size: 18),
                                  label: Text(
                                    isAttendedByMe ? 'RESPONDER' : 'ATENDER',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontFamily: 'Courier',
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: typeColor,
                                    foregroundColor: Colors.black,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (isAttendedByOther)
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.lock,
                                color: Colors.amber,
                                size: 30,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'BLOQUEADO POR:',
                                style: TextStyle(
                                  color: Colors.amber.withValues(alpha: 0.6),
                                  fontSize: 10,
                                  letterSpacing: 2,
                                  fontFamily: 'Courier',
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                (request.attendedByName?.toUpperCase() ??
                                    'ADMIN'),
                                style: const TextStyle(
                                  color: Colors.amber,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  fontFamily: 'Courier',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showResponseDialog(
    BuildContext context,
    AdminRequest request,
    User admin,
  ) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: Text(
          'RESPONDER A ${request.senderName.toUpperCase()}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontFamily: 'Courier',
          ),
        ),
        content: TextField(
          controller: controller,
          maxLines: 5,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Escribe tu respuesta técnica aquí...',
            hintStyle: TextStyle(color: Colors.white24),
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCELAR'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.isEmpty) return;
              await ref
                  .read(adminServiceProvider)
                  .resolveRequest(
                    request: request,
                    responseBody: controller.text,
                    adminId: admin.id,
                    adminName: admin.nombre,
                  );
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Respuesta enviada y tema cerrado.'),
                  ),
                );
              }
            },
            child: const Text('ENVIAR Y CERRAR'),
          ),
        ],
      ),
    );
  }

  void _showPromotionDialog(
    BuildContext context,
    AdminRequest request,
    User admin,
    bool approve,
  ) {
    final controller = TextEditingController();
    final actionName = approve ? 'APROBAR ASCENSO' : 'DENEGAR ASCENSO';
    final actionColor = approve ? Colors.orangeAccent : Colors.redAccent;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: Text(
          actionName,
          style: TextStyle(
            color: actionColor,
            fontSize: 14,
            fontFamily: 'Courier',
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Usuario: ${request.senderName}',
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 16),
            const Text(
              'Nota adicional (opcional):',
              style: TextStyle(color: Colors.white54, fontSize: 11),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              maxLines: 3,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: 'Ej: Cumple con los requisitos...',
                hintStyle: TextStyle(color: Colors.white24),
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCELAR'),
          ),
          ElevatedButton(
            onPressed: () async {
              await ref
                  .read(adminServiceProvider)
                  .handlePromotionRequest(
                    request: request,
                    approve: approve,
                    adminId: admin.id,
                    adminName: admin.nombre,
                    reason: controller.text.isNotEmpty ? controller.text : null,
                  );
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      approve
                          ? 'Usuario ascendido con éxito.'
                          : 'Solicitud denegada.',
                    ),
                    backgroundColor: approve ? Colors.green : Colors.red,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: actionColor),
            child: Text(
              approve ? 'CONFIRMAR ASCENSO' : 'CONFIRMAR DENEGACIÓN',
              style: const TextStyle(color: Colors.black),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoleSelector(WidgetRef ref, User currentUser, User targetUser) {
    final bool canEdit = _canEditRole(currentUser, targetUser);

    if (!canEdit) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Text(
          'Rol: ${targetUser.role.displayName}',
          style: TextStyle(color: Colors.grey[500], fontSize: 13),
        ),
      );
    }

    final availableRoles = _getAvailableRoles(currentUser);
    final authNotifier = ref.read(authProvider.notifier);

    // Si el usuario objetivo tiene un rol superior o igual al que podemos editar, mostramos solo texto.
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8.0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white24),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<UserRole>(
          value: availableRoles.contains(targetUser.role)
              ? targetUser.role
              : null,
          dropdownColor: Colors.grey[850],
          isDense: true,
          isExpanded: true,
          style: const TextStyle(color: Colors.white, fontSize: 13),
          icon: const Icon(Icons.arrow_drop_down, color: Colors.greenAccent),
          hint: Text(
            // Si el rol actual no está en la lista disponible (ej. Admin viendo Admin),
            // mostramos el nombre del rol actual como hint.
            availableRoles.contains(targetUser.role)
                ? targetUser.role.shortName
                : targetUser.role.displayName,
            style: const TextStyle(color: Colors.white),
          ),
          items: availableRoles.map((role) {
            return DropdownMenuItem(value: role, child: Text(role.displayName));
          }).toList(),
          onChanged: (UserRole? newRole) {
            if (newRole != null) {
              authNotifier.updateUserRole(targetUser.id, newRole);
            }
          },
        ),
      ),
    );
  }

  Widget _buildVaultSwitch({
    required String label,
    required bool value,
    required ValueChanged<bool>? onChanged,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        const SizedBox(width: 4),
        Transform.scale(
          scale: 0.8,
          child: Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: Colors.amber,
            activeTrackColor: Colors.amber.withValues(alpha: 0.5),
            inactiveThumbColor: Colors.grey,
            inactiveTrackColor: Colors.grey[700],
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ],
    );
  }
}

class _PermissionsDialog extends ConsumerWidget {
  final User user; // Usado como referencia inicial e ID
  final List<String> blockableFeatures;

  const _PermissionsDialog({
    required this.user,
    required this.blockableFeatures,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allUsersAsync = ref.watch(allUsersProvider);

    // Obtenemos la versión más reciente del usuario desde el stream global
    final latestUser = allUsersAsync.maybeWhen(
      data: (users) =>
          users.firstWhere((u) => u.id == user.id, orElse: () => user),
      orElse: () => user,
    );

    final authNotifier = ref.read(authProvider.notifier);
    final blockedFeatures = Set<String>.from(latestUser.blockedFeatures);

    return AlertDialog(
      backgroundColor: Colors.grey[850],
      title: Text(
        'Permisos para ${latestUser.nombre}',
        style: const TextStyle(color: Colors.white),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ...blockableFeatures.map((feature) {
              final isEnabled = !blockedFeatures.contains(feature);
              return SwitchListTile(
                title: Text(
                  _AdminPanelScreenState.featureDisplayName(feature),
                  style: const TextStyle(color: Colors.white70),
                ),
                value: isEnabled,
                onChanged: (bool value) {
                  authNotifier.toggleFeatureBlock(latestUser.id, feature);
                },
                activeThumbColor: Colors.greenAccent,
                activeTrackColor: Colors.greenAccent.withValues(alpha: 0.5),
              );
            }),
            const Divider(color: Colors.white24),
            SwitchListTile(
              title: const Text(
                'Restringir Mensajes',
                style: TextStyle(color: Colors.orangeAccent),
              ),
              subtitle: const Text(
                'El usuario no podrá enviar mensajes nuevos',
                style: TextStyle(color: Colors.grey, fontSize: 11),
              ),
              value: latestUser.isMessageRestricted,
              onChanged: (bool value) {
                authNotifier.toggleMessageRestriction(latestUser.id, value);
              },
              activeThumbColor: Colors.orangeAccent,
              activeTrackColor: Colors.orangeAccent.withValues(alpha: 0.5),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          child: const Text('Cerrar'),
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
      ],
    );
  }
}

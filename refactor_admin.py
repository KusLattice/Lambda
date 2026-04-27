import re

file_path = "lib/screens/admin_panel_screen.dart"
with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

# ADD IMPORT msg
if "message_model.dart" not in content:
    content = content.replace("import '../models/user_model.dart';", "import '../models/user_model.dart';\nimport '../models/message_model.dart';")

# PREPARE NEW BUILD METHOD
new_build = """  @override
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
      length: 3,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          title: const Text(
            'Terminal de Mando',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, fontFamily: 'Courier'),
          ),
          backgroundColor: Colors.grey[900],
          elevation: 0,
          actions: [
            PopupMenuButton<UserRole?>(
              icon: Icon(
                Icons.filter_list,
                color: _filterRole == null ? Colors.white54 : Colors.greenAccent,
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
                  child: Text('Todos los segmentos', style: TextStyle(color: Colors.white)),
                ),
                ...UserRole.values.map(
                  (role) => PopupMenuItem(
                    value: role,
                    child: Text(role.displayName, style: const TextStyle(color: Colors.white70)),
                  ),
                ),
              ],
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.orangeAccent),
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
            labelStyle: TextStyle(fontFamily: 'Courier', fontWeight: FontWeight.bold),
            tabs: [
              Tab(icon: Icon(Icons.people), text: 'USUARIOS'),
              Tab(icon: Icon(Icons.mail), text: 'SOLICITUDES'),
              Tab(icon: Icon(Icons.bar_chart), text: 'MÉTRICAS'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildUsersTab(context, allUsersAsync, currentUser, authNotifier, ref),
            _buildRequestsTab(context, authNotifier, ref, currentUser),
            _buildStatsTab(context, allUsersAsync),
          ],
        ),
      ),
    );
  }

  Widget _buildUsersTab(BuildContext context, AsyncValue<List<User>> allUsersAsync, User currentUser, dynamic authNotifier, WidgetRef ref) {
    return allUsersAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => Center(child: Text('Error: $err')),
      data: (users) {
        if (users.isEmpty) {
          return const Center(child: Text('No hay usuarios registrados.', style: TextStyle(color: Colors.white54)));
        }

        final filteredUsers = users.where((u) {
          if (_filterRole == null) return true;
          return u.role == _filterRole;
        }).toList();

        filteredUsers.sort((a, b) {
          const sebaEmail = 'kus4587@gmail.com';
          if (a.correo == sebaEmail) return -1;
          if (b.correo == sebaEmail) return 1;

          if (a.role == UserRole.SuperAdmin && b.role != UserRole.SuperAdmin) return -1;
          if (b.role == UserRole.SuperAdmin && a.role != UserRole.SuperAdmin) return 1;

          if (a.role == UserRole.Admin && b.role != UserRole.Admin) return -1;
          if (b.role == UserRole.Admin && a.role != UserRole.Admin) return 1;

          final dateA = a.fechaDeIngreso ?? DateTime(2000);
          final dateB = b.fechaDeIngreso ?? DateTime(2000);
          return dateA.compareTo(dateB);
        });

        if (filteredUsers.isEmpty) {
          return const Center(child: Text('No hay usuarios en este segmento.', style: TextStyle(color: Colors.white54)));
        }

        return ListView.builder(
          itemCount: filteredUsers.length,
          itemBuilder: (context, index) {
            final user = filteredUsers[index];
            final isCurrentUser = currentUser.id == user.id;

            Color presenceColor = Colors.grey;
            String presenceMsg = 'Desconectado';
            bool isOnline = false;

            if (user.lastActiveAt != null) {
              final diff = DateTime.now().difference(user.lastActiveAt!);
              if (diff.inMinutes <= 10) {
                presenceColor = Colors.greenAccent;
                presenceMsg = 'En línea';
                isOnline = true;
              } else if (diff.inMinutes <= 30) {
                presenceColor = Colors.yellowAccent;
                presenceMsg = 'Ausente (10-30 min)';
                isOnline = true;
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
                  margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  shape: RoundedRectangleBorder(
                    side: BorderSide(color: Colors.greenAccent.withOpacity(0.1), width: 1),
                    borderRadius: BorderRadius.circular(8),
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
                                  if (currentUser.role == UserRole.SuperAdmin) {
                                    Navigator.pushNamed(context, '/profile', arguments: user.id);
                                  }
                                },
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
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
                                        style: TextStyle(color: Colors.grey[400], fontSize: 12),
                                      ),
                                    Row(
                                      children: [
                                        const Icon(Icons.remove_red_eye, color: Colors.white24, size: 12),
                                        const SizedBox(width: 4),
                                        Text('${user.visitCount} visitas', style: const TextStyle(color: Colors.white38, fontSize: 11)),
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
                        if (currentUser.role == UserRole.SuperAdmin) ...[
                          const Divider(color: Colors.white24, height: 15),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _buildVaultSwitch(
                                label: 'Bóveda λ',
                                value: user.canAccessVaultLambda,
                                onChanged: isCurrentUser
                                    ? null
                                    : (value) => authNotifier.updateVaultAccess(userId: user.id, vault: 'lambda', hasAccess: value),
                              ),
                              _buildVaultSwitch(
                                label: 'Bóveda 👽',
                                value: user.canAccessVaultMartian,
                                onChanged: isCurrentUser
                                    ? null
                                    : (value) => authNotifier.updateVaultAccess(userId: user.id, vault: 'martian', hasAccess: value),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                if (user.isBanned)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        color: Colors.black.withOpacity(0.5),
                        child: Center(
                          child: Transform.rotate(
                            angle: -0.2,
                            child: Text(
                              'BANEADO',
                              style: TextStyle(
                                color: Colors.red.withOpacity(0.8),
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
                        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        color: Colors.black.withOpacity(0.3),
                        child: Center(
                          child: Transform.rotate(
                            angle: -0.2,
                            child: Text(
                              'PAPELERA',
                              style: TextStyle(
                                color: Colors.grey.withOpacity(0.7),
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
          },
        );
      },
    );
  }

  Widget _buildRequestsTab(BuildContext context, dynamic authNotifier, WidgetRef ref, User currentUser) {
    final stream = ref.watch(authProvider.notifier).getMessagesStream('inbox');
    return StreamBuilder<List<Message>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (snapshot.hasError) return Center(child: Text('Error: ${snapshot.error}'));

        final msgs = snapshot.data?.where((m) => m.subject.contains('Solicitud de Ascenso') && !m.labels.contains('trash_${currentUser.id}')).toList() ?? [];
        if (msgs.isEmpty) {
          return const Center(child: Text('Bandeja limpia, comandante.', style: TextStyle(color: Colors.white54, fontFamily: 'Courier')));
        }

        return ListView.builder(
          itemCount: msgs.length,
          itemBuilder: (context, index) {
            final msg = msgs[index];
            return Card(
              color: Colors.grey[900],
              margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              shape: RoundedRectangleBorder(
                side: BorderSide(color: Colors.greenAccent.withOpacity(0.5), width: 1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(msg.subject, style: const TextStyle(color: Colors.greenAccent, fontWeight: FontWeight.bold, fontFamily: 'Courier', fontSize: 16)),
                    const SizedBox(height: 8),
                    Text(msg.body, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton.icon(
                          icon: const Icon(Icons.delete, color: Colors.grey),
                          label: const Text('RECHAZAR', style: TextStyle(color: Colors.grey)),
                          onPressed: () async {
                             await ref.read(authProvider.notifier).moveMessageToTrash(msg.id, currentUser.id);
                             if (context.mounted) {
                               ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Solicitud rechazada/archivada.')));
                             }
                          },
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.check_circle, color: Colors.black),
                          label: const Text('APROBAR (ASCENDER)', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.greenAccent),
                          onPressed: () async {
                             try {
                               await authNotifier.updateUserRole(msg.senderId, UserRole.TecnicoVerificado);
                               await ref.read(authProvider.notifier).moveMessageToTrash(msg.id, currentUser.id);
                               if (context.mounted) {
                                 ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Técnico ascendido a Verificado.'), backgroundColor: Colors.green));
                               }
                             } catch (e) {
                               if (context.mounted) {
                                 ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
                               }
                             }
                          },
                        ),
                      ],
                    )
                  ],
                ),
              ),
            );
          }
        );
      }
    );
  }

  Widget _buildStatsTab(BuildContext context, AsyncValue<List<User>> allUsersAsync) {
    return allUsersAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, stack) => Center(child: Text('Error: $err')),
      data: (users) {
        int total = users.length;
        int verificados = users.where((u) => u.role == UserRole.TecnicoVerificado).length;
        int invitados = users.where((u) => u.role == UserRole.TecnicoInvitado).length;
        int admins = users.where((u) => u.role == UserRole.Admin || u.role == UserRole.SuperAdmin).length;
        int baneados = users.where((u) => u.isBanned).length;

        Widget buildStatCard(String title, int count, Color color) {
          return Card(
            color: Colors.black,
            shape: RoundedRectangleBorder(
              side: BorderSide(color: color.withOpacity(0.5), width: 1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
              child: Column(
                children: [
                  Text(title, style: TextStyle(color: color, fontFamily: 'Courier', fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  Text(count.toString(), style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          );
        }

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            buildStatCard('TOTAL USUARIOS', total, Colors.blueAccent),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: buildStatCard('VERIFICADOS', verificados, Colors.greenAccent)),
                const SizedBox(width: 10),
                Expanded(child: buildStatCard('INVITADOS', invitados, Colors.amber)),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: buildStatCard('ADMINS', admins, Colors.purpleAccent)),
                const SizedBox(width: 10),
                Expanded(child: buildStatCard('BANEADOS', baneados, Colors.redAccent)),
              ],
            ),
          ],
        );
      }
    );
  }
"""

pattern = r"(\s*@override\s*Widget build\(BuildContext context\) \{.*?)(\s*Widget _buildRoleSelector\(WidgetRef ref, User currentUser, User targetUser\) \{)"
match = re.search(pattern, content, re.DOTALL)
if match:
    old_build = match.group(1)
    content = content.replace(old_build, new_build + "\n\n")

    with open(file_path, "w", encoding="utf-8") as f:
        f.write(content)
    print("Replace successful")
else:
    print("Pattern not found")


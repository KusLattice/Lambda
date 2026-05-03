import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lambda_app/widgets/grid_background.dart';
import 'package:lambda_app/providers/stats_provider.dart';
import 'package:lambda_app/screens/admin_panel_screen.dart';
import 'package:lambda_app/screens/recycle_bin_screen.dart';
import 'package:lambda_app/screens/mercado_negro_screen.dart';
import 'package:lambda_app/screens/food_screen.dart';
import 'package:lambda_app/screens/hospedaje_screen.dart';
import 'package:lambda_app/screens/random_screen.dart';
import 'package:lambda_app/screens/tips_hacks_screen.dart';
import 'package:lambda_app/screens/la_nave_screen.dart';
import 'package:lambda_app/screens/map_screen.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:lambda_app/models/user_model.dart' as model;
import 'package:lambda_app/widgets/user_evolution_candlestick.dart';

class GlobalStatsScreen extends ConsumerStatefulWidget {
  static const String routeName = '/global_stats';

  const GlobalStatsScreen({super.key});

  @override
  ConsumerState<GlobalStatsScreen> createState() => _GlobalStatsScreenState();
}

class _GlobalStatsScreenState extends ConsumerState<GlobalStatsScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Chart data (Se mantienen por ser datos históricos no necesariamente reactivos en tiempo real)
  final Map<int, int> _usersByMonth = {};
  final List<model.User> _allUsers = [];
  final Map<String, int> _roleCounts = {};
  final Map<int, int> _peakHours = {};
  bool _isChartsLoading = true;
  
  // Weekly Ranking data
  final Map<String, int> _weeklyScores = {}; // userId -> score
  final Map<String, String> _userNames = {};  // userId -> apodo ?? nombre
  bool _isRankingLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHistoricalData();
    _loadWeeklyRanking();
  }

  Future<void> _loadHistoricalData() async {
    try {
      if (mounted) setState(() => _isChartsLoading = true);

      // Consultamos múltiples colecciones para tener una "Actividad Real"
      final results = await Future.wait([
        _db.collection('users').get(),
        _db.collection('market_items').get(),
        _db.collection('food_tracker').get(),
        _db.collection('lodging_tracker').get(),
        _db.collection('random_board').get(),
        _db.collection('hacks_vault').get(),
        _db.collection('nave_vault').get(),
      ]);

      final usersSnapshot = results[0];

      _usersByMonth.clear();
      _allUsers.clear();
      _roleCounts.clear();
      _peakHours.clear();

      // Procesar Usuarios (Ingresos y Roles)
      for (var doc in usersSnapshot.docs) {
        final userData = doc.data();
        final user = model.User.fromMap(userData, doc.id);
        _allUsers.add(user);

        final fechaIngreso = user.fechaDeIngreso;
        if (fechaIngreso != null) {
          final monthKey = fechaIngreso.year * 100 + fechaIngreso.month;
          _usersByMonth[monthKey] = (_usersByMonth[monthKey] ?? 0) + 1;
        }
        final roleShort = user.role.name;
        _roleCounts[roleShort] = (_roleCounts[roleShort] ?? 0) + 1;
      }

      // Procesar todas las actividades para el gráfico de horas pico
      for (var snapshot in results) {
        for (var doc in snapshot.docs) {
          final data = doc.data();
          // Buscamos cualquier campo que parezca un timestamp de creación
          final ts =
              (data['createdAt'] ?? data['timestamp'] ?? data['fechaDeIngreso'])
                  as Timestamp?;
          if (ts != null) {
            final hour = ts.toDate().hour;
            _peakHours[hour] = (_peakHours[hour] ?? 0) + 1;
          }
        }
      }

      if (mounted) setState(() => _isChartsLoading = false);
    } catch (e) {
      debugPrint('Error loading charts: $e');
      if (mounted) setState(() => _isChartsLoading = false);
    }
  }

  Future<void> _loadWeeklyRanking() async {
    try {
      if (mounted) setState(() => _isRankingLoading = true);
      
      final weekAgo = Timestamp.fromDate(
        DateTime.now().subtract(const Duration(days: 7))
      );
      
      final collections = [
        'lodging_tracker', 'food_tracker', 'market_items',
        'chambas', 'random_board', 'fiber_cut_reports'
      ];
      
      _weeklyScores.clear();
      _userNames.clear();
      
      for (final col in collections) {
        try {
          final snap = await _db.collection(col)
              .where('createdAt', isGreaterThan: weekAgo)
              .get();
              
          for (var doc in snap.docs) {
            final userId = doc.data()['userId'] as String?;
            if (userId != null) {
              _weeklyScores[userId] = (_weeklyScores[userId] ?? 0) + 1;
            }
          }
        } catch (e) {
          debugPrint('Error loading weekly ranking for $col: $e');
        }
      }
      
      // Si no hay actividad, detenemos aquí
      if (_weeklyScores.isEmpty) {
        if (mounted) setState(() => _isRankingLoading = false);
        return;
      }
      
      // Obtener nombres de los usuarios con actividad (Top 5 o más si es necesario)
      final activeUserIds = _weeklyScores.keys.toList();
      
      final sortedUserIds = _weeklyScores.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      
      final topIds = sortedUserIds.take(10).map((e) => e.key).toList();
      
      if (topIds.isNotEmpty) {
        final usersSnap = await _db.collection('users')
            .where(FieldPath.documentId, whereIn: topIds)
            .get();
            
        for (var doc in usersSnap.docs) {
          final userData = doc.data();
          final apodo = userData['apodo'] as String?;
          final nombre = userData['nombre'] as String? ?? 'Sin Nombre';
          _userNames[doc.id] = (apodo != null && apodo.isNotEmpty) ? apodo : nombre;
        }
      }
      
      if (mounted) setState(() => _isRankingLoading = false);
    } catch (e) {
      debugPrint('Error global ranking: $e');
      if (mounted) setState(() => _isRankingLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final statsAsync = ref.watch(statsProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text(
          'Base de Datos Lambda',
          style: TextStyle(
            fontFamily: 'Courier',
            color: Colors.amber,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.amber),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(statsProvider);
              _loadHistoricalData();
              _loadWeeklyRanking();
            },
          ),
        ],
      ),
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          const GridBackground(child: SizedBox.expand()),
          SafeArea(
            child: statsAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: Colors.amber),
              ),
              error: (err, stack) => Center(
                child: Text(
                  'Error: $err',
                  style: const TextStyle(color: Colors.red),
                ),
              ),
              data: (stats) => RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(statsProvider);
                  await Future.wait([
                    _loadHistoricalData(),
                    _loadWeeklyRanking(),
                  ]);
                },
                color: Colors.amber,
                backgroundColor: Colors.black,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _buildSectionHeader('👥 USUARIOS DEL SISTEMA'),
                    _buildStatRow(
                      'Totales Registrados',
                      stats.totalUsers,
                      Icons.people_alt,
                      Colors.white,
                      AdminPanelScreen.routeName,
                    ),
                    _buildStatRow(
                      'Visitas Totales',
                      stats.totalVisits,
                      Icons.visibility,
                      Colors.greenAccent,
                      '',
                    ),
                    _buildStatRow(
                      'En línea (última hora)',
                      stats.activeUsers,
                      Icons.online_prediction,
                      Colors.greenAccent,
                      AdminPanelScreen.routeName,
                    ),
                    _buildStatRow(
                      'Super Administradores',
                      stats.superAdminUsers,
                      Icons.security,
                      Colors.purpleAccent,
                      AdminPanelScreen.routeName,
                    ),
                    _buildStatRow(
                      'Administradores Locales',
                      stats.adminUsers,
                      Icons.shield,
                      Colors.deepPurpleAccent,
                      AdminPanelScreen.routeName,
                    ),
                    _buildStatRow(
                      'Usuarios Invitados',
                      stats.guestUsers,
                      Icons.person_outline,
                      Colors.grey,
                      AdminPanelScreen.routeName,
                    ),
                    _buildStatRow(
                      'Colegas Visibles Map',
                      stats.visibleUsers,
                      Icons.visibility,
                      Colors.cyanAccent,
                      MapScreen.routeName,
                    ),
                    _buildStatRow(
                      'Marcianos (La Nave)',
                      stats.marcianUsers,
                      Icons.catching_pokemon,
                      Colors.greenAccent,
                      AdminPanelScreen.routeName,
                    ),
                    _buildStatRow(
                      'Cuentas Castigadas',
                      stats.activeBans,
                      Icons.gavel,
                      Colors.redAccent,
                      AdminPanelScreen.routeName,
                    ),
                    _buildStatRow(
                      'Registros en Papelera',
                      stats.deletedUsers,
                      Icons.delete_sweep,
                      Colors.orange,
                      RecycleBinScreen.routeName,
                    ),
                    const SizedBox(height: 32),
                    _buildSectionHeader('📦 DATOS DE MÓDULOS'),
                    _buildStatRow(
                      'Bienes en Mercado Negro',
                      stats.marketPosts,
                      Icons.shopping_cart,
                      Colors.tealAccent,
                      MercadoNegroScreen.routeName,
                    ),
                    _buildStatRow(
                      'Aportes en Picás',
                      stats.foodPosts,
                      Icons.restaurant,
                      Colors.orangeAccent,
                      FoodScreen.routeName,
                    ),
                    _buildStatRow(
                      'Aportes en Hospedajes',
                      stats.lodgingPosts,
                      Icons.hotel,
                      Colors.indigoAccent,
                      HospedajeScreen.routeName,
                    ),
                    _buildStatRow(
                      'Hilos creados en Random',
                      stats.randomThreads,
                      Icons.casino,
                      Colors.pinkAccent,
                      RandomScreen.routeName,
                    ),
                    _buildStatRow(
                      'Secretos en La Libretita',
                      stats.hacks,
                      Icons.menu_book,
                      Colors.cyanAccent,
                      TipsHacksScreen.routeName,
                    ),
                    _buildStatRow(
                      'Mensajes en La Nave',
                      stats.navePosts,
                      Icons.forum,
                      Colors.greenAccent,
                      LaNaveScreen.routeName,
                    ),
                    const SizedBox(height: 32),
                    _buildSectionHeader('🏆 TOP CONTRIBUIDORES (SEMANAL)'),
                    _buildWeeklyRankingSection(),
                    const SizedBox(height: 32),
                    _buildSectionHeader('📊 ANÁLISIS VISUAL (PRO)'),
                    if (_isChartsLoading)
                      const Center(
                        child: CircularProgressIndicator(color: Colors.amber),
                      )
                    else ...[
                      _buildChartCard(
                        'Evolución de Usuarios (Velas Dinámicas)',
                        height: 350,
                        child: UserEvolutionCandlestick(users: _allUsers),
                      ),
                      const SizedBox(height: 16),
                      _buildChartCard(
                        'Distribución de Rangos',
                        height: 250,
                        child: _buildRolesPieChart(),
                      ),
                      const SizedBox(height: 16),
                      _buildChartCard(
                        'Actividad por Horas (Registro)',
                        height: 200,
                        child: _buildPeakHoursBarChart(),
                      ),
                    ],
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChartCard(
    String title, {
    required double height,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[900]?.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.amber,
              fontSize: 14,
              fontWeight: FontWeight.bold,
              fontFamily: 'Courier',
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(height: height, child: child),
        ],
      ),
    );
  }

  Widget _buildRolesPieChart() {
    if (_roleCounts.isEmpty) {
      return const Center(
        child: Text('Sin datos', style: TextStyle(color: Colors.grey)),
      );
    }

    final sections = _roleCounts.entries.map((e) {
      Color color;
      switch (e.key) {
        case 'SuperAdmin':
          color = Colors.purpleAccent;
          break;
        case 'Admin':
          color = Colors.deepPurpleAccent;
          break;
        case 'TecnicoVerificado':
          color = Colors.greenAccent;
          break;
        default:
          color = Colors.grey;
      }
      return PieChartSectionData(
        color: color,
        value: e.value.toDouble(),
        title: '${e.value}',
        radius: 50,
        titleStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      );
    }).toList();

    return Row(
      children: [
        Expanded(
          child: PieChart(
            PieChartData(
              sections: sections,
              centerSpaceRadius: 40,
              sectionsSpace: 2,
            ),
          ),
        ),
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: _roleCounts.entries.map((e) {
            Color color;
            switch (e.key) {
              case 'SuperAdmin':
                color = Colors.purpleAccent;
                break;
              case 'Admin':
                color = Colors.deepPurpleAccent;
                break;
              case 'TecnicoVerificado':
                color = Colors.greenAccent;
                break;
              default:
                color = Colors.grey;
            }
            return Row(
              children: [
                Container(width: 10, height: 10, color: color),
                const SizedBox(width: 4),
                Text(
                  e.key,
                  style: const TextStyle(color: Colors.white70, fontSize: 10),
                ),
              ],
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildPeakHoursBarChart() {
    if (_peakHours.isEmpty) {
      return const Center(
        child: Text('Sin datos', style: TextStyle(color: Colors.grey)),
      );
    }

    final barGroups = <BarChartGroupData>[];
    // Ahora procesamos todas las horas (24h) para máxima precisión
    for (int h = 0; h < 24; h++) {
      final val = _peakHours[h] ?? 0;
      barGroups.add(
        BarChartGroupData(
          x: h,
          barRods: [
            BarChartRodData(
              toY: val.toDouble(),
              gradient: LinearGradient(
                colors: [Colors.cyanAccent, Colors.cyanAccent.withValues(alpha: 0.3)],
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
              ),
              width: 6, // Un poco más delgadas para que quepan las 24
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(2),
              ),
              backDrawRodData: BackgroundBarChartRodData(
                show: true,
                toY:
                    (_peakHours.values.isEmpty
                            ? 0
                            : _peakHours.values.reduce((a, b) => a > b ? a : b))
                        .toDouble(),
                color: Colors.white.withValues(alpha: 0.05),
              ),
            ),
          ],
        ),
      );
    }

    return BarChart(
      BarChartData(
        gridData: const FlGridData(show: false),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final h = value.toInt();
                // Mostramos etiquetas cada 3 horas para no saturar
                if (h % 3 == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      '${h}h',
                      style: const TextStyle(
                        color: Colors.grey,
                        fontSize: 9,
                        fontFamily: 'Courier',
                      ),
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        barGroups: barGroups,
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => Colors.grey[900]!,
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              return BarTooltipItem(
                '${group.x}h: ${rod.toY.toInt()} acciones',
                const TextStyle(
                  color: Colors.cyanAccent,
                  fontWeight: FontWeight.bold,
                  fontSize: 10,
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildWeeklyRankingSection() {
    if (_isRankingLoading) {
      return Container(
        height: 100,
        alignment: Alignment.center,
        child: const CircularProgressIndicator(color: Colors.greenAccent),
      );
    }

    if (_weeklyScores.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white10),
        ),
        child: const Center(
          child: Text(
            'Sin actividad registrada esta semana.',
            style: TextStyle(color: Colors.white38, fontFamily: 'Courier'),
          ),
        ),
      );
    }

    final sortedEntries = _weeklyScores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    
    final top5 = sortedEntries.take(5).toList();

    return Column(
      children: top5.asMap().entries.map((entry) {
        final index = entry.key;
        final userId = entry.value.key;
        final score = entry.value.value;
        final displayName = _userNames[userId] ?? 'ID: ${userId.substring(0, 5)}...';
        
        Color rankColor;
        IconData rankIcon;
        double fontSize = 14;

        switch (index) {
          case 0:
            rankColor = Colors.amber;
            rankIcon = Icons.emoji_events;
            fontSize = 18;
            break;
          case 1:
            rankColor = const Color(0xFFC0C0C0); // Plata
            rankIcon = Icons.military_tech;
            fontSize = 16;
            break;
          case 2:
            rankColor = const Color(0xFFCD7F32); // Bronce
            rankIcon = Icons.military_tech_outlined;
            fontSize = 15;
            break;
          default:
            rankColor = Colors.white54;
            rankIcon = Icons.person_outline;
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: rankColor.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: rankColor.withValues(alpha: index < 3 ? 0.3 : 0.1),
              width: index == 0 ? 1.5 : 1.0,
            ),
          ),
          child: Row(
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  Icon(rankIcon, color: rankColor, size: 32),
                  if (index > 2)
                    Text(
                      '${index + 1}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName.toUpperCase(),
                      style: TextStyle(
                        color: rankColor,
                        fontSize: fontSize,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Courier',
                        letterSpacing: 1.1,
                      ),
                    ),
                    const Text(
                      'CONTRIBUIDOR ACTIVO',
                      style: TextStyle(color: Colors.white24, fontSize: 10),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    score.toString(),
                    style: TextStyle(
                      color: rankColor,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'Courier',
                    ),
                  ),
                  const Text(
                    'APORTES',
                    style: TextStyle(color: Colors.white38, fontSize: 9),
                  ),
                ],
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0, top: 8.0),
      child: Text(
        title,
        style: TextStyle(
          color: Colors.amber.withValues(alpha: 0.8),
          fontSize: 14,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
        ),
      ),
    );
  }

  Widget _buildStatRow(
    String label,
    int value,
    IconData icon,
    Color color,
    String route,
  ) {
    return InkWell(
      onTap: route.isEmpty
          ? null
          : () {
              Navigator.pushNamed(context, route);
            },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.grey[900]?.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(color: Colors.white70, fontSize: 15),
              ),
            ),
            Text(
              value.toString().padLeft(4, '0'),
              style: TextStyle(
                color: color,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                fontFamily: 'Courier',
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right, color: Colors.white24, size: 16),
          ],
        ),
      ),
    );
  }
}

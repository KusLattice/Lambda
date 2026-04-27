import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:lambda_app/models/user_model.dart';
import 'package:lambda_app/config/modules_config.dart';
import 'package:lambda_app/models/contribution_item.dart';
import 'package:lambda_app/services/mis_aportes_service.dart';
import 'package:lambda_app/screens/food_screen.dart';
import 'package:lambda_app/screens/hospedaje_screen.dart';
import 'package:lambda_app/screens/mercado_negro_screen.dart';
import 'package:lambda_app/screens/tips_hacks_screen.dart';
import 'package:lambda_app/screens/la_nave_screen.dart';
import 'package:lambda_app/screens/fiber_cut_screen.dart';
import 'package:lambda_app/screens/chambas_screen.dart';

/// Widget reutilizable que muestra una lista cronológica de aportes de un
/// usuario, con filtro por tipo de sección.
///
/// Usado tanto en [MisAportesScreen] (vista propia del drawer) como en
/// [ProfileScreen] para la sección admin cuando se visualiza a otro usuario.
class UserContributionsList extends StatefulWidget {
  final User user;

  /// Opcional: título de sección si se embebe dentro de otra pantalla.
  final String? sectionTitle;

  const UserContributionsList({
    super.key,
    required this.user,
    this.sectionTitle,
  });

  @override
  State<UserContributionsList> createState() => _UserContributionsListState();
}

class _UserContributionsListState extends State<UserContributionsList> {
  static const _service = MisAportesService();

  /// `null` significa "Todos" — sin filtro activo.
  ContributionType? _activeFilter;

  late final Future<List<ContributionItem>> _future;

  @override
  void initState() {
    super.initState();
    _future = _service.fetchContributions(widget.user);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.sectionTitle != null) _buildSectionHeader(),
        _buildFilterDropdown(),
        FutureBuilder<List<ContributionItem>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: CircularProgressIndicator(color: Colors.tealAccent),
                ),
              );
            }

            if (snapshot.hasError) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Error al cargar aportes: ${snapshot.error}',
                  style: const TextStyle(color: Colors.redAccent),
                ),
              );
            }

            final all = snapshot.data ?? [];
            final displayed = _activeFilter == null
                ? all
                : all.where((item) => item.type == _activeFilter).toList();

            if (displayed.isEmpty) {
              return _buildEmptyState();
            }

            return _buildList(displayed);
          },
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Sub-widgets
  // ---------------------------------------------------------------------------

  Widget _buildSectionHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
      child: Row(
        children: [
          const Icon(
            Icons.list_alt_rounded,
            color: Colors.tealAccent,
            size: 20,
          ),
          const SizedBox(width: 8),
          Text(
            widget.sectionTitle!,
            style: const TextStyle(
              color: Colors.tealAccent,
              fontSize: 16,
              fontWeight: FontWeight.bold,
              fontFamily: 'Courier',
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterDropdown() {
    final availableTypes = ContributionType.values.where((type) {
      // Determinamos a qué llave de feature corresponde cada ContributionType
      switch (type) {
        case ContributionType.picaFood:
          return _hasAccess('comida_access');
        case ContributionType.hospedaje:
          return _hasAccess('hospedaje_access');
        case ContributionType.mercado:
          return _hasAccess('mercado_negro_access');
        case ContributionType.truco:
          return widget.user.canAccessVaultLambda;
        case ContributionType.laNave:
          return !widget.user.blockedFeatures.contains('nave_access');
        case ContributionType.falla:
          return _hasAccess('fiber_cut_access');
        case ContributionType.chamba:
          return _hasAccess('chambas_access');
      }
    }).toList();

    // Si no tiene acceso a nada distinto (e.g. bloqueado de todo), no mostramos filtro
    if (availableTypes.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          const Icon(
            Icons.filter_list_rounded,
            color: Colors.tealAccent,
            size: 18,
          ),
          const SizedBox(width: 8),
          Theme(
            data: Theme.of(context).copyWith(canvasColor: Colors.grey[900]),
            child: DropdownButton<ContributionType?>(
              value: _activeFilter,
              icon: const Icon(Icons.arrow_drop_down, color: Colors.tealAccent),
              underline: const SizedBox(),
              style: const TextStyle(
                color: Colors.white,
                fontFamily: 'Courier',
                fontWeight: FontWeight.bold,
              ),
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('TODAS LAS SECCIONES'),
                ),
                ...availableTypes.map(
                  (type) => DropdownMenuItem(
                    value: type,
                    child: Text(
                      type.displayName.toUpperCase(),
                      style: TextStyle(color: type.color),
                    ),
                  ),
                ),
              ],
              onChanged: (newFilter) {
                setState(() => _activeFilter = newFilter);
              },
            ),
          ),
        ],
      ),
    );
  }

  bool _hasAccess(String featureKey) {
    if (widget.user.blockedFeatures.contains(featureKey)) return false;
    try {
      final module = kDashboardModules.firstWhere(
        (m) => m.featureKey == featureKey,
      );
      if (module.roleCheck != null && !module.roleCheck!(widget.user)) {
        return false;
      }
      return true;
    } catch (_) {
      return true;
    }
  }

  Widget _buildList(List<ContributionItem> items) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      itemBuilder: (context, index) => _ContributionTile(item: items[index]),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _activeFilter?.icon ?? Icons.inbox_outlined,
              size: 56,
              color: Colors.white12,
            ),
            const SizedBox(height: 12),
            Text(
              _activeFilter == null
                  ? 'Sin aportes aún.\n¡Hora de publicar algo!'
                  : 'Sin aportes en "${_activeFilter!.displayName}".',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white38,
                fontFamily: 'Courier',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Widgets privados del archivo
// ---------------------------------------------------------------------------

class _ContributionTile extends StatelessWidget {
  final ContributionItem item;

  const _ContributionTile({required this.item});

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('dd/MM/yyyy HH:mm').format(item.createdAt);

    return Card(
      color: (Colors.grey[900] ?? Colors.grey).withAlpha(217),
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 0),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: item.type.color.withAlpha(64)),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: item.type.color.withAlpha(31),
          child: Icon(item.type.icon, color: item.type.color, size: 20),
        ),
        title: Text(
          item.title,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w500,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          item.subtitle.isNotEmpty ? item.subtitle : item.type.displayName,
          style: const TextStyle(color: Colors.white54, fontSize: 12),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Text(
          dateStr,
          style: const TextStyle(color: Colors.white38, fontSize: 10),
        ),
        onTap: () {
          final String routeName;
          switch (item.type) {
            case ContributionType.picaFood:
              routeName = FoodScreen.routeName;
              break;
            case ContributionType.hospedaje:
              routeName = HospedajeScreen.routeName;
              break;
            case ContributionType.mercado:
              routeName = MercadoNegroScreen.routeName;
              break;
            case ContributionType.truco:
              routeName = TipsHacksScreen.routeName;
              break;
            case ContributionType.laNave:
              routeName = LaNaveScreen.routeName;
              break;
            case ContributionType.falla:
              routeName = FiberCutScreen.routeName;
              break;
            case ContributionType.chamba:
              routeName = ChambasScreen.routeName;
              break;
          }

          Navigator.pushNamed(context, routeName, arguments: item.sourceId);
        },
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError();
});

// Este mapa contiene las posiciones iniciales y por defecto de los módulos.
// La clave es el título del módulo, que usaremos como ID único.
final Map<String, Offset> _initialModulePositions = {
  'Brújula': const Offset(20, 20),
  'Mercado Negro': const Offset(160, 20),
  'Hospedaje': const Offset(20, 160),
  'Picás': const Offset(160, 160),
  'Random': const Offset(20, 300),
  'Mapa': const Offset(160, 300),
  'Chambas': const Offset(20, 440),
  'Fallas': const Offset(160, 440),
};

// StateNotifier para gestionar el estado del mapa de posiciones.
class DashboardModulesNotifier extends StateNotifier<Map<String, Offset>> {
  final SharedPreferences _prefs;
  static const String _prefsKeyPrefix = 'module_position_';

  DashboardModulesNotifier(this._prefs) : super(_initialModulePositions) {
    _loadPositions();
  }

  void _loadPositions() {
    final Map<String, Offset> loadedPositions = Map.from(state);
    bool hasChanges = false;

    for (final moduleId in _initialModulePositions.keys) {
      final dx = _prefs.getDouble('$_prefsKeyPrefix${moduleId}_dx');
      final dy = _prefs.getDouble('$_prefsKeyPrefix${moduleId}_dy');

      if (dx != null && dy != null) {
        loadedPositions[moduleId] = Offset(dx, dy);
        hasChanges = true;
      }
    }

    if (hasChanges) {
      state = loadedPositions;
    }
  }

  /// Actualiza la posición de un módulo específico.
  void updatePosition(String moduleId, Offset newPosition) {
    state = {...state, moduleId: newPosition};
    _prefs.setDouble('$_prefsKeyPrefix${moduleId}_dx', newPosition.dx);
    _prefs.setDouble('$_prefsKeyPrefix${moduleId}_dy', newPosition.dy);
  }

  /// Restablece las posiciones de todos los módulos a sus valores por defecto.
  void resetPositions() {
    state = _initialModulePositions;
    for (final moduleId in _initialModulePositions.keys) {
      _prefs.remove('$_prefsKeyPrefix${moduleId}_dx');
      _prefs.remove('$_prefsKeyPrefix${moduleId}_dy');
    }
  }
}

// El provider que expondremos a la UI.
final dashboardModulesProvider =
    StateNotifierProvider<DashboardModulesNotifier, Map<String, Offset>>((ref) {
      final prefs = ref.watch(sharedPreferencesProvider);
      return DashboardModulesNotifier(prefs);
    });

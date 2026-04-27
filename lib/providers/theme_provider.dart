import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------
// Definición de temas Lambda
// ---------------------------------------------------------------------------

class LambdaTheme {
  final String id;
  final String name;
  final String emoji;
  final Color accent;
  final Color secondaryAccent;
  final Color background;
  final Color surface;
  final Color onSurface;
  final Color cardColor;
  final String description;
  final List<Color>? backgroundGradient;
  final String? backgroundImageAsset;

  const LambdaTheme({
    required this.id,
    required this.name,
    required this.emoji,
    required this.accent,
    required this.secondaryAccent,
    required this.background,
    required this.surface,
    required this.onSurface,
    required this.cardColor,
    required this.description,
    this.backgroundGradient,
    this.backgroundImageAsset,
  });

  ThemeData toThemeData() {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      primaryColor: accent,
      colorScheme: ColorScheme.dark(
        primary: accent,
        secondary: accent,
        surface: surface,
        onSurface: onSurface,
        onPrimary: background,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: accent,
        titleTextStyle: TextStyle(
          color: accent,
          fontFamily: 'Courier',
          fontWeight: FontWeight.bold,
          fontSize: 18,
          letterSpacing: 2,
        ),
        iconTheme: IconThemeData(color: accent),
        elevation: 0,
      ),
      cardColor: cardColor,
      dividerColor: onSurface.withOpacity(0.1),
      textTheme: TextTheme(
        bodyLarge: TextStyle(color: onSurface),
        bodyMedium: TextStyle(color: onSurface.withOpacity(0.8)),
        bodySmall: TextStyle(color: onSurface.withOpacity(0.6)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: background,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        hintStyle: TextStyle(color: onSurface.withOpacity(0.4)),
        labelStyle: TextStyle(color: accent),
        focusedBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: accent),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: accent,
        foregroundColor: background,
      ),
      iconTheme: IconThemeData(color: onSurface.withOpacity(0.7)),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? accent : Colors.grey,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) =>
              s.contains(WidgetState.selected)
                  ? accent.withOpacity(0.4)
                  : Colors.grey.withOpacity(0.3),
        ),
      ),
      drawerTheme: DrawerThemeData(backgroundColor: background),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Catálogo de temas
// ---------------------------------------------------------------------------

const List<LambdaTheme> kLambdaThemes = [
  LambdaTheme(
    id: 'lambda_black',
    name: 'Lambda Core',
    emoji: '💚',
    accent: Color(0xFF00FF9C),
    secondaryAccent: Color(0xFF00FF9C),
    background: Color(0xFF080808),
    surface: Color(0xFF121212),
    onSurface: Color(0xFFF0F0F0),
    cardColor: Color(0xFF111111),
    description: 'Predeterminado. Terminal oscura y verde radioactivo.',
  ),
  LambdaTheme(
    id: 'sincronia',
    name: 'Conexión Estable',
    emoji: '💎',
    accent: Color(0xFF00D1FF),
    secondaryAccent: Color(0xFF4D80FF),
    background: Color(0xFF050B18),
    surface: Color(0xFF0A162C),
    onSurface: Color(0xFFE0F7FF),
    cardColor: Color(0xFF081224),
    description: 'Visibilidad total y señal sin interferencias.',
    backgroundGradient: [Color(0xFF050B18), Color(0xFF0A1E45), Color(0xFF050B18)],
    backgroundImageAsset: 'assets/images/themes/sincronia.png',
  ),
  LambdaTheme(
    id: 'noche_azul',
    name: 'Modo Nocturno',
    emoji: '🔵',
    accent: Color(0xFF4D9FFF),
    secondaryAccent: Color(0xFF1A56FF),
    background: Color(0xFF05080F),
    surface: Color(0xFF0D1526),
    onSurface: Color(0xFFCFE4FF),
    cardColor: Color(0xFF0A1220),
    description: 'Relajante y profundo para turnos de noche.',
    backgroundGradient: [Color(0xFF05080F), Color(0xFF0D1C38), Color(0xFF05080F)],
    backgroundImageAsset: 'assets/images/themes/noche_azul.png',
  ),
  LambdaTheme(
    id: 'rojo_operacion',
    name: 'Alerta Roja',
    emoji: '🔴',
    accent: Color(0xFFFF4444),
    secondaryAccent: Color(0xFFFF8800),
    background: Color(0xFF0A0000),
    surface: Color(0xFF1A0505),
    onSurface: Color(0xFFFFD0D0),
    cardColor: Color(0xFF140303),
    description: 'Diseño crítico para fallas graves en terreno.',
    backgroundGradient: [Color(0xFF0A0000), Color(0xFF240000), Color(0xFF0A0000)],
    backgroundImageAsset: 'assets/images/themes/alerta_roja.png',
  ),
  LambdaTheme(
    id: 'sunset_orange',
    name: 'Horizonte Cobre',
    emoji: '🌅',
    accent: Color(0xFFFF8C00),
    secondaryAccent: Color(0xFFFFD700),
    background: Color(0xFF0A0500),
    surface: Color(0xFF1A0E00),
    onSurface: Color(0xFFFFE0B0),
    cardColor: Color(0xFF140900),
    description: 'Tonos cálidos para enlaces de microondas.',
    backgroundGradient: [Color(0xFF0A0500), Color(0xFF291400), Color(0xFF0A0500)],
    backgroundImageAsset: 'assets/images/themes/sunset.png',
  ),
  LambdaTheme(
    id: 'girl_pink',
    name: 'Lambda Girl',
    emoji: '💅',
    accent: Color(0xFFFF69B4),
    secondaryAccent: Color(0xFFD800FF),
    background: Color(0xFF1A0A12),
    surface: Color(0xFF28101E),
    onSurface: Color(0xFFFFD6EC),
    cardColor: Color(0xFF1F0D18),
    description: 'Estilo sutil y armónico con acentos rosados.',
    backgroundGradient: [Color(0xFF1A0A12), Color(0xFF381428), Color(0xFF1A0A12)],
    backgroundImageAsset: 'assets/images/themes/aurora_pink.png',
  ),
  LambdaTheme(
    id: 'cyber_magenta',
    name: 'Neon Queen',
    emoji: '💗',
    accent: Color(0xFFFF2D78),
    secondaryAccent: Color(0xFFA500FF),
    background: Color(0xFF0F0008),
    surface: Color(0xFF1F000F),
    onSurface: Color(0xFFFFB3D4),
    cardColor: Color(0xFF18000A),
    description: 'Neón intenso para técnicas con estilo.',
    backgroundGradient: [Color(0xFF0F0008), Color(0xFF2A0014), Color(0xFF0F0008)],
    backgroundImageAsset: 'assets/images/themes/cyber_magenta.png',
  ),
];

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

const _kThemePrefKey = 'lambda_theme_id';

class ThemeNotifier extends StateNotifier<LambdaTheme> {
  ThemeNotifier() : super(kLambdaThemes.first) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final savedId = prefs.getString(_kThemePrefKey);
    if (savedId != null) {
      final found = kLambdaThemes.where((t) => t.id == savedId);
      if (found.isNotEmpty) state = found.first;
    }
  }

  Future<void> setTheme(LambdaTheme theme) async {
    state = theme;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kThemePrefKey, theme.id);
  }
}

final themeProvider = StateNotifierProvider<ThemeNotifier, LambdaTheme>(
  (ref) => ThemeNotifier(),
);

// ---------------------------------------------------------------------------
// FAB de cambio rápido de tema – visibilidad persistida
// ---------------------------------------------------------------------------

const _kFabVisibleKey = 'theme_fab_visible';

class ThemeFabNotifier extends StateNotifier<bool> {
  ThemeFabNotifier() : super(false) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool(_kFabVisibleKey) ?? false;
  }

  Future<void> setVisible(bool value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kFabVisibleKey, value);
  }
}

final themeFabVisibleProvider = StateNotifierProvider<ThemeFabNotifier, bool>(
  (ref) => ThemeFabNotifier(),
);

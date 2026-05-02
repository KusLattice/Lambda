import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lambda_app/config/app_config.dart';
import 'package:lambda_app/providers/auth_provider.dart';
import 'package:lambda_app/providers/theme_provider.dart';
import 'package:lambda_app/providers/dashboard_providers.dart';
import 'package:lambda_app/screens/about_screen.dart';
import 'package:lambda_app/screens/dashboard_screen.dart';
import 'package:lambda_app/screens/map_screen.dart';
import 'package:lambda_app/screens/profile_screen.dart';
import 'package:lambda_app/screens/tips_hacks_screen.dart';
import 'package:lambda_app/screens/create_hack_screen.dart';
import 'package:lambda_app/screens/admin_panel_screen.dart';
import 'package:lambda_app/screens/recycle_bin_screen.dart';
import 'package:lambda_app/screens/food_screen.dart';
import 'package:lambda_app/screens/create_food_post_screen.dart';
import 'package:lambda_app/screens/hospedaje_screen.dart';
import 'package:lambda_app/screens/create_lodging_post_screen.dart';
import 'package:lambda_app/screens/login_screen.dart';
import 'package:lambda_app/screens/mercado_negro_screen.dart';
import 'package:lambda_app/screens/random_screen.dart';
import 'package:lambda_app/screens/create_market_item_screen.dart';
import 'package:lambda_app/screens/global_stats_screen.dart';
import 'package:lambda_app/screens/la_nave_screen.dart';
import 'package:lambda_app/screens/create_nave_post_screen.dart';
import 'package:lambda_app/models/nave_post.dart';
import 'package:lambda_app/screens/mail_screen.dart';
import 'package:lambda_app/screens/public_profile_screen.dart';
import 'package:lambda_app/screens/chambas_screen.dart';
import 'package:lambda_app/screens/semantic_search_screen.dart';
import 'package:lambda_app/screens/fiber_cut_screen.dart';
import 'package:lambda_app/screens/create_fiber_cut_screen.dart';
import 'package:lambda_app/screens/chat_conversation_screen.dart';
import 'package:lambda_app/screens/mis_aportes_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';
import 'package:fvp/fvp.dart' as fvp;

Future<void> main() async {
  debugPrint('>>> MAIN: Initializing...');
  WidgetsFlutterBinding.ensureInitialized();
  debugPrint('>>> MAIN: WidgetsFlutterBinding initialized.');

  // Registramos fvp como el backend de video_player.
  try {
    debugPrint('>>> MAIN: Registering fvp...');
    fvp.registerWith();
    debugPrint('>>> MAIN: fvp registered successfully.');
  } catch (e) {
    debugPrint('>>> MAIN: Error registering fvp: $e');
  }

  try {
    debugPrint('>>> MAIN: Initializing Firebase...');
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
    debugPrint('>>> MAIN: Firebase initialized.');
  } catch (e) {
    debugPrint('>>> MAIN: Firebase initialization error: $e');
  }

  AppConfig.validate();
  debugPrint('>>> MAIN: Config validated. Running app...');
  final sharedPrefs = await SharedPreferences.getInstance();
  runApp(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(sharedPrefs)],
      child: const LambdaApp(),
    ),
  );
}

/// Usamos ConsumerWidget para que LambdaApp observe directamente [authProvider].
/// Esto evita depender del stream [authStateChanges()] de Firebase, que en Windows
/// tiene un bug de threading que impide que los eventos lleguen a Flutter.
class LambdaApp extends ConsumerStatefulWidget {
  const LambdaApp({super.key});

  @override
  ConsumerState<LambdaApp> createState() => _LambdaAppState();
}

class _LambdaAppState extends ConsumerState<LambdaApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(authProvider.notifier).updatePresence(isOnline: true);
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      ref.read(authProvider.notifier).updatePresence(isOnline: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authAsync = ref.watch(authProvider);
    final lambdaTheme = ref.watch(themeProvider);

    return MaterialApp(
      title: 'Lambda App',
      debugShowCheckedModeBanner: false,
      theme: lambdaTheme.toThemeData(),
      home: authAsync.when(
        // Cargando: spinner verde mientras se resuelve el estado inicial.
        loading: () => const Scaffold(
          body: Center(
            child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.greenAccent),
            ),
          ),
        ),
        // Error crítico: mostrar mensaje (ej. Firestore sin permisos).
        error: (error, _) => Scaffold(
          body: Center(
            child: Text(
              'Error crítico de inicio:\n$error',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ),
        // Datos: si hay usuario → Dashboard, si no → Login.
        data: (user) =>
            user != null ? const MainDashboard() : const LoginScreen(),
      ),
      routes: {
        ProfileScreen.routeName: (context) => const ProfileScreen(),
        MapScreen.routeName: (context) => const MapScreen(),
        TipsHacksScreen.routeName: (context) => const TipsHacksScreen(),
        CreateHackScreen.routeName: (context) => const CreateHackScreen(),
        AboutPage.routeName: (context) => const AboutPage(),
        MainDashboard.routeName: (context) => const MainDashboard(),
        LoginScreen.routeName: (context) => const LoginScreen(),
        AdminPanelScreen.routeName: (context) => const AdminPanelScreen(),
        RecycleBinScreen.routeName: (context) => const RecycleBinScreen(),
        MercadoNegroScreen.routeName: (context) => const MercadoNegroScreen(),
        CreateMarketItemScreen.routeName: (context) =>
            const CreateMarketItemScreen(),
        HospedajeScreen.routeName: (context) => const HospedajeScreen(),
        CreateLodgingPostScreen.routeName: (context) =>
            const CreateLodgingPostScreen(),
        FoodScreen.routeName: (context) => const FoodScreen(),
        CreateFoodPostScreen.routeName: (context) =>
            const CreateFoodPostScreen(),
        RandomScreen.routeName: (context) => const RandomScreen(),
        GlobalStatsScreen.routeName: (context) => const GlobalStatsScreen(),
        LaNaveScreen.routeName: (context) => const LaNaveScreen(),
        CreateNavePostScreen.routeName: (context) {
          final args = ModalRoute.of(context)!.settings.arguments;
          if (args is NavePost) {
            return CreateNavePostScreen(
              section: args.section,
              initialPost: args,
            );
          }
          // Si no es un post, asumimos que es el string de la sección (comportamiento original)
          return CreateNavePostScreen(section: args as String? ?? 'Foro');
        },
        MailScreen.routeName: (context) => const MailScreen(),
        MisAportesScreen.routeName: (context) => const MisAportesScreen(),
        PublicProfileScreen.routeName: (context) {
          final userId = ModalRoute.of(context)!.settings.arguments as String;
          return PublicProfileScreen(userId: userId);
        },
        '/chambas': (context) => const ChambasScreen(),
        '/semantic-search': (context) => const SemanticSearchScreen(),
        FiberCutScreen.routeName: (context) => const FiberCutScreen(),
        CreateFiberCutScreen.routeName: (context) =>
            const CreateFiberCutScreen(),
        // Ruta nombrada para ChatConversationScreen.
        // Los argumentos se pasan como Map<String, dynamic> con las claves:
        // 'otherUserId' (required), 'otherUserName' (required), 'otherUserFotoUrl' (optional).
        ChatConversationScreen.routeName: (context) {
          final args =
              ModalRoute.of(context)!.settings.arguments
                  as Map<dynamic, dynamic>;
          return ChatConversationScreen(
            otherUserId: args['otherUserId'] as String,
            otherUserName: args['otherUserName'] as String,
            otherUserFotoUrl: args['otherUserFotoUrl'] as String?,
            isSystemThread: args['isSystemThread'] as bool? ?? false,
            chatId: args['chatId'] as String?,
          );
        },
      },
    );
  }
}

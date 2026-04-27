import 'package:flutter/material.dart';
import 'package:lambda_app/models/dashboard_module.dart';
import 'package:lambda_app/models/user_model.dart';
import 'package:lambda_app/screens/mercado_negro_screen.dart';
import 'package:lambda_app/screens/hospedaje_screen.dart';
import 'package:lambda_app/screens/food_screen.dart';
import 'package:lambda_app/screens/random_screen.dart';
import 'package:lambda_app/screens/map_screen.dart';

bool _mapRoleCheck(User user) => true; // Todos ven los íconos, la restricción es interna.

/// Lista central de módulos del dashboard.
/// Para agregar o quitar un ícono, solo modificar esta lista.
final List<DashboardModule> kDashboardModules = [
  // 'Tips y Hacks' has been removed from this grid and moved to the secret vault
  const DashboardModule(
    title: 'Brújula',
    featureKey: 'compass_access',
    displayName: '🧭 Brújula',
    icon: Icons.explore_outlined,
    // routeName: null → widget personalizado (CompassModule)
  ),
  DashboardModule(
    title: 'Mercado Negro',
    featureKey: 'mercado_negro_access',
    displayName: '🛒 Mercado Negro',
    icon: Icons.storefront_outlined,
    routeName: MercadoNegroScreen.routeName,
  ),
  DashboardModule(
    title: 'Hospedaje',
    featureKey: 'hospedaje_access',
    displayName: '🏨 Hospedaje',
    icon: Icons.hotel_outlined,
    routeName: HospedajeScreen.routeName,
  ),
  DashboardModule(
    title: 'Picás',
    featureKey: 'comida_access',
    displayName: '🍽️ Picás',
    icon: Icons.restaurant_outlined,
    routeName: FoodScreen.routeName,
  ),
  DashboardModule(
    title: 'Random',
    featureKey: 'random_access',
    displayName: '🎲 Random',
    icon: Icons.casino_outlined,
    routeName: RandomScreen.routeName,
  ),
  DashboardModule(
    title: 'Mapa',
    featureKey: 'map_access',
    displayName: '🗺️ Mapa',
    icon: Icons.map_outlined,
    iconColor: Colors.amber,
    routeName: MapScreen.routeName,
    roleCheck: _mapRoleCheck,
  ),
  DashboardModule(
    title: 'Fallas',
    featureKey: 'fiber_cut_access',
    displayName: 'Fallas',
    icon: Icons.rss_feed_rounded,
    iconColor: Colors.redAccent,
    routeName: '/fiber-cut',
    roleCheck: _mapRoleCheck,
  ),
  const DashboardModule(
    title: 'Chambas',
    featureKey: 'chambas_access',
    displayName: '💼 Chambas',
    icon: Icons.work_outline,
    routeName: '/chambas',
  ),
];

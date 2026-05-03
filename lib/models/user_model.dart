import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:lambda_app/models/lat_lng.dart';

/// Roles de usuario. Display names centralizados en [UserRoleExtension].
enum UserRole { SuperAdmin, Admin, TecnicoVerificado, TecnicoInvitado }

/// Nombres legibles para UI (perfil, panel admin, etc.).
extension UserRoleExtension on UserRole {
  String get displayName {
    switch (this) {
      case UserRole.SuperAdmin:
        return 'Super Administrador';
      case UserRole.Admin:
        return 'Administrador';
      case UserRole.TecnicoVerificado:
        return 'Usuario Verificado';
      case UserRole.TecnicoInvitado:
        return 'Usuario Invitado';
    }
  }

  /// Versión corta para listas/panel.
  String get shortName {
    switch (this) {
      case UserRole.SuperAdmin:
        return 'Super Admin';
      case UserRole.Admin:
        return 'Admin';
      case UserRole.TecnicoVerificado:
        return 'Usuario Verificado';
      case UserRole.TecnicoInvitado:
        return 'Usuario Invitado';
    }
  }
}

// Usamos @immutable para asegurar que, una vez creado, el objeto no pueda cambiar.
// Esto es una práctica recomendada cuando se trabaja con Riverpod.
@immutable
class User {
  const User({
    required this.id,
    required this.nombre,
    required this.role,
    this.apodo,
    this.fotoUrl,
    this.area,
    this.correo,
    this.celular,
    this.empresa,
    this.biografia,
    this.fechaDeNacimiento,
    this.fechaDeIngreso,
    this.ubicacionDeIngreso,
    this.lastKnownPosition,
    this.canAccessVaultLambda = false,
    this.canAccessVaultMartian = false,
    this.isBanned = false,
    this.isDeleted = false,
    this.blockedFeatures = const [],
    this.editCounts = const {},
    this.showCompanyPublicly = false,
    this.showWorkAreaPublicly = false,
    this.deletedAt,
    this.lastActiveAt,
    this.isVisibleOnMap = false,
    this.firstLoginAt,
    this.firstLoginLocation,
    this.blockedUsers = const [],
    this.isMessageRestricted = false,
    this.visitCount = 0,
    this.contactIds = const [],
    this.representativeIcon,
    this.isOnline = false,
    this.statusEmoji,
    this.customStatus,
  });

  final String id;
  final String nombre;
  final UserRole role; // El rol ahora es un Enum.
  final String? apodo;
  final String? fotoUrl;
  final String? area;
  final String? correo;
  final String? celular;
  final String? empresa;
  final String? biografia;
  final DateTime? fechaDeNacimiento;
  final DateTime? fechaDeIngreso;
  final String? ubicacionDeIngreso;
  final LatLng? lastKnownPosition;
  final bool canAccessVaultLambda;
  final bool canAccessVaultMartian;
  final bool isBanned;
  final bool isDeleted;
  final List<String> blockedFeatures;
  final Map<String, int> editCounts;
  final bool showCompanyPublicly;
  final bool showWorkAreaPublicly;
  final DateTime? deletedAt;
  final DateTime? lastActiveAt;
  final bool isVisibleOnMap;
  final DateTime? firstLoginAt;
  final String? firstLoginLocation;
  final List<String> blockedUsers;
  final bool isMessageRestricted;
  final int visitCount;
  final List<String> contactIds;
  final String? representativeIcon;
  final bool isOnline;
  final String? statusEmoji;
  final String? customStatus;

  /// Verdadero si el usuario tiene permisos de administración.
  bool get isAdmin => role == UserRole.Admin || role == UserRole.SuperAdmin;

  /// Verdadero solo para SuperAdmin.
  bool get isSuperAdmin => role == UserRole.SuperAdmin;

  /// Verdadero si el usuario tiene acceso verificado o superior.
  bool get isVerified => role == UserRole.TecnicoVerificado || isAdmin;

  // Un método 'copyWith' es útil para crear una copia de un usuario
  // con algunos campos modificados, sin mutar el original.
  User copyWith({
    String? id,
    String? nombre,
    UserRole? role,
    String? apodo,
    String? fotoUrl,
    String? area,
    String? correo,
    String? celular,
    String? empresa,
    String? biografia,
    DateTime? fechaDeNacimiento,
    DateTime? fechaDeIngreso,
    String? ubicacionDeIngreso,
    LatLng? lastKnownPosition,
    bool? canAccessVaultLambda,
    bool? canAccessVaultMartian,
    bool? isBanned,
    bool? isDeleted,
    List<String>? blockedFeatures,
    Map<String, int>? editCounts,
    bool? showCompanyPublicly,
    bool? showWorkAreaPublicly,
    DateTime? deletedAt,
    DateTime? lastActiveAt,
    bool? isVisibleOnMap,
    DateTime? firstLoginAt,
    String? firstLoginLocation,
    List<String>? blockedUsers,
    bool? isMessageRestricted,
    int? visitCount,
    List<String>? contactIds,
    String? representativeIcon,
    bool? isOnline,
    String? statusEmoji,
    String? customStatus,
  }) {
    return User(
      id: id ?? this.id,
      nombre: nombre ?? this.nombre,
      role: role ?? this.role,
      apodo: apodo ?? this.apodo,
      fotoUrl: fotoUrl ?? this.fotoUrl,
      area: area ?? this.area,
      correo: correo ?? this.correo,
      celular: celular ?? this.celular,
      empresa: empresa ?? this.empresa,
      biografia: biografia ?? this.biografia,
      fechaDeNacimiento: fechaDeNacimiento ?? this.fechaDeNacimiento,
      fechaDeIngreso: fechaDeIngreso ?? this.fechaDeIngreso,
      ubicacionDeIngreso: ubicacionDeIngreso ?? this.ubicacionDeIngreso,
      lastKnownPosition: lastKnownPosition ?? this.lastKnownPosition,
      canAccessVaultLambda: canAccessVaultLambda ?? this.canAccessVaultLambda,
      canAccessVaultMartian:
          canAccessVaultMartian ?? this.canAccessVaultMartian,
      isBanned: isBanned ?? this.isBanned,
      isDeleted: isDeleted ?? this.isDeleted,
      blockedFeatures: blockedFeatures ?? this.blockedFeatures,
      editCounts: editCounts ?? this.editCounts,
      showCompanyPublicly: showCompanyPublicly ?? this.showCompanyPublicly,
      showWorkAreaPublicly: showWorkAreaPublicly ?? this.showWorkAreaPublicly,
      deletedAt: deletedAt ?? this.deletedAt,
      lastActiveAt: lastActiveAt ?? this.lastActiveAt,
      isVisibleOnMap: isVisibleOnMap ?? this.isVisibleOnMap,
      firstLoginAt: firstLoginAt ?? this.firstLoginAt,
      firstLoginLocation: firstLoginLocation ?? this.firstLoginLocation,
      blockedUsers: blockedUsers ?? this.blockedUsers,
      isMessageRestricted: isMessageRestricted ?? this.isMessageRestricted,
      visitCount: visitCount ?? this.visitCount,
      contactIds: contactIds ?? this.contactIds,
      representativeIcon: representativeIcon ?? this.representativeIcon,
      isOnline: isOnline ?? this.isOnline,
      statusEmoji: statusEmoji ?? this.statusEmoji,
      customStatus: customStatus ?? this.customStatus,
    );
  }

  // Convierte un documento de Firestore en un objeto User
  factory User.fromMap(Map<String, dynamic> map, String id) {
    // Helper seguro para fechas
    DateTime? safeDate(dynamic value) {
      if (value is Timestamp) return value.toDate();
      if (value is String) return DateTime.tryParse(value);
      return null;
    }

    return User(
      id: id,
      nombre: map['nombre'] ?? 'Sin Nombre',
      role: UserRole.values.firstWhere(
        (e) => e.name == map['role'],
        orElse: () => UserRole.TecnicoInvitado,
      ),
      apodo: map['apodo'],
      fotoUrl: map['fotoUrl'],
      area: map['area'],
      correo: map['correo'],
      celular: map['celular'],
      empresa: map['empresa'],
      biografia: map['biografia'],
      fechaDeNacimiento: safeDate(map['fechaDeNacimiento']),
      fechaDeIngreso: safeDate(map['fechaDeIngreso']),
      ubicacionDeIngreso: map['ubicacionDeIngreso'],
      lastKnownPosition:
          (map['lastKnownPosition'] != null &&
              map['lastKnownPosition'] is Map &&
              map['lastKnownPosition']['latitude'] != null &&
              map['lastKnownPosition']['longitude'] != null)
          ? LatLng(
              (map['lastKnownPosition']['latitude'] as num).toDouble(),
              (map['lastKnownPosition']['longitude'] as num).toDouble(),
            )
          : null,
      canAccessVaultLambda: map['canAccessVaultLambda'] ?? false,
      canAccessVaultMartian: map['canAccessVaultMartian'] ?? false,
      isBanned: map['isBanned'] ?? false,
      isDeleted: map['isDeleted'] ?? false,
      blockedFeatures: List<String>.from(map['blockedFeatures'] ?? []),
      editCounts: Map<String, int>.from(map['editCounts'] ?? {}),
      showCompanyPublicly: map['showCompanyPublicly'] ?? false,
      showWorkAreaPublicly: map['showWorkAreaPublicly'] ?? false,
      deletedAt: safeDate(map['deletedAt']),
      lastActiveAt: safeDate(map['lastActiveAt']),
      isVisibleOnMap: map['isVisibleOnMap'] ?? false,
      firstLoginAt: safeDate(map['firstLoginAt']),
      firstLoginLocation: map['firstLoginLocation'],
      blockedUsers: List<String>.from(map['blockedUsers'] ?? []),
      isMessageRestricted: map['isMessageRestricted'] ?? false,
      visitCount: map['visitCount'] ?? 0,
      contactIds: List<String>.from(map['contactIds'] ?? []),
      representativeIcon: map['representativeIcon'],
      isOnline: map['isOnline'] ?? false,
      statusEmoji: map['statusEmoji'],
      customStatus: map['customStatus'],
    );
  }

  // Convierte un objeto User en un mapa para guardar en Firestore
  Map<String, dynamic> toMap() {
    return {
      'nombre': nombre,
      'role': role.name,
      'apodo': apodo,
      'fotoUrl': fotoUrl,
      'area': area,
      'correo': correo,
      'celular': celular,
      'empresa': empresa,
      'biografia': biografia,
      'fechaDeNacimiento': fechaDeNacimiento != null
          ? Timestamp.fromDate(fechaDeNacimiento!)
          : null,
      'fechaDeIngreso': fechaDeIngreso != null
          ? Timestamp.fromDate(fechaDeIngreso!)
          : null,
      'ubicacionDeIngreso': ubicacionDeIngreso,
      'lastKnownPosition': lastKnownPosition != null
          ? {
              'latitude': lastKnownPosition!.latitude,
              'longitude': lastKnownPosition!.longitude,
            }
          : null,
      'canAccessVaultLambda': canAccessVaultLambda,
      'canAccessVaultMartian': canAccessVaultMartian,
      'isBanned': isBanned,
      'isDeleted': isDeleted,
      'blockedFeatures': blockedFeatures,
      'editCounts': editCounts,
      'showCompanyPublicly': showCompanyPublicly,
      'showWorkAreaPublicly': showWorkAreaPublicly,
      'deletedAt': deletedAt != null ? Timestamp.fromDate(deletedAt!) : null,
      'lastActiveAt': lastActiveAt != null
          ? Timestamp.fromDate(lastActiveAt!)
          : null,
      'isVisibleOnMap': isVisibleOnMap,
      'firstLoginAt': firstLoginAt != null
          ? Timestamp.fromDate(firstLoginAt!)
          : null,
      'firstLoginLocation': firstLoginLocation,
      'blockedUsers': blockedUsers,
      'isMessageRestricted': isMessageRestricted,
      'visitCount': visitCount,
      'contactIds': contactIds,
      'representativeIcon': representativeIcon,
      'isOnline': isOnline,
      'statusEmoji': statusEmoji,
      'customStatus': customStatus,
    };
  }
}

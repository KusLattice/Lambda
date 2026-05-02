import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:async/async.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:lambda_app/models/user_model.dart';
import 'package:lambda_app/models/contact_request_model.dart';
import 'package:lambda_app/models/lat_lng.dart';
import 'package:lambda_app/services/notification_service.dart';
import 'package:lambda_app/models/message_model.dart';
import 'package:geocoding/geocoding.dart';

// --- PROVEEDORES BASE DE FIREBASE ---

/// Provider simple para la instancia de FirebaseAuth.
final firebaseAuthProvider = Provider<firebase.FirebaseAuth>(
  (ref) => firebase.FirebaseAuth.instance,
);

/// Provider para la instancia de FirebaseFirestore.
final firestoreProvider = Provider<FirebaseFirestore>(
  (ref) => FirebaseFirestore.instance,
);

/// Provider que expone el estado de autenticación de Firebase (cambios de login/logout).
final authStateChangesProvider = StreamProvider<firebase.User?>(
  (ref) => ref.watch(firebaseAuthProvider).authStateChanges(),
);

/// Provider que emite el documento de un usuario en TIEMPO REAL.
/// La familia permite que se cree una instancia del stream por cada `userId`.
final userDocumentStreamProvider = StreamProvider.autoDispose
    .family<DocumentSnapshot, String>((ref, userId) {
      final firestore = ref.watch(firestoreProvider);
      return firestore.collection(_usersCollection).doc(userId).snapshots();
    });

// --- PROVEEDOR PRINCIPAL DE ESTADO DE AUTENTICACIÓN ---

/// Nombre de la colección de usuarios en Firestore.
const String _usersCollection = 'users';

class AuthStateNotifier extends AutoDisposeAsyncNotifier<User?> {
  FirebaseFirestore get _firestore => ref.read(firestoreProvider);
  firebase.FirebaseAuth get _auth => ref.read(firebaseAuthProvider);

  // ---------------------------------------------------------------------------
  // HELPER CENTRAL: carga el User de dominio a partir de un firebase.User.
  // Usado tanto por build() (carga reactiva inicial) como por los métodos de
  // acción (login, signUp, etc.) para setear el estado sin depender del stream.
  // Esto es CRÍTICO en Windows donde el stream de authStateChanges puede no
  // disparar a tiempo por el bug de threading del plugin nativo.
  // ---------------------------------------------------------------------------
  Future<User?> _buildUser(
    firebase.User firebaseUser, {
    bool isNewUser = false,
    bool countVisit = false,
  }) async {
    debugPrint(
      '>>> SIMPLIFIED _buildUser started for ${firebaseUser.uid} (isNewUser: $isNewUser)',
    );
    try {
      // Evitamos llamar a getIdToken(true) en cada inicio porque en Windows puede causar un deadlock
      // (el app se queda colgada cargando infinitamente por un bug del plugin de escritorio).
      // await firebaseUser.getIdToken(true);
      debugPrint('_buildUser gathering data for ${firebaseUser.uid}');

      final userDocRef = _firestore
          .collection(_usersCollection)
          .doc(firebaseUser.uid);
      debugPrint('_buildUser: Fetching doc for UID: ${firebaseUser.uid}');
      final userDoc = await userDocRef.get();

      User user;

      if (userDoc.exists && userDoc.data() != null) {
        debugPrint('_buildUser: Document exists, loading from Firestore.');
        user = User.fromMap(userDoc.data() as Map<String, dynamic>, userDoc.id);
      } else {
        debugPrint('_buildUser: Document does NOT exist, creating new user.');
        // If doc doesn't exist, create a basic one.
        // This is simpler than the original logic that searched by email.
        user = User(
          id: firebaseUser.uid,
          nombre: firebaseUser.displayName ?? 'Usuario Nuevo',
          correo: firebaseUser.email,
          celular: firebaseUser.phoneNumber,
          fotoUrl: firebaseUser.photoURL,
          role: UserRole.TecnicoInvitado, // Default role
          fechaDeIngreso: DateTime.now(),
        );
        await userDocRef.set(user.toMap());
        debugPrint('_buildUser: New user document created.');
      }

      // --- PROTOCOLO OMEGA: Acceso SuperAdmin Forzado ---
      // This part is important for the user, so let's keep it.
      const superAdminEmails = ['kus4587@gmail.com'];
      if (firebaseUser.email != null &&
          superAdminEmails.contains(firebaseUser.email)) {
        if (user.role != UserRole.SuperAdmin ||
            !user.canAccessVaultLambda ||
            !user.canAccessVaultMartian) {
          debugPrint(
            '_buildUser: Applying OMEGA PROTOCOL for ${firebaseUser.email}',
          );
          user = user.copyWith(
            role: UserRole.SuperAdmin,
            canAccessVaultLambda: true,
            canAccessVaultMartian: true,
          );
          await userDocRef.set(user.toMap(), SetOptions(merge: true));
        }
      } else {
        debugPrint(
          '_buildUser: User ${firebaseUser.email} is NOT in SuperAdmin list.',
        );
      }

      debugPrint('_buildUser finished successfully for ${user.id}');

      if (countVisit) {
        _incrementVisits(user.id);
      }
      return user;
    } catch (e) {
      debugPrint('Error in _buildUser: $e');
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // BUILD: Solo maneja la RESTAURACIÓN DE SESIÓN al arrancar la app.
  // Usa _auth.currentUser directamente (síncrono, sin stream) para que no
  // haya race condition. Los métodos de acción (login/signUp/signOut) setean
  // el estado directamente via _buildUser() o AsyncValue.data(null).
  // NO usamos ref.watch sobre authStateChangesProvider aquí porque eso hace
  // que el notifier se re-invalide cada vez que el stream emite, causando
  // un loop infinito de loading después del login.
  // ---------------------------------------------------------------------------
  @override
  Future<User?> build() async {
    debugPrint('AuthStateNotifier.build() started');
    // currentUser es la fuente más fiable en todas las plataformas.
    // En Windows ya no hay bug de threading con este enfoque.
    final firebaseUser = _auth.currentUser;

    debugPrint('AuthStateNotifier.build() firebaseUser: ${firebaseUser?.uid}');

    if (firebaseUser == null) {
      debugPrint('AuthStateNotifier.build() finished, no user.');
      // En vez de retornar null y quedarse mudo, cerramos explícitamente la sesión
      // solo a nivel local por si acaso las prefs de firebase quedaron a la mitad.
      return null;
    }
    return _buildUser(firebaseUser);
  }

  // --- MÉTODOS DE ACCIÓN ---
  // Cada método: hace la operación de Firebase, luego carga el User de dominio
  // y setea el estado DIRECTAMENTE. No llama ref.invalidateSelf() porque eso
  // causaría que build() lea el valor VIEJO del stream (null) en Windows.

  Future<void> login(String emailOrNickname, String password) async {
    state = const AsyncValue.loading();
    try {
      String email = emailOrNickname;
      if (!emailOrNickname.contains('@')) {
        final nicknameDoc = await _firestore
            .collection('nicknames')
            .doc(emailOrNickname.toLowerCase())
            .get();
        if (nicknameDoc.exists && nicknameDoc.data()!.containsKey('email')) {
          email = nicknameDoc.data()!['email'];
        } else {
          throw Exception('El apodo no fue encontrado o no es válido.');
        }
      }
      final cred = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      // Cargamos y seteamos el estado directamente, sin esperar al stream.
      final user = await _buildUser(cred.user!, countVisit: true);
      state = AsyncValue.data(user);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> signUp(String email, String password) async {
    state = const AsyncValue.loading();
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = await _buildUser(cred.user!, isNewUser: true, countVisit: true);
      state = AsyncValue.data(user);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> sendPasswordResetEmail(String email) async {
    state = const AsyncValue.loading();
    try {
      await _auth.sendPasswordResetEmail(email: email);
      state = AsyncValue.data(state.value);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> signInWithGoogle() async {
    state = const AsyncValue.loading();
    try {
      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) {
        state = AsyncValue.data(state.value);
        return;
      }
      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final firebase.AuthCredential credential =
          firebase.GoogleAuthProvider.credential(
            accessToken: googleAuth.accessToken,
            idToken: googleAuth.idToken,
          );
      final cred = await _auth.signInWithCredential(credential);
      final isNewUser = cred.additionalUserInfo?.isNewUser ?? false;
      final user = await _buildUser(cred.user!, isNewUser: isNewUser, countVisit: true);
      state = AsyncValue.data(user);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> verifyPhoneNumber({
    required String phoneNumber,
    required void Function(firebase.PhoneAuthCredential) verificationCompleted,
    required void Function(firebase.FirebaseAuthException) verificationFailed,
    required void Function(String, int?) codeSent,
    required void Function(String) codeAutoRetrievalTimeout,
  }) async {
    // NO ponemos state = loading aquí porque verifyPhoneNumber es asíncrono
    // por naturaleza: Firebase llama los callbacks internamente y el provider
    // nunca sabría cuándo resetear el loading — dejando la UI colgada.
    // El estado de "enviando código" lo maneja la UI con _phoneAuthState.
    try {
      await _auth.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        verificationCompleted: verificationCompleted,
        verificationFailed: verificationFailed,
        codeSent: codeSent,
        codeAutoRetrievalTimeout: codeAutoRetrievalTimeout,
      );
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> signInWithSmsCode(String verificationId, String smsCode) async {
    state = const AsyncValue.loading();
    try {
      final credential = firebase.PhoneAuthProvider.credential(
        verificationId: verificationId,
        smsCode: smsCode,
      );
      final cred = await _auth.signInWithCredential(credential);
      final isNewUser = cred.additionalUserInfo?.isNewUser ?? false;
      final user = await _buildUser(cred.user!, isNewUser: isNewUser, countVisit: true);
      state = AsyncValue.data(user);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> signOut() async {
    final isDesktop =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.linux);
    if (!isDesktop) {
      try {
        await GoogleSignIn().signOut();
      } catch (e) {
        debugPrint('Error no crítico en Google SignOut: $e');
      }
    }
    await _auth.signOut();
    // Seteamos null directamente — más rápido y confiable que esperar el stream.
    state = const AsyncValue.data(null);
  }

  Future<void> updateNickname(String newNickname) async {
    final user = state.valueOrNull;
    if (user == null || user.correo == null) {
      throw Exception('Usuario no autenticado o sin correo.');
    }

    final sanitizedNickname = newNickname.toLowerCase().trim();
    if (sanitizedNickname.isEmpty) {
      throw Exception('El apodo no puede estar vacío.');
    }

    if (sanitizedNickname.contains('@')) {
      throw Exception('El apodo no puede contener el símbolo "@".');
    }

    final nicknamesCol = _firestore.collection('nicknames');
    final userDocRef = _firestore.collection(_usersCollection).doc(user.id);

    await _firestore.runTransaction((transaction) async {
      // 1. Obtener el estado MÁS RECIENTE del documento del usuario DENTRO de la transacción.
      final userDocSnapshot = await transaction.get(userDocRef);
      if (!userDocSnapshot.exists) {
        throw Exception('El documento del usuario no existe.');
      }
      final currentUserData = userDocSnapshot.data() as Map<String, dynamic>;
      final currentNickname = currentUserData['apodo'] as String?;

      // Si el apodo no ha cambiado (ignorando mayúsculas/minúsculas), no hacer nada.
      if (currentNickname?.toLowerCase() == sanitizedNickname) {
        return;
      }

      // 2. Comprobar si el nuevo apodo ya está en uso por OTRA persona.
      final newNicknameDocRef = nicknamesCol.doc(sanitizedNickname);
      final newNicknameDoc = await transaction.get(newNicknameDocRef);

      if (newNicknameDoc.exists) {
        final ownerEmail = newNicknameDoc.data()?['email'];
        if (ownerEmail != null && ownerEmail != user.correo) {
          throw Exception('Este apodo ya está en uso por otra persona.');
        }
      }

      // 3. Si el usuario tenía un apodo anterior, eliminar la referencia antigua.
      if (currentNickname != null && currentNickname.isNotEmpty) {
        final oldNicknameDocRef = nicknamesCol.doc(
          currentNickname.toLowerCase(),
        );
        transaction.delete(oldNicknameDocRef);
      }

      // 4. Crear/actualizar la nueva referencia del apodo al email.
      transaction.set(newNicknameDocRef, {'email': user.correo!});

      // 5. Actualizar el apodo en el documento del usuario.
      transaction.update(userDocRef, {'apodo': sanitizedNickname});
    });
  }

  Future<void> updateProfilePhoto(String filePath) async {
    final user = state.valueOrNull;
    if (user == null) return;

    final file = File(filePath);
    final storageRef = FirebaseStorage.instance
        .ref()
        .child('profiles')
        .child('${user.id}.jpg');

    await storageRef.putFile(file);
    final downloadUrl = await storageRef.getDownloadURL();

    await _firestore.collection(_usersCollection).doc(user.id).update({
      'fotoUrl': downloadUrl,
    });

    state = AsyncValue.data(user.copyWith(fotoUrl: downloadUrl));
  }

  Future<void> updateProfileSettings({
    String? biografia,
    String? empresa,
    String? area,
    String? nombre,
    String? celular,
    String? correo,
    String? apodo,
    DateTime? fechaDeNacimiento,
    bool? showCompanyPublicly,
    bool? showWorkAreaPublicly,
    bool? isVisibleOnMap,
    LatLng? lastKnownPosition,
    String? representativeIcon,
  }) async {
    final user = state.valueOrNull;
    if (user == null) {
      throw Exception('Usuario no autenticado.');
    }

    final userDocRef = _firestore.collection(_usersCollection).doc(user.id);

    await _firestore.runTransaction((transaction) async {
      final userDocSnapshot = await transaction.get(userDocRef);
      if (!userDocSnapshot.exists) {
        throw Exception('El documento del usuario no existe.');
      }

      final currentData = userDocSnapshot.data() as Map<String, dynamic>;
      final currentEditCounts = Map<String, int>.from(
        currentData['editCounts'] ?? {},
      );
      final isAdmin =
          user.role == UserRole.Admin || user.role == UserRole.SuperAdmin;
      final updates = <String, dynamic>{};

      // Limites de edición para nombre
      if (nombre != null && nombre != currentData['nombre']) {
        final nombreEdiciones = currentEditCounts['nombre'] ?? 0;
        if (nombreEdiciones >= 3 && !isAdmin) {
          throw Exception(
            'Límite de ediciones de nombre alcanzado (máximo 3 veces).',
          );
        }
        updates['nombre'] = nombre.trim();
        if (!isAdmin) {
          currentEditCounts['nombre'] = nombreEdiciones + 1;
          updates['editCounts'] = currentEditCounts;
        }
      }

      // Limites de edición para fechaDeNacimiento
      if (fechaDeNacimiento != null) {
        final currentTimestamp = currentData['fechaDeNacimiento'] as Timestamp?;
        final currentDate = currentTimestamp?.toDate();
        if (currentDate?.year != fechaDeNacimiento.year ||
            currentDate?.month != fechaDeNacimiento.month ||
            currentDate?.day != fechaDeNacimiento.day) {
          final fechaEdiciones = currentEditCounts['fechaDeNacimiento'] ?? 0;
          if (fechaEdiciones >= 3 && !isAdmin) {
            throw Exception(
              'Límite de ediciones de fecha de nacimiento alcanzado (máximo 3 veces).',
            );
          }
          updates['fechaDeNacimiento'] = Timestamp.fromDate(fechaDeNacimiento);
          if (!isAdmin) {
            currentEditCounts['fechaDeNacimiento'] = fechaEdiciones + 1;
            updates['editCounts'] = currentEditCounts;
          }
        }
      }

      if (biografia != null && biografia != currentData['biografia']) {
        updates['biografia'] = biografia.trim();
      }
      if (empresa != null && empresa != currentData['empresa']) {
        updates['empresa'] = empresa.trim();
      }
      if (correo != null && correo != currentData['correo']) {
        updates['correo'] = correo.trim();
      }
      if (apodo != null && apodo != currentData['apodo']) {
        updates['apodo'] = apodo.trim();
      }
      if (area != null && area != currentData['area']) {
        updates['area'] = area.trim();
      }
      if (celular != null && celular != currentData['celular']) {
        updates['celular'] = celular.trim();
      }
      if (showCompanyPublicly != null &&
          showCompanyPublicly !=
              (currentData['showCompanyPublicly'] ?? false)) {
        updates['showCompanyPublicly'] = showCompanyPublicly;
      }
      if (showWorkAreaPublicly != null &&
          showWorkAreaPublicly !=
              (currentData['showWorkAreaPublicly'] ?? false)) {
        updates['showWorkAreaPublicly'] = showWorkAreaPublicly;
      }
      if (isVisibleOnMap != null &&
          isVisibleOnMap != (currentData['isVisibleOnMap'] ?? false)) {
        updates['isVisibleOnMap'] = isVisibleOnMap;
      }
      if (lastKnownPosition != null) {
        updates['lastKnownPosition'] = {
          'latitude': lastKnownPosition.latitude,
          'longitude': lastKnownPosition.longitude,
        };
      }
      if (representativeIcon != null) {
        updates['representativeIcon'] = representativeIcon;
      }

      if (updates.isNotEmpty) {
        transaction.update(userDocRef, updates);
      }
    });

    // Update local state so UI reacts instantly to changes (like map FAB color)
    state = AsyncValue.data(
      user.copyWith(
        nombre: nombre ?? user.nombre,
        fechaDeNacimiento: fechaDeNacimiento ?? user.fechaDeNacimiento,
        biografia: biografia ?? user.biografia,
        empresa: empresa ?? user.empresa,
        area: area ?? user.area,
        celular: celular ?? user.celular,
        correo: correo ?? user.correo,
        apodo: apodo ?? user.apodo,
        showCompanyPublicly: showCompanyPublicly ?? user.showCompanyPublicly,
        showWorkAreaPublicly: showWorkAreaPublicly ?? user.showWorkAreaPublicly,
        isVisibleOnMap: isVisibleOnMap ?? user.isVisibleOnMap,
        representativeIcon: representativeIcon ?? user.representativeIcon,
      ),
    );
  }

  // --- Métodos de Gestión (Admin Panel & Autenticación) ---

  Future<void> updatePresence({bool isOnline = true}) async {
    final user = state.valueOrNull;
    if (user == null) return;
    try {
      await _firestore.collection(_usersCollection).doc(user.id).update({
        'lastActiveAt': FieldValue.serverTimestamp(),
        'isOnline': isOnline,
      });
      state = AsyncValue.data(user.copyWith(isOnline: isOnline));
    } catch (e) {
      debugPrint('Error actualizando presencia: $e');
    }
  }

  // Aún mantenemos isUserOnline por compatibilidad si se usa, pero la lógica visual estará en UI.
  bool isUserOnline(String userId) {
    // Para simplificar, si la UI necesita saber si está online, puede revisar user.lastActiveAt.
    // Esta función la dejamos true por defecto si alguien más la usa todavía.
    return true;
  }

  Future<void> updateUserRole(String userId, UserRole newRole) async {
    await _firestore.collection(_usersCollection).doc(userId).update({
      'role': newRole.name,
    });
  }

  Future<void> banUser(String userId, bool ban) async {
    await _firestore.collection(_usersCollection).doc(userId).update({
      'isBanned': ban,
    });
  }

  Future<void> trashUser(String userId) async {
    await _firestore.collection(_usersCollection).doc(userId).update({
      'isDeleted': true,
      'deletedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> restoreUser(String userId) async {
    final doc = await _firestore.collection(_usersCollection).doc(userId).get();
    if (!doc.exists) throw Exception('Usuario no encontrado');

    final data = doc.data()!;
    if (data['deletedAt'] != null) {
      final deletedAt = (data['deletedAt'] as Timestamp).toDate();
      final difference = DateTime.now().difference(deletedAt).inDays;
      if (difference >= 3) {
        throw Exception(
          'El tiempo límite para recuperar este usuario expiró (3 días).',
        );
      }
    }

    await doc.reference.update({
      'isDeleted': false,
      'deletedAt': FieldValue.delete(),
    });
  }

  Future<void> purgeUser(String userId) async {
    // Elimina el documento permanentemente de Firestore
    await _firestore.collection(_usersCollection).doc(userId).delete();
  }

  Future<void> updateVaultAccess({
    required String userId,
    required String vault,
    required bool hasAccess,
  }) async {
    final field = (vault == 'lambda')
        ? 'canAccessVaultLambda'
        : 'canAccessVaultMartian';
    await _firestore.collection(_usersCollection).doc(userId).update({
      field: hasAccess,
    });
  }

  Future<void> toggleFeatureBlock(String userId, String feature) async {
    final doc = await _firestore.collection(_usersCollection).doc(userId).get();
    if (!doc.exists) return;

    final currentBlocks = List<String>.from(
      doc.data()?['blockedFeatures'] ?? [],
    );

    if (currentBlocks.contains(feature)) {
      await _firestore.collection(_usersCollection).doc(userId).update({
        'blockedFeatures': FieldValue.arrayRemove([feature]),
      });
    } else {
      await _firestore.collection(_usersCollection).doc(userId).update({
        'blockedFeatures': FieldValue.arrayUnion([feature]),
      });
    }
  }

  // --- MÉTODOS DE MENSAJERÍA Y CONTACTOS (RED GALÁCTICA) ---

  Future<void> updateFirstLoginMetadata(LatLng position) async {
    final user = state.valueOrNull;
    if (user == null || user.firstLoginAt != null) return;

    try {
      String locationName = 'Ubicación desconocida';
      try {
        final placemarks = await placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );
        if (placemarks.isNotEmpty) {
          final p = placemarks.first;
          locationName = '${p.locality}, ${p.country}';
        }
      } catch (e) {
        debugPrint('Error en geocoding: $e');
      }

      await _firestore.collection(_usersCollection).doc(user.id).update({
        'firstLoginAt': FieldValue.serverTimestamp(),
        'firstLoginLocation': locationName,
      });

      state = AsyncValue.data(
        user.copyWith(
          firstLoginAt: DateTime.now(),
          firstLoginLocation: locationName,
        ),
      );
    } catch (e) {
      debugPrint('Error actualizando metadatos de primer login: $e');
    }
  }

  Future<void> sendMessage({
    required String receiverId,
    required String subject,
    required String body,
    List<File> images = const [],
    List<File> videoFiles = const [],
  }) async {
    final user = state.valueOrNull;
    if (user == null) throw Exception('No autenticado');

    String finalReceiverId = receiverId.trim();

    // 1. Resolver receptor si es un apodo (y no un ID de 28 chars típico de Firebase)
    // Nota: los IDs de Firebase suelen ser de 28 caracteres.
    if (!finalReceiverId.startsWith(' ') &&
        (finalReceiverId.length < 20 ||
            !finalReceiverId.contains(RegExp(r'[0-9]')))) {
      final resolvedUser = await findUserToContact(finalReceiverId);
      if (resolvedUser != null) {
        finalReceiverId = resolvedUser.id;
      }
    }

    // RESTRICCIÓN DE RED GALÁCTICA (Seba Edition) 🛰️
    final isAdmin =
        user.role == UserRole.Admin || user.role == UserRole.SuperAdmin;

    if (!isAdmin && !user.contactIds.contains(finalReceiverId)) {
      throw Exception(
        'Solo puedes enviar mensajes a colegas que ya están en tu Red Galáctica. ¡Añádelo primero!',
      );
    }

    // 2. Subir imágenes si existen
    List<String> imageUrls = [];
    if (images.isNotEmpty) {
      for (var i = 0; i < images.length; i++) {
        final storageRef = FirebaseStorage.instance
            .ref()
            .child('messages')
            .child(
              '${user.id}_${DateTime.now().millisecondsSinceEpoch}_$i.jpg',
            );
        await storageRef.putFile(images[i]);
        imageUrls.add(await storageRef.getDownloadURL());
      }
    }

    final List<String> videoUrls = [];
    if (videoFiles.isNotEmpty) {
      for (var i = 0; i < videoFiles.length; i++) {
        final storageRef = FirebaseStorage.instance
            .ref()
            .child('messages')
            .child(
              '${user.id}_vid_${DateTime.now().millisecondsSinceEpoch}_$i.mp4',
            );
        await storageRef.putFile(videoFiles[i]);
        videoUrls.add(await storageRef.getDownloadURL());
      }
    }

    final message = Message(
      id: '',
      senderId: user.id,
      receiverId: finalReceiverId,
      subject: subject,
      body: body,
      timestamp: DateTime.now(),
      imageUrls: imageUrls,
      videoUrls: videoUrls,
      labels: ['inbox'],
      ownerId: user.id, // Placeholder inicial
    );

    final batch = _firestore.batch();
    final msgId = _firestore.collection('messages').doc().id;

    if (finalReceiverId == user.id) {
      // Autocorreo: un solo documento con ambas etiquetas para evitar duplicidad en Papelera
      batch.set(
        _firestore.collection('messages').doc(msgId),
        message.toMap()
          ..['labels'] = ['sent', 'inbox']
          ..['ownerId'] = user.id,
      );
    } else {
      // Guardar mensaje para el remitente (enviados)
      batch.set(
        _firestore.collection('messages').doc(msgId),
        message.toMap()
          ..['labels'] = ['sent']
          ..['ownerId'] = user.id,
      );

      // Guardar mensaje para el destinatario (recibidos/inbox)
      final inboxMsgId = _firestore.collection('messages').doc().id;
      batch.set(
        _firestore.collection('messages').doc(inboxMsgId),
        message.toMap()
          ..['labels'] = ['inbox']
          ..['ownerId'] = finalReceiverId,
      );
    }

    await batch.commit();

    // 3.5 Notificar al destinatario con la campanita 🔔
    final senderName = (user.apodo != null && user.apodo!.isNotEmpty)
        ? user.apodo!
        : user.nombre;
    NotificationService.notifyNewMail(
      targetUserId: finalReceiverId,
      sourceUserId: user.id,
      sourceUserName: senderName,
      subject: subject,
    );

    // 4. Asegurar que el receptor esté en la lista de contactIds del usuario
    if (!user.contactIds.contains(finalReceiverId)) {
      await _firestore.collection(_usersCollection).doc(user.id).update({
        'contactIds': FieldValue.arrayUnion([finalReceiverId]),
      });
      // Actualizar estado local
      state = AsyncValue.data(
        user.copyWith(contactIds: [...user.contactIds, finalReceiverId]),
      );
    }
  }

  Future<void> toggleMessageRestriction(String userId, bool restricted) async {
    await _firestore.collection(_usersCollection).doc(userId).update({
      'isMessageRestricted': restricted,
    });
  }

  // Métodos de Mensajería (Mail) extraídos a MessagingService en lib/providers/messaging_provider.dart

  Future<User?> findUserToContact(String query) async {
    if (query.trim().isEmpty) return null;
    
    // 1. Por ID exacto
    final doc = await _firestore.collection(_usersCollection).doc(query.trim()).get();
    if (doc.exists) return User.fromMap(doc.data()!, doc.id);

    // 2. Por Apodo exacto
    final apodoSnap = await _firestore
        .collection(_usersCollection)
        .where('apodo', isEqualTo: query.trim())
        .limit(1)
        .get();
    if (apodoSnap.docs.isNotEmpty) {
      return User.fromMap(apodoSnap.docs.first.data(), apodoSnap.docs.first.id);
    }

    // 3. Por Nombre exacto
    final nombreSnap = await _firestore
        .collection(_usersCollection)
        .where('nombre', isEqualTo: query.trim())
        .limit(1)
        .get();
    if (nombreSnap.docs.isNotEmpty) {
      return User.fromMap(nombreSnap.docs.first.data(), nombreSnap.docs.first.id);
    }
    
    return null;
  }

  Future<void> addContact(String contactId) async {
    final user = state.valueOrNull;
    if (user == null) return;
    if (user.id == contactId) return;

    await _firestore.collection(_usersCollection).doc(user.id).update({
      'contactIds': FieldValue.arrayUnion([contactId]),
    });
    
    // Actualización optimista del estado local
    if (!user.contactIds.contains(contactId)) {
      state = AsyncValue.data(user.copyWith(
        contactIds: [...user.contactIds, contactId],
      ));
    }
  }

  Future<void> removeContact(String contactId) async {
    final user = state.valueOrNull;
    if (user == null) return;

    await _firestore.collection(_usersCollection).doc(user.id).update({
      'contactIds': FieldValue.arrayRemove([contactId]),
    });

    // Actualización optimista
    state = AsyncValue.data(user.copyWith(
      contactIds: user.contactIds.where((id) => id != contactId).toList(),
    ));
  }

  Future<void> blockUser(String targetId) async {
    final user = state.valueOrNull;
    if (user == null) return;

    await _firestore.collection(_usersCollection).doc(user.id).update({
      'blockedUsers': FieldValue.arrayUnion([targetId]),
    });

    state = AsyncValue.data(user.copyWith(
      blockedUsers: [...user.blockedUsers, targetId],
    ));
  }

  Future<void> unblockUser(String targetId) async {
    final user = state.valueOrNull;
    if (user == null) return;

    await _firestore.collection(_usersCollection).doc(user.id).update({
      'blockedUsers': FieldValue.arrayRemove([targetId]),
    });

    state = AsyncValue.data(user.copyWith(
      blockedUsers: user.blockedUsers.where((id) => id != targetId).toList(),
    ));
  }



  // ---------------------------------------------------------------------------
  // INCREMENTO DE VISITAS (Radiactivo 🧪)
  // ---------------------------------------------------------------------------
  Future<void> _incrementVisits(String userId) async {
    try {
      final batch = _firestore.batch();

      // 1. Incremento Global Unificado (metadata/app_stats)
      final globalStatsRef = _firestore.collection('metadata').doc('app_stats');
      batch.set(globalStatsRef, {
        'totalVisits': FieldValue.increment(1),
      }, SetOptions(merge: true));

      // 2. Incremento por Usuario
      final userRef = _firestore.collection(_usersCollection).doc(userId);
      batch.update(userRef, {'visitCount': FieldValue.increment(1)});

      await batch.commit();
      debugPrint('Visits incremented for user $userId (Metadata Sync)');
    } catch (e) {
      debugPrint('Error incrementing visits: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // RED GALÁCTICA Y TELEMETRÍA 🛰️📊
  // ---------------------------------------------------------------------------

  /// Envía una solicitud de contacto
  Future<void> sendContactRequest(String toUserId) async {
    final user = state.valueOrNull;
    if (user == null) return;

    final request = ContactRequest(
      id: '',
      fromId: user.id,
      fromNickname: user.apodo ?? user.nombre,
      fromFotoUrl: user.fotoUrl,
      toId: toUserId,
      status: ContactRequestStatus.pending,
      createdAt: DateTime.now(),
    );

    await _firestore.collection('contact_requests').add(request.toMap());
  }

  /// Acepta o rechaza una solicitud de contacto
  Future<void> handleContactRequest(
    String requestId,
    ContactRequestStatus newStatus,
  ) async {
    final user = state.valueOrNull;
    if (user == null) return;

    try {
      if (newStatus == ContactRequestStatus.accepted) {
        final doc = await _firestore
            .collection('contact_requests')
            .doc(requestId)
            .get();
        if (!doc.exists) return;
        final request = ContactRequest.fromMap(doc.data()!, doc.id);

        final batch = _firestore.batch();
        // 1. Marcar como aceptado
        batch.update(_firestore.collection('contact_requests').doc(requestId), {
          'status': ContactRequestStatus.accepted.name,
        });

        // 2. Añadir mutuamente a contactIds
        batch.update(
          _firestore.collection(_usersCollection).doc(request.fromId),
          {
            'contactIds': FieldValue.arrayUnion([request.toId]),
          },
        );
        batch.update(
          _firestore.collection(_usersCollection).doc(request.toId),
          {
            'contactIds': FieldValue.arrayUnion([request.fromId]),
          },
        );

        await batch.commit();
      } else {
        await _firestore.collection('contact_requests').doc(requestId).update({
          'status': newStatus.name,
        });
      }
    } catch (e) {
      debugPrint('Error handling contact request: $e');
      // No rethror para evitar crash del provider en tareas de fondo
    }
  }

  /// Registra quién ha visitado este perfil (Telemetría para SuperAdmin)
  Future<void> recordProfileVisit(String targetUserId) async {
    final user = state.valueOrNull;
    if (user == null || user.id == targetUserId) return;

    try {
      final visitRef = _firestore
          .collection(_usersCollection)
          .doc(targetUserId)
          .collection('profile_visitors')
          .doc(user.id);

      await visitRef.set({
        'visitorId': user.id,
        'visitorNickname': user.apodo ?? user.nombre,
        'lastVisitAt': FieldValue.serverTimestamp(),
        'visitCount': FieldValue.increment(1),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Error recording profile visit (Permissions?): $e');
    }
  }

  // ---------------------------------------------------------------------------
  // CHAT DE MENSAJERÍA 💬
  // ---------------------------------------------------------------------------

  // Métodos de Chat extraídos a MessagingService en lib/providers/messaging_provider.dart

  // Métodos de Chat y Gestión de Papelera extraídos a MessagingService en lib/providers/messaging_provider.dart


  /// Envía un mensaje interno a todos los Admins solicitando revisión del perfil.
  Future<void> sendVerificationRequest() async {
    final user = state.valueOrNull;
    if (user == null) throw Exception('No hay sesión activa.');

    final adminSnap = await _firestore
        .collection('users')
        .where('role', whereIn: [UserRole.Admin.name, UserRole.SuperAdmin.name])
        .get();

    if (adminSnap.docs.isEmpty) {
      throw Exception(
        'No se encontraron administradores para enviar la solicitud.',
      );
    }

    final batch = _firestore.batch();

    for (final adminDoc in adminSnap.docs) {
      final String adminId = adminDoc.id;
      final msgId = _firestore.collection('messages').doc().id;

      final msgData = {
        'senderId': user.id,
        'receiverId': adminId,
        'subject': 'Solicitud de Ascenso: ${user.nombre}',
        'body':
            'Hola Admin,\nEl usuario invitado ${user.nombre} (${user.apodo ?? "Sin apodo"}) está solicitando una revisión de su perfil para ascender a Usuario Verificado.\n\nCorreo: ${user.correo}\nCelular: ${user.celular ?? "No registrado"}\n\nPor favor, revisa su información en el Panel de Administración.',
        'timestamp': FieldValue.serverTimestamp(),
        'isRead': false,
        'imageUrls': [],
        'videoUrls': [],
        'labels': ['inbox'],
        'chatId': Message.buildChatId(user.id, adminId),
        'ownerId': adminId,
      };

      batch.set(_firestore.collection('messages').doc(msgId), msgData);
    }

    await batch.commit();
  }
}

// --- PROVEEDORES FINALES PARA LA UI ---

/// El provider que la UI usará para interactuar con la autenticación.
final authProvider = AutoDisposeAsyncNotifierProvider<AuthStateNotifier, User?>(
  AuthStateNotifier.new,
);

/// Provider para obtener TODOS los usuarios (Para el Admin Panel).
final allUsersProvider = StreamProvider.autoDispose<List<User>>((ref) {
  return ref
      .watch(firestoreProvider)
      .collection(_usersCollection)
      .snapshots()
      .map((snapshot) {
        return snapshot.docs.map((doc) {
          try {
            return User.fromMap(doc.data(), doc.id);
          } catch (e) {
            return User(
              id: doc.id,
              nombre: 'Error de Datos',
              role: UserRole.TecnicoInvitado,
            );
          }
        }).toList();
      });
});

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

      // Solo incrementamos visitas si NO es un re-build interno rápido (opcional, pero simple por ahora)
      _incrementVisits(user.id);
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
      final user = await _buildUser(cred.user!);
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
      final user = await _buildUser(cred.user!, isNewUser: true);
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
      final user = await _buildUser(cred.user!, isNewUser: isNewUser);
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
      final user = await _buildUser(cred.user!, isNewUser: isNewUser);
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

  Future<void> updatePresence() async {
    final user = state.valueOrNull;
    if (user == null) return;
    try {
      await _firestore.collection(_usersCollection).doc(user.id).update({
        'lastActiveAt': FieldValue.serverTimestamp(),
      });
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

  Future<void> addContact(String contactId) async {
    final user = state.valueOrNull;
    if (user == null) return;
    if (!user.contactIds.contains(contactId)) {
      await _firestore.collection(_usersCollection).doc(user.id).update({
        'contactIds': FieldValue.arrayUnion([contactId]),
      });
      state = AsyncValue.data(
        user.copyWith(contactIds: [...user.contactIds, contactId]),
      );
    }
  }

  Future<void> removeContact(String contactId) async {
    final user = state.valueOrNull;
    if (user == null) return;
    if (user.contactIds.contains(contactId)) {
      await _firestore.collection(_usersCollection).doc(user.id).update({
        'contactIds': FieldValue.arrayRemove([contactId]),
      });
      final newContacts = List<String>.from(user.contactIds)..remove(contactId);
      state = AsyncValue.data(user.copyWith(contactIds: newContacts));
    }
  }

  Future<void> blockUser(String userIdToBlock) async {
    final user = state.valueOrNull;
    if (user == null) return;

    final blocked = List<String>.from(user.blockedUsers);
    if (!blocked.contains(userIdToBlock)) {
      blocked.add(userIdToBlock);
      await _firestore.collection(_usersCollection).doc(user.id).update({
        'blockedUsers': blocked,
      });
      state = AsyncValue.data(user.copyWith(blockedUsers: blocked));
    }
  }

  Future<void> unblockUser(String userIdToUnblock) async {
    final user = state.valueOrNull;
    if (user == null) return;

    final blocked = List<String>.from(user.blockedUsers);
    if (blocked.contains(userIdToUnblock)) {
      blocked.remove(userIdToUnblock);
      await _firestore.collection(_usersCollection).doc(user.id).update({
        'blockedUsers': blocked,
      });
      state = AsyncValue.data(user.copyWith(blockedUsers: blocked));
    }
  }

  Future<void> toggleMessageRestriction(String userId, bool restricted) async {
    await _firestore.collection(_usersCollection).doc(userId).update({
      'isMessageRestricted': restricted,
    });
  }

  Future<void> moveMessageToTrash(String messageId) async {
    final user = state.valueOrNull;
    if (user == null) return;

    // Usamos tanto la global para Mail como la privada para Chat para seguridad
    await _firestore.collection('messages').doc(messageId).update({
      'labels': FieldValue.arrayUnion(['trash', 'trash_${user.id}']),
    });
  }

  Future<void> restoreMessageFromTrash(String messageId) async {
    final user = state.valueOrNull;
    if (user == null) return;

    await _firestore.collection('messages').doc(messageId).update({
      'labels': FieldValue.arrayRemove(['trash', 'trash_${user.id}']),
    });
  }

  Stream<List<Message>> getMessagesStream(String label) {
    final user = state.valueOrNull;
    if (user == null) return Stream.value([]);

    // Filtramos mensajes donde el usuario es remitente (sent) o destinatario (inbox/trash)
    // El usuario ha creado los índices necesarios en la consola de Firebase.
    Query query = _firestore.collection('messages');

    // Para la papelera, usamos la etiqueta privada única del usuario.
    // Esto evita errores de índice y garantiza privacidad total.
    final String labelToQuery = label == 'trash' ? 'trash_${user.id}' : label;

    // Filtramos por ID en Firestore por seguridad (privacidad),
    // pero ordenamos en Dart para evitar pedir índices compuestos.
    if (label == 'sent') {
      query = query.where('senderId', isEqualTo: user.id);
    } else if (label != 'trash') {
      query = query.where('receiverId', isEqualTo: user.id);
    }

    return query
        .where('labels', arrayContains: labelToQuery)
        .snapshots()
        .handleError((error) {
          debugPrint(
            'ERROR EN STREAM DE MENSAJES (Probable falta de índice): $error',
          );
          throw error;
        })
        .map((snapshot) {
          return snapshot.docs
              .map(
                (doc) =>
                    Message.fromMap(doc.data() as Map<String, dynamic>, doc.id),
              )
              .where((msg) {
                // Si el mensaje tiene dueño, debe ser el usuario actual
                if (msg.ownerId != null && msg.ownerId != user.id) return false;

                // Si estamos en una carpeta activa (no trash), ocultar si está en la papelera
                if (label != 'trash') {
                  if (msg.labels.contains('trash')) return false;
                  if (msg.labels.contains('trash_${user.id}')) return false;
                }

                return true;
              })
              .toList()
            ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
        });
  }

  /// Stream para buscar usuarios específicos por sus IDs (usado en lista de contactos)
  Stream<List<User>> getContactsDataStream() {
    final user = state.valueOrNull;
    if (user == null || user.contactIds.isEmpty) return Stream.value([]);

    // Firestore limita whereIn a 10 items por consulta generalmente,
    // pero contactIds suele ser pequeña. Si crece, habrá que paginar.
    return _firestore
        .collection(_usersCollection)
        .where(FieldPath.documentId, whereIn: user.contactIds.take(10).toList())
        .snapshots()
        .map(
          (snap) =>
              snap.docs.map((doc) => User.fromMap(doc.data(), doc.id)).toList(),
        );
  }

  /// Busca un usuario por su Apodo o ID para añadirlo
  Future<User?> findUserToContact(String query) async {
    final sanitizedQuery = query.toLowerCase().trim();
    if (sanitizedQuery.isEmpty) return null;

    // 1. Buscar por ID exacto
    final docById = await _firestore
        .collection(_usersCollection)
        .doc(query)
        .get();
    if (docById.exists) {
      return User.fromMap(docById.data() as Map<String, dynamic>, docById.id);
    }

    // 2. Buscar por apodo
    final nicknameDoc = await _firestore
        .collection('nicknames')
        .doc(sanitizedQuery)
        .get();
    if (nicknameDoc.exists) {
      final email = nicknameDoc.data()?['email'];
      final userSnap = await _firestore
          .collection(_usersCollection)
          .where('correo', isEqualTo: email)
          .get();
      if (userSnap.docs.isNotEmpty) {
        return User.fromMap(userSnap.docs.first.data(), userSnap.docs.first.id);
      }
    }
    return null;
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

  /// Envía un mensaje de chat (1 sola copia en Firestore con chatId).
  /// Compatible con las reglas Firestore existentes (colección `messages`).
  Future<void> sendChatMessage({
    required String receiverId,
    required String body,
    List<File> images = const [],
    List<File> videoFiles = const [],
    String? senderIdOverride, // Nuevo: permite actuar como system_admin
  }) async {
    final user = state.valueOrNull;
    if (user == null) throw Exception('No autenticado.');
    if (body.trim().isEmpty && images.isEmpty && videoFiles.isEmpty) return;

    final effectiveSenderId = senderIdOverride ?? user.id;

    final isAdmin =
        user.role == UserRole.Admin || user.role == UserRole.SuperAdmin;
    if (!isAdmin &&
        !user.contactIds.contains(receiverId) &&
        senderIdOverride != 'system_admin') {
      throw Exception(
        'Solo puedes chatear con colegas de tu Red Galáctica. ¡Añádelo primero!',
      );
    }

    final List<String> imageUrls = [];
    if (images.isNotEmpty) {
      for (var i = 0; i < images.length; i++) {
        final storageRef = FirebaseStorage.instance
            .ref()
            .child('messages')
            .child(
              '${effectiveSenderId}_img_${DateTime.now().millisecondsSinceEpoch}_$i.jpg',
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
              '${effectiveSenderId}_vid_${DateTime.now().millisecondsSinceEpoch}_$i.mp4',
            );
        await storageRef.putFile(videoFiles[i]);
        videoUrls.add(await storageRef.getDownloadURL());
      }
    }

    final chatId = Message.buildChatId(effectiveSenderId, receiverId);
    final message = Message(
      id: '',
      senderId: effectiveSenderId,
      receiverId: receiverId,
      subject: '',
      body: body.trim(),
      imageUrls: imageUrls,
      videoUrls: videoUrls,
      timestamp: DateTime.now(),
      labels: const [],
      chatId: chatId,
    );

    await _firestore.collection('messages').add(message.toMap());

    final senderName = (user.apodo?.isNotEmpty == true)
        ? user.apodo!
        : user.nombre;
    NotificationService.notifyNewMail(
      targetUserId: receiverId,
      sourceUserId: user.id,
      sourceUserName: senderName,
      subject: body.trim().length > 50
          ? '${body.trim().substring(0, 50)}…'
          : body.trim(),
    );

    if (!user.contactIds.contains(receiverId)) {
      await _firestore.collection(_usersCollection).doc(user.id).update({
        'contactIds': FieldValue.arrayUnion([receiverId]),
      });
      state = AsyncValue.data(
        user.copyWith(contactIds: [...user.contactIds, receiverId]),
      );
    }
  }

  /// Stream de conversaciones activas (último mensaje por chatId).
  Stream<List<Message>> getChatConversationsStream() {
    final user = state.valueOrNull;
    if (user == null) return Stream.value([]);

    final isAdmin =
        user.role == UserRole.Admin || user.role == UserRole.SuperAdmin;

    final asSenderQuery = _firestore
        .collection('messages')
        .where('senderId', isEqualTo: user.id);

    final asReceiverQuery = _firestore
        .collection('messages')
        .where('receiverId', isEqualTo: user.id);

    // Si es admin, también escucha a system_admin
    final List<Stream<QuerySnapshot>> streams = [
      asSenderQuery.snapshots(),
      asReceiverQuery.snapshots(),
    ];

    if (isAdmin) {
      streams.add(
        _firestore
            .collection('messages')
            .where('senderId', isEqualTo: 'system_admin')
            .snapshots(),
      );
      streams.add(
        _firestore
            .collection('messages')
            .where('receiverId', isEqualTo: 'system_admin')
            .snapshots(),
      );
    }

    // Usamos un stream combinado reactivo directo de Firestore en lugar de periodic polling.
    // Esto es mucho más eficiente y responde al instante.
    final combinedStream = StreamGroup.merge([
      asSenderQuery.snapshots(),
      asReceiverQuery.snapshots(),
      if (isAdmin) ...[
        _firestore
            .collection('messages')
            .where('senderId', isEqualTo: 'system_admin')
            .snapshots(),
        _firestore
            .collection('messages')
            .where('receiverId', isEqualTo: 'system_admin')
            .snapshots(),
      ],
    ]);

    return combinedStream
        .map((_) {
          // Re-consultar todos los documentos para asegurar coherencia total en la combinación
          // (StreamGroup.merge emite cada vez que uno de los hijos cambia).
          // Nota: En una app de producción esto se optimizaría con caché local.
          return []; // Placeholder temporal para la estructura asyncExpand debajo
        })
        .asyncExpand((_) async* {
          final List<QuerySnapshot> snapshots = [];
          for (final s in streams) {
            snapshots.add(await s.first);
          }

          final allDocs = snapshots.expand((s) => s.docs).toList();
          final allMessages = allDocs
              .map(
                (doc) =>
                    Message.fromMap(doc.data() as Map<String, dynamic>, doc.id),
              )
              .toList();

          final Map<String, Message> latestByChatId = {};
          for (final msg in allMessages) {
            if (msg.chatId.isEmpty) continue;

            // Aislamiento por dueño:
            // 1. Si no tiene dueño, pasa (es chat normal).
            // 2. Si el dueño soy YO, pasa.
            // 3. ESPECIAL: Si involucra a system_admin, PASA para todos los Admins (Red compartida).
            final bool isSystemInvolved =
                msg.senderId == 'system_admin' ||
                msg.receiverId == 'system_admin';
            final bool canSeeSharedAdmin = isAdmin && isSystemInvolved;

            if (msg.ownerId != null &&
                msg.ownerId != user.id &&
                !canSeeSharedAdmin) {
              continue;
            }

            // Ignorar mensajes en papelera PRIVADA del usuario
            if (msg.labels.contains('trash_${user.id}')) continue;
            if (msg.labels.contains('deleted_${user.id}')) continue;
            if (msg.labels.contains('trash')) continue;

            final existing = latestByChatId[msg.chatId];
            if (existing == null || msg.timestamp.isAfter(existing.timestamp)) {
              latestByChatId[msg.chatId] = msg;
            }
          }

          final conversations = latestByChatId.values.toList()
            ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
          yield conversations;
        })
        .distinct((prev, next) {
          if (prev.length != next.length) return false;
          for (int i = 0; i < prev.length; i++) {
            if (prev[i].id != next[i].id ||
                prev[i].timestamp != next[i].timestamp) {
              return false;
            }
          }
          return true;
        });
  }

  /// Stream del historial de mensajes de una conversación.
  /// Excluye mensajes que han sido movidos a la Papelera.
  Stream<List<Message>> getChatMessagesStream(String chatId) {
    final user = state.valueOrNull;
    if (user == null) return Stream.value([]);

    final isAdmin =
        user.role == UserRole.Admin || user.role == UserRole.SuperAdmin;

    // Quitamos 'orderBy' de la query de Firestore para evitar errores de índices ausentes.
    // Ordenamos en memoria para mayor robustez durante el desarrollo.
    return _firestore
        .collection('messages')
        .snapshots()
        .handleError((e) {
          debugPrint('getChatMessagesStream error: $e');
        })
        .map((snap) {
          final messages = snap.docs
              .map((doc) {
                return Message.fromMap(doc.data(), doc.id);
              })
              .where((msg) {
                // Filtrar por el chatId solicitado (reconstruido en el cliente si es necesario)
                if (msg.chatId != chatId) return false;

                // Aislamiento por dueño:
                // 1. Si no tiene dueño, pasa.
                // 2. Si el dueño soy YO, pasa.
                // 3. ESPECIAL: Si involucra a system_admin, PASA para todos los Admins (Red compartida).
                final bool isSystemInvolved =
                    msg.senderId == 'system_admin' ||
                    msg.receiverId == 'system_admin';
                final bool canSeeSharedAdmin = isAdmin && isSystemInvolved;

                if (msg.ownerId != null &&
                    msg.ownerId != user.id &&
                    !canSeeSharedAdmin) {
                  return false;
                }

                // Filtrar mensajes borrados
                if (msg.labels.contains('trash')) return false;
                if (msg.labels.contains('trash_${user.id}')) return false;
                if (msg.labels.contains('deleted_${user.id}')) return false;

                return true;
              })
              .toList();

          // Ordenar cronológicamente en memoria
          messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
          return messages;
        });
  }

  /// Marca como leídos todos mis mensajes no leídos en un chat.
  Future<void> markChatMessagesAsRead(String chatId) async {
    final user = state.valueOrNull;
    if (user == null) return;

    final isAdmin =
        user.role == UserRole.Admin || user.role == UserRole.SuperAdmin;

    try {
      // Un admin puede marcar mensajes enviados a 'system_admin' como leídos.
      final receiverIds = [user.id];
      if (isAdmin) receiverIds.add('system_admin');

      final snap = await _firestore
          .collection('messages')
          .where('receiverId', whereIn: receiverIds)
          .where('isRead', isEqualTo: false)
          .get();

      if (snap.docs.isEmpty) return;
      final batch = _firestore.batch();
      int updatedCount = 0;
      for (final doc in snap.docs) {
        final msgData = doc.data();
        final msgChatId = msgData['chatId'] as String? ?? '';

        // Si el chatId coincide directamente en Firestore, o si está vacío pero el Message.fromMap lo asimilaría a este chat
        bool matches = false;
        if (msgChatId == chatId) {
          matches = true;
        } else if (msgChatId.isEmpty) {
          final senderId = msgData['senderId'] as String? ?? '';
          final receiverId = msgData['receiverId'] as String? ?? '';
          if (Message.buildChatId(senderId, receiverId) == chatId) {
            matches = true;
          }
        }

        if (matches) {
          batch.update(doc.reference, {'isRead': true});
          updatedCount++;
        }
      }

      if (updatedCount > 0) {
        await batch.commit();
      }
    } catch (e) {
      debugPrint('markChatMessagesAsRead error: $e');
    }
  }

  /// Mueve un mensaje de chat a la papelera PRIVADA del usuario.
  Future<void> deleteChatMessage(String messageId) async {
    final user = state.valueOrNull;
    if (user == null) return;

    await _firestore.collection('messages').doc(messageId).update({
      'labels': FieldValue.arrayUnion(['trash_${user.id}']),
    });
  }

  /// Mueve TODOS los mensajes de un chatId a la papelera (eliminar conversación).
  Future<void> deleteChatConversation(String chatId) async {
    final user = state.valueOrNull;
    if (user == null) return;

    // Buscamos TODOS los mensajes. Filtramos por chatId en el cliente para ser robustos ante mensajes sin campo explícito.
    final snap = await _firestore.collection('messages').get();

    final batch = _firestore.batch();
    int count = 0;
    for (final doc in snap.docs) {
      final msg = Message.fromMap(doc.data(), doc.id);
      if (msg.chatId == chatId) {
        batch.update(doc.reference, {
          'labels': FieldValue.arrayUnion(['trash_${user.id}']),
        });
        count++;
      }
    }

    if (count > 0) {
      await batch.commit();
    }
  }

  /// Elimina definitivamente un mensaje.
  /// Para correos tradicionales, borra el documento.
  /// Para chats, solo lo oculta visualmente; lo borra de la BD solo si la otra persona también lo borró.
  Future<void> permanentlyDeleteMessage(String messageId) async {
    final user = state.valueOrNull;
    if (user == null) return;

    final doc = await _firestore.collection('messages').doc(messageId).get();
    if (!doc.exists) return;

    final data = doc.data()!;
    // Si es un correo tradicional (ownerId presente) lo borramos de inmediato.
    if (data['ownerId'] != null) {
      await doc.reference.delete();
      return;
    }

    final labels = List<String>.from(data['labels'] ?? []);
    final otherUserId = data['senderId'] == user.id
        ? data['receiverId']
        : data['senderId'];
    final isDeletedByOther = labels.contains('deleted_$otherUserId');

    if (isDeletedByOther) {
      await doc.reference.delete();
    } else {
      labels.remove('trash');
      labels.remove('trash_${user.id}');
      if (!labels.contains('deleted_${user.id}')) {
        labels.add('deleted_${user.id}');
      }
      await doc.reference.update({'labels': labels});
    }
  }

  /// Restaura una conversación completa de la papelera (Chat).
  Future<void> restoreChatConversation(String chatId) async {
    final user = state.valueOrNull;
    if (user == null) return;

    final snap = await _firestore
        .collection('messages')
        .where('chatId', isEqualTo: chatId)
        .get();

    if (snap.docs.isEmpty) return;

    final batch = _firestore.batch();
    for (final doc in snap.docs) {
      final labels = List<String>.from(doc.data()['labels'] ?? []);
      if (labels.contains('trash_${user.id}')) {
        batch.update(doc.reference, {
          'labels': FieldValue.arrayRemove(['trash', 'trash_${user.id}']),
        });
      }
    }
    await batch.commit();
  }

  /// Elimina definitivamente todos los mensajes de un chat que estaban en papelera para este usuario.
  Future<void> permanentlyDeleteChatConversation(String chatId) async {
    final user = state.valueOrNull;
    if (user == null) return;

    final snap = await _firestore
        .collection('messages')
        .where('chatId', isEqualTo: chatId)
        .get();

    if (snap.docs.isEmpty) return;

    final batch = _firestore.batch();
    for (final doc in snap.docs) {
      final data = doc.data();

      final labels = List<String>.from(data['labels'] ?? []);
      final otherUserId = data['senderId'] == user.id
          ? data['receiverId']
          : data['senderId'];
      final isDeletedByOther = labels.contains('deleted_$otherUserId');

      if (labels.contains('trash_${user.id}')) {
        if (isDeletedByOther) {
          batch.delete(doc.reference);
        } else {
          labels.remove('trash');
          labels.remove('trash_${user.id}');
          if (!labels.contains('deleted_${user.id}')) {
            labels.add('deleted_${user.id}');
          }
          batch.update(doc.reference, {'labels': labels});
        }
      }
    }
    await batch.commit();
  }

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

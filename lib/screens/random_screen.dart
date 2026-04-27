import 'dart:io';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:lambda_app/providers/auth_provider.dart';
import 'package:lambda_app/providers/notification_providers.dart';
import 'package:lambda_app/models/user_model.dart';
import 'package:lambda_app/screens/thread_screen.dart';

class RandomScreen extends ConsumerStatefulWidget {
  static const String routeName = '/random';
  const RandomScreen({super.key});

  @override
  ConsumerState<RandomScreen> createState() => _RandomScreenState();
}

class _RandomScreenState extends ConsumerState<RandomScreen> {
  final TextEditingController _titleCtrl = TextEditingController();
  final TextEditingController _msgCtrl = TextEditingController();
  late String _anonId;
  File? _selectedImage;
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    _anonId = Random().nextInt(99999999).toString().padLeft(8, '0');
    _incrementVisits();
    // Marca Random como visto para limpiar el badge en el dashboard
    WidgetsBinding.instance.addPostFrameCallback((_) {
      markRandomAsSeen(ref.read(lastSeenRandomTimestampProvider.notifier));
    });
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 75,
    );
    if (picked != null) {
      setState(() {
        _selectedImage = File(picked.path);
      });
    }
  }

  Future<String?> _uploadImage(File img) async {
    try {
      final ext = img.path.split('.').last;
      final fileName = '${DateTime.now().millisecondsSinceEpoch}_$_anonId.$ext';
      final ref = FirebaseStorage.instance
          .ref()
          .child('random_board')
          .child(fileName);
      final uploadTask = await ref.putFile(img);
      return await uploadTask.ref.getDownloadURL();
    } catch (e) {
      debugPrint('====================================');
      debugPrint('Error upload: $e');
      debugPrint('====================================');
      return null;
    }
  }

  Future<void> _createThread() async {
    final user = ref.read(authProvider).valueOrNull;
    if (user == null) return;

    final title = _titleCtrl.text.trim();
    final text = _msgCtrl.text.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'El cuerpo del post no puede estar vacío, po weón.',
            style: TextStyle(color: Colors.redAccent),
          ),
        ),
      );
      return;
    }

    setState(() => _isUploading = true);

    String? imageUrl;
    if (_selectedImage != null) {
      imageUrl = await _uploadImage(_selectedImage!);
    }

    try {
      final docRef = FirebaseFirestore.instance
          .collection('random_board')
          .doc();
      final newPostId = await FirebaseFirestore.instance.runTransaction<int>((
        tx,
      ) async {
        final counterRef = FirebaseFirestore.instance
            .collection('metadata')
            .doc('app_stats');
        final snapshot = await tx.get(counterRef);
        int currentId = 0;
        if (snapshot.exists) {
          currentId = (snapshot.data()?['randomCount'] as int?) ?? 0;
        }
        final nextId = currentId + 1;
        tx.set(counterRef, {'randomCount': nextId}, SetOptions(merge: true));

        tx.set(docRef, {
          'title': title.isNotEmpty ? title : 'Sin título',
          'text': text,
          'timestamp': FieldValue.serverTimestamp(),
          'authorId': _anonId,
          'postId': nextId,
          'userId': user.id,
          'apodo': user.apodo,
          'correo': user.correo,
          'imageUrl': imageUrl,
          'replyCount': 0,
          'lastBump': FieldValue.serverTimestamp(), // Para ordenar el board
        });
        return nextId;
      });

      _titleCtrl.clear();
      _msgCtrl.clear();
      setState(() {
        _selectedImage = null;
        _isUploading = false;
      });
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ThreadScreen(
              threadId: docRef.id,
              opData: {
                'title': title.isNotEmpty ? title : 'Sin título',
                'text': text,
                'authorId': _anonId,
                'postId': newPostId,
                'apodo': user.apodo,
                'correo': user.correo,
                'userId': user.id,
                'imageUrl': imageUrl,
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Pucha, error al crear OP: $e',
              style: const TextStyle(color: Colors.redAccent),
            ),
          ),
        );
      }
      setState(() => _isUploading = false);
    }
  }

  Future<void> _moveToRecycleBin(
    String docId,
    Map<String, dynamic> data,
    String reason,
  ) async {
    final user = ref.read(authProvider).valueOrNull;
    try {
      final docRef = FirebaseFirestore.instance
          .collection('random_board')
          .doc(docId);
      final recycleRef = FirebaseFirestore.instance
          .collection('recycle_bin_posts')
          .doc();

      await FirebaseFirestore.instance.runTransaction((tx) async {
        tx.set(recycleRef, {
          'originalPath': docRef.path,
          'isOP': true,
          'reason': reason,
          'deletedAt': FieldValue.serverTimestamp(),
          'deletedBy': user?.id ?? 'Unknown',
          'data': data,
        });
        tx.delete(docRef);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Hilo mandado a la papelera, todo un vio',
              style: TextStyle(color: Colors.white),
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Cagamos, error: $e',
              style: const TextStyle(color: Colors.white),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showDeleteDialog(
    BuildContext context,
    String docId,
    Map<String, dynamic> data,
  ) {
    final reasonCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text(
          'Mover a Papelera',
          style: TextStyle(color: Colors.redAccent),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Tírate una justificación pa mandar este hilo a la papelera:',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: 'La pulenta razón...',
                hintStyle: TextStyle(color: Colors.grey),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.grey),
                ),
                focusedBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.redAccent),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            child: const Text(
              'Cancelar',
              style: TextStyle(color: Colors.white),
            ),
            onPressed: () => Navigator.of(ctx).pop(),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              final reason = reasonCtrl.text.trim();
              if (reason.isEmpty) return;
              Navigator.of(ctx).pop();
              _moveToRecycleBin(docId, data, reason);
            },
            child: const Text(
              'A Papelera',
              style: TextStyle(color: Colors.black),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _incrementVisits() async {
    try {
      await FirebaseFirestore.instance
          .collection('metadata')
          .doc('board_stats')
          .set(
            {'totalVisits': FieldValue.increment(1)},
            SetOptions(merge: true),
          );
    } catch (_) {
      // Si falla, no rompemos la UI
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _msgCtrl.dispose();
    super.dispose();
  }

  void _showNewThreadBottomSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0F0F0F),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 16,
          right: 16,
          top: 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'ARMA TU WEÁ DE HILO',
              style: TextStyle(
                color: Color(0xFFE5B56D),
                fontSize: 16,
                fontWeight: FontWeight.bold,
                fontFamily: 'Courier',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _titleCtrl,
              style: const TextStyle(
                color: Color(0xFFC5C8C6),
                fontFamily: 'Courier',
              ),
              decoration: InputDecoration(
                hintText: 'Asunto...',
                hintStyle: const TextStyle(color: Colors.white24),
                filled: true,
                fillColor: const Color(0xFF282A2E),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                focusedBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFFE5B56D), width: 1.0),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _msgCtrl,
              style: const TextStyle(
                color: Color(0xFFC5C8C6),
                fontFamily: 'Courier',
              ),
              maxLines: 5,
              minLines: 3,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: '> be me...',
                hintStyle: const TextStyle(
                  color: Color(0xFF789922),
                  fontStyle: FontStyle.italic,
                ),
                filled: true,
                fillColor: const Color(0xFF282A2E),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                focusedBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFFE5B56D), width: 1.0),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(4),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (_selectedImage != null)
              Stack(
                alignment: Alignment.topRight,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(
                      _selectedImage!,
                      height: 120,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.cancel, color: Colors.white),
                    onPressed: () => setState(() => _selectedImage = null),
                  ),
                ],
              ),
            if (_selectedImage == null)
              OutlinedButton.icon(
                onPressed: _pickImage,
                icon: const Icon(Icons.image, color: Color(0xFFC5C8C6)),
                label: const Text(
                  'Adjuntar Fotito',
                  style: TextStyle(
                    color: Color(0xFFC5C8C6),
                    fontFamily: 'Courier',
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFF373B41)),
                ),
              ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _isUploading
                  ? null
                  : () {
                      Navigator.pop(context);
                      _createThread();
                    },
              icon: _isUploading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.black,
                      ),
                    )
                  : const Icon(Icons.send, color: Colors.black),
              label: Text(
                _isUploading ? 'SUBIENDO LA WEÁ...' : 'POSTEAR',
                style: TextStyle(
                  color: Colors.black,
                  fontFamily: 'Courier',
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE5B56D),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userAsync = ref.watch(authProvider);
    final currentUser = userAsync.valueOrNull;
    final isAdmin =
        currentUser?.role == UserRole.Admin ||
        currentUser?.role == UserRole.SuperAdmin;

    return Scaffold(
      backgroundColor: const Color(0xFF1D1F21),
      appBar: AppBar(
        title: const Text(
          'Random',
          style: TextStyle(
            color: Colors.yellowAccent,
            fontFamily: 'Courier',
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: const Color(0xFF0F0F0F),
        iconTheme: const IconThemeData(color: Color(0xFFE5B56D)),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showNewThreadBottomSheet,
        backgroundColor: const Color(0xFFE5B56D),
        child: const Icon(Icons.add, color: Colors.black),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('random_board')
            .orderBy('lastBump', descending: true)
            .limit(15)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Error: ${snapshot.error}',
                style: const TextStyle(color: Colors.red),
              ),
            );
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Color(0xFFE5B56D)),
            );
          }

          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Center(
              child: Text(
                'Puta la weá vacía. Échale carbón y sé el primer OP.',
                style: TextStyle(
                  color: Color(0xFFC5C8C6),
                  fontFamily: 'Courier',
                ),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.only(top: 16, bottom: 80),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final data = docs[index].data() as Map<String, dynamic>;
              final threadId = docs[index].id;
              final title = data['title'] as String? ?? '';
              final text = data['text'] as String? ?? '';
              final authorId = data['authorId'] as String? ?? '00000000';
              final postIdVal = data['postId'] as int?;
              final displayId = postIdVal?.toString() ?? authorId;
              final correo = data['correo'] as String? ?? '';
              final imageUrl = data['imageUrl'] as String?;
              final repCount = data['replyCount'] as int? ?? 0;
              final ts = data['timestamp'] as Timestamp?;

              final dateStr = ts != null
                  ? DateFormat('MM/dd/yy(EEE)HH:mm:ss').format(ts.toDate())
                  : '??/??/??(???)??:??:??';
              final previewText = text.split('\n').first;

              return InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          ThreadScreen(threadId: threadId, opData: data),
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 8,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // File info + Header
                      if (imageUrl != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2.0),
                          child: Text(
                            'File: image.jpg (1024x768, 500 KB)',
                            style: const TextStyle(
                              color: Color(0xFFC5C8C6),
                              fontSize: 12,
                              fontFamily: 'Courier',
                            ),
                          ),
                        ),
                      RichText(
                        text: TextSpan(
                          children: [
                            TextSpan(
                              text: '$title ',
                              style: const TextStyle(
                                color: Color(0xFF0f0c5c), // Dark blue subject
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                fontFamily: 'Courier',
                              ),
                            ),
                            TextSpan(
                              text: 'Anonymous ',
                              style: const TextStyle(
                                color: Color(0xFF117743), // 4chan green name
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            if (isAdmin && correo.isNotEmpty)
                              TextSpan(
                                text: '[$correo] ',
                                style: const TextStyle(
                                  color: Colors.redAccent,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            TextSpan(
                              text: '$dateStr ',
                              style: const TextStyle(
                                color: Color(0xFFC5C8C6),
                                fontSize: 13,
                                fontFamily: 'Courier',
                              ),
                            ),
                            TextSpan(
                              text: 'No.$displayId ',
                              style: const TextStyle(
                                color: Color(0xFFE5B56D),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      // Image and text
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (imageUrl != null)
                            Padding(
                              padding: const EdgeInsets.only(
                                right: 16.0,
                                bottom: 4.0,
                              ),
                              child: MouseRegion(
                                cursor: SystemMouseCursors.click,
                                child: GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () {
                                    showDialog(
                                      context: context,
                                      builder: (_) => Dialog(
                                        backgroundColor: Colors.transparent,
                                        insetPadding: EdgeInsets.zero,
                                        child: Stack(
                                          alignment: Alignment.center,
                                          children: [
                                            InteractiveViewer(
                                              child: Image.network(imageUrl),
                                            ),
                                            Positioned(
                                              top: 40,
                                              right: 20,
                                              child: IconButton(
                                                icon: const Icon(
                                                  Icons.close,
                                                  color: Colors.white,
                                                  size: 30,
                                                ),
                                                onPressed: () =>
                                                    Navigator.pop(context),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                  child: Image.network(
                                    imageUrl,
                                    width: 150,
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              ),
                            ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  previewText.length > 300
                                      ? '${previewText.substring(0, 300)}...'
                                      : previewText,
                                  style: TextStyle(
                                    color:
                                        previewText.trimLeft().startsWith('>')
                                        ? const Color(0xFF789922)
                                        : const Color(0xFFC5C8C6),
                                    fontSize: 13,
                                    fontFamily: 'Courier',
                                  ),
                                ),
                                const SizedBox(height: 12),
                                // Replies link
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '[Ver hilo]',
                                        style: const TextStyle(
                                          color: Color(0xFF81A2BE),
                                          fontSize: 13,
                                          fontFamily: 'Courier',
                                          decoration: TextDecoration.underline,
                                        ),
                                      ),
                                    ),
                                    Row(
                                      children: [
                                        Text(
                                          'Respuestas: $repCount',
                                          style: const TextStyle(
                                            color: Color(0xFF969896),
                                            fontSize: 12,
                                            fontFamily: 'Courier',
                                          ),
                                        ),
                                        if (isAdmin)
                                          IconButton(
                                            padding: const EdgeInsets.only(
                                              left: 8,
                                            ),
                                            constraints: const BoxConstraints(),
                                            icon: const Icon(
                                              Icons.delete_outline,
                                              color: Colors.redAccent,
                                              size: 20,
                                            ),
                                            onPressed: () {
                                              _showDeleteDialog(
                                                context,
                                                threadId,
                                                data,
                                              );
                                            },
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Divider(color: Color(0xFF373B41), height: 1),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

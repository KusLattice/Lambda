import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:lambda_app/providers/auth_provider.dart';
import 'package:lambda_app/models/user_model.dart';
import 'dart:math';

class ThreadScreen extends ConsumerStatefulWidget {
  final String threadId;
  final Map<String, dynamic> opData;

  const ThreadScreen({super.key, required this.threadId, required this.opData});

  @override
  ConsumerState<ThreadScreen> createState() => _ThreadScreenState();
}

class _ThreadScreenState extends ConsumerState<ThreadScreen> {
  final TextEditingController _replyCtrl = TextEditingController();
  late String _anonId;
  File? _selectedImage;
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    _anonId = Random().nextInt(99999999).toString().padLeft(8, '0');
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
      debugPrint('Error upload in thread: $e');
      debugPrint('====================================');
      return null;
    }
  }

  Future<void> _postReply() async {
    final user = ref.read(authProvider).valueOrNull;
    if (user == null) return;

    final text = _replyCtrl.text.trim();
    if (text.isEmpty && _selectedImage == null) return;

    setState(() => _isUploading = true);

    String? imageUrl;
    if (_selectedImage != null) {
      imageUrl = await _uploadImage(_selectedImage!);
    }

    try {
      final threadRef = FirebaseFirestore.instance
          .collection('random_board')
          .doc(widget.threadId);
      final replyRef = threadRef.collection('replies').doc();

      // Transacción: Crear respuesta y actualizar contador + timestamp de hilo
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final counterRef = FirebaseFirestore.instance
            .collection('metadata')
            .doc('board_stats');
        final counterSnap = await tx.get(counterRef);
        int currentId = 2; // Empezamos de 3
        if (counterSnap.exists) {
          currentId = (counterSnap.data()?['lastPostId'] as int?) ?? 2;
        }
        final newPostId = currentId + 1;
        tx.set(counterRef, {'lastPostId': newPostId}, SetOptions(merge: true));

        tx.set(replyRef, {
          'text': text,
          'timestamp': FieldValue.serverTimestamp(),
          'authorId': _anonId,
          'postId': newPostId,
          'userId': user.id,
          'apodo': user.apodo,
          'correo': user.correo,
          'imageUrl': imageUrl,
        });
        tx.update(threadRef, {
          'replyCount': FieldValue.increment(1),
          'lastBump': FieldValue.serverTimestamp(),
        });
      });
      _replyCtrl.clear();
      setState(() {
        _selectedImage = null;
        _isUploading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error al responder: $e',
              style: const TextStyle(color: Colors.redAccent),
            ),
          ),
        );
      }
      setState(() => _isUploading = false);
    }
  }

  @override
  void dispose() {
    _replyCtrl.dispose();
    super.dispose();
  }

  Future<void> _moveToRecycleBin(
    String docId,
    Map<String, dynamic> data,
    bool isOP,
    String reason,
  ) async {
    final user = ref.read(authProvider).valueOrNull;
    try {
      final docRef = isOP
          ? FirebaseFirestore.instance.collection('random_board').doc(docId)
          : FirebaseFirestore.instance
                .collection('random_board')
                .doc(widget.threadId)
                .collection('replies')
                .doc(docId);
      final recycleRef = FirebaseFirestore.instance
          .collection('recycle_bin_posts')
          .doc();

      await FirebaseFirestore.instance.runTransaction((tx) async {
        tx.set(recycleRef, {
          'originalPath': docRef.path,
          'isOP': isOP,
          'reason': reason,
          'deletedAt': FieldValue.serverTimestamp(),
          'deletedBy': user?.id ?? 'Unknown',
          'data': data,
        });
        tx.delete(docRef);
        if (!isOP) {
          final threadRef = FirebaseFirestore.instance
              .collection('random_board')
              .doc(widget.threadId);
          tx.update(threadRef, {'replyCount': FieldValue.increment(-1)});
        }
      });
      if (mounted) {
        if (isOP) {
          Navigator.pop(
            context,
          ); // si borramos el OP, nos salimos del thread screen
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Respuesta enviada a la papelera',
                style: TextStyle(color: Colors.white),
              ),
              backgroundColor: Colors.orange,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error: $e',
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
    bool isOP,
  ) {
    final reasonCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: Text(
          isOP ? 'Mover Hilo a Papelera' : 'Mover Respuesta a Papelera',
          style: const TextStyle(color: Colors.redAccent),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Ingresa la justificación para enviar este post a la papelera:',
              style: TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: 'Razón...',
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
              _moveToRecycleBin(docId, data, isOP, reason);
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

  Widget _buildPostBox(
    String docId,
    Map<String, dynamic> data,
    bool isOP,
    bool isAdmin,
  ) {
    final title = data['title'] as String?;
    final text = data['text'] as String? ?? '';
    final authorId = data['authorId'] as String? ?? '00000000';
    final postIdVal = data['postId'] as int?;
    final displayId = postIdVal?.toString() ?? authorId;
    final correo = data['correo'] as String? ?? '';
    final imageUrl = data['imageUrl'] as String?;
    final ts = data['timestamp'] as Timestamp?;

    final dateStr = ts != null
        ? DateFormat('MM/dd/yy(EEE)HH:mm:ss').format(ts.toDate())
        : '??/??/??(???)??:??:??';
    final lines = text.split('\n');

    return Container(
      margin: EdgeInsets.only(left: isOP ? 4 : 16, right: 8, top: 4, bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      decoration: isOP
          ? null
          : BoxDecoration(
              color: const Color(0xFF282A2E), // Reply background hue
              border: Border(
                top: BorderSide(color: const Color(0xFF373B41), width: 1.0),
                left: BorderSide(color: const Color(0xFF373B41), width: 1.0),
                bottom: BorderSide(color: const Color(0xFF0F0F0F), width: 1.0),
                right: BorderSide(color: const Color(0xFF0F0F0F), width: 1.0),
              ),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header info
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: RichText(
                  text: TextSpan(
                    children: [
                      if (isOP && title != null)
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
                        text: 'No.$displayId',
                        style: const TextStyle(
                          color: Color(0xFFE5B56D),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (isAdmin)
                IconButton(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  icon: const Icon(
                    Icons.delete_outline,
                    color: Colors.redAccent,
                    size: 20,
                  ),
                  onPressed: () {
                    _showDeleteDialog(context, docId, data, isOP);
                  },
                ),
            ],
          ),
          const SizedBox(height: 6),
          // Body
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (imageUrl != null)
                Padding(
                  padding: const EdgeInsets.only(right: 16.0, bottom: 4.0),
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
                                    onPressed: () => Navigator.pop(context),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                      child: Image.network(
                        imageUrl,
                        width: isOP ? 250 : 150,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: lines.map((l) {
                    final isGreen = l.trimLeft().startsWith('>');
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 2.0),
                      child: Text(
                        l,
                        style: TextStyle(
                          color: isGreen
                              ? const Color(0xFF789922)
                              : const Color(0xFFC5C8C6),
                          fontSize: 13,
                          fontFamily: 'Courier',
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ],
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
          'HILO',
          style: TextStyle(
            color: Color(0xFFE5B56D),
            fontFamily: 'Courier',
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: const Color(0xFF0F0F0F),
        iconTheme: const IconThemeData(color: Color(0xFFE5B56D)),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                // El Post Original
                _buildPostBox(widget.threadId, widget.opData, true, isAdmin),
                const Divider(color: Color(0xFF373B41)),
                // Respuestas
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection('random_board')
                      .doc(widget.threadId)
                      .collection('replies')
                      .orderBy('timestamp', descending: false)
                      .limit(500)
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
                      return const SizedBox.shrink();
                    }

                    final replies = snapshot.data?.docs ?? [];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: replies
                          .map(
                            (doc) => _buildPostBox(
                              doc.id,
                              doc.data() as Map<String, dynamic>,
                              false,
                              isAdmin,
                            ),
                          )
                          .toList(),
                    );
                  },
                ),
              ],
            ),
          ),

          // Área de Posteo
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            color: const Color(0xFF0F0F0F),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _replyCtrl,
                    style: const TextStyle(
                      color: Color(0xFFC5C8C6),
                      fontFamily: 'Courier',
                    ),
                    maxLines: 4,
                    minLines: 1,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: 'Responder...',
                      hintStyle: const TextStyle(color: Colors.white24),
                      filled: true,
                      fillColor: const Color(0xFF282A2E),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      focusedBorder: const OutlineInputBorder(
                        borderSide: BorderSide(
                          color: Color(0xFFE5B56D),
                          width: 1.0,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(4),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (_selectedImage != null)
                  Stack(
                    alignment: Alignment.topRight,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(
                          _selectedImage!,
                          height: 48,
                          width: 48,
                          fit: BoxFit.cover,
                        ),
                      ),
                      Positioned(
                        right: -10,
                        top: -10,
                        child: IconButton(
                          icon: const Icon(
                            Icons.cancel,
                            color: Colors.white,
                            size: 16,
                          ),
                          onPressed: () =>
                              setState(() => _selectedImage = null),
                        ),
                      ),
                    ],
                  ),
                if (_selectedImage == null)
                  IconButton(
                    icon: const Icon(Icons.image, color: Color(0xFFC5C8C6)),
                    onPressed: _pickImage,
                  ),
                const SizedBox(width: 4),
                InkWell(
                  onTap: _isUploading ? null : _postReply,
                  borderRadius: BorderRadius.circular(50),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: const BoxDecoration(
                      color: Color(0xFF282A2E),
                      shape: BoxShape.circle,
                    ),
                    child: _isUploading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFFE5B56D),
                            ),
                          )
                        : const Icon(
                            Icons.send,
                            color: Color(0xFFE5B56D),
                            size: 20,
                          ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

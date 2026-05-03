import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lambda_app/models/fiber_cut_report.dart';
import 'package:lambda_app/providers/fiber_cut_provider.dart';
import 'package:lambda_app/screens/create_fiber_cut_screen.dart';
import 'package:lambda_app/models/user_model.dart';
import 'package:lambda_app/providers/auth_provider.dart';
import 'package:lambda_app/screens/map_screen.dart';
import 'package:lambda_app/widgets/image_zoom_gallery.dart';
import 'package:lambda_app/widgets/video_section.dart';
import 'package:timeago/timeago.dart' as timeago;

class FiberCutScreen extends ConsumerWidget {
  static const String routeName = '/fiber-cut';

  const FiberCutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportsAsync = ref.watch(activeFiberCutReportsProvider);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text(
          'FALLAS',
          style: TextStyle(fontFamily: 'Courier', fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.black,
        foregroundColor: Colors.redAccent,
        actions: const [],
      ),
      body: reportsAsync.when(
        data: (reports) {
          if (reports.isEmpty) {
            return const Center(
              child: Text(
                'NO SE DETECTAN FALLAS ACTIVAS.',
                style: TextStyle(color: Colors.white24, fontFamily: 'Courier'),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: reports.length,
            itemBuilder: (context, index) {
              final report = reports[index];
              return _FiberCutCard(report: report);
            },
          );
        },
        loading: () => const Center(
          child: CircularProgressIndicator(color: Colors.redAccent),
        ),
        error: (err, stack) => Center(
          child: Text(
            'ERROR DEL SISTEMA: $err',
            style: const TextStyle(color: Colors.red),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.redAccent,
        foregroundColor: Colors.black,
        onPressed: () {
          Navigator.pushNamed(context, CreateFiberCutScreen.routeName);
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _FiberCutCard extends ConsumerWidget {
  final FiberCutReport report;

  const _FiberCutCard({required this.report});

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final act = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.grey[900],
        title: const Text(
          'Eliminar Falla',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          '¿Estás seguro de que deseas eliminar este reporte?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Cancelar',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Eliminar',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );

    if (act == true) {
      try {
        await ref.read(fiberCutServiceProvider).deleteReport(report.id);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Reporte eliminado'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error al eliminar: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timeStr = timeago.format(report.createdAt, locale: 'es');
    final currentUser = ref.watch(authProvider).valueOrNull;

    final isCreator = currentUser?.id == report.reporterId;
    final isSuperAdmin = currentUser?.isSuperAdmin ?? false;
    final isAdmin = currentUser?.isAdmin ?? false;

    final canEdit = isCreator || isSuperAdmin;
    final canDelete = isCreator || isAdmin || isSuperAdmin;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.redAccent.withValues(alpha: 0.05),
        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (report.imageUrls.isNotEmpty)
            GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        ImageZoomGallery(imageUrls: report.imageUrls),
                  ),
                );
              },
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(8),
                ),
                child: SizedBox(
                  height: 200,
                  child: PageView.builder(
                    itemCount: report.imageUrls.length,
                    itemBuilder: (context, idx) {
                      return Image.network(
                        report.imageUrls[idx],
                        width: double.infinity,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const Icon(
                          Icons.broken_image,
                          color: Colors.white24,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'REPORTADO POR: ${report.reporterNickname.toUpperCase()}',
                            style: const TextStyle(
                              color: Colors.redAccent,
                              fontFamily: 'Courier',
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            timeStr,
                            style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 10,
                              fontFamily: 'Courier',
                            ),
                          ),
                        ],
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (canEdit)
                          IconButton(
                            icon: const Icon(
                              Icons.edit,
                              color: Colors.white54,
                              size: 20,
                            ),
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (ctx) => CreateFiberCutScreen(
                                    initialReport: report,
                                  ),
                                ),
                              );
                            },
                          ),
                        if (canDelete)
                          IconButton(
                            icon: const Icon(
                              Icons.delete,
                              color: Colors.white54,
                              size: 20,
                            ),
                            onPressed: () => _confirmDelete(context, ref),
                          ),
                        IconButton(
                          icon: const Icon(
                            Icons.location_on,
                            color: Colors.amber,
                          ),
                          onPressed: () {
                            Navigator.pushNamed(
                              context,
                              MapScreen.routeName,
                              arguments: report.location,
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (report.description != null &&
                    report.description!.isNotEmpty)
                  Text(
                    report.description!,
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                if (report.videoUrls.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  VideoSection(
                    videoUrls: report.videoUrls,
                    accentColor: Colors.redAccent,
                  ),
                ],
                const SizedBox(height: 12),
                // Detalles técnicos de ubicación
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.redAccent.withValues(alpha: 0.1),
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.map_outlined,
                            color: Colors.redAccent,
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${report.comuna ?? "SC"}, ${report.region ?? "SR"}'
                                  .toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                                fontFamily: 'Courier',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Divider(color: Colors.white10, height: 16),
                      Row(
                        children: [
                          const Icon(
                            Icons.location_on,
                            color: Colors.redAccent,
                            size: 14,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              report.address ?? 'DIRECCIÓN NO DISPONIBLE',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 10,
                                fontFamily: 'Courier',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(
                            Icons.gps_fixed,
                            color: Colors.redAccent,
                            size: 14,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'COORDS: ${report.location.latitude}, ${report.location.longitude}',
                            style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 9,
                              fontFamily: 'Courier',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Divider(color: Colors.white10),
                const SizedBox(height: 4),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

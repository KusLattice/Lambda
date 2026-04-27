import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lambda_app/models/fiber_cut_report.dart';
import 'package:lambda_app/services/fiber_cut_service.dart';

final fiberCutServiceProvider = Provider((ref) => FiberCutService());

final activeFiberCutReportsProvider = StreamProvider<List<FiberCutReport>>((
  ref,
) {
  final service = ref.watch(fiberCutServiceProvider);
  return service.getActiveReports();
});

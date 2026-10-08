import 'clinic_membership.dart';

String staffLabel(
  String userId,
  Iterable<Map<String, dynamic>> people, {
  String? role,
}) {
  final name = people
      .where((p) => p['user_id'] == userId)
      .firstOrNull?['display_name'];
  if (name is String && name.trim().isNotEmpty) return name.trim();
  final code = userId.length > 8 ? userId.substring(0, 8) : userId;
  final label = role == null ? 'Integrante' : ClinicRole.parse(role).label;
  return '$label · $code';
}

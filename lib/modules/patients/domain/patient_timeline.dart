import 'patient_models.dart';

String timelineSearchKey(String value) {
  var out = value.toLowerCase().trim();
  const accents = {'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u', 'ü': 'u'};
  for (final e in accents.entries) {
    out = out.replaceAll(e.key, e.value);
  }
  return out.replaceAll(RegExp(r'\s+'), ' ');
}

String eventReason(PatientEvent event) => event.kind == EventKind.soap
    ? (event.data['reason'] as String? ?? '').trim()
    : '';
DateTime eventClinicalDate(PatientEvent event) {
  // Unknown/approximate preventive dates are not represented as exact applications.
  if (event.kind == EventKind.preventive &&
      event.data['preventive_version'] == 1 &&
      event.data['date_precision'] != 'exact') {
    return event.createdAt.toUtc();
  }
  return DateTime.tryParse('${event.data['date']}T00:00:00Z') ??
      event.createdAt.toUtc();
}

List<PatientEvent> patientTimeline(
  List<PatientEvent> events, {
  String query = '',
  EventKind? kind,
  bool oldestFirst = false,
  bool byReason = false,
}) {
  final key = timelineSearchKey(query);
  final result = events
      .where(
        (e) =>
            (kind == null || e.kind == kind) &&
            (key.isEmpty || timelineSearchKey(eventReason(e)).contains(key)),
      )
      .toList();
  result.sort((a, b) {
    if (byReason) {
      final reasonA = timelineSearchKey(eventReason(a)),
          reasonB = timelineSearchKey(eventReason(b));
      final c = (reasonA.isEmpty ? '\uffff' : reasonA).compareTo(
        reasonB.isEmpty ? '\uffff' : reasonB,
      );
      if (c != 0) return c;
    }
    var c = eventClinicalDate(a).compareTo(eventClinicalDate(b));
    if (c == 0) c = a.createdAt.compareTo(b.createdAt);
    if (c == 0) c = a.id.compareTo(b.id);
    return oldestFirst ? c : -c;
  });
  return result;
}

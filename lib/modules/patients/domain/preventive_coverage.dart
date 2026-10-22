// Labels for manual recording, never a vaccination protocol or product mapping.
const preventiveCoverages = <String, String>{
  'rabies': 'Rabia',
  'canine_distemper': 'Moquillo canino',
  'canine_parvovirus': 'Parvovirosis canina',
  'canine_adenovirus': 'Adenovirus / hepatitis canina',
  'canine_parainfluenza': 'Parainfluenza canina',
  'leptospirosis': 'Leptospirosis (especificar serovares si se conocen)',
  'bordetella': 'Bordetella bronchiseptica',
  'feline_panleukopenia': 'Panleucopenia felina',
  'feline_herpesvirus': 'Herpesvirus / rinotraqueítis felina',
  'feline_calicivirus': 'Calicivirus felino',
  'feline_leukemia': 'Leucemia felina',
  'feline_chlamydia': 'Chlamydia felis',
  'internal_parasites': 'Parásitos internos (especificar)',
  'external_parasites': 'Parásitos externos (especificar)',
};

String coverageText(Iterable<String> components, String other) => [
  ...components.map((key) => preventiveCoverages[key] ?? key),
  if (other.trim().isNotEmpty) other.trim(),
].join('; ');

List<String> validateCoverage(dynamic value) {
  if (value is! List ||
      value.length > preventiveCoverages.length ||
      value.any((v) => v is! String || !preventiveCoverages.containsKey(v)) ||
      value.toSet().length != value.length) {
    throw const FormatException('Revisa las coberturas seleccionadas.');
  }
  return value.cast<String>().toList()..sort();
}

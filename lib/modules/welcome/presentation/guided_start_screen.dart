import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

const guideSteps = <(String, String, String)>[
  (
    '1. Elige tu espacio',
    'Usa tu espacio personal o la clínica de tu equipo. Los roles vienen de tu cuenta.',
    'Mi cuenta',
  ),
  (
    '2. Personaliza tu experiencia',
    'Elige una de las cinco paletas y apariencia clara u oscura.',
    'Ajustes',
  ),
  (
    '3. Conoce tus herramientas',
    'Explora las funciones y sus límites antes de cargar datos reales.',
    'Producto y costos',
  ),
  (
    '4. Revisa tu perfil y formatos',
    'Captura tus datos profesionales y revisa membrete, permisos y plantillas antes de emitir documentos.',
    'Receta',
  ),
  (
    '5. Registra tu primer paciente',
    'Captura datos con consentimiento y revisa el expediente. No agregamos pacientes de prueba automáticamente.',
    'Pacientes',
  ),
  (
    '6. Configura IA y revisa el plan',
    'La clave y el modelo son opcionales. Decide qué contexto compartir y consulta tu plan.',
    'Planes',
  ),
  (
    '7. Encuentra ayuda',
    'Reporta problemas, adjunta archivos y consulta el seguimiento de soporte.',
    'Ayuda y soporte',
  ),
];

class GuidedStartScreen extends StatefulWidget {
  const GuidedStartScreen({
    super.key,
    required this.scope,
    required this.onNavigate,
  });
  final String scope;
  final void Function(String) onNavigate;
  @override
  State<GuidedStartScreen> createState() => _GuidedStartScreenState();
}

class _GuidedStartScreenState extends State<GuidedStartScreen> {
  Set<int> done = {};
  bool loaded = false;
  String? error;
  String get storageKey => 'guided_start_v1_${widget.scope}';
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final values = p.getStringList(storageKey) ?? [];
      if (mounted) {
        setState(() {
          done = values.map(int.tryParse).whereType<int>().toSet();
          loaded = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          loaded = true;
          error = 'No se pudo recuperar tu progreso.';
        });
      }
    }
  }

  Future<void> mark(int i, bool value) async {
    final next = {...done};
    value ? next.add(i) : next.remove(i);
    try {
      final p = await SharedPreferences.getInstance();
      if (!await p.setStringList(storageKey, next.map((v) => '$v').toList())) {
        throw StateError('save');
      }
      if (mounted) {
        setState(() {
          done = next;
          error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error = 'No se pudo guardar el progreso en este dispositivo.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text('Inicio guiado', style: Theme.of(context).textTheme.headlineSmall),
      const Text(
        'Avanza a tu ritmo. Marcar un paso indica que lo revisaste; no verifica una configuración ni cambia tus permisos. Puedes volver a esta guía cuando quieras.',
      ),
      if (!loaded) const LinearProgressIndicator(),
      if (error != null) Text(error!),
      for (var i = 0; i < guideSteps.length; i++)
        Card(
          child: Column(
            children: [
              CheckboxListTile(
                value: done.contains(i),
                onChanged: !loaded ? null : (v) => mark(i, v ?? false),
                title: Text(guideSteps[i].$1),
                subtitle: Text(guideSteps[i].$2),
              ),
              TextButton(
                onPressed: () => widget.onNavigate(guideSteps[i].$3),
                child: const Text('Abrir'),
              ),
            ],
          ),
        ),
      Text(
        '${done.length} de ${guideSteps.length} pasos revisados · Progreso guardado solo en este dispositivo.',
      ),
    ],
  );
}

class FirstStepsBanner extends StatefulWidget {
  const FirstStepsBanner({
    super.key,
    required this.scope,
    required this.onOpen,
  });
  final String scope;
  final VoidCallback onOpen;
  @override
  State<FirstStepsBanner> createState() => _FirstStepsBannerState();
}

class _FirstStepsBannerState extends State<FirstStepsBanner> {
  bool visible = false;
  String get storageKey => 'guided_start_invitation_v1_${widget.scope}';
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final p = await SharedPreferences.getInstance();
      if (mounted) setState(() => visible = !(p.getBool(storageKey) ?? false));
    } catch (_) {
      if (mounted) setState(() => visible = true);
    }
  }

  Future<void> dismiss() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool(storageKey, true);
    } catch (_) {}
    if (mounted) setState(() => visible = false);
  }

  @override
  Widget build(BuildContext context) => !visible
      ? const SizedBox.shrink()
      : Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Bienvenido: configura tu espacio paso a paso'),
                const Text(
                  'Revisa la guía antes de comenzar. Puedes retomarla desde el menú.',
                ),
                Wrap(
                  children: [
                    FilledButton(
                      onPressed: widget.onOpen,
                      child: const Text('Comenzar guía'),
                    ),
                    TextButton(
                      onPressed: dismiss,
                      child: const Text('Más tarde'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
}

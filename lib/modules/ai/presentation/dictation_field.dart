import 'package:flutter/material.dart';
import '../../patients/application/voice_dictation.dart';

class DictationField extends StatefulWidget {
  const DictationField({
    super.key,
    required this.controller,
    required this.label,
    this.voice,
    this.onChanged,
    this.onListening,
    this.maxLength = 4000,
  });
  final TextEditingController controller;
  final String label;
  final VoiceDictation? voice;
  final VoidCallback? onChanged;
  final ValueChanged<bool>? onListening;
  final int maxLength;
  @override
  State<DictationField> createState() => _DictationFieldState();
}

class _DictationFieldState extends State<DictationField>
    with WidgetsBindingObserver {
  late final VoiceDictation voice = widget.voice ?? DeviceVoiceDictation();
  bool listening = false;
  int generation = 0;
  String? error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    generation++;
    WidgetsBinding.instance.removeObserver(this);
    voice.stop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && listening) stop();
  }

  Future<void> stop() async {
    generation++;
    await voice.stop();
    if (mounted) {
      setState(() => listening = false);
      widget.onListening?.call(false);
    }
  }

  Future<void> toggle() async {
    if (listening) {
      await stop();
      return;
    }
    final request = ++generation;
    final original = widget.controller.text.trimRight();
    setState(() {
      listening = true;
      error = null;
    });
    widget.onListening?.call(true);
    try {
      final ready = await voice.start(
        (text) {
          if (!mounted || request != generation) return;
          final value = [original, text].where((e) => e.isNotEmpty).join('\n');
          if (value.length > widget.maxLength) {
            setState(
              () => error =
                  'La transcripción supera el límite del campo. Detén el dictado y revisa el texto.',
            );
            return;
          }
          widget.controller.text = value;
          widget.onChanged?.call();
        },
        (message) {
          if (mounted && request == generation) {
            generation++;
            setState(() {
              error = message;
              listening = false;
            });
            widget.onListening?.call(false);
          }
        },
      );
      if (!mounted || request != generation) return;
      if (!ready) {
        setState(() {
          listening = false;
          error = 'El dictado no está disponible. Puedes escribir el texto.';
        });
        widget.onListening?.call(false);
      }
    } catch (_) {
      if (mounted && request == generation) {
        setState(() {
          listening = false;
          error = 'No se pudo iniciar el micrófono. Puedes escribir el texto.';
        });
        widget.onListening?.call(false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      TextField(
        controller: widget.controller,
        maxLines: 6,
        maxLength: widget.maxLength,
        onChanged: (_) => widget.onChanged?.call(),
        decoration: InputDecoration(labelText: widget.label),
      ),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          onPressed: toggle,
          icon: Icon(listening ? Icons.stop : Icons.mic),
          label: Text(listening ? 'Detener dictado' : 'Dictar texto'),
        ),
      ),
      if (error != null)
        Text(
          error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      const Text(
        'Revisa la transcripción antes de usarla. La disponibilidad del dictado depende del teléfono.',
      ),
    ],
  );
}

class VoiceNoteScreen extends StatefulWidget {
  const VoiceNoteScreen({
    super.key,
    required this.label,
    required this.initial,
    this.voice,
  });
  final String label, initial;
  final VoiceDictation? voice;
  @override
  State<VoiceNoteScreen> createState() => _VoiceNoteScreenState();
}

class _VoiceNoteScreenState extends State<VoiceNoteScreen> {
  late final controller = TextEditingController(text: widget.initial);
  bool listening = false, reviewed = false;
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.label)),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        DictationField(
          controller: controller,
          label: 'Nota escrita o dictada',
          voice: widget.voice,
          onChanged: () => setState(() => reviewed = false),
          onListening: (v) => setState(() => listening = v),
        ),
        CheckboxListTile(
          title: const Text('Revisé y corregí la transcripción'),
          value: reviewed,
          onChanged: listening
              ? null
              : (v) => setState(() => reviewed = v == true),
        ),
        FilledButton(
          onPressed: listening || !reviewed
              ? null
              : () => Navigator.pop(context, controller.text.trim()),
          child: const Text('Incorporar texto revisado'),
        ),
      ],
    ),
  );
}

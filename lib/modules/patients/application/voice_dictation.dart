import 'package:speech_to_text/speech_to_text.dart';

abstract interface class VoiceDictation {
  Future<bool> start(
    void Function(String) onText,
    void Function(String) onError,
  );
  Future<void> stop();
}

class DeviceVoiceDictation implements VoiceDictation {
  final speech = SpeechToText();
  int _generation = 0;
  @override
  Future<bool> start(
    void Function(String) onText,
    void Function(String) onError,
  ) async {
    final generation = ++_generation;
    final ready = await speech.initialize(
      onError: (_) => onError(
        'No se pudo transcribir. Revisa el permiso del micrófono o captura la nota manualmente.',
      ),
    );
    if (!ready || generation != _generation) return false;
    final locales = await speech.locales();
    if (generation != _generation) return false;
    final spanish = locales
        .where((l) => l.localeId.toLowerCase().startsWith('es'))
        .toList();
    if (spanish.isEmpty) {
      onError('No hay reconocimiento de voz en español disponible.');
      return false;
    }
    final locale =
        spanish
            .where(
              (l) => l.localeId.toLowerCase().replaceAll('-', '_') == 'es_mx',
            )
            .firstOrNull ??
        spanish.first;
    await speech.listen(
      onResult: (r) {
        if (generation == _generation) onText(r.recognizedWords);
      },
      listenOptions: SpeechListenOptions(
        localeId: locale.localeId,
        partialResults: true,
        cancelOnError: true,
      ),
    );
    if (generation != _generation) {
      await speech.cancel();
      return false;
    }
    return true;
  }

  @override
  Future<void> stop() {
    _generation++;
    return speech.cancel();
  }
}

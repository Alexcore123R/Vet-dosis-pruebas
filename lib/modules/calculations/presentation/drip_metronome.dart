import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class DripMetronome extends StatefulWidget {
  const DripMetronome({super.key, required this.dropsPerMinute});
  final double dropsPerMinute;
  @override
  State<DripMetronome> createState() => _DripMetronomeState();
}

class _DripMetronomeState extends State<DripMetronome>
    with WidgetsBindingObserver {
  Timer? timer;
  bool pulse = false, sound = false;
  bool get supported =>
      widget.dropsPerMinute.isFinite &&
      widget.dropsPerMinute > 0 &&
      widget.dropsPerMinute <= 240;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  void stop() {
    timer?.cancel();
    timer = null;
    if (mounted) setState(() => pulse = false);
  }

  @override
  void didUpdateWidget(covariant DripMetronome oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.dropsPerMinute != widget.dropsPerMinute) stop();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) stop();
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void start() {
    if (!supported) return;
    timer = Timer.periodic(
      Duration(microseconds: (60000000 / widget.dropsPerMinute).round()),
      (_) {
        if (!mounted) return;
        if (ModalRoute.of(context)?.isCurrent != true) {
          stop();
          return;
        }
        setState(() => pulse = !pulse);
        if (sound) SystemSound.play(SystemSoundType.click);
      },
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const Text('Metrónomo de goteo'),
      const Text(
        'Ayuda visual en primer plano; cada cambio de color representa una gota. No mide ni controla la infusión. Verifica el equipo y el goteo real.',
      ),
      Icon(
        Icons.water_drop,
        size: 36,
        color: pulse
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.outline,
      ),
      SwitchListTile(
        title: const Text('Sonido (según dispositivo)'),
        value: sound,
        onChanged: (v) => setState(() => sound = v),
      ),
      if (!supported)
        const Text(
          'Ritmo fuera del intervalo de reproducción: mayor que 0 y hasta 240 gotas/min.',
        ),
      OutlinedButton(
        onPressed: timer != null
            ? stop
            : supported
            ? start
            : null,
        child: Text(timer == null ? 'Iniciar metrónomo' : 'Detener metrónomo'),
      ),
    ],
  );
}

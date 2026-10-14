import 'package:flutter/material.dart';
import '../../hospital/application/hospital_alerts.dart';

class AlertPreferencesPanel extends StatefulWidget {
  const AlertPreferencesPanel({
    super.key,
    required this.alerts,
    this.onUpdated,
  });
  final HospitalAlerts? alerts;
  final Future<void> Function()? onUpdated;
  @override
  State<AlertPreferencesPanel> createState() => _AlertPreferencesPanelState();
}

class _AlertPreferencesPanelState extends State<AlertPreferencesPanel> {
  bool busy = false;
  String? error;
  Future<void> update({
    bool? sound,
    bool? vibration,
    bool? stockWarnings,
    int? lead,
  }) async {
    if (busy || widget.alerts == null) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.alerts!.updateOptions(
        sound: sound,
        vibration: vibration,
        stockWarnings: stockWarnings,
        leadMinutes: lead,
      );
      await widget.onUpdated?.call();
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'No se pudo guardar o actualizar los avisos. Revisa hospitalización.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final alerts = widget.alerts;
    if (alerts == null) {
      return const Text('Preferencias de avisos no disponibles.');
    }
    return ListenableBuilder(
      listenable: alerts,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SwitchListTile(
            title: const Text('Alerta sonora'),
            value: alerts.sound,
            onChanged: busy ? null : (value) => update(sound: value),
          ),
          SwitchListTile(
            title: const Text('Vibración'),
            subtitle: const Text(
              'Android; en iPhone depende de los ajustes del sistema.',
            ),
            value: alerts.vibration,
            onChanged: busy ? null : (value) => update(vibration: value),
          ),
          SwitchListTile(
            title: const Text('Aviso visual de stock bajo'),
            value: alerts.stockWarnings,
            onChanged: busy ? null : (value) => update(stockWarnings: value),
          ),
          const Text('Anticipación de avisos de hospitalización'),
          Wrap(
            spacing: 8,
            children: [
              for (final minutes in [0, 5, 10, 15, 30])
                ChoiceChip(
                  label: Text(
                    minutes == 0 ? 'Sin anticipación' : '$minutes min',
                  ),
                  selected: alerts.leadMinutes == minutes,
                  onSelected: busy ? null : (_) => update(lead: minutes),
                ),
            ],
          ),
          Text(alerts.status),
          const Text(
            'Activa los avisos en Hospitalización. El sonido, vibración y entrega dependen de permisos, canales y batería del teléfono. Al cambiar preferencias, abre la hoja para revisar todos los horarios.',
          ),
          if (error != null) Text(error!),
          if (busy) const LinearProgressIndicator(),
        ],
      ),
    );
  }
}

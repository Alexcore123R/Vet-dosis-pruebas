import 'package:flutter/material.dart';
import '../domain/storage_budget.dart';

class StorageBudgetPanel extends StatelessWidget {
  const StorageBudgetPanel({
    super.key,
    required this.used,
    required this.limit,
    required this.personal,
  });
  final dynamic used, limit;
  final bool personal;
  @override
  Widget build(BuildContext context) {
    final budget = StorageBudget.read(used, limit);
    if (budget == null) {
      return const Text(
        'Uso de almacenamiento no disponible. Actualiza para consultarlo.',
      );
    }
    final message = switch (budget.level) {
      StorageLevel.normal => 'Tienes espacio disponible en tu plan.',
      StorageLevel.warning =>
        'Has alcanzado el 80% del almacenamiento. Revisa tu uso y las opciones de plan.',
      StorageLevel.critical =>
        'Has alcanzado el 95% del almacenamiento. Te queda poco espacio para nuevos datos.',
      StorageLevel.full =>
        'Alcanzaste el límite. Se conservan tus registros; las operaciones que aumenten el uso pueden bloquearse.',
    };
    final color =
        budget.level == StorageLevel.critical ||
            budget.level == StorageLevel.full
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.primary;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Almacenamiento · ${budget.percent}% estimado',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: budget.fraction,
              color: color,
              semanticsLabel: 'Almacenamiento estimado utilizado',
              semanticsValue: '${budget.percent}%',
            ),
            const SizedBox(height: 12),
            Text(message),
            Text(
              personal
                  ? 'Límite propio de tu espacio individual.'
                  : 'Límite compartido por todo el equipo de esta clínica.',
            ),
            const SizedBox(height: 8),
            const Text(
              'El presupuesto incluye datos y archivos contabilizados; las fotos de inventario reservan 4 MiB por foto.',
            ),
            if (budget.level != StorageLevel.normal) ...[
              const SizedBox(height: 8),
              const Text(
                'Ampliación de almacenamiento: tarifa pendiente. No hay cobros automáticos por exceso de uso.',
              ),
            ],
          ],
        ),
      ),
    );
  }
}

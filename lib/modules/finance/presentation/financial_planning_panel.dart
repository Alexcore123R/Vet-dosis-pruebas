import 'package:flutter/material.dart';
import '../../../core/widgets/workspace_panel.dart';
import '../domain/financial_plan.dart';

class FinancialPlanningPanel extends StatefulWidget {
  const FinancialPlanningPanel({super.key});
  @override
  State<FinancialPlanningPanel> createState() => _FinancialPlanningPanelState();
}

class _FinancialPlanningPanelState extends State<FinancialPlanningPanel> {
  final form = GlobalKey<FormState>();
  static const labels = [
    'Ingresos estimados al mes',
    'Costos fijos al mes',
    'Costos variables al mes',
    'Depreciación mensual',
    'Inversión inicial en activos',
    'Fondos disponibles para el proyecto',
    'Reserva para imprevistos',
  ];
  final fields = List.generate(7, (_) => TextEditingController());
  FinancialPlan? result;
  @override
  void dispose() {
    for (final field in fields) {
      field.dispose();
    }
    super.dispose();
  }

  String money(num cents) => '${(cents / 100).toStringAsFixed(2)} MXN';
  void calculate() {
    if (!form.currentState!.validate()) return;
    final values = fields.map((f) => parsePlanAmount(f.text)!).toList();
    setState(
      () => result = FinancialPlan(
        income: values[0],
        fixedCosts: values[1],
        variableCosts: values[2],
        depreciation: values[3],
        investment: values[4],
        availableFunds: values[5],
        reserve: values[6],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Form(
    key: form,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Planeación financiera',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const Text('Simulador mensual · MXN'),
        const SizedBox(height: 8),
        const Text(
          'Para una clínica o unidad productiva. Esta simulación no se guarda: '
          'al salir del apartado se borran los datos. No modifica Caja ni consulta sus movimientos.',
        ),
        const SizedBox(height: 16),
        const Text(
          'Captura todos los importes para el mismo mes, sin separadores de miles. '
          'Usa 0 cuando no corresponda. Los costos se capturan sin depreciación; '
          'esta se introduce por separado. La inversión incluye activos como equipo e instalaciones, '
          'sin fondo operativo ni reserva.',
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < fields.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: TextFormField(
              controller: fields[i],
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: labels[i],
                suffixText: 'MXN',
              ),
              validator: (value) => parsePlanAmount(value ?? '') == null
                  ? 'Introduce de 0 a 1000000000, con hasta 2 decimales.'
                  : null,
              onChanged: (_) {
                if (result != null) setState(() => result = null);
              },
            ),
          ),
        FilledButton(
          onPressed: calculate,
          child: const Text('Calcular escenario'),
        ),
        TextButton(
          onPressed: () {
            for (final field in fields) {
              field.clear();
            }
            form.currentState!.reset();
            setState(() => result = null);
          },
          child: const Text('Limpiar simulación'),
        ),
        if (result case final plan?) ...[
          WorkspacePanel(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Resultado del escenario',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Resultado estimado con los conceptos capturados: ${money(plan.estimatedResult)}',
                  ),
                  const Text(
                    'Ingresos − costos fijos − costos variables − depreciación.',
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Saldo operativo estimado de efectivo: ${money(plan.operatingCash)}',
                  ),
                  const Text(
                    'Ingresos − costos fijos − costos variables. Excluye depreciación.',
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Fondos adicionales estimados: ${money(plan.fundingGap)}',
                  ),
                  const Text(
                    'Inversión + un mes de costos en efectivo + reserva − fondos disponibles; '
                    'mínimo 0. No se restan ingresos que aún no se han cobrado.',
                  ),
                  const SizedBox(height: 12),
                  Text(
                    plan.breakEvenIncome == null
                        ? 'Punto de equilibrio: no estimable con estos ingresos y costos variables.'
                        : 'Ingresos mensuales de equilibrio: ${money(plan.breakEvenIncome!)}',
                  ),
                  const Text(
                    '(Costos fijos + depreciación) ÷ (1 − costos variables / ingresos). '
                    'Supone precios, proporción de costos variables y mezcla de ventas constantes.',
                  ),
                  const SizedBox(height: 12),
                  Text(
                    plan.investment == 0
                        ? 'Recuperación: no se capturó inversión inicial.'
                        : plan.recoveryMonths == null
                        ? 'Recuperación: no estimable con saldo operativo cero o negativo.'
                        : 'Recuperación simple de la inversión: ${plan.recoveryMonths!.toStringAsFixed(1)} meses',
                  ),
                  const Text(
                    'Inversión ÷ saldo operativo mensual positivo. Supone meses iguales '
                    'y cobro/pago dentro del mes; excluye reserva y financiación.',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Estimaciones antes de impuestos, intereses, deuda y variaciones de capital '
            'de trabajo. No representan utilidad neta definitiva ni garantizan viabilidad.',
          ),
        ],
      ],
    ),
  );
}

import 'dart:convert';
import 'package:flutter/material.dart';
import '../../ai/domain/ai_repository.dart';
import '../../ai/domain/assisted_drafts.dart';
import '../../ai/presentation/request_ai_draft.dart';
import '../../auth/domain/clinic_membership.dart';

class PromotionOptionsScreen extends StatefulWidget {
  const PromotionOptionsScreen({
    super.key,
    required this.ai,
    required this.member,
  });
  final AiRepository ai;
  final ClinicMembership member;
  @override
  State<PromotionOptionsScreen> createState() => _PromotionOptionsScreenState();
}

class _PromotionOptionsScreenState extends State<PromotionOptionsScreen> {
  final service = TextEditingController(),
      discount = TextEditingController(),
      conditions = TextEditingController();
  DateTime? start, end;
  String? error;
  List<PromotionOption> options = [];
  Map<String, dynamic>? generatedBrief;
  @override
  void dispose() {
    service.dispose();
    discount.dispose();
    conditions.dispose();
    super.dispose();
  }

  String date(DateTime d) => d.toIso8601String().substring(0, 10);
  Future<void> chooseDate(bool first) async {
    final result = await showDatePicker(
      context: context,
      initialDate: (first ? start : end) ?? DateUtils.dateOnly(DateTime.now()),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (result != null && mounted) {
      setState(() {
        if (first) {
          start = result;
        } else {
          end = result;
        }
        options = [];
      });
    }
  }

  Future<void> suggest() async {
    final amount = discount.text.trim().isEmpty
        ? null
        : double.tryParse(discount.text.trim().replaceAll(',', '.'));
    if (service.text.trim().isEmpty ||
        service.text.trim().length > 150 ||
        start == null ||
        end == null ||
        end!.isBefore(start!) ||
        (discount.text.trim().isNotEmpty &&
            (amount == null ||
                !amount.isFinite ||
                amount < 0 ||
                amount > 100))) {
      setState(
        () => error =
            'Indica servicio, vigencia válida y un descuento entre 0 y 100, o déjalo vacío.',
      );
      return;
    }
    final brief = <String, dynamic>{
      'service_name': service.text.trim(),
      'starts_on': date(start!),
      'ends_on': date(end!),
      'discount_percent': amount?.toString() ?? '',
      'conditions': conditions.text.trim(),
    };
    final response = await requestAiDraft(
      context,
      repository: widget.ai,
      member: widget.member,
      title: 'Tres opciones de promoción',
      prompt:
          'Crea exactamente tres opciones de promoción distintas a partir de estos datos capturados por el administrador: ${jsonEncode(brief)}. '
          'Conserva exactamente servicio, vigencia y descuento. Si no hay descuento, no inventes uno. Respeta las condiciones capturadas. '
          'No inventes precios, disponibilidad, beneficios clínicos, regalos ni servicios incluidos. No añadas condiciones comerciales nuevas como hechos; si falta un dato usa [por confirmar]. '
          'Devuelve únicamente JSON válido con este formato: {"options":[{"title":"Título","message":"Mensaje breve","conditions":"Condiciones"}, ...]}. '
          'Deben ser tres elementos. Título máximo 150 caracteres; mensaje y condiciones máximo 2000 cada uno.',
    );
    if (!mounted || response == null) return;
    try {
      final parsed = PromotionOption.parse(response);
      setState(() {
        options = parsed;
        generatedBrief = brief;
        error = null;
      });
    } catch (_) {
      setState(
        () => error =
            'La IA no devolvió tres opciones válidas. Puedes volver a pedirlas o crear la promoción manualmente.',
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Preparar tres promociones')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: service,
          maxLength: 150,
          decoration: const InputDecoration(
            labelText: 'Servicio o producto que ofrece la clínica',
          ),
          onChanged: (_) => setState(() => options = []),
        ),
        TextField(
          controller: discount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Descuento % (opcional)',
          ),
          onChanged: (_) => setState(() => options = []),
        ),
        TextField(
          controller: conditions,
          maxLength: 2000,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Condiciones definidas por el administrador',
          ),
          onChanged: (_) => setState(() => options = []),
        ),
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton(
              onPressed: () => chooseDate(true),
              child: Text(start == null ? 'Inicio de vigencia' : date(start!)),
            ),
            OutlinedButton(
              onPressed: () => chooseDate(false),
              child: Text(end == null ? 'Fin de vigencia' : date(end!)),
            ),
          ],
        ),
        FilledButton.icon(
          onPressed: suggest,
          icon: const Icon(Icons.auto_awesome),
          label: const Text('Generar tres opciones'),
        ),
        if (error != null)
          Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        for (var i = 0; i < options.length; i++)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Opción ${i + 1}: ${options[i].title}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text(options[i].message),
                  const SizedBox(height: 8),
                  Text('Condiciones: ${options[i].conditions}'),
                  FilledButton(
                    key: ValueKey('promotion-option-$i'),
                    onPressed: () => Navigator.pop(context, <String, dynamic>{
                      ...generatedBrief!,
                      'kind': 'promocion',
                      'title': options[i].title,
                      'message': options[i].message,
                      'conditions': options[i].conditions,
                    }),
                    child: const Text('Elegir y editar esta opción'),
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}

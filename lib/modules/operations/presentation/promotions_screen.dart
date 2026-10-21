import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../auth/domain/clinic_membership.dart';
import '../../patients/domain/patient_contacts.dart';
import '../../prescribing/presentation/rx_entry_screen.dart';
import '../domain/operations_repository.dart';

class PromotionsScreen extends StatefulWidget {
  const PromotionsScreen({super.key, required this.repository, required this.member});
  final OperationsRepository repository;
  final ClinicMembership member;
  @override
  State<PromotionsScreen> createState() => _PromotionsScreenState();
}

class _PromotionsScreenState extends State<PromotionsScreen> {
  List<Map<String, dynamic>> promotions = [], clients = [];
  bool busy = false;
  String? error;
  MarketingRepository get marketing => widget.repository as MarketingRepository;
  ContactDirectoryRepository get directory => widget.repository as ContactDirectoryRepository;
  bool get admin => widget.member.role == ClinicRole.admin;

  @override
  void initState() { super.initState(); load(); }
  Future<void> load() async {
    if (busy) return;
    setState(() { busy = true; error = null; });
    try {
      final next = await Future.wait([
        marketing.promotions(widget.member.clinicId),
        directory.clients(widget.member.clinicId),
      ]);
      if (mounted) setState(() { promotions = next[0]; clients = next[1]; });
    } catch (_) {
      if (mounted) setState(() => error = 'No se pudieron cargar promociones y clientes. Revisa patient.read y SQL 14J.');
    } finally { if (mounted) setState(() => busy = false); }
  }

  Future<void> edit([Map<String, dynamic>? promotion]) async {
    final saved = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => RxEntryScreen(
      title: promotion == null ? 'Nueva promoción' : 'Editar promoción',
      initial: promotion == null ? const {'kind': 'promocion'} : {
        'id': promotion['id'], 'kind': promotion['kind'], 'title': promotion['title'],
        'message': promotion['message'], 'discount_percent': promotion['discount_percent']?.toString() ?? '',
        'starts_on': promotion['starts_on'] ?? '', 'ends_on': promotion['ends_on'] ?? '',
      },
      fields: const [
        RxField('kind', 'Tipo', type: 'select', required: true, options: {
          'promocion': 'Promoción', 'recompensa': 'Recompensa de fidelidad', 'evento': 'Evento promocional',
        }),
        RxField('title', 'Nombre', required: true),
        RxField('message', 'Mensaje o condiciones de la recompensa', required: true),
        RxField('discount_percent', 'Descuento % (opcional)'),
        RxField('starts_on', 'Inicia', type: 'local_date'),
        RxField('ends_on', 'Termina', type: 'local_date'),
      ],
      submit: (values, _) async {
        try { await marketing.savePromotion(widget.member.clinicId, values); }
        catch (_) { throw const FormatException('No se pudo guardar. Revisa datos, permisos y SQL 14J.'); }
      },
    )));
    if (saved == true && mounted) await load();
  }

  Future<void> archive(Map<String, dynamic> promotion) async {
    final yes = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      title: const Text('Archivar promoción'),
      content: Text('¿Archivar ${promotion['title']}?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Archivar')),
      ],
    ));
    if (yes != true) return;
    try { await marketing.savePromotion(widget.member.clinicId, {'id': promotion['id'], 'archive': true}); await load(); }
    catch (_) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se pudo archivar la promoción.'))); }
  }

  Future<void> recipients(Map<String, dynamic> promotion, String channel) async {
    final eligible = clients.where((c) => channel == 'whatsapp'
        ? c['whatsapp_allowed'] == true && contactWhatsapp('${c['phone'] ?? ''}', '${promotion['message']}') != null
        : c['email_allowed'] == true && '${c['email'] ?? ''}'.isNotEmpty).toList();
    await showModalBottomSheet<void>(context: context, isScrollControlled: true, builder: (sheetContext) => SafeArea(child: SizedBox(
      height: MediaQuery.sizeOf(sheetContext).height * .7,
      child: ListView(children: [
        const ListTile(title: Text('Elegir cliente'), subtitle: Text('Solo aparecen clientes con autorización registrada para este canal. El envío se confirma fuera de la app.')),
        if (eligible.isEmpty) const ListTile(title: Text('No hay clientes autorizados con contacto válido.')),
        for (final client in eligible) ListTile(
          title: Text('${client['name']}'),
          subtitle: Text(channel == 'whatsapp' ? '${client['phone']}' : '${client['email']}'),
          onTap: () async {
            final uri = channel == 'whatsapp'
                ? contactWhatsapp('${client['phone']}', '${promotion['message']}')!
                : Uri(scheme: 'mailto', path: '${client['email']}', queryParameters: {'subject': '${promotion['title']}', 'body': '${promotion['message']}'});
            try { await launchUrl(uri, mode: LaunchMode.externalApplication); } catch (_) {
              if (sheetContext.mounted) ScaffoldMessenger.of(sheetContext).showSnackBar(const SnackBar(content: Text('No se pudo abrir la aplicación de mensajería.')));
            }
          },
        ),
      ]),
    )));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Promociones y fidelidad'), actions: [IconButton(onPressed: busy ? null : load, icon: const Icon(Icons.refresh))]),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      const Text('Crea promociones, recompensas y eventos. Los descuentos son informativos; aplicarlos en una venta requiere capturar el precio correspondiente en Caja.'),
      if (busy) const LinearProgressIndicator(),
      if (error != null) Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
      if (admin) FilledButton.icon(onPressed: () => edit(), icon: const Icon(Icons.add), label: const Text('Agregar promoción, recompensa o evento')),
      for (final promotion in promotions.where((p) => p['active'] == true)) Card(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('${promotion['title']} · ${promotion['kind']}', style: Theme.of(context).textTheme.titleMedium),
        Text('${promotion['message']}'),
        if (promotion['discount_percent'] != null) Text('Descuento: ${promotion['discount_percent']}%'),
        if (promotion['starts_on'] != null || promotion['ends_on'] != null) Text('Vigencia: ${promotion['starts_on'] ?? 'sin inicio'} a ${promotion['ends_on'] ?? 'sin fin'}'),
        Wrap(spacing: 8, children: [
          TextButton(onPressed: () => recipients(promotion, 'whatsapp'), child: const Text('WhatsApp')),
          TextButton(onPressed: () => recipients(promotion, 'email'), child: const Text('Correo')),
          if (admin) TextButton(onPressed: () => edit(promotion), child: const Text('Editar')),
          if (admin) TextButton(onPressed: () => archive(promotion), child: const Text('Archivar')),
        ]),
      ]))),
      if (!busy && error == null && promotions.where((p) => p['active'] == true).isEmpty) const Text('Aún no hay promociones activas.'),
    ]),
  );
}

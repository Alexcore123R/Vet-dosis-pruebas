import 'package:flutter/material.dart';
import '../../core/presentation/module_page.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../auth/domain/clinic_membership.dart';
import '../../ai/domain/ai_repository.dart';
import 'promotion_options_screen.dart';
import '../domain/promotion_text.dart';
import '../../patients/domain/patient_contacts.dart';
import '../../patients/presentation/patient_view_model.dart'
    show newOperationId;
import '../../prescribing/presentation/rx_entry_screen.dart';
import 'promotion_image_screen.dart';
import '../domain/operations_repository.dart';

class PromotionsScreen extends StatefulWidget {
  const PromotionsScreen({
    super.key,
    required this.repository,
    required this.member,
    this.ai,
    this.embedded = false,
  });
  final OperationsRepository repository;
  final ClinicMembership member;
  final AiRepository? ai;
  final bool embedded;
  @override
  State<PromotionsScreen> createState() => _PromotionsScreenState();
}

class _PromotionsScreenState extends State<PromotionsScreen> {
  List<Map<String, dynamic>> promotions = [], clients = [];
  bool busy = false;
  String? error;
  MarketingRepository get marketing => widget.repository as MarketingRepository;
  ContactDirectoryRepository get directory =>
      widget.repository as ContactDirectoryRepository;
  bool get admin => widget.member.role == ClinicRole.admin;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final next = await Future.wait([
        marketing.promotions(widget.member.clinicId),
        directory.clients(widget.member.clinicId),
      ]);
      if (mounted) {
        setState(() {
          promotions = next[0];
          clients = next[1];
        });
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => error =
              'No se pudieron cargar promociones y clientes. Revisa patient.read y SQL 14J.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> edit([
    Map<String, dynamic>? promotion,
    Map<String, dynamic>? draft,
  ]) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => RxEntryScreen(
          title: promotion == null
              ? 'Nueva oferta o promoción'
              : 'Editar oferta o promoción',
          initial: promotion == null
              ? {'kind': 'promocion', ...?draft}
              : {
                  'id': promotion['id'],
                  'kind': promotion['kind'],
                  'title': promotion['title'],
                  'message': promotion['message'],
                  'conditions': promotion['conditions'] ?? '',
                  'service_name': promotion['service_name'] ?? '',
                  'discount_percent':
                      promotion['discount_percent']?.toString() ?? '',
                  'starts_on': promotion['starts_on'] ?? '',
                  'ends_on': promotion['ends_on'] ?? '',
                },
          fields: const [
            RxField(
              'kind',
              'Tipo',
              type: 'select',
              required: true,
              options: {
                'promocion': 'Oferta o promoción',
                'recompensa': 'Recompensa de fidelidad',
                'evento': 'Evento promocional',
              },
            ),
            RxField('title', 'Nombre', required: true),
            RxField('service_name', 'Servicio o producto'),
            RxField(
              'message',
              'Mensaje de la promoción o recompensa',
              required: true,
            ),
            RxField('conditions', 'Condiciones'),
            RxField('discount_percent', 'Descuento % (opcional)'),
            RxField('starts_on', 'Inicia', type: 'local_date'),
            RxField('ends_on', 'Termina', type: 'local_date'),
          ],
          submit: (values, _) async {
            try {
              await marketing.savePromotion(widget.member.clinicId, values);
            } catch (_) {
              throw const FormatException(
                'No se pudo guardar. Revisa datos, permisos y SQL 14J.',
              );
            }
          },
        ),
      ),
    );
    if (saved == true && mounted) await load();
  }

  Future<void> archive(Map<String, dynamic> promotion) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Archivar promoción'),
        content: Text('¿Archivar ${promotion['title']}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Archivar'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    try {
      await marketing.savePromotion(widget.member.clinicId, {
        'id': promotion['id'],
        'archive': true,
      });
      await load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo archivar la promoción.')),
        );
      }
    }
  }

  Future<void> suggestWithAi() async {
    if (widget.ai == null) return;
    final draft = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            PromotionOptionsScreen(ai: widget.ai!, member: widget.member),
      ),
    );
    if (mounted && draft != null) await edit(null, draft);
  }

  Future<void> openLoyalty(Map<String, dynamic> owner) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _LoyaltyAccountScreen(
          repository: marketing,
          member: widget.member,
          owner: owner,
          rewards: promotions.where((p) => p['kind'] == 'recompensa').toList(),
        ),
      ),
    );
  }

  Future<void> recipients(
    Map<String, dynamic> promotion,
    String channel,
  ) async {
    final eligible = clients
        .where(
          (c) => channel == 'whatsapp'
              ? c['whatsapp_allowed'] == true &&
                    contactWhatsapp(
                          '${c['phone'] ?? ''}',
                          promotionMessage(promotion),
                        ) !=
                        null
              : c['email_allowed'] == true && '${c['email'] ?? ''}'.isNotEmpty,
        )
        .toList();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * .7,
          child: ListView(
            children: [
              const ListTile(
                title: Text('Elegir cliente'),
                subtitle: Text(
                  'Solo aparecen clientes con autorización registrada para este canal. El envío se confirma fuera de la app.',
                ),
              ),
              if (eligible.isEmpty)
                const ListTile(
                  title: Text(
                    'No hay clientes autorizados con contacto válido.',
                  ),
                ),
              for (final client in eligible)
                ListTile(
                  title: Text('${client['name']}'),
                  subtitle: Text(
                    channel == 'whatsapp'
                        ? '${client['phone']}'
                        : '${client['email']}',
                  ),
                  onTap: () async {
                    try {
                      final current = await directory.clients(
                        widget.member.clinicId,
                      );
                      final selected = current
                          .where((c) => c['id'] == client['id'])
                          .firstOrNull;
                      if (selected == null ||
                          selected[channel == 'whatsapp'
                                  ? 'whatsapp_allowed'
                                  : 'email_allowed'] !=
                              true) {
                        throw const FormatException(
                          'La autorización ya no está vigente. Actualiza los clientes.',
                        );
                      }
                      final uri = channel == 'whatsapp'
                          ? contactWhatsapp(
                              '${selected['phone'] ?? ''}',
                              promotionMessage(promotion),
                            )
                          : ('${selected['email'] ?? ''}'.isEmpty
                                ? null
                                : Uri(
                                    scheme: 'mailto',
                                    path: '${selected['email']}',
                                    queryParameters: {
                                      'subject': '${promotion['title']}',
                                      'body': promotionMessage(promotion),
                                    },
                                  ));
                      if (uri == null) {
                        throw const FormatException(
                          'El cliente no tiene un contacto válido para este canal.',
                        );
                      }
                      if (!sheetContext.mounted) return;
                      if (!await launchUrl(
                        uri,
                        mode: LaunchMode.externalApplication,
                      )) {
                        throw const FormatException(
                          'No se pudo abrir la aplicación de mensajería.',
                        );
                      }
                    } catch (e) {
                      if (sheetContext.mounted) {
                        ScaffoldMessenger.of(sheetContext).showSnackBar(
                          SnackBar(
                            content: Text(
                              e is FormatException
                                  ? e.message
                                  : 'No se pudo verificar la autorización. Actualiza antes de reintentar.',
                            ),
                          ),
                        );
                      }
                    }
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ModulePage(
    embedded: widget.embedded,
    title: 'Promociones y fidelidad',
    actions: [
      IconButton(
        onPressed: busy ? null : load,
        icon: const Icon(Icons.refresh),
      ),
    ],
    body: ListView(
      shrinkWrap: widget.embedded,
      physics: widget.embedded ? const NeverScrollableScrollPhysics() : null,
      padding: const EdgeInsets.all(16),
      children: [
        const Text(
          'Crea promociones, recompensas y eventos. Los descuentos son informativos; aplicarlos en una venta requiere capturar el precio correspondiente en Caja.',
        ),
        if (busy) const LinearProgressIndicator(),
        if (error != null)
          Text(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (admin)
          FilledButton.icon(
            onPressed: () => edit(),
            icon: const Icon(Icons.add),
            label: const Text('Agregar oferta, promoción, recompensa o evento'),
          ),
        if (admin && widget.ai != null)
          OutlinedButton.icon(
            onPressed: suggestWithAi,
            icon: const Icon(Icons.auto_awesome),
            label: const Text('Pedir ideas a la IA'),
          ),
        if (promotions.any((p) => p['kind'] == 'recompensa'))
          ExpansionTile(
            title: const Text('Recompensas por cliente'),
            subtitle: const Text(
              'Registrar otorgamientos y canjes; ver saldo e historial.',
            ),
            children: [
              for (final client in clients)
                ListTile(
                  title: Text('${client['name']}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => openLoyalty(client),
                ),
            ],
          ),
        for (final promotion in promotions.where((p) => p['active'] == true))
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${promotion['title']} · ${promotion['kind']}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  Text('${promotion['message']}'),
                  if ('${promotion['conditions'] ?? ''}'.isNotEmpty)
                    Text('Condiciones: ${promotion['conditions']}'),
                  if (promotion['discount_percent'] != null)
                    Text('Descuento: ${promotion['discount_percent']}%'),
                  if (promotion['starts_on'] != null ||
                      promotion['ends_on'] != null)
                    Text(
                      'Vigencia: ${promotion['starts_on'] ?? 'sin inicio'} a ${promotion['ends_on'] ?? 'sin fin'}',
                    ),
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton.icon(
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => PromotionImageScreen(
                              clinicName: widget.member.clinicName,
                              promotion: promotion,
                            ),
                          ),
                        ),
                        icon: const Icon(Icons.image_outlined),
                        label: const Text('Crear imagen'),
                      ),
                      TextButton(
                        onPressed: () => recipients(promotion, 'whatsapp'),
                        child: const Text('WhatsApp'),
                      ),
                      TextButton(
                        onPressed: () => recipients(promotion, 'email'),
                        child: const Text('Correo'),
                      ),
                      if (admin)
                        TextButton(
                          onPressed: () => edit(promotion),
                          child: const Text('Editar'),
                        ),
                      if (admin)
                        TextButton(
                          onPressed: () => archive(promotion),
                          child: const Text('Archivar'),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        if (!busy &&
            error == null &&
            promotions.where((p) => p['active'] == true).isEmpty)
          const Text('Aún no hay promociones activas.'),
      ],
    ),
  );
}

class _LoyaltyAccountScreen extends StatefulWidget {
  const _LoyaltyAccountScreen({
    required this.repository,
    required this.member,
    required this.owner,
    required this.rewards,
  });
  final MarketingRepository repository;
  final ClinicMembership member;
  final Map<String, dynamic> owner;
  final List<Map<String, dynamic>> rewards;
  @override
  State<_LoyaltyAccountScreen> createState() => _LoyaltyAccountScreenState();
}

class _LoyaltyAccountScreenState extends State<_LoyaltyAccountScreen> {
  Map<String, dynamic> data = {};
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await widget.repository.loyaltyAccount(
        widget.member.clinicId,
        '${widget.owner['id']}',
      );
      if (mounted) setState(() => data = result);
    } catch (_) {
      if (mounted) {
        setState(
          () =>
              error = 'No se pudo cargar el saldo. Revisa permisos y SQL 14K.',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> record(String action) async {
    final rewards = widget.rewards
        .where((p) => p['active'] == true || action == 'redeem')
        .toList();
    if (rewards.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Primero crea una recompensa activa.')),
      );
      return;
    }
    String selected = '${rewards.first['id']}';
    final units = TextEditingController(text: '1');
    final note = TextEditingController();
    final operation = newOperationId();
    String? formError;
    bool saving = false;
    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, update) => AlertDialog(
            title: Text(
              action == 'grant' ? 'Otorgar recompensa' : 'Canjear recompensa',
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: selected,
                    decoration: const InputDecoration(labelText: 'Recompensa'),
                    items: [
                      for (final reward in rewards)
                        DropdownMenuItem(
                          value: '${reward['id']}',
                          child: Text('${reward['title']}'),
                        ),
                    ],
                    onChanged: saving
                        ? null
                        : (v) => update(() => selected = v ?? selected),
                  ),
                  TextField(
                    controller: units,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Unidades'),
                  ),
                  TextField(
                    controller: note,
                    maxLength: 500,
                    decoration: const InputDecoration(
                      labelText: 'Motivo o referencia (opcional)',
                    ),
                  ),
                  if (formError != null)
                    Text(
                      formError!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(dialogContext),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: saving
                    ? null
                    : () async {
                        final count = int.tryParse(units.text.trim());
                        if (count == null || count < 1 || count > 100000) {
                          update(
                            () => formError =
                                'Ingresa entre 1 y 100000 unidades.',
                          );
                          return;
                        }
                        update(() {
                          saving = true;
                          formError = null;
                        });
                        try {
                          await widget.repository.recordLoyalty(
                            widget.member.clinicId,
                            '${widget.owner['id']}',
                            selected,
                            action,
                            count,
                            note.text.trim(),
                            operation,
                          );
                          if (dialogContext.mounted) {
                            Navigator.pop(dialogContext);
                          }
                          if (mounted) await load();
                        } catch (_) {
                          update(
                            () => formError = action == 'redeem'
                                ? 'No se pudo canjear. Revisa el saldo, permisos y SQL 14K.'
                                : 'No se pudo otorgar. Revisa permisos y SQL 14K.',
                          );
                        } finally {
                          if (dialogContext.mounted) {
                            update(() => saving = false);
                          }
                        }
                      },
                child: const Text('Guardar'),
              ),
            ],
          ),
        ),
      );
    } finally {
      units.dispose();
      note.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final balances = (data['balances'] as List? ?? [])
        .cast<Map<String, dynamic>>();
    final movements = (data['movements'] as List? ?? [])
        .cast<Map<String, dynamic>>();
    return Scaffold(
      appBar: AppBar(
        title: Text('Recompensas · ${widget.owner['name']}'),
        actions: [
          IconButton(
            onPressed: busy ? null : load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (busy) const LinearProgressIndicator(),
          if (error != null)
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          Wrap(
            spacing: 8,
            children: [
              FilledButton(
                onPressed: busy || error != null ? null : () => record('grant'),
                child: const Text('Otorgar'),
              ),
              OutlinedButton(
                onPressed: busy || error != null
                    ? null
                    : () => record('redeem'),
                child: const Text('Canjear'),
              ),
            ],
          ),
          Text('Saldos', style: Theme.of(context).textTheme.titleLarge),
          if (!busy && error == null && balances.isEmpty)
            const Text('Sin recompensas registradas.'),
          for (final balance in balances)
            ListTile(
              title: Text('${balance['title']}'),
              trailing: Text('${balance['units']} disponibles'),
            ),
          Text('Movimientos', style: Theme.of(context).textTheme.titleLarge),
          for (final movement in movements)
            ListTile(
              title: Text(
                '${movement['action'] == 'grant' ? 'Otorgada' : 'Canjeada'} · ${movement['title']}',
              ),
              subtitle: Text('${movement['created_at']} · ${movement['note']}'),
              trailing: Text(
                '${movement['action'] == 'grant' ? '+' : '-'}${movement['units']}',
              ),
            ),
        ],
      ),
    );
  }
}

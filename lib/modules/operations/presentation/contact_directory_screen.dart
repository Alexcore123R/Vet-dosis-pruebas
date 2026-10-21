import 'package:flutter/material.dart';
import '../../core/presentation/module_page.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../auth/domain/clinic_membership.dart';
import '../../patients/presentation/contact_actions.dart' show patientContactChannel;
import '../../prescribing/presentation/rx_entry_screen.dart';
import '../domain/operations_repository.dart';

class ContactDirectoryScreen extends StatefulWidget {
  const ContactDirectoryScreen({super.key, required this.repository, required this.member, this.embedded=false});
  final OperationsRepository repository;
  final ClinicMembership member;
  final bool embedded;
  @override
  State<ContactDirectoryScreen> createState() => _ContactDirectoryScreenState();
}

class _ContactDirectoryScreenState extends State<ContactDirectoryScreen> {
  Map<String, dynamic>? data;
  String kind = 'staff';
  String? error;
  bool busy = false;
  String search = '';
  ContactDirectoryRepository get directory => widget.repository as ContactDirectoryRepository;

  @override
  void initState() { super.initState(); load(); }

  Future<void> load() async {
    if (busy) return;
    setState(() { busy = true; error = null; });
    try {
      final next = await directory.contactDirectory(widget.member.clinicId);
      try {
        next['clients'] = await directory.clients(widget.member.clinicId);
        next['clients_allowed'] = true;
      } catch (_) {
        next['clients'] = <Map<String, dynamic>>[];
        next['clients_allowed'] = false;
      }
      if (mounted) setState(() => data = next);
    } catch (_) {
      if (mounted) setState(() => error = 'No se pudo consultar el directorio. Revisa conexión, permisos y SQL 14I.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> edit(Map<String, dynamic> entry) async {
    final saved = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => RxEntryScreen(
      title: 'Contacto: ${entry['name']}',
      initial: {
        'phone': entry['phone'] ?? '', 'whatsapp': entry['whatsapp'] ?? '',
        'email': entry['email'] ?? '', 'address': entry['address'] ?? '',
      },
      fields: const [
        RxField('phone', 'Teléfono'), RxField('whatsapp', 'WhatsApp'),
        RxField('email', 'Correo'), RxField('address', 'Dirección'),
      ],
      submit: (values, _) async {
        try {
          await directory.saveContact(widget.member.clinicId, kind, '${entry['id']}', values);
        } catch (_) {
          throw const FormatException('No se pudo guardar el contacto. Revisa formato y permisos.');
        }
      },
    )));
    if (saved == true && mounted) await load();
  }

  Future<void> marketingPreferences(Map<String, dynamic> entry) async {
    final saved = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => RxEntryScreen(
      title: 'Promociones: ${entry['name']}',
      initial: {
        'whatsapp': entry['whatsapp_allowed'] == true,
        'email': entry['email_allowed'] == true,
        'source': entry['consent_source'] ?? '',
      },
      fields: const [
        RxField('whatsapp', 'Autorizó WhatsApp promocional', type: 'checkbox'),
        RxField('email', 'Autorizó correo promocional', type: 'checkbox'),
        RxField('source', 'Fuente y fecha de autorización; o motivo de retiro'),
      ],
      submit: (values, _) async {
        try {
          await directory.saveMarketingPreferences(widget.member.clinicId,
            '${entry['id']}', values['whatsapp'] == true,
            values['email'] == true, '${values['source'] ?? ''}');
        } catch (_) {
          throw const FormatException('No se pudo guardar. Revisa la fuente y el permiso patient.write.');
        }
      },
    )));
    if (saved == true && mounted) await load();
  }

  Future<void> open(Uri uri) async {
    try { if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return; } catch (_) { /* handled below */ }
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No se pudo abrir la aplicación de contacto.')));
  }

  Future<void> saveToPhone(Map<String, dynamic> entry) async {
    final confirmed = await showDialog<bool>(context: context, builder: (dialogContext) => AlertDialog(
      title: const Text('Guardar en agenda telefónica'),
      content: const Text('Se abrirá la agenda del teléfono con los datos visibles. El teléfono decidirá dónde guardar y sincronizar el contacto.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: const Text('Continuar')),
      ],
    ));
    if (confirmed != true || !mounted) return;
    try {
      await patientContactChannel.invokeMethod<void>('insertContact', {
        'name': '${entry['name'] ?? ''}', 'phone': '${entry['phone'] ?? ''}',
        'email': '${entry['email'] ?? ''}', 'address': '${entry['address'] ?? ''}',
      });
    } on PlatformException {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('La agenda del teléfono no está disponible.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final source = (data?[kind] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).where((e) => '${e['name']} ${e['phone']} ${e['email']}'.toLowerCase().contains(search.toLowerCase())).toList();
    final allowed = data?['${kind == 'staff' ? 'team' : kind}_allowed'] == true;
    final editable = kind != 'clients' && data?['${kind == 'staff' ? 'team' : 'supplier'}_manage'] == true;
    return ModulePage(embedded:widget.embedded,
      title:'Agenda telefónica', actions: [IconButton(onPressed: busy ? null : load, icon: const Icon(Icons.refresh), tooltip: 'Actualizar')],
      body: ListView(shrinkWrap:widget.embedded,physics:widget.embedded?const NeverScrollableScrollPhysics():null,padding: const EdgeInsets.all(16), children: [
        const Text('Directorio de la clínica. Guardar en el teléfono requiere tu confirmación.'),
        const SizedBox(height: 12),
        SegmentedButton<String>(segments: const [ButtonSegment(value: 'staff', label: Text('Personal')), ButtonSegment(value: 'suppliers', label: Text('Proveedores')), ButtonSegment(value: 'clients', label: Text('Clientes'))], selected: {kind}, onSelectionChanged: (value) => setState(() => kind = value.first)),
        const SizedBox(height: 12),
        TextField(decoration: const InputDecoration(prefixIcon: Icon(Icons.search), labelText: 'Buscar contacto'), onChanged: (value) => setState(() => search = value)),
        if (busy) const LinearProgressIndicator(),
        if (error != null) Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        if (data != null && !allowed) const Padding(padding: EdgeInsets.all(16), child: Text('Necesitas permiso de equipo o proveedores para ver estos contactos.')),
        if (data != null && allowed && source.isEmpty) const Padding(padding: EdgeInsets.all(16), child: Text('Sin contactos registrados en esta categoría.')),
        if (allowed) for (final entry in source)
          Card(child: ExpansionTile(title: Text('${entry['name']}'), subtitle: Text(kind == 'staff' ? 'Personal' : kind == 'clients' ? 'Cliente' : '${entry['kind'] ?? 'Proveedor'}'), childrenPadding: const EdgeInsets.all(12), children: [
            if ('${entry['phone'] ?? ''}'.isNotEmpty) SelectableText('Teléfono: ${entry['phone']}'),
            if ('${entry['whatsapp'] ?? ''}'.isNotEmpty) SelectableText('WhatsApp: ${entry['whatsapp']}'),
            if ('${entry['email'] ?? ''}'.isNotEmpty) SelectableText('Correo: ${entry['email']}'),
            if ('${entry['address'] ?? ''}'.isNotEmpty) SelectableText('Dirección: ${entry['address']}'),
            Wrap(spacing: 8, children: [
              if ('${entry['phone'] ?? ''}'.isNotEmpty) TextButton(onPressed: () => open(Uri(scheme: 'tel', path: '${entry['phone']}')), child: const Text('Llamar')),
              if ('${entry['whatsapp'] ?? ''}'.isNotEmpty) TextButton(onPressed: () => open(Uri.https('wa.me', '${entry['whatsapp']}'.replaceAll(RegExp(r'[^0-9]'), ''))), child: const Text('WhatsApp')),
              if ('${entry['email'] ?? ''}'.isNotEmpty) TextButton(onPressed: () => open(Uri(scheme: 'mailto', path: '${entry['email']}')), child: const Text('Correo')),
              if ('${entry['address'] ?? ''}'.isNotEmpty) TextButton(onPressed: () => open(Uri.https('www.google.com', '/maps/search/', {'api': '1', 'query': '${entry['address']}'})), child: const Text('Mapa')),
              if (editable) TextButton(onPressed: () => edit(entry), child: const Text('Editar ficha')),
              if (kind == 'clients') TextButton(onPressed: () => marketingPreferences(entry), child: const Text('Permisos para promociones')),
              TextButton(onPressed: () => saveToPhone(entry), child: const Text('Guardar en teléfono')),
            ]),
          ])),
        TextButton.icon(onPressed: () async {
          try { await patientContactChannel.invokeMethod<void>('openContacts'); } catch (_) {
            if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('La agenda del teléfono no está disponible.')));
          }
        }, icon: const Icon(Icons.contacts_outlined), label: const Text('Abrir agenda del teléfono')),
      ]),
    );
  }
}

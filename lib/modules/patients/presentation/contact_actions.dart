import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../domain/patient_contacts.dart';

const patientContactChannel = MethodChannel('vetdosis/contact_actions');

class ContactActions extends StatelessWidget {
  const ContactActions({
    super.key,
    required this.owner,
    required this.patientName,
    this.showAddress = true,
  });
  final Map<String, dynamic> owner;
  final String patientName;
  final bool showAddress;

  Future<void> open(BuildContext context, Uri uri) async {
    try {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
    } catch (_) {
      /* Report a generic failure without including contact data. */
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo abrir la aplicación de contacto.'),
        ),
      );
    }
  }

  Future<void> phoneAgenda(BuildContext context, {required bool insert}) async {
    if (insert) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Guardar contacto en el teléfono'),
          content: const Text(
            'Se abrirá la agenda del dispositivo con nombre y teléfono. Si lo guardas, su copia y posible sincronización dependerán del teléfono.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Continuar'),
            ),
          ],
        ),
      );
      if (confirmed != true || !context.mounted) return;
    }
    try {
      await patientContactChannel.invokeMethod<void>(
        insert ? 'insertContact' : 'openContacts',
        insert ? {'name': owner['name'], 'phone': owner['phone']} : null,
      );
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'La agenda del teléfono no está disponible. Puedes usar el número mostrado.',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final address = owner['address'] as String? ?? '';
    final phoneRows = <(String, String)>[
      (
        'Principal · ${owner['name'] ?? 'Tutor'}',
        owner['phone'] as String? ?? '',
      ),
      (
        'Alternativo · ${owner['name'] ?? 'Tutor'}',
        owner['phone_alt'] as String? ?? '',
      ),
      if (owner['contact_authorized'] == true)
        (
          'Contacto autorizado · ${owner['contact_name'] ?? ''}',
          owner['contact_phone'] as String? ?? '',
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Tutor: ${owner['name'] ?? ''}'),
        for (final row in phoneRows)
          if (row.$2.isNotEmpty) ...[
            SelectableText('${row.$1}: ${row.$2}'),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.call_outlined),
                  label: const Text('Llamar'),
                  onPressed: contactCall(row.$2) == null
                      ? null
                      : () => open(context, contactCall(row.$2)!),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.message_outlined),
                  label: const Text('Preparar WhatsApp'),
                  onPressed: contactWhatsapp(row.$2, '') == null
                      ? null
                      : () => open(
                          context,
                          contactWhatsapp(
                            row.$2,
                            'Hola. Nos comunicamos de la clínica sobre $patientName. ¿Podrías contactarnos?',
                          )!,
                        ),
                ),
              ],
            ),
          ],
        if ((owner['phone'] as String? ?? '').isEmpty)
          const Text('Sin teléfono principal registrado.'),
        if ((owner['email'] as String? ?? '').isNotEmpty)
          SelectableText('Correo: ${owner['email']}'),
        if (showAddress && address.isNotEmpty) ...[
          SelectableText('Dirección: $address'),
          TextButton.icon(
            onPressed: () => open(
              context,
              Uri.https('www.google.com', '/maps/search/', {
                'api': '1',
                'query': address,
              }),
            ),
            icon: const Icon(Icons.map_outlined),
            label: const Text('Abrir dirección en mapas'),
          ),
        ],
        if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android)
          Wrap(
            spacing: 8,
            children: [
              TextButton.icon(
                onPressed: contactPhone(owner['phone'] as String? ?? '') == null
                    ? null
                    : () => phoneAgenda(context, insert: true),
                icon: const Icon(Icons.person_add_alt),
                label: const Text('Guardar contacto en teléfono'),
              ),
              TextButton.icon(
                onPressed: () => phoneAgenda(context, insert: false),
                icon: const Icon(Icons.contacts_outlined),
                label: const Text('Abrir agenda telefónica'),
              ),
            ],
          ),
      ],
    );
  }
}

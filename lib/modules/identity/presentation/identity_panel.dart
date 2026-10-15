import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../auth/domain/clinic_membership.dart';
import '../../forms/domain/form_repository.dart';
import '../../forms/presentation/branding_editor.dart';

final identityChanges = ValueNotifier<int>(0);
const profileIcons = [
  Icons.person,
  Icons.pets,
  Icons.local_hospital,
  Icons.science,
  Icons.agriculture,
];

/// Personal appearance stays on this device, scoped to the signed-in account.
class AccountAvatar extends StatelessWidget {
  const AccountAvatar({super.key, required this.userId});
  final String userId;
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
    valueListenable: identityChanges,
    builder: (context, value, _) => FutureBuilder<SharedPreferences>(
      key: ValueKey('$userId:$value'),
      future: SharedPreferences.getInstance(),
      builder: (context, snapshot) {
        final prefs = snapshot.data;
        final photo = prefs?.getString('profile.photo.$userId');
        final index = prefs?.getInt('profile.icon.$userId') ?? 0;
        Uint8List? photoBytes;
        try {
          if (photo != null && photo.length <= 667000) {
            photoBytes = base64Decode(photo);
          }
        } catch (_) {}
        return CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
          child: photoBytes != null
              ? ClipOval(
                  child: Image.memory(
                    photoBytes,
                    width: 40,
                    height: 40,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const Icon(Icons.person),
                  ),
                )
              : Icon(
                  profileIcons[index >= 0 && index < profileIcons.length
                      ? index
                      : 0],
                ),
        );
      },
    ),
  );
}

class ClinicIdentity extends StatefulWidget {
  const ClinicIdentity({
    super.key,
    required this.member,
    this.repository,
    this.editable = false,
  });
  final ClinicMembership member;
  final FormRepository? repository;
  final bool editable;
  @override
  State<ClinicIdentity> createState() => _ClinicIdentityState();
}

class _ClinicIdentityState extends State<ClinicIdentity> {
  late Future<Map<String, dynamic>> brand = load();
  Future<Map<String, dynamic>> load() =>
      widget.repository != null &&
          [
            ClinicRole.admin,
            ClinicRole.mvz,
            ClinicRole.auxiliar,
          ].contains(widget.member.role)
      ? widget.repository!.branding(widget.member.clinicId)
      : Future.value({});
  @override
  void didUpdateWidget(covariant ClinicIdentity oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.member.clinicId != widget.member.clinicId ||
        oldWidget.member.userId != widget.member.userId ||
        oldWidget.member.role != widget.member.role ||
        oldWidget.repository != widget.repository) {
      brand = load();
    }
  }

  Future<void> edit() async {
    try {
      final data = await load();
      final templates = await widget.repository!.templates(
        widget.member.clinicId,
      );
      if (!mounted) return;
      if (templates.isEmpty) throw StateError('No templates');
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => BrandingEditor(
            repository: widget.repository!,
            clinicId: widget.member.clinicId,
            schema: templates.first.schema,
            initial: data,
          ),
        ),
      );
      if (mounted) setState(() => brand = load());
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No se pudo abrir el membrete. Revisa conexión, permisos y plantillas de Formatos.',
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
    future: brand,
    builder: (context, snapshot) {
      Uint8List? bytes;
      try {
        final logo = snapshot.data?['logo'];
        if (logo is String && logo.length <= 334000) bytes = base64Decode(logo);
      } catch (_) {
        /* Invalid branding uses the clinic placeholder. */
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: bytes == null
                ? const Icon(Icons.business, size: 40)
                : Image.memory(
                    bytes,
                    width: 48,
                    height: 48,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) =>
                        const Icon(Icons.business, size: 40),
                  ),
            title: Text(widget.member.clinicName),
            subtitle: Text(
              snapshot.hasError
                  ? 'Logo no disponible · revisa conexión y acceso'
                  : widget.member.isPersonal
                  ? 'Espacio personal'
                  : 'Clínica activa',
            ),
          ),
          if (widget.editable &&
              widget.member.role == ClinicRole.admin &&
              widget.repository != null)
            OutlinedButton.icon(
              onPressed: edit,
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Logo y membrete de la clínica'),
            ),
        ],
      );
    },
  );
}

class ProfileAppearance extends StatefulWidget {
  const ProfileAppearance({super.key, required this.userId});
  final String userId;
  @override
  State<ProfileAppearance> createState() => _ProfileAppearanceState();
}

class _ProfileAppearanceState extends State<ProfileAppearance> {
  bool busy = false;
  Future<void> save(int? icon) async {
    final userId = widget.userId;
    setState(() => busy = true);
    try {
      String? photo;
      if (icon == null) {
        final file = await ImagePicker().pickImage(
          source: ImageSource.gallery,
          maxWidth: 512,
          maxHeight: 512,
          imageQuality: 80,
        );
        if (file == null) return;
        if (await file.length() > 5000000) throw const FormatException();
        final buffer = await ui.ImmutableBuffer.fromUint8List(
          await file.readAsBytes(),
        );
        final descriptor = await ui.ImageDescriptor.encoded(buffer);
        try {
          if (descriptor.width * descriptor.height > 16000000) {
            throw const FormatException();
          }
          final codec = await descriptor.instantiateCodec(targetWidth: 256);
          try {
            final frame = await codec.getNextFrame();
            try {
              final data = await frame.image.toByteData(
                format: ui.ImageByteFormat.png,
              );
              if (data == null || data.lengthInBytes > 500000) {
                throw const FormatException();
              }
              photo = base64Encode(
                data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
              );
            } finally {
              frame.image.dispose();
            }
          } finally {
            codec.dispose();
          }
        } finally {
          descriptor.dispose();
          buffer.dispose();
        }
      }
      if (!mounted || userId != widget.userId) return;
      final prefs = await SharedPreferences.getInstance();
      if (icon != null) {
        await prefs.setInt('profile.icon.$userId', icon);
        await prefs.remove('profile.photo.$userId');
      } else {
        await prefs.setString('profile.photo.$userId', photo!);
      }
      identityChanges.value++;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No se pudo guardar la foto. Elige una imagen más pequeña.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      AccountAvatar(userId: widget.userId),
      const Text('Mi imagen · solo en este dispositivo'),
      TextButton.icon(
        onPressed: busy ? null : () => save(null),
        icon: const Icon(Icons.add_photo_alternate_outlined),
        label: const Text('Subir foto de perfil'),
      ),
      Wrap(
        children: [
          for (var i = 0; i < profileIcons.length; i++)
            IconButton(
              tooltip: 'Elegir icono ${i + 1}',
              onPressed: busy ? null : () => save(i),
              icon: Icon(profileIcons[i]),
            ),
        ],
      ),
      const Divider(),
    ],
  );
}

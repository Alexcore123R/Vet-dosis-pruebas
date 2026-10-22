import 'dart:io';
import '../domain/promotion_text.dart';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class PromotionImageScreen extends StatefulWidget {
  const PromotionImageScreen({super.key, required this.clinicName, required this.promotion});
  final String clinicName;
  final Map<String, dynamic> promotion;

  @override
  State<PromotionImageScreen> createState() => _PromotionImageScreenState();
}

class _PromotionImageScreenState extends State<PromotionImageScreen> {
  final imageKey = GlobalKey();
  late final title = TextEditingController(text: '${widget.promotion['title'] ?? ''}');
  late final message = TextEditingController(text: '${widget.promotion['message'] ?? ''}');
  late final footer = TextEditingController(text: widget.clinicName);
  int palette = 0;
  bool exporting = false;
  String? error;

  static const palettes = [
    (Color(0xFF075E52), Color(0xFFE6F7EF), Color(0xFF06372F)),
    (Color(0xFF5531A6), Color(0xFFF1EAFE), Color(0xFF301665)),
    (Color(0xFFBA4B39), Color(0xFFFFF0E9), Color(0xFF692819)),
  ];

  @override
  void dispose() {
    title.dispose();
    message.dispose();
    footer.dispose();
    super.dispose();
  }

  Future<void> shareImage() async {
    if (exporting) return;
    if (title.text.trim().isEmpty || message.text.trim().isEmpty) {
      setState(() => error = 'Escribe un título y un mensaje para la imagen.');
      return;
    }
    setState(() { exporting = true; error = null; });
    try {
      await WidgetsBinding.instance.endOfFrame;
      final boundary = imageKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw StateError('preview_unavailable');
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (bytes == null) throw StateError('png_unavailable');
      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/promocion-${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
      await SharePlus.instance.share(ShareParams(
        files: [XFile(file.path, mimeType: 'image/png')],
        title: title.text.trim(),
        text: promotionMessage(widget.promotion),
      ));
    } catch (_) {
      if (mounted) setState(() => error = 'No se pudo crear o compartir la imagen. Inténtalo de nuevo.');
    } finally {
      if (mounted) setState(() => exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = palettes[palette];
    final discount = widget.promotion['discount_percent'];
    final period = [widget.promotion['starts_on'], widget.promotion['ends_on']]
        .where((value) => value != null && '$value'.isNotEmpty).join(' — ');
    return Scaffold(
      appBar: AppBar(title: const Text('Imagen promocional')),
      body: SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Ajusta la versión para imagen. Estos cambios solo afectan al PNG; la promoción guardada permanece igual.'),
        const SizedBox(height: 12),
        TextField(controller: title, maxLength: 70, onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(labelText: 'Título para la imagen')),
        TextField(controller: message, maxLength: 220, maxLines: 4, onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(labelText: 'Mensaje breve para la imagen')),
        TextField(controller: footer, maxLength: 80, onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(labelText: 'Nombre de la clínica o cierre')),
        Wrap(spacing: 8, children: [for (var i = 0; i < palettes.length; i++)
          ChoiceChip(label: Text(['Verde', 'Violeta', 'Coral'][i]), selected: palette == i,
            onSelected: (_) => setState(() => palette = i)),
        ]),
        const SizedBox(height: 16),
        Center(child: RepaintBoundary(key: imageKey, child: SizedBox(width: 360, height: 450,
          child: DecoratedBox(decoration: BoxDecoration(color: colors.$2), child: Padding(
            padding: const EdgeInsets.all(28), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [Icon(Icons.pets, color: colors.$1), const SizedBox(width: 8),
                Expanded(child: Text(footer.text.trim().isEmpty ? widget.clinicName : footer.text.trim(),
                  maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colors.$3, fontSize: 16, fontWeight: FontWeight.bold)))]),
              const Spacer(),
              Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: colors.$1, borderRadius: BorderRadius.circular(18)),
                child: const Text('OFERTA DE LA CLÍNICA', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold))),
              const SizedBox(height: 16),
              Text(title.text.trim(), maxLines: 3, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: colors.$3, fontSize: 32, height: 1.08, fontWeight: FontWeight.bold)),
              const SizedBox(height: 14),
              Text(message.text.trim(), maxLines: 7, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: colors.$3, fontSize: 16, height: 1.3)),
              const Spacer(),
              if (discount != null) Text('$discount% de descuento',
                style: TextStyle(color: colors.$1, fontSize: 22, fontWeight: FontWeight.bold)),
              if (period.isNotEmpty) Text('Vigencia: $period', maxLines: 2,
                style: TextStyle(color: colors.$3, fontSize: 12)),
              const SizedBox(height: 8),
              Text('Consulta las condiciones con la clínica.',
                style: TextStyle(color: colors.$3, fontSize: 11)),
            ]),
          )))),
        ),
        const SizedBox(height: 12),
        if (error != null) Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        FilledButton.icon(onPressed: exporting ? null : shareImage,
          icon: const Icon(Icons.ios_share), label: Text(exporting ? 'Creando PNG…' : 'Compartir o guardar PNG')),
      ])),
    );
  }
}

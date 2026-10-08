import 'package:flutter/material.dart';
import '../../auth/domain/clinic_membership.dart';
import '../domain/inventory_repository.dart';
import 'barcode_screen.dart';
import 'inventory_screen.dart';

class QuickScanScreen extends StatefulWidget {
  const QuickScanScreen({
    super.key,
    required this.repository,
    required this.member,
  });
  final InventoryRepository repository;
  final ClinicMembership member;
  @override
  State<QuickScanScreen> createState() => _QuickScanScreenState();
}

class _QuickScanScreenState extends State<QuickScanScreen> {
  final code = TextEditingController();
  @override
  void dispose() {
    code.dispose();
    super.dispose();
  }

  Future<void> scan() async {
    final value = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const BarcodeScreen()),
    );
    if (mounted && value != null) setState(() => code.text = value);
  }

  void search() {
    final value = code.text.trim();
    if (value.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Producto encontrado')),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: InventoryScreen(
              repository: widget.repository,
              member: widget.member,
              initialSearch: value,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'Escanear producto',
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      const Text(
        'Busca por código de barras en tu inventario. El código no verifica concentración ni dosis; leer una etiqueta con OCR sigue pendiente.',
      ),
      FilledButton.icon(
        onPressed: scan,
        icon: const Icon(Icons.qr_code_scanner),
        label: const Text('Abrir cámara'),
      ),
      TextField(
        controller: code,
        maxLength: 200,
        decoration: const InputDecoration(
          labelText: 'Código manual o escaneado',
        ),
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => search(),
      ),
      FilledButton(
        onPressed: code.text.trim().isEmpty ? null : search,
        child: const Text('Buscar en inventario'),
      ),
    ],
  );
}

import '../../core/domain/plan_errors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../doses/domain/quantity.dart';
import '../../prescribing/presentation/rx_entry_screen.dart';
import '../../patients/presentation/patient_view_model.dart'
    show newOperationId;
import '../domain/inventory_models.dart';
import '../domain/inventory_repository.dart';
import 'barcode_screen.dart';

String inventoryError(Object error) {
  final planMessage = planActionError(error);
  if (planMessage != null) return planMessage;
  if (error is PostgrestException &&
      (error.code == 'PGRST202' || error.code == '42883')) {
    return 'Falta una función de base de datos para esta versión. Comprueba las migraciones SQL.';
  }
  if (error is ArgumentError) {
    return 'La app aún no permite esta operación. Actualiza a la beta más reciente.';
  }
  final text = error.toString();
  const messages = {
    'explicit_permission_required':
        'Falta un permiso vigente para esta acción. Actualiza o consulta con la administración.',
    'inventory_read_permission_required':
        'Tu acceso de consulta a inventario no está vigente.',
    'cash_collection_permission_required':
        'Cobrar requiere un permiso vigente de caja.',
    'verified_dispensing_permission_required':
        'Dispensar requiere MVZ habilitado y permiso vigente; cobrar una entrega ya registrada es un acto separado.',
    'dispensing_limit_reauthorization_required':
        'El MVZ responsable debe revisar y autorizar nuevamente la cantidad; el límite histórico no concede autoridad.',
    'dispensing_limit_authority_changed':
        'La autorización de cantidad perdió vigencia. Actualiza y solicita revisión del MVZ responsable.',
    'legacy_delivery_delegation_disabled':
        'Las delegaciones antiguas no habilitan dispensación. Se requiere habilitación profesional y permiso por persona.',
    'controlled_or_unverified_stock_adjustment_denied':
        'Este producto controlado o sin clasificación verificada no admite ajustes libres.',
    'dispensing_quantity_authorization_required':
        'El MVZ responsable debe autorizar la cantidad total de stock a dispensar para esta receta.',
    'dispensing_authorized_quantity_exceeded':
        'La cantidad supera el total autorizado para esta receta, incluyendo ventas anteriores.',
    'application_already_paid':
        'Esta aplicación ya tiene un cobro activo. Actualiza antes de cobrar.',
    'delivery_already_paid': 'Esta entrega ya tiene un cobro activo.',
    'application_tariff_required':
        'El administrador debe configurar el precio por aplicación.',
    'use_current_application_record':
        'Usa la corrección vigente del registro clínico.',
    'expired_lot_blocked':
        'Lote caducado o sin caducidad exigida; dispensación bloqueada.',
    'insufficient_stock':
        'El stock cambió o no alcanza. Actualiza el inventario.',
    'sale_price_changed': 'El precio cambió. Actualiza antes de cobrar.',
    'sale_total_changed':
        'El total no coincide. Revisa el carrito antes de cobrar.',
    'service_version_changed':
        'El servicio cambió. Vuelve a abrir Caja y revisa su precio.',
    'price_below_service_commission':
        'El nuevo precio del catálogo no puede ser menor que la comisión fija configurada.',
    'catalog_service_line_invalid':
        'Un servicio del catálogo aparece repetido o tiene datos inválidos.',
    'closed_shift': 'El turno está cerrado. Abre un turno nuevo.',
    'verified_medication_reference_required':
        'Falta clasificación verificada de la presentación comercial. No se dispensa.',
    'quantified_dispensing_professional_only':
        'Solo un MVZ habilitado puede dispensar este producto.',
    'issued_matching_prescription_required':
        'Selecciona una receta emitida de esta presentación exacta.',
    'ordinary_dispensing_delegation_required':
        'Se requiere permiso vigente del MVZ responsable para este caso.',
    'whole_package_required':
        'La venta por envase requiere una cantidad entera.',
    'cash_discrepancy_reason_required':
        'Explica la diferencia entre efectivo esperado y contado.',
    'product_revision_conflict_or_legacy':
        'El producto cambió o necesita revisión de sus saldos anteriores.',
    'legacy_stock_reconciliation_required':
        'El stock anterior no coincide con los lotes; requiere conciliación antes de habilitarlo.',
    'inventory_admin_required':
        'Esta operación requiere administrador de la clínica.',
    'controlled_reversal_professional_only':
        'Este reverso requiere un administrador con habilitación profesional.',
    'vial_inventory_identity_mismatch':
        'El frasco, producto, lote o unidad no coinciden.',
    'reorder_below_minimum':
        'El punto de reorden debe ser igual o mayor al stock mínimo.',
    'operation_content_changed':
        'La operación anterior tenía otros datos. Actualiza y vuelve a revisar.',
    'invoice_reversed_sale': 'No se puede solicitar factura de una venta revertida.',
    'invoice_fiscal_data_invalid': 'Revisa RFC, régimen, código postal, uso de CFDI y correo.',
    'invoice_request_already_processed': 'Esta solicitud de factura ya fue procesada.',
  };
  for (final e in messages.entries) {
    if (text.contains(e.key)) return e.value;
  }
  return 'No se pudo completar la operación. Comprueba conexión y permisos antes de reintentar.';
}

class SaleScreen extends StatefulWidget {
  const SaleScreen({
    super.key,
    required this.repository,
    required this.shift,
    required this.products,
    required this.prescriptions,
    required this.staff,
    required this.admin,
    this.canUpdateCatalog = false,
    this.services = const [],
    this.catalogUnavailable = false,
    this.clinicName = 'Clínica veterinaria',
    this.charges = const [],
    this.deliveries = const [],
    this.acts = const [],
  });
  final InventoryRepository repository;
  final String shift;
  final List<Map<String, dynamic>> products, prescriptions, staff;
  final bool admin;
  final bool canUpdateCatalog;
  final List<Map<String, dynamic>> services;
  final bool catalogUnavailable;
  final String clinicName;
  final List<Map<String, dynamic>> charges, deliveries, acts;
  @override
  State<SaleScreen> createState() => _SaleScreenState();
}

class _SaleScreenState extends State<SaleScreen> {
  final lines = <Map<String, dynamic>>[];
  String method = 'efectivo', operation = newOperationId();
  String? error;
  bool busy = false, reviewed = false;
  Money get total => lines.fold(
    Money(BigInt.zero),
    (a, l) =>
        a +
        Money.parse(
          l['price'] as String,
        ).times(Quantity.parse(l['quantity'] as String)),
  );
  void changed() {
    reviewed = false;
    operation = newOperationId();
    error = null;
  }

  Future<void> scanProduct() async {
    final code = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const BarcodeScreen()),
    );
    if (!mounted || code == null) return;
    await addByCode(code);
  }

  Future<void> enterBarcode() async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Ingresar código de barras'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Código del producto'),
          onSubmitted: (value) => Navigator.pop(dialogContext, value),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text), child: const Text('Buscar')),
        ],
      ),
    );
    controller.dispose();
    if (!mounted || code == null || code.trim().isEmpty) return;
    await addByCode(code);
  }

  Future<void> addByCode(String code) async {
    final matches = widget.products.where(
      (p) => p['m8_enabled'] == true &&
          p['active'] == true &&
          (p['codigo_barras']?.toString().trim() == code.trim() ||
              p['barcode']?.toString().trim() == code.trim()),
    ).toList();
    if (matches.length == 1) {
      await addProduct(matches.single);
    } else {
      setState(() => error = matches.isEmpty
          ? 'No se encontró un producto activo con ese código de barras.'
          : 'El código coincide con varios productos. Selecciona uno de la lista.');
    }
  }

  Future<void> addProduct(Map<String, dynamic> p) async {
    final lots = (p['lots'] as List)
        .map((e) => Map<String, dynamic>.from(e))
        .where(
          (l) =>
              l['expired'] != true &&
              Quantity.parse(l['cantidad'] as String).positive,
        )
        .toList();
    final rx = widget.prescriptions
        .where((r) => r['product_version_id'] == p['medication_version_id'])
        .toList();
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => RxEntryScreen(
          title: 'Agregar ${p['nombre']}',
          fields: [
            RxField(
              'lot',
              'Lote exacto',
              type: 'select',
              required: true,
              options: {
                for (final l in lots)
                  l['id'] as String:
                      '${l['lote']} · ${l['cantidad']} · ${l['caducidad'] ?? 'sin fecha'}',
              },
            ),
            const RxField(
              'quantity',
              'Cantidad de stock (no dosis)',
              type: 'quantity',
              required: true,
            ),
            if (p['m8_kind'] == 'farmaco')
              RxField(
                'rx',
                'Receta emitida / producto exacto',
                type: 'select',
                required: true,
                options: {
                  for (final r in rx)
                    r['id'] as String:
                        '${r['folio'] ?? 'Receta ordinaria'} · ${r['prescription_id']}',
                },
              ),
          ],
          submit: (d, _) async {
            final q = Quantity.parse(d['quantity'] as String);
            if (['unidad', 'frasco', 'caja'].contains(p['stock_unit']) &&
                q.n % q.d != BigInt.zero) {
              throw const FormatException('Cantidad entera por envase.');
            }
            final lot = lots.firstWhere((l) => l['id'] == d['lot']);
            final already = lines
                .where((l) => l['lot_id'] == lot['id'])
                .fold(
                  Quantity.parse('0'),
                  (a, l) => Quantity(
                    a.n * Quantity.parse(l['quantity']).d +
                        Quantity.parse(l['quantity']).n * a.d,
                    a.d * Quantity.parse(l['quantity']).d,
                  ),
                );
            if (Quantity(
                  already.n * q.d + q.n * already.d,
                  already.d * q.d,
                ).compareTo(Quantity.parse(lot['cantidad'])) >
                0) {
              throw const FormatException(
                'El lote no alcanza para el carrito.',
              );
            }
            setState(() {
              lines.add({
                'kind': 'producto',
                'item_id': p['id'],
                'lot_id': lot['id'],
                'quantity': d['quantity'],
                'price': p['precio_venta'],
                'prescription_item_id': d['rx'],
                'display': p['nombre'],
                'lot_display': lot['lote'],
                'unit': p['stock_unit'],
              });
              changed();
            });
          },
        ),
      ),
    );
  }

  Future<void> addService() async {
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => RxEntryScreen(
          title: 'Servicio manual',
          fields: [
            const RxField('name', 'Servicio', required: true),
            const RxField(
              'quantity',
              'Cantidad',
              type: 'quantity',
              required: true,
            ),
            const RxField('price', 'Precio unitario MXN', required: true),
            const RxField('cost', 'Costo TOTAL capturado MXN', required: true),
          ],
          submit: (d, _) async {
            for (final key in ['price', 'cost']) {
              d[key] = Money.parse(d[key] as String).decimal;
            }
            setState(() {
              lines.add({
                ...d,
                'commission': '0.00',
                'kind': 'servicio',
                'display': d['name'],
              });
              changed();
            });
          },
        ),
      ),
    );
  }

  Future<void> addCatalogService(Map<String, dynamic> service) async {
    if (lines.any((line) => line['catalog_service_id'] == service['id'])) {
      setState(() => error = 'Ese servicio ya está en la nota. Elimínalo para cambiar su precio.');
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => RxEntryScreen(
          title: '${service['name']} · precio para esta venta',
          initial: {'price': '${service['price']}', 'quantity': '1', 'cost': '0'},
          fields: [
            const RxField('quantity', 'Cantidad', type: 'quantity', required: true),
            const RxField('price', 'Precio unitario de esta venta MXN', required: true),
            const RxField('cost', 'Costo TOTAL interno MXN', required: true),
            RxField(
              'price_mode',
              'Qué hacer con el precio del catálogo',
              type: 'select',
              required: true,
              options: {
                'solo_venta': 'Usar solo en esta venta',
                if (widget.canUpdateCatalog) 'actualizar_catalogo': 'Actualizar precio para ventas futuras',
              },
            ),
          ],
          submit: (data, _) async {
            final price = Money.parse(data['price'] as String);
            if (price.cents <= BigInt.zero) {
              throw const FormatException('El precio debe ser mayor que cero.');
            }
            final cost = Money.parse(data['cost'] as String);
            final quantity = Quantity.parse(data['quantity'] as String);
            if (!quantity.positive) throw const FormatException('La cantidad debe ser mayor que cero.');
            setState(() {
              lines.add({
                'kind': 'servicio',
                'catalog_service_id': service['id'],
                'catalog_service_version': service['version'],
                'catalog_price_mode': data['price_mode'],
                'name': service['name'],
                'display': service['name'],
                'quantity': data['quantity'],
                'price': price.decimal,
                'cost': cost.decimal,
                'commission': '0.00',
              });
              changed();
            });
          },
        ),
      ),
    );
  }

  Future<void> post() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final saleId = await widget.repository.write(
          lines.any((line) => line['catalog_service_id'] != null)
              ? 'inv_catalog_service_sale_post'
              : 'inv_sale_post', {
        'p_shift': widget.shift,
        'p_method': method,
        'p_lines': [
          for (final l in lines)
            Map<String, dynamic>.from(l)
              ..remove('display')
              ..remove('lot_display')
              ..remove('unit'),
        ],
        'p_expected_total': total.decimal,
        'p_operation': operation,
      });
      if (mounted) {
        await receiptActions('$saleId');
        if (mounted) Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) setState(() => error = inventoryError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> receiptActions(String saleId) async {
    try {
      final bytes = await buildReceipt(saleId);
      if (!mounted) return;
      final action = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Venta registrada'),
          content: Text('Folio: $saleId\nPuedes imprimir o compartir la nota en PDF por WhatsApp.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dialogContext, 'close'), child: const Text('Terminar')),
            TextButton(onPressed: () => Navigator.pop(dialogContext, 'print'), child: const Text('Imprimir nota')),
            FilledButton(onPressed: () => Navigator.pop(dialogContext, 'share'), child: const Text('Compartir · WhatsApp')),
            TextButton(onPressed: () => Navigator.pop(dialogContext, 'invoice'), child: const Text('Solicitar factura')),
          ],
        ),
      );
      if (action == 'print') {
        await Printing.layoutPdf(onLayout: (_) async => bytes);
      } else if (action == 'share') {
        await Printing.sharePdf(bytes: bytes, filename: 'nota-venta-$saleId.pdf');
      } else if (action == 'invoice' && mounted) {
        await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (_) => RxEntryScreen(
              title: 'Solicitud de factura · $saleId',
              fields: const [
                RxField('fiscal_name', 'Nombre o razón social fiscal', required: true),
                RxField('rfc', 'RFC', required: true),
                RxField('fiscal_regime', 'Régimen fiscal (3 dígitos)', required: true),
                RxField('postal_code', 'Código postal fiscal', required: true),
                RxField('cfdi_use', 'Uso de CFDI (clave de 3 caracteres)', required: true),
                RxField('email', 'Correo para enviar CFDI', required: true),
              ],
              submit: (data, _) async {
                try {
                  await widget.repository.write('inv_invoice_request', {
                    'p_sale': saleId,
                    'p_data': data,
                  });
                } catch (e) {
                  throw FormatException(inventoryError(e));
                }
              },
            ),
          ),
        );
      }
    } catch (_) {
      // La venta ya fue registrada; un fallo al crear o compartir el PDF no la revierte.
    }
  }

  Future<Uint8List> buildReceipt(String saleId) async {
      final font = pw.Font.ttf(await rootBundle.load('assets/fonts/DejaVuSans.ttf'));
      final pdf = pw.Document(theme: pw.ThemeData.withFont(base: font, bold: font));
      pdf.addPage(pw.Page(build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(widget.clinicName, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
          pw.Text('Nota de venta', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
          pw.Text('Folio: $saleId'),
          pw.Text('Fecha: ${DateTime.now().toLocal()}'),
          pw.SizedBox(height: 16),
          for (final line in lines)
            pw.Text('${line['display']} · ${line['quantity']} × ${Money.parse(line['price'] as String).display} = ${Money.parse(line['price'] as String).times(Quantity.parse(line['quantity'] as String)).display}'),
          pw.Divider(),
          pw.Text('Total a pagar: ${total.display}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          pw.Text('Método de pago: $method'),
          pw.Text('Nota interna de venta. No es factura fiscal.'),
        ],
      )));
      return pdf.save();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Punto de venta')),
    body: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Venta interna en MXN. Los precios capturados son finales; no se genera factura fiscal. El servidor confirma lote, caducidad, stock, precio y permisos al registrar.',
          ),
          if (widget.catalogUnavailable)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'El catálogo de servicios no está disponible en esta base de datos. Puedes registrar una venta manual; para elegir un servicio guardado, comprueba la función inv_catalog_services del SQL 14F.',
              ),
            ),
          OutlinedButton.icon(
            onPressed: busy ? null : scanProduct,
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('Escanear producto para la nota de venta'),
          ),
          TextButton.icon(
            onPressed: busy ? null : enterBarcode,
            icon: const Icon(Icons.keyboard),
            label: const Text('Ingresar código de barras'),
          ),
          for (final p in widget.products.where(
            (p) => p['m8_enabled'] == true && p['active'] == true,
          ))
            ListTile(
              title: Text(
                '${p['nombre']} · ${Money.parse(p['precio_venta']).display}',
              ),
              subtitle: Text('${p['stock_unit']} · stock ${p['stock']}'),
              trailing: IconButton(
                onPressed: busy ? null : () => addProduct(p),
                icon: const Icon(Icons.add_shopping_cart),
              ),
            ),
          if (widget.admin)
            for (final service in widget.services.where((s) => s['active'] == true))
              ListTile(
                title: Text('${service['name']} · ${Money.parse('${service['price']}').display}'),
                subtitle: const Text('Puedes usar otro precio solo en esta venta.'),
                trailing: IconButton(
                  tooltip: 'Agregar servicio del catálogo',
                  onPressed: busy ? null : () => addCatalogService(service),
                  icon: const Icon(Icons.add_shopping_cart),
                ),
              ),
          if (widget.admin)
            TextButton(
              onPressed: busy ? null : addService,
              child: const Text('Agregar servicio manual sin comisión'),
            ),
          const Divider(),
          const Text(
            'Cobrar aplicaciones y entregas ya registradas (sin descontar stock de nuevo)',
          ),
          for (final entry in [
            ...widget.charges
                .where((c) => c['paid'] != true)
                .map((c) => (c, 'charge_id')),
            ...widget.acts
                .where((c) => c['paid'] != true)
                .map((c) => (c, 'service_act_id')),
            ...widget.deliveries
                .where((c) => c['paid'] != true)
                .map((c) => (c, 'delivery_id')),
          ])
            ListTile(
              title: Text(
                '${entry.$1['name']} · ${displayMoney(entry.$1['price'])}',
              ),
              trailing: IconButton(
                onPressed: busy
                    ? null
                    : () {
                        if (lines.any((l) => l[entry.$2] == entry.$1['id'])) {
                          return;
                        }
                        setState(() {
                          lines.add({
                            'kind': 'servicio',
                            entry.$2: entry.$1['id'],
                            'quantity': '1',
                            'price': entry.$1['price'],
                            'display': entry.$1['name'],
                          });
                          changed();
                        });
                      },
                icon: const Icon(Icons.add),
              ),
            ),

          for (var index = 0; index < lines.length; index++)
            ListTile(
              title: Text(
                '${lines[index]['display']} · ${lines[index]['quantity']} ${lines[index]['unit'] ?? 'servicio'}',
              ),
              subtitle: Text(
                '${lines[index]['lot_display'] ?? ''} · ${Money.parse(lines[index]['price']).times(Quantity.parse(lines[index]['quantity'])).display}',
              ),
              trailing: IconButton(
                onPressed: busy
                    ? null
                    : () {
                        setState(() {
                          lines.removeAt(index);
                          changed();
                        });
                      },
                icon: const Icon(Icons.delete_outline),
              ),
            ),
          Text(
            'Total a pagar: ${total.display}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const Text('Las comisiones son internas; no se suman al total del cliente.'),
          DropdownButtonFormField<String>(
            initialValue: method,
            decoration: const InputDecoration(labelText: 'Método de pago'),
            items: [
              for (final m in ['efectivo', 'tarjeta', 'transferencia'])
                DropdownMenuItem(value: m, child: Text(m)),
            ],
            onChanged: busy
                ? null
                : (m) {
                    if (m != null) {
                      setState(() {
                        method = m;
                        changed();
                      });
                    }
                  },
          ),
          CheckboxListTile(
            value: reviewed,
            title: const Text(
              'Revisé cantidades de venta, lotes, receta y total a cobrar.',
            ),
            onChanged: busy
                ? null
                : (v) => setState(() => reviewed = v ?? false),
          ),
          if (error != null)
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          FilledButton(
            onPressed: busy || !reviewed || lines.isEmpty ? null : post,
            child: Text(busy ? 'Registrando…' : 'Registrar venta y pago'),
          ),
        ],
      ),
    ),
  );
}

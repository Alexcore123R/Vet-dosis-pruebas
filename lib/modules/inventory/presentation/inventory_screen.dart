import '../../identity/domain/identity_repository.dart';
import '../../ai/domain/ai_repository.dart';
import 'inventory_insights_screen.dart';
import '../../exports/domain/branded_export.dart';
import '../../exports/presentation/branded_export_action.dart';
import 'payments_screen.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../auth/domain/clinic_membership.dart';
import '../../doses/domain/quantity.dart';
import '../../prescribing/presentation/rx_entry_screen.dart';
import '../domain/inventory_models.dart';
import '../domain/inventory_repository.dart';
import 'inventory_view_model.dart';
import 'barcode_screen.dart';
import 'sale_screen.dart';
import 'workflow_screen.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({
    super.key,
    required this.repository,
    required this.member,
    this.identity,
    this.initialSearch = '',
    this.initialSection = 'stock',
    this.ai,
  });
  final InventoryRepository repository;
  final AiRepository? ai;
  final ClinicMembership member;
  final IdentityRepository? identity;
  final String initialSearch;
  final String initialSection;
  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  late InventoryViewModel model;
  final searchController = TextEditingController();
  String section = 'stock', filter = 'todos', search = '';
  @override
  void initState() {
    super.initState();
    section = widget.initialSection;
    search = widget.initialSearch;
    searchController.text = search;
    model = InventoryViewModel(widget.repository, widget.member);
    model.load();
  }

  @override
  void didUpdateWidget(covariant InventoryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.member.userId != widget.member.userId ||
        oldWidget.member.clinicId != widget.member.clinicId ||
        oldWidget.repository != widget.repository) {
      model.dispose();
      model = InventoryViewModel(widget.repository, widget.member);
      section = widget.initialSection;
      search = widget.initialSearch;
      filter = 'todos';
      searchController.text = search;
      model.load();
    }
  }

  @override
  void dispose() {
    searchController.dispose();
    model.dispose();
    super.dispose();
  }

  Future<void> inventoryIdeas() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => InventoryInsightsScreen(
          repository: widget.repository,
          member: widget.member,
          ai: widget.ai,
        ),
      ),
    );
  }

  Future<void> entry(
    String title,
    List<RxField> fields,
    Future<void> Function(Map<String, dynamic>, String) submit, {
    Map<String, dynamic> initial = const {},
  }) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => RxEntryScreen(
          title: title,
          fields: fields,
          initial: initial,
          submit: (d, op) async {
            try {
              await submit(d, op);
            } on FormatException {
              rethrow;
            } catch (e) {
              throw FormatException(inventoryError(e));
            }
          },
        ),
      ),
    );
    if (result == true && mounted) await model.load();
  }

  Map<String, String> get catalog => {
    for (final p in model.rows('catalog'))
      p['id'] as String:
          '${p['name']} · ${p['presentation']} · ${p['source_status']}',
  };
  Future<void> product([Map<String, dynamic>? p]) => entry(
    p == null ? 'Nuevo producto' : 'Editar producto',
    [
      const RxField('name', 'Nombre', required: true),
      const RxField('presentation', 'Presentación', required: true),
      const RxField(
        'kind',
        'Tipo (no es clasificación regulatoria)',
        type: 'select',
        options: {
          'producto': 'Producto no farmacológico',
          'farmaco': 'Fármaco',
        },
        required: true,
      ),
      const RxField(
        'unit',
        'Unidad de stock',
        type: 'select',
        options: {
          'unidad': 'unidad',
          'frasco': 'frasco',
          'caja': 'caja',
          'g': 'g',
          'kg': 'kg',
          'ml': 'ml',
          'L': 'L',
        },
        required: true,
      ),
      RxField(
        'medication_version_id',
        'Presentación comercial del catálogo verificado',
        type: 'select',
        options: catalog,
      ),
      const RxField('price', 'Precio final unitario MXN', required: true),
      const RxField(
        'cost',
        'Costo de referencia MXN (el lote conserva su costo)',
        required: true,
      ),
      const RxField('minimum', 'Stock mínimo', required: true),
      const RxField('reorder', 'Punto de reorden', required: true),
      const RxField('barcode', 'Código de barras'),
      const RxField('supplier', 'Proveedor'),
      const RxField('notes', 'Notas'),
      if (p != null)
        const RxField('active', 'Producto activo', type: 'checkbox'),
    ],
    (d, op) async {
      for (final k in ['price', 'cost']) {
        d[k] = Money.parse(d[k] as String).decimal;
      }
      for (final k in ['minimum', 'reorder']) {
        d[k] = stockQuantity(d[k] as String, zero: true);
      }
      await widget.repository.write('inv_product_save', {
        'p_clinic': widget.member.clinicId,
        'p_id': p?['id'],
        'p_version': p?['version'] ?? 0,
        'p_data': d,
        'p_operation': op,
      });
    },
    initial: p == null
        ? {'barcode': search}
        : {
            'name': p['nombre'],
            'presentation': p['presentacion'],
            'kind': p['m8_kind'],
            'unit': p['stock_unit'],
            'medication_version_id': p['medication_version_id'],
            'price': p['precio_venta'],
            'cost': p['precio_compra'],
            'minimum': p['stock_minimo'],
            'reorder': p['reorder_point'],
            'barcode': p['codigo_barras'],
            'supplier': p['proveedor'],
            'notes': p['notas'],
            'active': p['active'],
          },
  );
  Future<void> receive(Map<String, dynamic> p) => entry(
    'Entrada: ${p['nombre']}',
    [
      const RxField('lot', 'Lote', required: true),
      const RxField(
        'expiry',
        'Caducidad AAAA-MM-DD (obligatoria para fármacos)',
      ),
      const RxField(
        'quantity',
        'Cantidad de stock',
        type: 'quantity',
        required: true,
      ),
      const RxField('cost', 'Costo unitario MXN del lote', required: true),
    ],
    (d, op) async {
      final expiry = (d['expiry'] as String? ?? '').trim();
      if (expiry.isNotEmpty) {
        final date = DateTime.tryParse(expiry);
        if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(expiry) ||
            date == null ||
            date.toIso8601String().substring(0, 10) != expiry) {
          throw const FormatException('Fecha real en formato AAAA-MM-DD.');
        }
      }
      if (p['m8_kind'] == 'farmaco' && expiry.isEmpty) {
        throw const FormatException('Captura la caducidad del fármaco.');
      }
      await widget.repository.write('inv_lot_receive', {
        'p_item': p['id'],
        'p_lot': d['lot'],
        'p_expiry': expiry.isEmpty ? null : expiry,
        'p_quantity': d['quantity'],
        'p_cost': Money.parse(d['cost']).decimal,
        'p_operation': op,
      });
    },
  );
  Future<void> adjust(Map<String, dynamic> l) => entry(
    'Ajuste anexado al lote ${l['lote']}',
    [
      const RxField(
        'delta',
        'Cambio de stock (negativo para merma)',
        required: true,
      ),
      const RxField('reason', 'Motivo obligatorio', required: true),
    ],
    (d, op) async {
      final raw = (d['delta'] as String).trim().replaceAll(',', '.');
      stockQuantity(raw.startsWith('-') ? raw.substring(1) : raw);
      await widget.repository.write('inv_stock_adjust', {
        'p_lot': l['id'],
        'p_delta': raw,
        'p_reason': d['reason'],
        'p_operation': op,
      });
    },
  );
  Future<void> enable(Map<String, dynamic> p) => entry(
    'Revisar inventario anterior (sin alterar saldos)',
    [
      const RxField(
        'kind',
        'Tipo revisado',
        type: 'select',
        options: {
          'producto': 'Producto no farmacológico',
          'farmaco': 'Fármaco',
        },
        required: true,
      ),
      const RxField(
        'unit',
        'Unidad revisada',
        type: 'select',
        options: {
          'unidad': 'unidad',
          'frasco': 'frasco',
          'caja': 'caja',
          'g': 'g',
          'kg': 'kg',
          'ml': 'ml',
          'L': 'L',
        },
        required: true,
      ),
      RxField(
        'med',
        'Presentación comercial',
        type: 'select',
        options: catalog,
      ),
    ],
    (d, op) async {
      await widget.repository.write('inv_enable_legacy', {
        'p_id': p['id'],
        'p_kind': d['kind'],
        'p_unit': d['unit'],
        'p_medication': d['med'],
        'p_operation': op,
      });
    },
  );
  Future<void> scan() async {
    final code = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const BarcodeScreen()),
    );
    if (code != null && mounted) {
      setState(() {
        search = code;
        searchController.text = code;
        filter = 'todos';
      });
    }
  }

  Future<void> photo(Map<String, dynamic> p, ImageSource source) async {
    try {
      final file = await ImagePicker().pickImage(
        source: source,
        maxWidth: 2000,
        maxHeight: 2000,
        imageQuality: 85,
      );
      if (file == null || !mounted) return;
      final bytes = await file.readAsBytes();
      final png =
          bytes.length > 8 &&
          bytes[0] == 137 &&
          bytes[1] == 80 &&
          bytes[2] == 78 &&
          bytes[3] == 71;
      final jpg =
          bytes.length > 3 &&
          bytes[0] == 255 &&
          bytes[1] == 216 &&
          bytes[2] == 255;
      if (!png && !jpg) {
        throw const FormatException('Selecciona una foto JPEG o PNG.');
      }
      await widget.repository.photo(
        widget.member.clinicId,
        p['id'],
        p['version'],
        bytes,
        png ? 'png' : 'jpg',
      );
      if (mounted) await model.load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is FormatException
                  ? e.message
                  : 'No se pudo guardar la foto. Revisa permisos, conexión y la configuración de fotos privadas.',
            ),
          ),
        );
      }
    }
  }

  Future<void> viewPhoto(String path) async {
    try {
      final url = await widget.repository.photoUrl(path);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => Dialog(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Image.network(
              url,
              errorBuilder: (_, _, _) =>
                  const Text('Foto no disponible; vuelve a abrirla.'),
            ),
          ),
        ),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo abrir la fotografía privada.'),
          ),
        );
      }
    }
  }

  Future<void> sale() async {
    var loading = 'cargos y entregas';
    try {
      final workflow = Map<String, dynamic>.from(
        await widget.repository.read('inv_workflow_dashboard', {
          'p_clinic': widget.member.clinicId,
        }),
      );
      loading = 'servicios del catálogo';
      var catalogServices = <Map<String, dynamic>>[];
      var catalogUnavailable = false;
      if (model.canManual) {
        try {
          catalogServices =
              (await widget.repository.read('inv_catalog_services', {
                        'p_clinic': widget.member.clinicId,
                      })
                      as List)
                  .map((e) => Map<String, dynamic>.from(e as Map))
                  .toList();
        } on PostgrestException catch (e) {
          if (e.code != 'PGRST202' && e.code != '42883') rethrow;
          catalogUnavailable = true;
        }
      }
      loading = 'servicios pendientes de cobro';
      final operations = model.managementKnown
          ? {
              'acts': await widget.repository.read('inv_billable_services', {
                'p_clinic': widget.member.clinicId,
              }),
            }
          : Map<String, dynamic>.from(
              await widget.repository.read('ops_dashboard', {
                'p_clinic': widget.member.clinicId,
              }),
            );
      if (!mounted) return;

      final result = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => SaleScreen(
            repository: widget.repository,
            clinicName: widget.member.clinicName,
            shift: model.ownShift!['id'],
            products: model.dispensingKnown && !model.canDispense
                ? model.products
                      .where((p) => p['m8_kind'] != 'farmaco')
                      .toList()
                : model.products,
            prescriptions: model.rows('prescription_items'),
            staff: model.rows('staff'),
            services: catalogServices,
            catalogUnavailable: catalogUnavailable,
            canUpdateCatalog: widget.member.role == ClinicRole.admin,
            charges: (workflow['charges'] as List? ?? [])
                .map((e) => Map<String, dynamic>.from(e))
                .toList(),
            deliveries: (workflow['deliveries'] as List? ?? [])
                .map((e) => Map<String, dynamic>.from(e))
                .toList(),
            acts: (operations['acts'] as List? ?? [])
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList(),
            admin: model.canManual,
          ),
        ),
      );
      if (result == true && mounted) await model.load();
    } catch (e) {
      if (mounted) {
        final detail = switch (e) {
          PostgrestException(:final code) when code != null =>
            ' (código $code)',
          ArgumentError() => ' (operación no disponible en esta versión)',
          TypeError() => ' (respuesta inesperada)',
          _ => '',
        };
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error al cargar $loading$detail. ${inventoryError(e)}',
            ),
            duration: const Duration(seconds: 10),
          ),
        );
      }
    }
  }

  Future<void> invoiceRequests() async {
    try {
      final requests =
          (await widget.repository.read('inv_invoice_requests', {
                    'p_clinic': widget.member.clinicId,
                  })
                  as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Solicitudes de factura'),
          content: SizedBox(
            width: 420,
            height: 400,
            child: requests.isEmpty
                ? const Text('Aún no hay solicitudes de CFDI.')
                : ListView.builder(
                    itemCount: requests.length,
                    itemBuilder: (_, index) {
                      final request = requests[index];
                      return ListTile(
                        title: Text(
                          '${request['fiscal_name']} · ${request['status']}',
                        ),
                        subtitle: Text(
                          'RFC ${request['rfc']} · ${request['email']}\nVenta ${request['sale_id']} · ${displayMoney(request['total'])}',
                        ),
                        isThreeLine: true,
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cerrar'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(inventoryError(e))));
      }
    }
  }

  Future<void> openShift() => entry(
    'Abrir turno de caja',
    [const RxField('opening', 'Fondo inicial de efectivo MXN', required: true)],
    (d, op) async {
      await widget.repository.write('inv_shift_open', {
        'p_clinic': widget.member.clinicId,
        'p_opening': Money.parse(d['opening']).decimal,
        'p_operation': op,
      });
    },
  );
  Future<void> cashMove() => entry(
    'Movimiento de efectivo',
    [
      const RxField(
        'kind',
        'Tipo',
        type: 'select',
        options: {
          'ingreso': 'Ingreso adicional (no venta)',
          'retiro': 'Retiro (no gasto)',
          'gasto': 'Gasto operativo pagado en efectivo',
        },
        required: true,
      ),
      const RxField('amount', 'Importe MXN', required: true),
      const RxField('reason', 'Motivo', required: true),
    ],
    (d, op) async {
      await widget.repository.write('inv_cash_move', {
        'p_shift': model.ownShift!['id'],
        'p_kind': d['kind'],
        'p_amount': Money.parse(d['amount']).decimal,
        'p_reason': d['reason'],
        'p_operation': op,
      });
    },
  );
  Future<void> cut(String id) async {
    try {
      await model.readCut(id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(inventoryError(e))));
      }
    }
  }

  Future<void> closeShift() => entry(
    'Cerrar turno: se congela el corte',
    [
      const RxField('counted', 'Efectivo contado MXN', required: true),
      const RxField('reason', 'Motivo de diferencia (si existe)'),
    ],
    (d, op) async {
      final id = model.ownShift!['id'];
      await widget.repository.write('inv_shift_close', {
        'p_shift': id,
        'p_counted': Money.parse(d['counted']).decimal,
        'p_reason': d['reason'] ?? '',
        'p_operation': op,
      });
    },
  );
  Future<void> reverse(String id) => entry(
    'Reverso: productos al lote; aplicaciones no se deshacen',
    [
      const RxField(
        'reason',
        'Motivo; confirmar devolución física solo de productos',
        required: true,
      ),
    ],
    (d, op) async {
      await widget.repository.write('inv_sale_reverse', {
        'p_sale': id,
        'p_shift': model.ownShift!['id'],
        'p_reason': d['reason'],
        'p_operation': op,
      });
    },
  );
  Future<Map<String, dynamic>> freshCut() async {
    final selectedModel = model;
    final id = selectedModel.cut?['shift_id'];
    if (id is! String) throw StateError('shift_access_required');
    final result = await selectedModel.readCut(id);
    if (!mounted || selectedModel != model) {
      throw StateError('shift_access_required');
    }
    return result;
  }

  Future<void> exportCut() async {
    try {
      final current = await freshCut();
      await FilePicker.saveFile(
        fileName: 'corte-${current['shift_id']}.csv',
        bytes: Uint8List.fromList(utf8.encode(cutCsv(current))),
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo guardar el CSV.')),
        );
      }
    }
  }

  Future<void> newOrder() => entry(
    'Borrador de pedido: revisa antes de aprobar',
    [
      const RxField('supplier', 'Proveedor', required: true),
      const RxField('message', 'Mensaje editable (sin envío)', required: true),
    ],
    (d, op) async {
      await widget.repository.write('inv_order_draft', {
        'p_clinic': widget.member.clinicId,
        'p_supplier': d['supplier'],
        'p_message': d['message'],
        'p_operation': op,
      });
    },
    initial: {
      'message':
          'Hola. Solicito cotización y disponibilidad de los siguientes productos:\n${model.products.where((p) => p['m8_enabled'] == true && p['active'] == true && p['reorder'] == true).map((p) => '- ${p['nombre']} (${p['presentacion']}), stock disponible ${p['available_stock'] ?? p['stock']}; cantidad a pedir: [por revisar]').join('\n')}\nFavor de confirmar lotes, caducidad, precio y entrega. Gracias.',
    },
  );
  Future<void> approve(Map<String, dynamic> d) => entry(
    'Aprobar texto exacto del pedido',
    [
      const RxField(
        'review',
        'Revisé mensaje, cantidades y proveedor',
        type: 'checkbox',
        required: true,
      ),
    ],
    (data, op) async {
      if (data['review'] != true) {
        throw const FormatException('Confirma la revisión.');
      }
      await widget.repository.write('inv_order_approve', {
        'p_id': d['id'],
        'p_operation': op,
      });
    },
  );
  Future<void> orderWhatsApp(Map<String, dynamic> d) => entry(
    'Abrir WhatsApp: el envío será manual',
    [
      const RxField(
        'phone',
        'Número del proveedor con código de país',
        required: true,
      ),
    ],
    (data, _) async {
      final phone = (data['phone'] as String).replaceAll(RegExp(r'[^0-9]'), '');
      if (!RegExp(r'^\d{10,15}$').hasMatch(phone)) {
        throw const FormatException('Número internacional de 10 a 15 dígitos.');
      }
      if (!await launchUrl(
        Uri.parse(
          'https://wa.me/$phone?text=${Uri.encodeComponent(d['message'])}',
        ),
        mode: LaunchMode.externalApplication,
      )) {
        throw const FormatException('No se pudo abrir WhatsApp.');
      }
    },
  );
  Future<void> authorizeDispensing() => entry(
    'Autorizar stock total de una receta (MVZ responsable)',
    [
      RxField(
        'item',
        'Producto farmacológico',
        type: 'select',
        required: true,
        options: {
          for (final p in model.products.where(
            (p) => p['m8_enabled'] == true && p['m8_kind'] == 'farmaco',
          ))
            p['id'] as String: '${p['nombre']} · ${p['stock_unit']}',
        },
      ),
      RxField(
        'rx',
        'Ítem exacto de receta emitida',
        type: 'select',
        required: true,
        options: {
          for (final r in model.rows('prescription_items'))
            r['id'] as String:
                '${r['folio'] ?? 'Ordinaria'} · ${r['prescription_id']}',
        },
      ),
      const RxField(
        'quantity',
        'Cantidad TOTAL autorizada en unidad de stock (0 revoca)',
        required: true,
      ),
      const RxField(
        'until',
        'Vigente hasta UTC (AAAA-MM-DDTHH:MM:SSZ)',
        type: 'instant',
        required: true,
      ),
      const RxField('reason', 'Motivo y revisión de unidades', required: true),
    ],
    (d, op) async {
      if (!model.canAuthorizeDispensing) {
        throw StateError('verified_dispensing_permission_required');
      }
      await widget.repository.write('inv_dispensing_authorize', {
        'p_item': d['item'],
        'p_rx': d['rx'],
        'p_quantity': stockQuantity(d['quantity'], zero: true),
        'p_until': d['until'],
        'p_reason': d['reason'],
        'p_operation': op,
      });
    },
  );
  Future<void> linkVial() async {
    try {
      final raw = await widget.repository.read('rx_vials', {
        'p_clinic': widget.member.clinicId,
      });
      if (!mounted) return;
      final vials = (raw as List)
          .map((e) => Map<String, dynamic>.from(e))
          .where((v) => v['responsible_id'] == widget.member.userId)
          .toList();
      final lots = <Map<String, dynamic>>[
        for (final p in model.products.where(
          (p) => p['m8_enabled'] == true && p['m8_kind'] == 'farmaco',
        ))
          for (final l in (p['lots'] as List).cast<Map>())
            {...l, 'name': p['nombre']},
      ];
      await entry(
        'Vincular envase a frasco abierto',
        [
          RxField(
            'vial',
            'Frasco reportado',
            type: 'select',
            required: true,
            options: {
              for (final v in vials)
                v['id'] as String: '${v['lot']} · ${v['id']}',
            },
          ),
          RxField(
            'lot',
            'Lote exacto de inventario',
            type: 'select',
            required: true,
            options: {
              for (final l in lots)
                l['id'] as String: '${l['name']} · ${l['lote']}',
            },
          ),
          const RxField(
            'packages',
            'Envases abiertos (cantidad entera, no ml)',
            type: 'quantity',
            required: true,
          ),
        ],
        (d, op) async {
          await widget.repository.write('inv_vial_link', {
            'p_vial': d['vial'],
            'p_lot': d['lot'],
            'p_packages': d['packages'],
            'p_operation': op,
          });
        },
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(inventoryError(e))));
      }
    }
  }

  Widget totals(Map<String, dynamic> t) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final e in {
        'gross': 'Ventas menos reversos',
        'cash': 'Efectivo por ventas/reversos',
        'card': 'Tarjeta',
        'transfer': 'Transferencia',
        'cost': 'Costo de mercancía/servicios',
        'commission': 'Comisiones del equipo (internas; no se suman al cobro)',
        'margin': 'Margen después de costos y comisiones',
        'expense': 'Gastos capturados en efectivo',
        'recorded_net': 'Resultado con gastos capturados',
        'income': 'Ingresos adicionales',
        'withdrawal': 'Retiros de efectivo',
      }.entries)
        if (t[e.key] != null)
          Text(
            '${e.value}: ${Money.parse(t[e.key] as String, signed: true).display}',
          ),
      const Text(
        'El resultado no acredita que todos los gastos ni costos pendientes estén incluidos. Ingresos y retiros no se cuentan como ventas/utilidad.',
      ),
    ],
  );
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: model,
    builder: (context, _) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Inventario y ventas',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                onPressed: model.busy ? null : model.load,
                child: const Text('Actualizar'),
              ),
              if (model.canPrepareOrder || model.canReadFinance)
                TextButton.icon(
                  onPressed: inventoryIdeas,
                  icon: const Icon(Icons.auto_awesome),
                  label: const Text(
                    'Analizar existencias, caducidades y ventas',
                  ),
                ),
              if (model.canManage)
                TextButton(
                  onPressed: model.busy
                      ? null
                      : () => entry(
                          'Zona horaria de la clínica',
                          [
                            const RxField(
                              'timezone',
                              'Zona IANA (ej. America/Mexico_City)',
                              required: true,
                            ),
                          ],
                          (d, _) async {
                            await widget.repository.write('inv_settings', {
                              'p_clinic': widget.member.clinicId,
                              'p_timezone': d['timezone'],
                            });
                          },
                          initial: {
                            'timezone':
                                model.dashboard?['timezone'] ??
                                'America/Mexico_City',
                          },
                        ),
                  child: const Text('Zona horaria'),
                ),
            ],
          ),
          if (model.busy) const LinearProgressIndicator(),
          if (model.error != null) Text(model.error!),
          if (model.dashboard != null) ...[
            TextButton(
              onPressed: () async {
                await Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => InventoryWorkflowScreen(
                      repository: widget.repository,
                      member: widget.member,
                      dashboard: model.dashboard!,
                    ),
                  ),
                );
                if (mounted) await model.load();
              },
              child: const Text('Entregas, aplicaciones y permisos'),
            ),
            if (!model.managementKnown ||
                model.canCollect ||
                model.canReadFinance)
              TextButton.icon(
                onPressed: model.busy
                    ? null
                    : () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => PaymentsScreen(
                            repository: widget.repository,
                            member: widget.member,
                            identity: widget.identity,
                          ),
                        ),
                      ),
                icon: const Icon(Icons.payments_outlined),
                label: const Text('Cobros, pagos y referencias externas'),
              ),

            Text(
              'Fecha del servidor en clínica: ${model.dashboard!['today']} · ${model.dashboard!['timezone']}',
            ),
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: section,
              items: [
                for (final e in {
                  'stock': 'Productos y lotes',
                  'cash': 'Punto de venta y caja',
                  'orders': 'Pedidos pendientes de aprobación',
                }.entries)
                  DropdownMenuItem(
                    value: e.key,
                    child: Text(
                      e.value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (v) {
                if (v != null) setState(() => section = v);
              },
            ),
            const SizedBox(height: 16),
            if (section == 'stock') ...[
              TextField(
                controller: searchController,
                decoration: const InputDecoration(
                  labelText: 'Buscar nombre, presentación o código',
                ),
                onChanged: (v) => setState(() => search = v),
              ),
              Wrap(
                spacing: 8,
                children: [
                  TextButton(
                    onPressed: scan,
                    child: const Text('Escanear código'),
                  ),
                  if (model.canManage)
                    TextButton(
                      onPressed: () => product(),
                      child: const Text('Nuevo producto'),
                    ),
                  if (model.canLinkVial)
                    TextButton(
                      onPressed: linkVial,
                      child: const Text('Vincular frasco abierto'),
                    ),
                  if (model.canAuthorizeDispensing)
                    TextButton(
                      onPressed: authorizeDispensing,
                      child: const Text('Autorizar cantidad de receta'),
                    ),
                ],
              ),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: filter,
                items: [
                  for (final e in {
                    'todos': 'Todos',
                    'low': 'Stock bajo / reorden',
                    '30': 'Caducidad ≤30 días',
                    '60': 'Caducidad ≤60 días',
                  }.entries)
                    DropdownMenuItem(
                      value: e.key,
                      child: Text(
                        e.value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => filter = v);
                },
              ),
              for (final p in model.products.where((p) {
                final text =
                    '${p['nombre']} ${p['presentacion']} ${p['codigo_barras'] ?? ''}'
                        .toLowerCase();
                if (!text.contains(search.trim().toLowerCase())) return false;
                if (filter == 'low') {
                  return p['low_stock'] == true || p['reorder'] == true;
                }
                if (filter == '30' || filter == '60') {
                  return (p['lots'] as List).cast<Map>().any(
                    (l) =>
                        l['days'] is int &&
                        (l['days'] as int) <= int.parse(filter) &&
                        Quantity.parse(l['cantidad']).positive,
                  );
                }
                return true;
              }))
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${p['nombre']} · ${p['presentacion']}',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          'Total: ${p['stock']} ${p['stock_unit']} · Disponible: ${p['available_stock'] ?? p['stock']} · Mínimo: ${p['stock_minimo']} · Reorden: ${p['reorder_point']}',
                        ),
                        Text(
                          'Precio: ${displayMoney(p['precio_venta'])} · Código: ${p['codigo_barras'] ?? 'sin capturar'}',
                        ),
                        if (p['low_stock'] == true || p['reorder'] == true)
                          Text(
                            'Revisar resurtimiento',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        if (p['m8_enabled'] != true)
                          const Text(
                            'Registro anterior: necesita revisión de saldos y clasificación antes de usarlo.',
                          ),
                        if (p['m8_enabled'] == true &&
                            (model.canManage || model.canReceive))
                          Wrap(
                            spacing: 8,
                            children: [
                              if (model.canManage)
                                TextButton(
                                  onPressed: () => product(p),
                                  child: const Text('Editar datos/precios'),
                                ),
                              if (model.canReceive)
                                TextButton(
                                  onPressed: () => receive(p),
                                  child: const Text('Entrada de lote'),
                                ),
                              if (model.canManage)
                                TextButton(
                                  onPressed: () => photo(p, ImageSource.camera),
                                  child: const Text('Foto con cámara'),
                                ),
                              if (model.canManage)
                                TextButton(
                                  onPressed: () =>
                                      photo(p, ImageSource.gallery),
                                  child: const Text('Elegir foto'),
                                ),
                            ],
                          ),
                        if (p['m8_enabled'] != true && model.canManage)
                          TextButton(
                            onPressed: () => enable(p),
                            child: const Text('Revisar inventario anterior'),
                          ),
                        if (p['photo_path'] != null)
                          TextButton(
                            onPressed: () => viewPhoto(p['photo_path']),
                            child: const Text('Ver foto privada'),
                          ),
                        for (final l in (p['lots'] as List).cast<Map>())
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              'Lote ${l['lote']} · ${l['cantidad']} ${p['stock_unit']}',
                            ),
                            subtitle: Text(
                              expiryLabel(Map<String, dynamic>.from(l)),
                              style: TextStyle(
                                color:
                                    l['expired'] == true ||
                                        l['days'] is int &&
                                            (l['days'] as int) <= 30
                                    ? Theme.of(context).colorScheme.error
                                    : null,
                              ),
                            ),
                            trailing: model.canAdjust && p['m8_enabled'] == true
                                ? IconButton(
                                    onPressed: () =>
                                        adjust(Map<String, dynamic>.from(l)),
                                    icon: const Icon(Icons.edit_note),
                                  )
                                : null,
                          ),
                      ],
                    ),
                  ),
                ),
              if (model.products.isEmpty)
                const Text(
                  'Sin productos. El administrador puede registrar el primero; no hay productos ficticios precargados.',
                ),
            ],
            if (section == 'cash') ...[
              if (model.ownShift == null && model.canCollect)
                FilledButton(
                  onPressed: openShift,
                  child: const Text('Abrir mi turno'),
                ),
              if (model.ownShift != null)
                Wrap(
                  spacing: 8,
                  children: [
                    FilledButton(
                      onPressed: model.canCollect ? sale : null,
                      child: const Text('Nueva venta'),
                    ),
                    TextButton(
                      onPressed: model.canMoveCash ? cashMove : null,
                      child: const Text('Ingreso / retiro / gasto'),
                    ),
                    TextButton(
                      onPressed: () => cut(model.ownShift!['id']),
                      child: const Text('Revisar corte actual'),
                    ),
                    TextButton(
                      onPressed: model.canCollect ? closeShift : null,
                      child: const Text('Contar y cerrar turno'),
                    ),
                  ],
                ),
              if (model.canReadFinance)
                TextButton.icon(
                  onPressed: invoiceRequests,
                  icon: const Icon(Icons.receipt_long),
                  label: const Text('Solicitudes de factura'),
                ),
              if (model.canReadFinance &&
                  model.dashboard!['day_totals'] != null) ...[
                const Text('Resumen del día · todas las cajas de la clínica'),
                totals(
                  Map<String, dynamic>.from(model.dashboard!['day_totals']),
                ),
              ],
              for (final sh in model.rows('shifts'))
                ListTile(
                  title: Text(
                    '${sh['closed_at'] == null ? 'Abierto' : 'Cerrado'} · ${sh['opened_at']}',
                  ),
                  subtitle: Text('Cajero ${sh['cashier_id']}'),
                  onTap: () => cut(sh['id']),
                ),
              if (model.cut != null) ...[
                const Divider(),
                Text(
                  'Corte ${model.cut!['closed_at'] == null ? 'EN CURSO' : 'CONGELADO'}',
                ),
                totals(Map<String, dynamic>.from(model.cut!['totals'])),
                Text(
                  'Esperado: ${Money.parse(model.cut!['expected_cash'], signed: true).display} · Contado: ${model.cut!['counted_cash'] ?? 'pendiente'} · Diferencia: ${model.cut!['difference'] ?? 'pendiente'}',
                ),
                TextButton(
                  onPressed: exportCut,
                  child: const Text('Exportar corte CSV para Excel'),
                ),
                BrandedExportAction(
                  repository: widget.identity,
                  clinicId: widget.member.clinicId,
                  clinicName: widget.member.clinicName,
                  title: 'Corte interno · No comprobante fiscal · MXN',
                  fileName: 'corte-${model.cut!["shift_id"]}',
                  rows: () async => csvRows(cutCsv(await freshCut())),
                ),
                for (final s in (model.cut!['sales'] as List).cast<Map>())
                  ListTile(
                    title: Text(
                      '${s['method']} · ${Money.parse(s['total']).display}',
                    ),
                    subtitle: Text('${s['created_at']} · ${s['id']}'),
                    trailing: model.canReverse && model.ownShift != null
                        ? TextButton(
                            onPressed: () => reverse(s['id']),
                            child: const Text('Reverso completo'),
                          )
                        : null,
                  ),
              ],
            ],
            if (section == 'orders') ...[
              const Text(
                'Borradores preparados con datos de inventario. El envío se abre manualmente después de aprobar el texto exacto. La redacción con proveedor de IA y la comparación de mercado siguen pendientes.',
              ),
              if (model.canReadFinance &&
                  model.rows('top_products').isNotEmpty) ...[
                const Text('Mayor importe vendido en 30 días, menos reversos'),
                for (final p in model.rows('top_products'))
                  Text(
                    '${p['name']} · ${p['quantity']} ${p['unit']} · ${displayMoney(p['amount'], signed: true)}',
                  ),
              ],
              if (model.canPrepareOrder)
                TextButton(
                  onPressed: newOrder,
                  child: const Text('Preparar borrador de resurtimiento'),
                ),
              for (final d in model.rows('orders'))
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${d['supplier']} · ${d['approval'] == null ? 'Pendiente de aprobación' : 'Aprobado'}',
                        ),
                        SelectableText(d['message']),
                        if (model.canApproveOrder && d['approval'] == null)
                          TextButton(
                            onPressed: () => approve(d),
                            child: const Text('Revisar y aprobar'),
                          ),
                        if (model.canPrepareOrder && d['approval'] != null)
                          Wrap(
                            children: [
                              TextButton(
                                onPressed: () => Clipboard.setData(
                                  ClipboardData(text: d['message']),
                                ),
                                child: const Text('Copiar mensaje aprobado'),
                              ),
                              TextButton(
                                onPressed: () => orderWhatsApp(d),
                                child: const Text(
                                  'Abrir WhatsApp · envío manual',
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ],
        ],
      );
    },
  );
}

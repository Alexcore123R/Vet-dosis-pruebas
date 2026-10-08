import 'package:flutter/material.dart';

class FormExitController extends ChangeNotifier {
  bool completed = false;
  void close(BuildContext context, [Object? result]) {
    completed = true;
    notifyListeners();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) Navigator.pop(context, result);
    });
  }
}

/// Protects in-app navigation; it does not store clinical data on the device.
class UnsavedFormScope extends StatefulWidget {
  const UnsavedFormScope({
    super.key,
    required this.controller,
    required this.dirty,
    required this.busy,
    required this.child,
  });
  final FormExitController controller;
  final bool dirty, busy;
  final Widget child;
  @override
  State<UnsavedFormScope> createState() => _UnsavedFormScopeState();
}

class _UnsavedFormScopeState extends State<UnsavedFormScope> {
  bool asking = false, leaving = false;
  Future<void> requestExit() async {
    if (widget.busy || asking) return;
    asking = true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cambios sin guardar'),
        content: const Text(
          'Si sales, perderás los cambios de este formulario.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Seguir editando'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Salir sin guardar'),
          ),
        ],
      ),
    );
    asking = false;
    if (discard != true || !mounted || widget.busy) return;
    setState(() => leaving = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context);
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (_, _) => PopScope<Object?>(
      canPop:
          widget.controller.completed ||
          leaving ||
          (!widget.dirty && !widget.busy),
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) requestExit();
      },
      child: widget.child,
    ),
  );
}

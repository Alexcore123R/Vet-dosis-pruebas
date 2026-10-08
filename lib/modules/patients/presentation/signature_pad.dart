import 'package:flutter/material.dart';

class SignaturePad extends StatefulWidget {
  const SignaturePad({
    super.key,
    required this.onChanged,
    this.label = 'Firma del tutor (dibuja dentro del recuadro)',
  });
  final ValueChanged<List<List<double>?>> onChanged;
  final String label;
  @override
  State<SignaturePad> createState() => _SignaturePadState();
}

class _SignaturePadState extends State<SignaturePad> {
  final points = <Offset?>[];
  void add(Offset point, Size size) {
    setState(
      () => points.add(
        Offset(
          (point.dx / size.width).clamp(0, 1),
          (point.dy / size.height).clamp(0, 1),
        ),
      ),
    );
    widget.onChanged(
      points.map((p) => p == null ? null : [p.dx, p.dy]).toList(),
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(widget.label),
      const SizedBox(height: 8),
      LayoutBuilder(
        builder: (context, constraints) {
          final size = Size(constraints.maxWidth, 180);
          return Semantics(
            label: 'Área para dibujar la firma del tutor',
            child: Container(
              height: 180,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border.all(
                  color: Theme.of(context).colorScheme.outline,
                ),
              ),
              child: GestureDetector(
                onPanStart: (d) => add(d.localPosition, size),
                onPanUpdate: (d) => add(d.localPosition, size),
                onPanEnd: (_) {
                  setState(() => points.add(null));
                  widget.onChanged(
                    points.map((p) => p == null ? null : [p.dx, p.dy]).toList(),
                  );
                },
                child: CustomPaint(
                  painter: SignaturePainter(
                    List.of(points),
                    Theme.of(context).colorScheme.onSurface,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          );
        },
      ),
      TextButton(
        onPressed: () {
          setState(points.clear);
          widget.onChanged([]);
        },
        child: const Text('Limpiar firma'),
      ),
    ],
  );
}

class SignaturePainter extends CustomPainter {
  SignaturePainter(this.points, this.color);
  final List<Offset?> points;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (var i = 1; i < points.length; i++) {
      final a = points[i - 1], b = points[i];
      if (a != null && b != null) {
        canvas.drawLine(
          Offset(a.dx * size.width, a.dy * size.height),
          Offset(b.dx * size.width, b.dy * size.height),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant SignaturePainter old) =>
      old.points != points || old.color != color;
}

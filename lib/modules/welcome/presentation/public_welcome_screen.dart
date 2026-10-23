import 'package:flutter/material.dart';

import '../../auth/presentation/auth_screen.dart';
import '../../auth/presentation/auth_view_model.dart';

/// Public product entry shown before authentication.
class PublicWelcomeScreen extends StatelessWidget {
  const PublicWelcomeScreen({super.key, required this.auth});

  final AuthViewModel? auth;

  void _openAccess(BuildContext context, {bool register = false}) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AuthScreen(
          model: auth,
          configured: auth != null,
          initialRegister: register,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const SizedBox(height: 20),
                Icon(Icons.pets_rounded, size: 56, color: color.primary),
                const SizedBox(height: 16),
                Text(
                  'Bienvenido a VetDosis',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
                const SizedBox(height: 12),
                Text(
                  'Herramientas para organizar la atención veterinaria en un solo lugar.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => _openAccess(context),
                  icon: const Icon(Icons.login),
                  label: const Text('Iniciar sesión'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: auth == null
                      ? null
                      : () => _openAccess(context, register: true),
                  child: const Text('Crear cuenta'),
                ),
                const SizedBox(height: 28),
                Text('¿Qué puedes hacer?', style: Theme.of(context).textTheme.headlineSmall),
                const _Feature(Icons.calculate_outlined, 'Cálculos y vademécum',
                    'Consulta fichas y prepara cálculos con revisión profesional.'),
                const _Feature(Icons.medical_information_outlined, 'Pacientes y documentos',
                    'Organiza expedientes, recetas y formatos de la clínica.'),
                const _Feature(Icons.groups_outlined, 'Trabajo en equipo',
                    'Coordina agenda, tareas, mensajes e inventario según permisos.'),
                const SizedBox(height: 24),
                Text('Planes y costos', style: Theme.of(context).textTheme.headlineSmall),
                const Text('Precios propuestos en MXN. Los cobros aún están desactivados.'),
                const _Plan('Gratis', '\$0', 'Espacio personal · 50 pacientes · 250 MiB'),
                const _Plan('Individual', '\$199/mes · \$1,990/año',
                    'Espacio propio · 5,000 pacientes · 2 GiB'),
                const _Plan('Clínica', '\$799/mes · \$7,990/año',
                    'Equipo completo · 50,000 pacientes · 10 GiB'),
                const SizedBox(height: 8),
                const Text(
                  'Beta cerrada. Precios y límites sujetos a revisión antes del lanzamiento. Las referencias y respuestas asistidas requieren revisión veterinaria.',
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Feature extends StatelessWidget {
  const _Feature(this.icon, this.title, this.description);
  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          leading: Icon(icon),
          title: Text(title),
          subtitle: Text(description),
        ),
      );
}

class _Plan extends StatelessWidget {
  const _Plan(this.name, this.price, this.description);
  final String name;
  final String price;
  final String description;

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          title: Text('$name · $price'),
          subtitle: Text(description),
        ),
      );
}

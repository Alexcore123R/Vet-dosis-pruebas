import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

class AppVersionLabel extends StatefulWidget {
  const AppVersionLabel({super.key});
  @override
  State<AppVersionLabel> createState() => _AppVersionLabelState();
}

class _AppVersionLabelState extends State<AppVersionLabel> {
  late final Future<PackageInfo> version = PackageInfo.fromPlatform();
  @override
  Widget build(BuildContext context) => FutureBuilder<PackageInfo>(
    future: version,
    builder: (context, snapshot) {
      final info = snapshot.data;
      return SelectableText(
        info == null
            ? 'VetDosis Pro · ${snapshot.hasError ? 'Versión no disponible' : 'Consultando versión…'}'
            : 'VetDosis Pro · ${info.version} · Compilación ${info.buildNumber}\n${info.packageName}',
      );
    },
  );
}

import 'package:flutter/foundation.dart';

/// Invalidates only the active clinic's visible identity after a saved version.
class ClinicIdentityEvents extends ChangeNotifier {
  String? clinicId;
  void saved(String id) {
    clinicId = id;
    notifyListeners();
  }
}

final clinicIdentityEvents = ClinicIdentityEvents();

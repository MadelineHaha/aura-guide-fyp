import 'package:flutter/material.dart';

/// After Firebase Auth succeeds, return to the app root so [RoleHomeGate]
/// can route to the correct role-specific home screen.
void returnToRoleHome(BuildContext context) {
  Navigator.of(context).popUntil((route) => route.isFirst);
}

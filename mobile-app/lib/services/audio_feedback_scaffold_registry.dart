import 'package:flutter/material.dart';

/// Tracks the main menu [Scaffold] so audio feedback can detect an open drawer.
class AudioFeedbackScaffoldRegistry {
  AudioFeedbackScaffoldRegistry._();

  static GlobalKey<ScaffoldState>? mainMenuScaffoldKey;

  static bool get isMainMenuDrawerOpen =>
      mainMenuScaffoldKey?.currentState?.isDrawerOpen ?? false;

  static bool isDescendantOfDrawer(BuildContext context) {
    var found = false;
    context.visitAncestorElements((ancestor) {
      if (ancestor.widget is Drawer) {
        found = true;
        return false;
      }
      return true;
    });
    return found;
  }

  /// When the drawer is open, only drawer content is focusable; when closed,
  /// drawer offstage widgets are excluded.
  static bool shouldIncludeForDrawerState(BuildContext context) {
    final inDrawer = isDescendantOfDrawer(context);
    return isMainMenuDrawerOpen ? inDrawer : !inDrawer;
  }
}

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'audio_feedback_bounds.dart';
import 'audio_feedback_route_notifier.dart';
import 'audio_feedback_scaffold_registry.dart';

/// One readable text block discovered on the visible route.
class ScannedTextBlock {
  const ScannedTextBlock({
    required this.id,
    required this.text,
    required this.bounds,
  });

  final String id;
  final String text;
  final Rect bounds;
}

/// Finds [RenderParagraph] nodes on the current route so text inside cards and
/// containers is included without wrapping every [Text] widget manually.
class AudioFeedbackTextScanner {
  AudioFeedbackTextScanner._();

  /// Reads the nearest [ModalRoute] without registering an inherited dependency.
  /// [ModalRoute.of] must not be used while walking the element tree — it corrupts
  /// the dependency graph and triggers framework assertions.
  static ModalRoute<dynamic>? _modalRouteForElement(Element element) {
    ModalRoute<dynamic>? route;
    element.visitAncestorElements((ancestor) {
      final widget = ancestor.widget;
      if (widget.runtimeType.toString() == '_ModalScopeStatus') {
        route = (widget as dynamic).route as ModalRoute<dynamic>?;
        return false;
      }
      return true;
    });
    return route;
  }

  /// Skips subtrees that belong to a route other than the visible one.
  /// Ancestors above any [ModalRoute] (route == null) must keep traversing.
  static bool _shouldSkipSubtree(
    Element element,
    Route<dynamic>? topRoute,
  ) {
    final route = _modalRouteForElement(element);
    if (route == null) return false;
    if (topRoute != null) return route != topRoute;
    return !route.isCurrent;
  }

  static List<ScannedTextBlock> scan(BuildContext context) {
    final rootElement = WidgetsBinding.instance.rootElement;
    if (rootElement == null) return const [];

    final topRoute = AudioFeedbackRouteNotifier.instance.topRoute;
    final screenSize = AudioFeedbackBounds.screenSizeFor(context);
    final blocks = <ScannedTextBlock>[];
    final seen = <String>{};

    void visit(Element element) {
      if (_shouldSkipSubtree(element, topRoute)) {
        return;
      }

      final matchesDrawer =
          AudioFeedbackScaffoldRegistry.shouldIncludeForDrawerState(element);
      if (!matchesDrawer) {
        element.visitChildren(visit);
        return;
      }

      final renderObject = element.renderObject;
      if (renderObject is RenderParagraph &&
          renderObject.hasSize &&
          renderObject.attached) {
        final text = renderObject.text
            .toPlainText(
              includeSemanticsLabels: false,
              includePlaceholders: false,
            )
            .trim();
        if (text.isNotEmpty) {
          final rect = renderObject.localToGlobal(Offset.zero) & renderObject.size;
          if (rect.width >= 4 &&
              rect.height >= 4 &&
              !AudioFeedbackBounds.isScreenFilling(rect, screenSize)) {
            final key = '${rect.top.toStringAsFixed(1)}:'
                '${rect.left.toStringAsFixed(1)}:$text';
            if (seen.add(key)) {
              blocks.add(
                ScannedTextBlock(
                  id: 'scan:${identityHashCode(renderObject)}',
                  text: text,
                  bounds: rect,
                ),
              );
            }
          }
        }
      }

      element.visitChildren(visit);
    }

    visit(rootElement);

    blocks.sort((a, b) {
      final y = a.bounds.top.compareTo(b.bounds.top);
      if (y != 0) return y;
      return a.bounds.left.compareTo(b.bounds.left);
    });

    return blocks;
  }
}

import 'package:flutter/material.dart';

List<String> conversationSearchTerms(String query) {
  return query
      .trim()
      .split(RegExp(r'\s+'))
      .where((term) => term.isNotEmpty)
      .toList();
}

List<InlineSpan> buildHighlightedTextSpans({
  required String text,
  required String query,
  required TextStyle style,
  required Color highlightColor,
}) {
  final terms = conversationSearchTerms(query);
  if (terms.isEmpty) {
    return [TextSpan(text: text, style: style)];
  }

  final pattern = RegExp(
    '(${terms.map(RegExp.escape).join('|')})',
    caseSensitive: false,
  );
  final spans = <InlineSpan>[];
  for (final part in text.split(pattern)) {
    if (part.isEmpty) continue;
    final isMatch = terms.any(
      (term) => part.toLowerCase() == term.toLowerCase(),
    );
    spans.add(
      TextSpan(
        text: part,
        style: isMatch
            ? style.copyWith(
                backgroundColor: highlightColor,
                fontWeight: FontWeight.w700,
              )
            : style,
      ),
    );
  }
  return spans;
}

Widget highlightedMessageText({
  required String text,
  required String query,
  required TextStyle style,
  Color highlightColor = const Color(0xFFFFF176),
}) {
  return Text.rich(
    TextSpan(
      children: buildHighlightedTextSpans(
        text: text,
        query: query,
        style: style,
        highlightColor: highlightColor,
      ),
    ),
  );
}

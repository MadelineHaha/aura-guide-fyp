/**
 * Formats free-text typed by staff: sentence case + terminal punctuation.
 * e.g. "patient is stable" → "Patient is stable."
 */
export function formatTypedSentence(text) {
  const trimmed = String(text || "").trim();
  if (!trimmed) return trimmed;

  let formatted = trimmed
    .toLowerCase()
    .replace(/(^\w|[.!?]\s+\w)/g, (match) => match.toUpperCase());

  if (!/[.!?]$/.test(formatted)) {
    formatted += ".";
  }

  return formatted;
}

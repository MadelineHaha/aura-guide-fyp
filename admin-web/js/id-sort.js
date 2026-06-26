/** Compare IDs like U00001 and S00002 by letter prefix, then numeric suffix. */
export function comparePrefixedIds(leftId, rightId) {
  const left = String(leftId || "").trim().toUpperCase();
  const right = String(rightId || "").trim().toUpperCase();

  if (!left || left === "—") return !right || right === "—" ? 0 : 1;
  if (!right || right === "—") return -1;

  const leftMatch = left.match(/^([A-Z]+)(\d+)$/);
  const rightMatch = right.match(/^([A-Z]+)(\d+)$/);

  if (leftMatch && rightMatch) {
    if (leftMatch[1] !== rightMatch[1]) {
      return leftMatch[1].localeCompare(rightMatch[1]);
    }
    const leftNum = Number(leftMatch[2]);
    const rightNum = Number(rightMatch[2]);
    if (leftNum !== rightNum) return leftNum - rightNum;
    return left.localeCompare(right);
  }

  return left.localeCompare(right);
}

export function sortByPrefixedId(items, getId) {
  return [...items].sort((a, b) => comparePrefixedIds(getId(a), getId(b)));
}

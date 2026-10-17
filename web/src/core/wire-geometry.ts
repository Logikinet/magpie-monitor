// Adapted from yetone/magpie (MIT), internal/gui/assets/plugins/routing/client.js @7660399
/** Coordinates are relative to the stage; callers measure DOM nodes separately. */
export interface NodeRect {
  l: number;
  r: number;
  t: number;
  b: number;
  cx: number;
  cy: number;
}
export function relativeRect(
  node: { left: number; right: number; top: number; bottom: number },
  stage: { left: number; top: number },
): NodeRect {
  return {
    l: node.left - stage.left,
    r: node.right - stage.left,
    t: node.top - stage.top,
    b: node.bottom - stage.top,
    cx: (node.left + node.right) / 2 - stage.left,
    cy: (node.top + node.bottom) / 2 - stage.top,
  };
}
function cubic(source: NodeRect, target: NodeRect): string {
  const mx = (source.r + target.l) / 2;
  return `M${source.r} ${source.cy} C${mx} ${source.cy} ${mx} ${target.cy} ${target.l} ${target.cy}`;
}
export function agentToHub(source: NodeRect, hub: NodeRect): string {
  return hub.l > source.r ? cubic(source, hub) : `M${source.cx} ${source.b} L${hub.cx} ${hub.t}`;
}
export function hubToRow(hub: NodeRect, row: NodeRect, agentsBottom = hub.b): string {
  if (row.l > hub.r) return cubic(hub, row);
  const x = row.l - 12,
    y = Math.max(hub.b, agentsBottom - 8);
  return `M${hub.cx} ${hub.b} L${hub.cx} ${y} C${hub.cx} ${y + 22} ${x} ${y + 2} ${x} ${y + 24} L${x} ${row.cy - 10} Q${x} ${row.cy} ${row.l} ${row.cy}`;
}
export function subheaderToRow(header: NodeRect, row: NodeRect): string {
  // Place the group rail 9px left of its heading.
  const x = header.l - 9;
  return `M${header.l} ${header.cy} Q${x} ${header.cy} ${x} ${header.cy + 9} L${x} ${row.cy - 9} Q${x} ${row.cy} ${row.l} ${row.cy}`;
}

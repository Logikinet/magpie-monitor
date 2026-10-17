import { expect, it } from 'vitest';
import { agentToHub, hubToRow, relativeRect, subheaderToRow } from '../../src/core/wire-geometry';
const rect = (l: number, t: number, w = 20, h = 20) => ({
  l,
  t,
  r: l + w,
  b: t + h,
  cx: l + w / 2,
  cy: t + h / 2,
});
it('normalizes node coordinates to the stage origin', () => {
  expect(relativeRect({ left: 100, right: 120, top: 50, bottom: 70 }, { left: 80, top: 30 })).toEqual(
    rect(20, 20),
  );
});
it('uses midpoint cubic curves to the right, and a line for stacked agents', () => {
  expect(agentToHub(rect(0, 0), rect(60, 20))).toBe('M20 10 C40 10 40 30 60 30');
  expect(hubToRow(rect(0, 0), rect(60, 20))).toBe('M20 10 C40 10 40 30 60 30');
  expect(agentToHub(rect(0, 0), rect(0, 40))).toBe('M10 20 L10 40');
});
it('routes stacked rows down a 12px rail and rounds into the row', () => {
  expect(hubToRow(rect(20, 0), rect(20, 100), 40)).toBe(
    'M30 20 L30 32 C30 54 8 34 8 56 L8 100 Q8 110 20 110',
  );
});
it('branches from a sub-header on a 9px left rail with quadratic joins', () => {
  expect(subheaderToRow(rect(30, 40), rect(30, 80))).toBe('M30 50 Q21 50 21 59 L21 81 Q21 90 30 90');
});

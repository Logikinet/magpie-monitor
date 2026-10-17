const palette = [
  '#171717',
  '#cd3131',
  '#0dbc79',
  '#e5e510',
  '#2472c8',
  '#bc3fbc',
  '#11a8cd',
  '#e5e5e5',
  '#666666',
  '#f14c4c',
  '#23d18b',
  '#f5f543',
  '#3b8eea',
  '#d670d6',
  '#29b8db',
  '#ffffff',
];
export function terminalColor(n: number): string {
  if (n < 16) return palette[n] ?? palette[7];
  if (n >= 232) {
    const g = 8 + (Math.min(255, n) - 232) * 10;
    return `rgb(${g},${g},${g})`;
  }
  const v = n - 16,
    level = (x: number) => (x === 0 ? 0 : 55 + x * 40);
  return `rgb(${level(Math.floor(v / 36))},${level(Math.floor(v / 6) % 6)},${level(v % 6)})`;
}
export function ansiToHtml(text: string): string {
  const escape = (s: string) =>
    s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  let fg = '',
    bg = '',
    bold = false,
    result = '',
    end = 0;
  const append = (s: string) => {
    result += `<span style="color:${fg || 'inherit'};background:${bg || 'transparent'};font-weight:${bold ? 700 : 400}">${escape(s.replace(/\x1b\][^\x07]*(?:\x07|$)/g, '').replace(/\x1b\[[0-?]*[ -/]*[@-~]/g, ''))}</span>`;
  };
  for (const m of text.matchAll(/\x1b\[([0-9;]*)m/g)) {
    append(text.slice(end, m.index));
    end = m.index! + m[0].length;
    const codes = (m[1] || '0').split(';').map(Number);
    for (let i = 0; i < codes.length; i++) {
      const c = codes[i];
      if (c === 0) {
        fg = '';
        bg = '';
        bold = false;
      } else if (c === 1) bold = true;
      else if (c === 22) bold = false;
      else if (c === 39) fg = '';
      else if (c === 49) bg = '';
      else if ((c === 38 || c === 48) && codes[i + 1] === 5) {
        const color = terminalColor(codes[i + 2]);
        if (c === 38) fg = color;
        else bg = color;
        i += 2;
      } else if (c >= 30 && c <= 37) fg = terminalColor(c - 30);
      else if (c >= 90 && c <= 97) fg = terminalColor(c - 90 + 8);
      else if (c >= 40 && c <= 47) bg = terminalColor(c - 40);
    }
  }
  append(text.slice(end));
  return result;
}

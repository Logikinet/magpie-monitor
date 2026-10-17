import { expect, test, type Locator, type Page, type TestInfo } from '@playwright/test';

type NodeFs = {
  mkdirSync: (path: string, options: { recursive: boolean }) => void;
  writeFileSync: (path: string, data: string) => void;
};
type NodePath = { dirname: (path: string) => string };

const load = new Function('specifier', 'return import(specifier)') as (
  specifier: string,
) => Promise<NodeFs & NodePath>;

async function installCursor(page: Page) {
  await page.addInitScript(() => {
    const paint = () => {
      if (document.getElementById('demo-cursor')) return;
      const style = document.createElement('style');
      style.textContent =
        '#demo-cursor{position:fixed;z-index:2147483647;width:14px;height:14px;margin:-2px 0 0 -2px;border-radius:50%;background:#7dd3fc;box-shadow:0 0 0 2px #0b1220,0 2px 8px rgba(0,0,0,.45);pointer-events:none;transform:translate(-80px,-80px)}';
      document.head.appendChild(style);
      const cursor = document.createElement('div');
      cursor.id = 'demo-cursor';
      document.body.appendChild(cursor);
      addEventListener(
        'mousemove',
        (event) => {
          cursor.style.transform = `translate(${event.clientX}px, ${event.clientY}px)`;
        },
        true,
      );
    };
    if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', paint);
    else paint();
  });
}

async function glide(page: Page, dy: number, ms: number) {
  if (ms <= 0) return;
  if (Math.abs(dy) < 1) {
    await page.waitForTimeout(ms);
    return;
  }
  await page.evaluate(
    ({ dy, ms }) => {
      const startY = window.scrollY;
      const t0 = performance.now();
      const step = (now: number) => {
        const p = Math.min(1, (now - t0) / ms);
        const eased = p < 0.5 ? 2 * p * p : 1 - Math.pow(-2 * p + 2, 2) / 2;
        window.scrollTo(0, startY + dy * eased);
        if (p < 1) requestAnimationFrame(step);
      };
      requestAnimationFrame(step);
    },
    { dy, ms },
  );
  const frames = 6;
  for (let i = 1; i <= frames; i += 1) {
    const t = i / frames;
    await page.mouse.move(760 + Math.sin(t * Math.PI) * 48, 430 + t * 36, { steps: 5 });
    await page.waitForTimeout(ms / frames);
  }
}

async function humanClick(page: Page, locator: Locator) {
  await locator.scrollIntoViewIfNeeded();
  const box = await locator.boundingBox();
  if (!box) throw new Error('element is not visible');
  const x = box.x + Math.min(Math.max(box.width / 2, 8), box.width - 8);
  const y = box.y + box.height / 2;
  await page.mouse.move(x, y, { steps: 20 });
  await page.waitForTimeout(180);
  await locator.click();
}

async function scrollRoom(page: Page) {
  return page.evaluate(() =>
    Math.max(0, document.documentElement.scrollHeight - window.innerHeight - window.scrollY),
  );
}

async function writeTimeline(testInfo: TestInfo, json: string) {
  const fs = await load('node:fs');
  const path = await load('node:path');
  const dest = testInfo.outputPath('demo-timeline.json');
  fs.mkdirSync(path.dirname(dest), { recursive: true });
  fs.writeFileSync(dest, json);
}

test('mock walk', async ({ page }, testInfo) => {
  test.setTimeout(180_000);
  await installCursor(page);
  const origin = Date.now();
  const marks: Record<string, number> = {};
  const mark = (name: string) => {
    marks[name] = Number(((Date.now() - origin) / 1000).toFixed(2));
  };
  const beat = (ms: number) => page.waitForTimeout(ms);
  const nav = page.locator('nav.desktop-nav');
  try {
    await page.goto('/?mock=1&theme=dark#/home');
    await expect(page.getByTestId('view-home')).toBeVisible();
    await expect(page.getByTestId('mock-badge')).toBeVisible();
    await expect(page.locator('.collector-stats strong').first()).toBeVisible();
    await page.mouse.move(760, 420, { steps: 12 });
    mark('homeStart');
    await beat(1400);
    await glide(page, Math.min(await scrollRoom(page), 1500), 7000);
    await beat(1200);
    mark('homeEnd');

    await humanClick(page, nav.getByRole('link', { name: '动态', exact: true }));
    await page.evaluate(() => window.scrollTo(0, 0));
    await expect(page.getByTestId('view-activity')).toBeVisible();
    await beat(900);
    const commit = page.locator('.activity-toolbar').getByRole('button', { name: /^提交/ });
    await expect(commit).toBeVisible();
    await humanClick(page, commit);
    await expect(commit).toHaveAttribute('aria-pressed', 'true');
    await beat(900);
    await glide(page, Math.min(await scrollRoom(page), 520), 2500);
    await beat(600);

    await humanClick(page, nav.getByRole('link', { name: 'Tmux', exact: true }));
    await page.evaluate(() => window.scrollTo(0, 0));
    await expect(page.getByTestId('view-tmux')).toBeVisible();
    await beat(1000);
    await humanClick(page, page.getByRole('button', { name: '全屏', exact: true }).first());
    const dialog = page.getByRole('dialog');
    await expect(dialog).toBeVisible();
    await expect(dialog.getByRole('checkbox', { name: '实时监看' })).toBeChecked();
    await expect(dialog.locator('pre')).toContainText(/devbox|codex/, { timeout: 10_000 });
    await beat(4500);
    await humanClick(page, dialog.getByRole('button', { name: '关闭', exact: true }));
    await expect(dialog).toBeHidden();
    await beat(500);

    await humanClick(page, nav.getByRole('link', { name: '服务', exact: true }));
    await page.evaluate(() => window.scrollTo(0, 0));
    await expect(page.getByTestId('view-svc')).toBeVisible();
    await beat(800);
    const filters = page.locator('.service-filters');
    for (const name of [/^Docker/, /^定时任务/, /^用户/]) {
      const chip = filters.getByRole('button', { name });
      await humanClick(page, chip);
      await expect(chip).toHaveAttribute('aria-pressed', 'true');
      await beat(1400);
    }

    await humanClick(page, nav.getByRole('link', { name: 'Agent', exact: true }));
    await page.evaluate(() => window.scrollTo(0, 0));
    await expect(page.getByTestId('view-agent')).toBeVisible();
    await expect(page.getByTestId('routing-view')).toBeVisible({ timeout: 15_000 });
    mark('routingStart');
    await beat(10_000);
    const seat = await page.evaluate(() => {
      const rows = [...document.querySelectorAll<HTMLElement>('[data-seat]')];
      const mid = window.innerHeight / 2;
      const ranked = rows
        .map((el) => el.getBoundingClientRect())
        .filter((rect) => rect.width > 0 && rect.bottom > 90 && rect.top < window.innerHeight - 16)
        .sort((a, b) => Math.abs((a.top + a.bottom) / 2 - mid) - Math.abs((b.top + b.bottom) / 2 - mid));
      const rect = ranked[0];
      if (!rect) return null;
      return { x: rect.left + Math.min(rect.width / 2, 200), y: rect.top + rect.height / 2 };
    });
    if (!seat) throw new Error('no routing seat in view');
    await page.mouse.move(seat.x, seat.y, { steps: 24 });
    await beat(1200);
    const requestsDelta = await page.evaluate(() => {
      const el = document.querySelector('#rt-requests');
      if (!el) return 0;
      return el.getBoundingClientRect().top - 110;
    });
    await glide(page, requestsDelta, 1000);
    const request = page.locator('#rt-requests button[data-seq]').nth(1);
    await expect(request).toBeVisible();
    await humanClick(page, request);
    const backToLive = page.locator('.rt-actions').getByRole('button', { name: '回到实时', exact: true });
    await expect(backToLive).toBeVisible();
    await beat(1400);
    await glide(page, await page.evaluate(() => -window.scrollY), 800);
    await humanClick(page, backToLive);
    await expect(page.locator('.rt-actions').getByRole('button', { name: '回到实时', exact: true })).toHaveCount(0);
    await beat(900);
    mark('routingEnd');

    await humanClick(page, page.locator('nav.agent-subnav').getByRole('button', { name: '用量与配额', exact: true }));
    await page.evaluate(() => window.scrollTo(0, 0));
    const usage = page.getByTestId('usage-view');
    await expect(usage).toBeVisible();
    await beat(1000);
    const week = usage.getByRole('button', { name: '近 7 日', exact: true });
    await humanClick(page, week);
    await expect(week).toHaveAttribute('aria-pressed', 'true');
    await beat(1400);
    const used = usage.getByRole('button', { name: '已用', exact: true });
    await humanClick(page, used);
    await expect(used).toHaveAttribute('aria-pressed', 'true');
    await beat(1200);
    const remain = usage.getByRole('button', { name: '剩余', exact: true });
    await humanClick(page, remain);
    await expect(remain).toHaveAttribute('aria-pressed', 'true');
    await beat(700);
    await glide(page, Math.min(await scrollRoom(page), 420), 1600);

    await humanClick(page, page.locator('nav.agent-subnav').getByRole('button', { name: '服务商', exact: true }));
    await page.evaluate(() => window.scrollTo(0, 0));
    await expect(page.getByTestId('providers-view')).toBeVisible();
    await beat(1100);
    await glide(page, Math.min(await scrollRoom(page), 480), 2000);
    await beat(800);

    await humanClick(page, page.locator('nav.agent-subnav').getByRole('button', { name: '运行时', exact: true }));
    await page.evaluate(() => window.scrollTo(0, 0));
    const runtimeFilters = page.getByRole('navigation', { name: '运行时' });
    await expect(runtimeFilters).toBeVisible();
    await beat(1100);
    const running = runtimeFilters.getByRole('button', { name: '运行中', exact: true });
    await humanClick(page, running);
    await expect(running).toHaveAttribute('aria-pressed', 'true');
    await beat(1600);
    const tasks = runtimeFilters.getByRole('button', { name: '任务', exact: true });
    await humanClick(page, tasks);
    await expect(tasks).toHaveAttribute('aria-pressed', 'true');
    await beat(1400);
    mark('end');
  } finally {
    const json = JSON.stringify(
      {
        home: [marks.homeStart ?? 0, marks.homeEnd ?? 0],
        routing: [marks.routingStart ?? 0, marks.routingEnd ?? 0],
        marks,
      },
      null,
      2,
    );
    try {
      await writeTimeline(testInfo, json);
    } catch (error) {
      console.error(error);
    }
  }
});

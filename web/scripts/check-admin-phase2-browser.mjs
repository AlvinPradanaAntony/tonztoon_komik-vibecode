import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { Browser, sleep } from '../../.agents/skills/taste-skill/scripts/lib/cdp.mjs';
const base = process.env.ADMIN_QA_URL ?? 'http://127.0.0.1:3102';
const out = path.resolve('../docs/screenshots/admin-phase2-complete'); fs.mkdirSync(out, { recursive: true });
const routes = ['/login','/overview','/endpoints','/endpoints/reader','/requests','/requests/demo-req-0001','/runtime-logs','/runtime-logs/demo-req-0001','/health','/alerts','/alerts/reader-latency','/data/comics','/data/comics/c1','/data/comics/c1/edit','/data/comics/c1/chapters','/data/chapters/c1-12.5','/data/chapters/c1-12.5/edit','/data/genres','/data/sources','/data/sources/komiku','/data/accounts','/data/accounts/u1','/data/accounts/u1/edit','/data/accounts/u1/library','/data/helpdesk','/data/helpdesk/HD-DEMO-001','/data/audit','/data/audit/audit-001','/comic-preview','/comic-preview/komiku/komik-contoh-a','/comic-preview/komiku/komik-contoh-a/chapters/12.5','/data-flow','/data-model'];
const browser = await Browser.launch(), report = { routes: [], states: [], failures: [], console: [] };
async function ready(page,route){for(let i=0;i<80;i++){const done=await page.eval(path=>!!document.documentElement&&!!document.querySelector('h1')&&!document.querySelector('.tt-page-skeleton')&&location.pathname===path,new URL(base+route).pathname).catch(()=>false);if(done)return;await sleep(100);}throw new Error('Route did not become ready: '+route);}
try {
  const page = await browser.newPage({ reducedMotion: true });
  for (const theme of ['light','dark']) {
    await page.send('Page.addScriptToEvaluateOnNewDocument', { source: `try{localStorage.setItem('tt-admin-theme','${theme}')}catch{}` });
    for (const width of [1440,360]) {
      await page.setViewport({ width, height: 900 });
      for (let index = 0; index < routes.length; index++) {
        const route = routes[index];
        const errorStart=page.consoleErrors.length;
        await page.goto(base + route, { settleMs: 700 });
        await ready(page,route);
        const result = await page.eval(() => ({ heading: [...document.querySelectorAll('h1')].map(n => n.textContent), width: innerWidth, scrollWidth: document.documentElement.scrollWidth, errors: [...document.querySelectorAll('main')].some(n => n.textContent.includes('Application error')), controls: [...document.querySelectorAll('main button,main input,main select,main textarea')].filter(n => n.getClientRects().length && !n.closest('dialog:not([open])')).length, theme: document.documentElement.dataset.theme }));
        const row = { theme, width, route, ...result, console:page.consoleErrors.slice(errorStart) }; report.routes.push(row);
        if (result.heading.length !== 1 || result.scrollWidth > result.width + 1 || result.errors) report.failures.push(row);
        await page.screenshot({ path: path.join(out, `${String(index + 1).padStart(2,'0')}-${theme}-${width}.jpg`), quality: 60 });
      }
      console.log(`Browser matrix: ${theme} ${width}, ${routes.length} routes checked.`);
    }
  }
  for (const route of ['/overview','/endpoints','/runtime-logs','/data/comics','/data/accounts','/comic-preview','/data-flow','/data-model']) {
    for (const state of ['loading','empty','error','denied','stale','partial','timeout','gap','down']) {
      await page.goto(`${base}${route}?state=${state}`, { settleMs: 180 });
      await ready(page,route);
      const result = await page.eval(() => ({ headings: document.querySelectorAll('h1').length, overflow: document.documentElement.scrollWidth > innerWidth + 1, text: document.querySelector('main')?.textContent.slice(0,450) }));
      report.states.push({ route, state, ...result }); if (result.headings !== 1 || result.overflow) report.failures.push({ route, state, ...result });
    }
  }
  report.console = page.consoleErrors;
  fs.writeFileSync(path.join(out, 'browser-matrix.json'), JSON.stringify(report, null, 2));
  console.log(JSON.stringify({ routes: report.routes.length, states: report.states.length, failures: report.failures.length, consoleErrors: report.console.length }));
  assert.equal(report.failures.length, 0, JSON.stringify(report.failures.slice(0,3)));
  assert.equal(report.console.length, 0, JSON.stringify(report.console.slice(0,3)));
} finally { await browser.close(); }

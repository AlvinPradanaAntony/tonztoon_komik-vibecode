import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { Browser, sleep } from '../../.agents/skills/taste-skill/scripts/lib/cdp.mjs';
const base = process.env.ADMIN_QA_URL ?? 'http://127.0.0.1:3102';
const out = path.resolve('../docs/screenshots/admin-phase2-complete'); fs.mkdirSync(out, { recursive: true });
const browser = await Browser.launch(), page = await browser.newPage({ reducedMotion: true });
// Each group starts from a clean document, deliberately accepting the editor's unload guard.
browser.listeners.set(page.sessionId+'|Page.javascriptDialogOpening',new Set([()=>{void page.send('Page.handleJavaScriptDialog',{accept:true});}]));
const report = { groups: [], checks: [], failures: [], console: [] };
const text = () => page.eval(() => document.querySelector('main')?.innerText ?? '');
const check = (name, condition) => { report.checks.push({ name, pass: !!condition }); assert.ok(condition, name); };
const wait = async (fn, label) => { for (let i = 0; i < 40; i++) { if (await fn()) return; await sleep(150); } throw new Error('Timeout: ' + label); };
const goto = async route => { await page.goto(base + route, { settleMs: 800 }); assert.equal(await page.eval(()=>location.pathname),new URL(base+route).pathname); };
async function click(label, scope = 'main') {
  const point = await page.eval(({ label, scope }) => {
    const el = [...document.querySelectorAll(`${scope} button,${scope} a,${scope} summary,${scope} label`)].find(n => n.getClientRects().length && (n.textContent.trim() === label || n.getAttribute('aria-label') === label));
    if (!el) throw new Error('Missing clickable: ' + label);
    el.scrollIntoView({ block: 'center', behavior: 'instant' }); const r = el.getBoundingClientRect(); return { x: r.x + r.width / 2, y: r.y + r.height / 2, href:el.getAttribute('href') };
  }, { label, scope });
  await page.send('Input.dispatchMouseEvent', { type: 'mousePressed', x:point.x,y:point.y, button: 'left', clickCount: 1 });
  await page.send('Input.dispatchMouseEvent', { type: 'mouseReleased', x:point.x,y:point.y, button: 'left', clickCount: 1 }); await sleep(250);
  if(point.href?.startsWith('/')&&!point.href.startsWith('//')){
    await wait(()=>page.eval(href=>location.pathname===new URL(href,location.origin).pathname,point.href),'link navigation');
    await wait(()=>page.eval(()=>!document.querySelector('.tt-page-skeleton,.tt-navigation-progress')),'route content');await sleep(100);
  }
}
async function field(label, value) {
  await page.eval(({ label, value }) => {
    const target = [...document.querySelectorAll('label')].find(n => n.textContent.trim() === label);
    if (!target) throw new Error('Missing label: ' + label);
    const el = document.getElementById(target.htmlFor);
    const proto = el.tagName === 'SELECT' ? HTMLSelectElement.prototype : el.tagName === 'TEXTAREA' ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
    Object.getOwnPropertyDescriptor(proto, 'value').set.call(el, value);
    el.dispatchEvent(new Event(el.tagName === 'SELECT' ? 'change' : 'input', { bubbles: true }));
    el.dispatchEvent(new Event('blur', { bubbles: true }));
  }, { label, value }); await sleep(360);
}
async function key(key, code = key) { const windowsVirtualKeyCode={Escape:27,Tab:9,Enter:13}[key]; await page.send('Input.dispatchKeyEvent', { type: 'keyDown', key, code,windowsVirtualKeyCode,...(key==='Enter'?{text:'\r'}:{}) }); await page.send('Input.dispatchKeyEvent', { type: 'keyUp', key, code,windowsVirtualKeyCode }); await sleep(350); }
async function group(name, fn) { if(process.env.ADMIN_QA_GROUP&&!name.includes(process.env.ADMIN_QA_GROUP))return;const errorStart=page.consoleErrors.length;try { await fn(); report.groups.push({ name, pass: true,console:page.consoleErrors.slice(errorStart) }); console.log('PASS ' + name); } catch (error) { report.groups.push({ name, pass: false,console:page.consoleErrors.slice(errorStart) }); report.failures.push({ name, message: error.stack }); console.log('FAIL ' + name + ': ' + error.message); } }
try {
  await group('Login validation and 401/403/expired', async () => {
    await goto('/login'); await click('Periksa login contoh'); check('login required fields', (await text()).includes('Identifier wajib diisi'));
    for (const scenario of ['401','403','expired','success']) { await field('Identifier / email', 'admin-contoh'); await field('Password', 'example-only'); await field('Hasil login contoh', scenario); await click('Periksa login contoh'); const body = await text(); check('login outcome ' + scenario, scenario === 'expired' ? body.includes('kedaluwarsa') : scenario === 'success' ? body.includes('Validasi frontend selesai') : body.includes(scenario + ' contoh')); }
    check('login secrets not in storage', await page.eval(() => !JSON.stringify({ ...localStorage, ...sessionStorage }).includes('example-only')));
  });
  await group('Catalog editor validation, preview, focus and local commit', async () => {
    await goto('/data/comics/c1/edit'); await field('Judul', ''); await click('Periksa perubahan'); check('editor error summary', (await text()).includes('Judul wajib diisi'));
    await field('Judul', 'Komik Contoh A editorial QA'); await click('Periksa perubahan'); check('preview opened', await page.eval(() => !!document.querySelector('dialog[open]')));
    check('preview diff before/after', await page.eval(() => document.querySelector('dialog[open]').textContent.includes('Komik Contoh A editorial QA')));
    await key('Escape'); check('Escape closes preview', await page.eval(() => !document.querySelector('dialog[open]')));
    check('focus restored after preview', await page.eval(() => document.activeElement?.textContent.includes('Periksa perubahan')));
    await click('Periksa perubahan'); await click('Simpan contoh', 'dialog[open]'); check('local commit labeled', (await text()).includes('Perubahan contoh disimpan'));
    await click('Kembali ke daftar / detail'); await wait(async () => (await text()).includes('Komik Contoh A editorial QA'), 'effective title');
    check('source override effective columns', (await text()).includes('Efektif'));
    await click('Kembalikan title ke source'); await click('Konfirmasi contoh', 'dialog[open]'); check('reset override', !(await text()).includes('Kembalikan title ke source'));
    await click('Chapter / relasi');check('detail relations tab',(await text()).includes('Buka semua chapter'));await click('Aktivitas');await click('Lihat audit resource');check('local audit correlation',(await text()).includes('Perubahan lokal contoh'));
  });
  await group('Draft, conflict and uncertain operation reconciliation', async () => {
    await goto('/data/comics/c1/edit'); await field('Judul', 'Draft konflik QA'); await click('Skenario penyimpanan contoh'); await field('Hasil submit contoh', 'conflict'); await click('Periksa perubahan'); await click('Simpan contoh', 'dialog[open]'); check('conflict draft retained', (await text()).includes('Konflik versi contoh') && await page.eval(() => document.getElementById('editor-title').value === 'Draft konflik QA'));
    await click('Salin draft aman'); check('copy draft feedback', (await text()).includes('disalin') || (await text()).includes('Clipboard tidak tersedia'));
    await field('Hasil submit contoh', 'pending'); await click('Periksa perubahan'); await click('Simpan contoh', 'dialog[open]'); check('pending no success', (await text()).includes('Hasil contoh belum pasti'));
    await click('Periksa status tindakan contoh'); check('reconciled result', (await text()).includes('Perubahan contoh disimpan'));
    await goto('/data/comics/c1/edit'); await click('Pulihkan draft sesi'); check('draft absence after confirmed commit', (await text()).includes('Belum ada draft tersimpan'));
  });
  await group('Archive restore and URL filters pagination', async () => {
    await goto('/data/comics/c1'); await click('Arsipkan Komik Contoh A'); await click('Konfirmasi contoh', 'dialog[open]'); check('archive state', (await text()).includes('Pulihkan Komik Contoh A'));
    await click('Pulihkan Komik Contoh A'); await click('Konfirmasi contoh', 'dialog[open]'); check('restored state', (await text()).includes('Arsipkan Komik Contoh A'));
    await goto('/data/comics?size=5'); await click('Berikutnya'); check('pagination URL', await page.eval(() => new URL(location.href).searchParams.get('page') === '2'));
    await field('Cari Komik', 'no-match-QA'); check('filter empty', (await text()).includes('Tidak ada hasil'));
    await click('Reset filter'); await field('Source', 'shinigami'); check('source URL filter', await page.eval(() => new URL(location.href).searchParams.get('source') === 'shinigami'));
    await click('Komik Contoh Bshinigami/komik-contoh-b'); await click('Kembali'); check('return preserves source', await page.eval(() => new URL(location.href).searchParams.get('source') === 'shinigami'));
  });
  await group('Genre/chapter/account/helpdesk editors', async () => {
    await goto('/data/genres/new'); await field('Nama genre', 'Genre QA'); await field('Slug unik', 'genre-qa'); await click('Periksa perubahan'); await click('Simpan contoh', 'dialog[open]'); check('genre created locally', (await text()).includes('Perubahan contoh disimpan'));
    await goto('/data/comics/c1/chapters/new'); await field('Nomor chapter', '14.5'); await field('Judul chapter', 'Chapter 14.5 QA'); await field('Source URL HTTPS', 'https://example.test/chapter-14.5'); await click('Periksa perubahan'); await click('Simpan contoh', 'dialog[open]'); check('fractional chapter create', (await text()).includes('Perubahan contoh disimpan'));
    await goto('/data/accounts/new'); await field('Username', 'qa_reader'); await field('Nama tampilan', 'QA Reader'); await field('Email untuk akun contoh', 'qareader@example.test'); await field('Password awal contoh', 'example-secret-123'); await click('Periksa perubahan'); check('account preview excludes secret', await page.eval(() => !document.querySelector('dialog[open]').textContent.includes('example-secret-123'))); await click('Simpan contoh', 'dialog[open]'); check('account local mutation', (await text()).includes('Perubahan contoh disimpan')); check('account no secret storage', await page.eval(() => !JSON.stringify({ ...sessionStorage, ...localStorage }).includes('example-secret-123')));
    await goto('/data/helpdesk/HD-DEMO-001/edit'); await field('Status penanganan', 'resolved'); await field('Catatan internal contoh', 'Catatan QA contoh'); await click('Periksa perubahan'); await click('Simpan contoh', 'dialog[open]'); await click('Kembali ke daftar / detail'); check('helpdesk updated', (await text()).includes('resolved'));
  });
  await group('Demo permissions and recovery states', async () => {
    await goto('/data/accounts'); await click('Opsi data contoh'); await field('Profil izin contoh', 'viewer'); check('account denied without rows', (await text()).includes('Akses ditolak') && !(await text()).includes('reader_contoh_01'));
    await field('Profil izin contoh', 'all'); await field('State data', 'loading'); check('loading state', (await text()).includes('Selesaikan pemuatan')); await click('Selesaikan pemuatan contoh');
    await field('State data', 'error'); await click('Coba lagi contoh'); check('retry restores rows', (await text()).includes('reader_contoh_01'));
  });
  await group('Request pause, filters, exact ID and runtime correlation', async () => {
    await goto('/requests'); await click('Jeda tampilan'); await click('Tambahkan batch contoh'); check('paused new event count', (await text()).includes('25 event baru menunggu')); await click('Lanjutkan tampilan');
    await field('Request ID persis / route', 'demo-req-0600'); check('request exact ID found', (await text()).includes('demo-req-0600')); await click('demo-req-0600'); await wait(async () => (await text()).includes('Metadata request tersanitasi'), 'request detail'); await click('Lihat runtime terkait'); check('runtime inspector correlation', (await text()).includes('Inspector event'));
  });
  await group('Runtime shared modes, buffer, filters, copy, clear and selection', async () => {
    await goto('/runtime-logs'); await click('Jeda tampilan'); await click('Tambahkan batch contoh'); check('runtime waiting events', (await text()).includes('25 event baru'));
    await click('Terstruktur'); check('mode URL', await page.eval(() => new URL(location.href).searchParams.get('mode') === 'structured')); check('pause survives mode', (await text()).includes('Dijeda'));
    await field('Level', 'ERROR'); check('runtime empty filter', (await text()).includes('Tidak ada hasil')); await click('Reset filter'); await click('Terminal'); await click('Salin log tersanitasi'); check('runtime copy feedback', (await text()).includes('disalin') || (await text()).includes('Clipboard tidak tersedia'));
    await click('Perluas panel'); check('runtime expanded', (await text()).includes('Kembalikan panel')); await click('Kembalikan panel');
    await click('Bungkus baris');check('runtime wrap toggle',await page.eval(()=>getComputedStyle(document.querySelector('[aria-label="Output runtime contoh"]')).whiteSpace==='pre'));await click('Bungkus baris');
    await click('Ke event terbaru'); await click('Bersihkan tampilan lokal'); check('runtime clear local', (await text()).includes('Belum ada pesan sesuai filter')); await click('Lanjutkan tampilan'); await click('Tambahkan batch contoh'); check('new logs after clear', !(await text()).includes('Belum ada pesan sesuai filter'));
  });
  await group('Health unknown slots and alert states', async () => {
    await goto('/health'); await field('Environment', 'staging'); check('health unknown', (await text()).includes('Unknown') && (await text()).includes('Belum tersedia'));
    await goto('/alerts'); await click('Skenario monitoring lokal'); await field('Skenario', 'errors'); for (let i = 0; i < 4; i++) await click('Langkah 30 detik'); check('alert firing state', (await text()).includes('firing'));
    if(await page.eval(()=>document.querySelector('.tt-admin').dataset.sidebar!=='collapsed'))await click('Ubah lebar sidebar','body');await sleep(350);check('collapsed alert badge remains inside link',await page.eval(()=>{const el=document.querySelector('aside.tt-sidebar a[aria-label="Alert"] [aria-label$="insiden perlu diperiksa"]');if(!el)return false;const a=el.getBoundingClientRect(),b=el.closest('a').getBoundingClientRect();return a.left>=b.left&&a.right<=b.right&&a.top>=b.top&&a.bottom<=b.bottom;}));
    await field('Skenario', 'gap'); await click('Langkah 30 detik'); check('alert unknown state', (await text()).includes('unknown'));
  });
  await group('Custom time window validation and investigation cutoff',async()=>{
    await goto('/overview');await click('Kustom');await wait(()=>page.eval(()=>[...document.querySelectorAll('label')].some(label=>label.textContent==='Awal rentang UTC+7')),'custom range fields');await field('Awal rentang UTC+7','2026-10-20T13:19:29');await field('Akhir rentang UTC+7','2026-10-28T13:19:29');await click('Terapkan rentang kustom');check('custom range maximum seven days',(await text()).includes('maksimal tujuh hari'));
    await field('Awal rentang UTC+7','2026-10-28T13:09:29');await field('Akhir rentang UTC+7','2026-10-28T13:14:29');await click('Terapkan rentang kustom');check('custom range URL applied',await page.eval(()=>new URL(location.href).searchParams.get('window_to')==='2026-10-28T06:14:29.000Z'));
    await click('Request log contoh');check('investigation preserves custom cutoff',await page.eval(()=>location.pathname==='/requests'&&new URL(location.href).searchParams.get('range')==='custom'&&new URL(location.href).searchParams.get('window_to')==='2026-10-28T06:14:29.000Z'));
    await field('Rentang','15');check('predefined range restored',await page.eval(()=>new URL(location.href).searchParams.get('range')==='15'));
  });
  await group('Preview source scope, fractional chapter and reader measurements', async () => {
    await goto('/comic-preview');await click('Popular');check('popular fixture order',await page.eval(()=>document.querySelector('main article h2')?.textContent==='Komik Contoh H'));await click('Latest');check('latest fixture order',await page.eval(()=>document.querySelector('main article h2')?.textContent==='Komik Contoh A'));
    await field('Scope source', 'komiku'); await field('Cari judul komik', 'Contoh A'); await click('Komik Contoh A'); await wait(async () => (await text()).includes('Semua chapter'), 'preview detail'); await field('Cari nomor / judul chapter', '12.5'); await click('Chapter 12.5'); await wait(async () => (await text()).includes('Reader diagnostik'), 'reader');
    await click('Periksa seluruh page chapter ini'); await wait(async () => (await text()).includes('3 berhasil'), 'valid decode'); check('reader measured http and bytes', (await text()).includes('HTTP aktual') && (await text()).includes('200'));
    await field('Skenario attempt berikutnya', '503'); await click('Retry page 1'); await wait(async () => (await text()).includes('HTTP 503 diterima'), '503 fixture'); check('HTTP error measured', (await text()).includes('503'));
    await field('Skenario attempt berikutnya', 'html'); await click('Retry page 1'); await wait(async () => (await text()).includes('bukan gambar'), 'HTML payload'); check('HTML 200 separated from decode', (await text()).includes('text/html'));
    await field('Skenario attempt berikutnya', 'valid'); await click('Retry page 1'); await wait(async () => (await text()).includes('3 berhasil'), 'retry valid'); check('failed attempts retained', (await text()).includes('HTTP 503 diterima'));
    await field('Skenario attempt berikutnya', 'duplicate'); check('duplicate payload flagged', (await text()).includes('Nomor page duplikat')); await click('Stop'); await click('Reset sesi lokal'); check('reader reset explicit', (await text()).includes('Hasil lokal direset'));
  });
  await group('Custom flow selection, pan, zoom, edge and motion semantics', async () => {
    await goto('/data-flow');await page.eval(()=>document.querySelector('[data-flow-node="api"]').focus());await sleep(150);check('flow focus does not select',await page.eval(()=>!new URL(location.href).searchParams.has('node')));await key('Enter');await wait(()=>page.eval(()=>new URL(location.href).searchParams.get('node')==='api'),'keyboard flow selection');check('flow Enter selects',await page.eval(()=>new URL(location.href).searchParams.get('node')==='api'));await key('Escape');await wait(()=>page.eval(()=>!new URL(location.href).searchParams.has('node')),'flow clear');check('flow Escape clears and restores focus',await page.eval(()=>!new URL(location.href).searchParams.has('node')&&document.activeElement?.dataset.flowNode==='api'));
    await field('Cari node', 'FastAPI'); await click('Pilih FastAPI'); check('flow node inspector', (await text()).includes('Inspector FastAPI'));
    await click('Perbesar'); await click('Perkecil'); await click('Fit view'); await click('Reset viewport');
    await field('Mode alur', 'demo'); await click('Putar demonstrasi arah'); check('demo labeled', (await text()).includes('Demonstrasi, bukan trafik nyata'));
    check('reduced motion static edges', await page.eval(() => [...document.querySelectorAll('svg path[role=button]')].every(n => getComputedStyle(n).animationName === 'none')));
    await field('Tampilan flow', 'list'); await field('Cari node', ''); await click('Daftar relasi dan arah'); await click('Request bisnis'); check('flow edge inspector', (await text()).includes('Inspector Request bisnis'));
  });
  await group('Readonly ERD four diagrams, search, dictionary and relations', async () => {
    await goto('/data-model?view=list'); await field('Cari tabel / kolom', 'images'); await click('Pilih chapters'); check('ERD JSONB and generated', (await text()).includes('jsonb') && (await text()).includes('generated'));
    for (const diagram of ['users','monitoring','admin','catalog']) { await field('Diagram', diagram); check('ERD diagram ' + diagram, (await text()).includes(diagram === 'users' ? 'profiles' : diagram === 'monitoring' ? 'api_endpoints' : diagram === 'admin' ? 'admin_operations' : 'comics')); }
    await field('Tampilan ERD', 'canvas'); await wait(() => page.eval(() => !!document.querySelector('.react-flow')), 'React Flow mount'); await click('Perbesar ERD'); await click('Perkecil ERD'); await click('Fit ERD'); await click('Reset ERD');
    check('ERD readonly nodes', await page.eval(() => !document.querySelector('.react-flow__node.draggable')));
    check('ERD readonly keyboard instructions',await page.eval(()=>document.querySelector('.tt-erd').textContent.includes('Diagram baca saja.')));await page.eval(()=>document.querySelector('.react-flow__node').focus());await key('Enter');await wait(()=>page.eval(()=>new URL(location.href).searchParams.has('table')),'keyboard ERD selection');check('ERD Enter selects',await page.eval(()=>new URL(location.href).searchParams.has('table')));await key('Escape');await wait(()=>page.eval(()=>!new URL(location.href).searchParams.has('table')),'ERD clear');check('ERD Escape clears selection',await page.eval(()=>!new URL(location.href).searchParams.has('table')));
    await click('Relasi dan constraint');await click('profiles → user_bookmarks');check('logical relation inspector',await page.eval(()=>document.querySelector('section[aria-label="Inspector relasi"]')?.textContent.includes('Relasi logis')));
  });
  await group('Mobile drawer, focus return and desktop sidebar preference', async () => {
    await page.setViewport({ width: 360, height: 800 }); await goto('/data/comics'); await click('Buka menu navigasi', 'body'); check('mobile drawer open', await page.eval(() => !!document.querySelector('dialog[open]'))); await key('Escape'); check('drawer focus return', await page.eval(() => document.activeElement?.getAttribute('aria-label') === 'Buka menu navigasi'));
    await page.setViewport({ width: 1440, height: 900 }); await click('Ubah lebar sidebar', 'body'); check('sidebar saved preference', await page.eval(() => ['expanded','collapsed'].includes(sessionStorage.getItem('tt-admin-sidebar')))); await goto('/data/comics'); check('sidebar preference reload', await page.eval(() => document.querySelector('.tt-admin').dataset.sidebar === sessionStorage.getItem('tt-admin-sidebar')));
  });
  await group('Sidebar destinations and component/login links',async()=>{
    await page.setViewport({width:1440,height:900});await goto('/overview');
    for(const [label,route] of [['Endpoint','/endpoints'],['Request log','/requests'],['Log runtime','/runtime-logs'],['Health','/health'],['Alert','/alerts'],['Preview Komik','/comic-preview'],['Katalog & chapter','/data/comics'],['Genre','/data/genres'],['Source','/data/sources'],['Akun','/data/accounts'],['Helpdesk','/data/helpdesk'],['Audit','/data/audit'],['Data flow','/data-flow'],['ERD explorer','/data-model'],['Overview','/overview']]){await click(label,'aside.tt-sidebar');check('sidebar '+label,await page.eval(target=>location.pathname===target&&!!document.querySelector('h1'),route));}
    await click('Login contoh','body');check('login header link',await page.eval(()=>location.pathname==='/login'));await goto('/overview');await click('Pemeriksaan komponen','body');check('component footer link',await page.eval(()=>location.pathname==='/'));
  });
  report.console = page.consoleErrors;
  fs.writeFileSync(path.join(out, process.env.ADMIN_QA_GROUP?'interactions-targeted.json':'interactions.json'), JSON.stringify(report, null, 2));
  console.log(JSON.stringify({ groups: report.groups.length, checks: report.checks.length, failedGroups: report.failures.length, consoleErrors: report.console.length }));
  assert.equal(report.failures.length, 0, JSON.stringify(report.failures.map(f => ({ name: f.name, message: f.message.split('\n')[0] }))));
  assert.equal(report.console.length, 0);
} finally { await browser.close(); }

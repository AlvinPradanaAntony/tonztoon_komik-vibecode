'use strict';

(() => {
  const $ = (selector, root = document) => root.querySelector(selector);
  const $$ = (selector, root = document) => [...root.querySelectorAll(selector)];
  const nf = new Intl.NumberFormat('id-ID');
  const route = '/api/v1/sources/{source_name}/comics/{slug}/chapters/{chapter_number}';
  const memory = {};
  const store = {
    persistent: true,
    get(key, fallback) { try { return JSON.parse(sessionStorage.getItem(key)) ?? fallback; } catch { this.persistent=false; return memory[key] ?? fallback; } },
    set(key, value) { memory[key] = value; try { sessionStorage.setItem(key, JSON.stringify(value)); this.persistent=true; } catch { this.persistent=false; } },
    clearDemo() {
      const isDemo = key => key.startsWith('tt-draft:') || key.startsWith('tt-feed-') || key === 'tt-preview-run' || key === 'tt-simulation-v1';
      Object.keys(memory).filter(isDemo).forEach(key=>delete memory[key]);
      try { Object.keys(sessionStorage).filter(isDemo).forEach(key=>sessionStorage.removeItem(key)); } catch { this.persistent=false; }
    }
  };
  let model = store.get('tt-prototype-v2', { records: {}, audit: [], role: 'all', revision: 0 });
  if (!model || typeof model !== 'object' || !model.records || !Array.isArray(model.audit)) model = { records: {}, audit: [], role: 'all', revision: 0 };
  const save = () => store.set('tt-prototype-v2', model);
  const params = new URLSearchParams(location.search);
  const pageFile=(location.pathname.split('/').pop()||'index.html').replace(/\.html$/,'');
  let refreshSimulation=()=>{};
  let overviewSimulationRefresh=null;
  let simulationResetting=false;
  const demo=createSimulation();

  function createSimulation(){
    const definitions=[['ep1','GET',route,'Sources'],['ep2','GET','/api/v1/images/proxy','Images'],['ep3','GET','/api/v1/search','Search'],['ep4','GET','/api/v1/sources/{source_name}/comics','Sources'],['ep5','GET','/api/v1/genres','Genres'],['ep6','POST','/api/v1/helpdesk/submissions','Helpdesk'],['ep7','GET','/api/v1/account-manager/accounts','Accounts'],['ep8','POST','/api/v1/auth/login','Auth']].map(([id,method,path,group])=>({id,method,route:path,group}));
    const scenarios={healthy:'Normal / pulih',latency:'Latensi reader tinggi',errors:'HTTP 5xx meningkat',down:'API tidak terjangkau',gap:'Telemetry terputus',burst:'Lonjakan trafik'};
    let state=store.get('tt-simulation-v1',null);
    const valid=state&&state.version===2&&Array.isArray(state.requests)&&Array.isArray(state.runtime)&&Array.isArray(state.probes)&&Array.isArray(state.incidents)&&Array.isArray(state.losses)&&Number.isFinite(state.now);
    if(!valid)state={version:2,id:(globalThis.crypto?.randomUUID?.()||Date.now().toString(36)+Math.random().toString(36).slice(2,8)).slice(0,8),now:Date.now(),sequence:0,running:false,scenario:'healthy',environment:'production',requests:[],runtime:[],probes:[],incidents:[],losses:[],evictions:[],retainedDrops:0,lastReceived:{},lastWall:Date.now()};
    const id=prefix=>'demo-'+prefix+'-'+state.id+'-'+String(++state.sequence).padStart(6,'0');
    const quantile=(values,q)=>{const sorted=values.filter(Number.isFinite).sort((a,b)=>a-b);return sorted.length?sorted[Math.max(0,Math.ceil(sorted.length*q)-1)]:null;};
    state.evictions ||= [];
    function cap(list,max=1000){if(list.length>max){state.retainedDrops+=list.length-max;const removed=list.splice(0,list.length-max);if(list===state.requests){state.evictions.push(...removed.map(r=>({at:r.at,environment:r.environment,scope:r.scope,endpoint:r.endpoint})));state.evictions=state.evictions.slice(-1000);}}}
    function runtime(message,{request='',level='INFO',kind='application',logger='app.demo',environment=state.environment,run='',operation='',at=state.now}={}){
      const event={id:id('runtime'),seq:state.sequence,at,received:state.now,environment,instance:'demo-api-01',message,request,level,kind,logger,run,operation};state.runtime.push(event);cap(state.runtime);return event;
    }
    function request(endpoint,{environment=state.environment,at=state.now,status=200,duration=120,scope='reader',run='',operation='',outcome,statusSource='Skenario browser lokal',path,method,quiet=false,pending=false}={}){
      const definition=definitions.find(d=>d.id===endpoint);
      const event={id:id('req'),seq:state.sequence,observation:'demo-observation-'+state.sequence,endpoint,route:path||definition?.route||'/demo/admin/operation',method:method||definition?.method||'POST',at,environment,instance:'demo-api-01',status,duration,scope,run,operation,pending,outcome:outcome||(Number(status)>=400?'http_error':'completed'),statusSource};
      state.requests.push(event);cap(state.requests);
      if(!quiet&&!pending)runtime(event.method+' '+event.route+' → '+(status??'tanpa HTTP')+' · '+event.outcome,{request:event.id,environment,at,run,operation,level:Number(status)>=500?'ERROR':Number(status)>=400?'WARNING':'INFO',kind:Number(status)>=500?'application':'access',logger:definition?.id==='ep1'?'app.chapter':definition?.id==='ep2'?'app.image':'uvicorn.access'});
      return event;
    }
    function selected(environment,minutes=15,scope,endpoint){const lower=state.now-minutes*60000;return state.requests.filter(r=>r.at>lower&&r.at<=state.now&&(!environment||r.environment===environment)&&(!scope||r.scope===scope)&&(!endpoint||r.endpoint===endpoint)&&!r.pending);}
    function summary(environment,minutes=15,scope,endpoint){
      const rows=selected(environment,minutes,scope,endpoint),statuses={success:0,client:0,server:0,none:0};rows.forEach(r=>{statuses[r.status==null?'none':r.status>=500?'server':r.status>=400?'client':'success']++;});
      const lost=state.losses.filter(e=>e.at>state.now-minutes*60000&&(!environment||e.environment===environment)).reduce((n,e)=>n+e.count,0),evicted=state.evictions.filter(e=>e.at>state.now-minutes*60000&&(!environment||e.environment===environment)&&(!scope||e.scope===scope)&&(!endpoint||e.endpoint===endpoint)).length,coverage=rows.length+lost+evicted?rows.length/(rows.length+lost+evicted):0;
      return {rows,count:rows.length,errors:statuses.server,client:statuses.client,statuses,p50:quantile(rows.map(r=>r.duration),.5),p95:quantile(rows.map(r=>r.duration),.95),p99:quantile(rows.map(r=>r.duration),.99),evicted,rate:rows.length?statuses.server/rows.length:null,rps:rows.length/(minutes*60),coverage,lost,lastSeen:Math.max(0,...rows.map(r=>r.at)),inFlight:state.requests.filter(r=>r.pending&&(!environment||r.environment===environment)).length};
    }
    function buckets(environment,minutes=15,count=15,scope,endpoint){return Array.from({length:count},(_,i)=>{const from=state.now-minutes*60000+i*minutes*60000/count,to=from+minutes*60000/count,rows=selected(environment,minutes,scope,endpoint).filter(r=>r.at>from&&r.at<=to);return{at:from,count:rows.length,errors:rows.filter(r=>r.status>=500).length,client:rows.filter(r=>r.status>=400&&r.status<500).length,p95:quantile(rows.map(r=>r.duration),.95)};});}
    function health(environment,minutes=15){
      const rows=state.probes.filter(p=>p.environment===environment&&p.at>state.now-minutes*60000),known=rows.filter(p=>p.status!=='unknown'),success=known.filter(p=>p.status==='success').length,latest=rows.at(-1),recent=rows.slice(-2);
      return{rows,known:known.length,success,scheduled:minutes*12,availability:known.length?success/known.length:null,coverage:Math.min(1,known.length/(minutes*12)),service:!latest||state.now-latest.at>30000?'unknown':recent.length===2&&recent.every(p=>p.status==='failed')?'down':recent.length===2&&recent.every(p=>p.status==='success')?'up':'unknown',pipeline:state.scenario==='gap'&&state.environment===environment?'down':state.lastReceived[environment]?'up':'unknown'};
    }
    function transition(incident,next,note){if(incident.status===next)return;incident.status=next;incident.updated=state.now;incident.timeline.push({at:state.now,status:next,note});incident.timeline=incident.timeline.slice(-50);runtime('Insiden '+incident.rule+' → '+next,{environment:incident.environment,kind:'pipeline',logger:'collector',level:next==='firing'?'ERROR':next==='unknown'?'WARNING':'INFO'});}
    function evaluateRule(environment,rule,condition,available,value,immediate=false){
      let incident=state.incidents.findLast(i=>i.environment===environment&&i.rule===rule&&i.status!=='resolved');
      if(!available){if(incident)transition(incident,'unknown','Data tidak cukup/stale; tidak dianggap pulih.');return;}
      if(condition){
        if(!incident){incident={id:id('incident'),environment,rule,title:({latency:'Latensi reader melewati ambang batas',errors:'HTTP 5xx reader meningkat',liveness:'API tidak terjangkau',pipeline:'Telemetry terputus'})[rule],status:'pending',since:state.now,updated:state.now,value,timeline:[{at:state.now,status:'pending',note:'Kondisi rule demo terpenuhi.'}]};state.incidents.push(incident);cap(state.incidents,100);}
        incident.value=value;delete incident.clearSince;if(incident.status==='unknown')transition(incident,'pending','Data kembali cukup untuk evaluasi.');
        if(immediate||state.now-incident.since>=60000)transition(incident,'firing',immediate?(rule==='pipeline'?'Ingest tidak diterima selama 30 detik.':'Dua probe gagal berturut-turut.'):'Kondisi bertahan 60 detik jam demo.');
      }else if(incident){incident.clearSince??=state.now;if(immediate||state.now-incident.clearSince>=60000)transition(incident,'resolved',immediate?(rule==='pipeline'?'Ingest kembali berjalan.':'Dua probe sukses berturut-turut.'):'Kondisi sehat selama 60 detik jam demo.');}
    }
    function evaluate(environment){
      const stats=summary(environment,5,'reader'),probe=health(environment,5),gap=state.scenario==='gap'&&environment===state.environment;
      const available=!gap&&!(state.scenario==='down'&&state.environment===environment)&&stats.coverage>=.8&&stats.count>=100;
      evaluateRule(environment,'latency',stats.p95>2000,available,stats.p95==null?'Belum tersedia':stats.p95+' ms');evaluateRule(environment,'errors',stats.rate>.05,available,(100*(stats.rate||0)).toFixed(2)+'%');
      evaluateRule(environment,'pipeline',gap,true,gap?'Tidak ada ingest selama ≥30 detik':'Ingest kembali berjalan',true);
      if(probe.service==='up'||probe.service==='down')evaluateRule(environment,'liveness',probe.service==='down',true,probe.service==='down'?'2+ probe gagal':'2+ probe sukses',true);
    }
    function persist(){if(!simulationResetting)store.set('tt-simulation-v1',state);}
    function publish(){persist();refreshSimulation();}
    function tick(){
      const environment=state.environment,scenario=state.scenario;state.now+=30000;
      if(scenario==='gap'){state.losses.push({at:state.now,environment,count:25});cap(state.losses,1000);}
      else if(scenario!=='down'){
        const count=scenario==='burst'?60:25;
        for(let i=0;i<count;i++){const endpoint=i%10<6?'ep1':i%10<8?'ep2':i%10===8?'ep3':'ep4',failure=scenario==='errors',slow=scenario==='latency';request(endpoint,{environment,at:state.now-29000+i*29000/count,status:failure?(endpoint==='ep2'?504:503):200,duration:slow?2400+(i%7)*180:failure?1500+(i%6)*220:85+(i%9)*23});}
        state.lastReceived[environment]=state.now;
      }else runtime('Probe independen: koneksi API ditolak; proses tidak menghasilkan access log.',{environment,kind:'server',logger:'collector',level:'ERROR'});
      for(let i=0;i<6;i++){state.probes.push({id:id('probe'),at:state.now-25000+i*5000,environment,status:'success',http:200,duration:35+i*3});const p=state.probes.at(-1);if(scenario==='down'){p.status='failed';p.http=null;p.duration=2000;}if(scenario==='gap')p.status='unknown';}
      cap(state.probes,1000);evaluate(environment);state.lastWall=Date.now();
    }
    if(!valid){
      const recent=['ep1','ep1','ep1','ep1','ep1','ep1','ep2','ep2','ep3','ep4'];
      for(let i=0;i<1000;i++){const at=i<400?state.now-86400000+(i+1)*85500000/400:state.now-900000+(i-399)*899000/600;request(i<400?definitions[i%8].id:recent[i%10],{at,status:200,duration:90+(i%17)*19,scope:i<400&&['ep6','ep7','ep8'].includes(definitions[i%8].id)?'admin_operation':'reader'});}
      for(let i=0;i<180;i++)state.probes.push({id:id('probe'),environment:'production',at:state.now-895000+i*5000,status:'success',http:200,duration:40+i%11});
      state.lastReceived.production=state.now;runtime('Sesi demo siap. Event, probe dan metrik memakai sumber yang sama.',{kind:'server',logger:'collector'});persist();
    }
    return {state,definitions,scenarios,summary,buckets,health,selected,quantile,persist,
      scenario(value){if(!scenarios[value])return;state.scenario=value;runtime('Skenario demo dipilih: '+scenarios[value],{kind:'server',logger:'collector'});publish();},
      environment(value){if(!['production','staging'].includes(value))return;state.environment=value;publish();},
      advance(steps=1){for(let i=0;i<Math.max(1,Math.min(10,steps));i++)tick();publish();},
      running(value){state.running=value;state.lastWall=Date.now();publish();},
      catchUp(){if(!state.running)return;const elapsed=Math.floor((Date.now()-state.lastWall)/2000);if(!elapsed)return;const count=Math.min(elapsed,10);for(let i=0;i<count;i++)tick();if(elapsed>10)runtime('Demo dilanjutkan setelah tab tidak aktif; catch-up dibatasi 10 tick.',{kind:'pipeline',logger:'collector',level:'WARNING'});publish();},
      once(){if(['gap','down'].includes(state.scenario)){this.advance();return null;}state.now+=1000;const failure=state.scenario==='errors',r=request('ep1',{status:failure?503:200,duration:state.scenario==='latency'?2800:failure?1800:180});state.lastReceived[state.environment]=state.now;evaluate(state.environment);publish();return r;},
      lifecycle(){state.now+=1000;const r=runtime('Application lifecycle demo: event proses tanpa request ID.',{kind:'server',logger:'uvicorn.error'});publish();return r;},
      probe(){state.now+=5000;const failed=state.scenario==='down';state.probes.push({id:id('probe'),at:state.now,environment:state.environment,status:state.scenario==='gap'?'unknown':failed?'failed':'success',http:state.scenario==='gap'||failed?null:200,duration:failed?2000:42});cap(state.probes);runtime('Probe liveness demo '+(state.scenario==='gap'?'unknown':failed?'gagal':'sukses'),{kind:'pipeline',logger:'collector',level:failed?'ERROR':'INFO'});evaluate(state.environment);publish();},
      admin(kind,resource,action,status=200){state.now+=1000;const operation=id('operation');const r=request(null,{path:'/demo/admin/'+kind+'/{id}',method:action==='create'?'POST':action==='archive'||action==='ban'?'PATCH':'PUT',status,duration:120,scope:'admin_operation',operation});publish();return r;},
      preview(path,endpoint,run,extra={}){state.now+=200;const r=request(endpoint,{path,run,scope:'admin_preview',duration:80,...extra});publish();return r;},
      imageStart(run){const r=request('ep2',{run,scope:'admin_preview',status:null,duration:null,pending:true,outcome:'in_flight',statusSource:'Attempt gambar placeholder lokal'});persist();return r.id;},
      imageFinish(requestId,status,duration,outcome){const r=state.requests.find(r=>r.id===requestId);if(!r||!r.pending)return;r.pending=false;r.status=status;r.duration=Math.round(duration);r.outcome=outcome;runtime('Gambar placeholder lokal: '+outcome,{request:r.id,run:r.run,environment:r.environment,logger:'app.image',level:outcome==='completed'?'INFO':outcome==='cancelled'?'WARNING':'ERROR'});publish();}
    };
  }
  const roleCaps = {
    all: ['monitoring','logs','preview','catalog','accounts','helpdesk','audit','library','urls'],
    viewer: ['monitoring'], catalog: ['monitoring','catalog'],
    helpdesk: ['monitoring','helpdesk'], accounts: ['accounts'], auditor: ['audit']
  };
  const permitted = cap => !cap || cap === 'public' || (roleCaps[model.role] || roleCaps.all).includes(cap);
  function linkCapability(href) {
    const file = new URL(href,location.href).pathname.split('/').pop();
    if (/^runtime-/.test(file)) return 'logs';
    if (file === 'account-library.html') return 'library';
    if (/^account/.test(file)) return 'accounts';
    if (/^helpdesk/.test(file)) return 'helpdesk';
    if (/^audit/.test(file)) return 'audit';
    if (/^(comic-preview|preview-)/.test(file)) return 'preview';
    if (/^(comic|chapter|genre|source|data-model)/.test(file)) return 'catalog';
    return file === 'login.html' ? 'public' : 'monitoring';
  }
  const tones = { neutral: 'status neutral', success: 'status success', warning: 'status warning', danger: 'status danger' };
  let toastTimer;
  function notify(message) {
    const toast = $('#toast');
    if (!toast) return;
    toast.textContent = message; toast.hidden = false;
    const announcer = $('[data-announcer]'); if (announcer) announcer.textContent = message;
    clearTimeout(toastTimer); toastTimer = setTimeout(() => { toast.hidden = true; }, 5500);
  }
  function setParam(name, value) {
    const url = new URL(location.href);
    value ? url.searchParams.set(name, value) : url.searchParams.delete(name);
    value ? params.set(name, String(value)) : params.delete(name);
    try { history.replaceState(null, '', url); } catch { /* file previews still work. */ }
  }
  function text(selector, value, root = document) { $$(selector, root).forEach(el => { el.textContent = value; }); }
  function linksTo(file, root = $('main') || document) { return $$('a[href]',root).filter(link=>new URL(link.href,location.href).pathname.split('/').pop()===file); }
  function dd(root, label, value) { const term = $$('dt', root).find(el => el.textContent.trim() === label); if (term?.nextElementSibling) term.nextElementSibling.textContent = value; }
  const record = (kind, id) => model.records[kind + ':' + id] || {};
  function genreName(name){return name?(Object.entries(model.records).find(([key,value])=>key.startsWith('genre:')&&value._originalName===name)?.[1].name||name):name;}
  const formDefaults=new WeakMap($$('form[data-editor]').map(form=>[form,Object.fromEntries([...form.elements].filter(input=>input.name).map(input=>[input.name,input.value]))]));
  const modalOpeners = new WeakMap();
  function openDialog(dialog) {
    if (!dialog || dialog.open) return;
    modalOpeners.set(dialog, document.activeElement);
    dialog.showModal();
    updateOverlayInertness();
  }
  function closeDialog(dialog) {
    if (dialog?.open) {
      dialog.close();
      updateOverlayInertness();
    }
  }
  $$('dialog').forEach(dialog => {
    dialog.addEventListener('close', () => {
      const opener = modalOpeners.get(dialog);
      if (opener?.isConnected && opener.getClientRects().length) opener.focus();
      updateOverlayInertness();
    });
    dialog.addEventListener('cancel', () => {
      updateOverlayInertness();
    });
  });
  async function copy(value) {
    try {
      if (!navigator.clipboard) throw new Error('clipboard unavailable');
      await navigator.clipboard.writeText(value); notify('Teks yang terlihat berhasil disalin.');
    } catch {
      let dialog = $('#copy-dialog');
      if (!dialog) {
        dialog = document.createElement('dialog'); dialog.id = 'copy-dialog'; dialog.className = 'app-modal';
        dialog.setAttribute('aria-labelledby', 'copy-dialog-title');
        const h = document.createElement('h2'); h.id = 'copy-dialog-title'; h.textContent = 'Salin teks secara manual';
        const label = document.createElement('label'); label.className = 'field';
        const caption = document.createElement('span'); caption.textContent = 'Teks tersanitasi';
        const area = document.createElement('textarea'); area.readOnly = true; area.rows = 8;
        const close = document.createElement('button'); close.type = 'button'; close.className = 'button mt-4'; close.textContent = 'Tutup';
        close.addEventListener('click', () => dialog.close());
        dialog.addEventListener('close', () => {
          const opener = modalOpeners.get(dialog);
          if (opener?.isConnected && opener.getClientRects().length) opener.focus();
          updateOverlayInertness();
        });
        dialog.addEventListener('cancel', () => {
          updateOverlayInertness();
        });
        label.append(caption, area); dialog.append(h, label, close); document.body.append(dialog);
      }
      $('textarea', dialog).value = value; openDialog(dialog); $('textarea', dialog).focus(); $('textarea', dialog).select();
    }
  }

  // Native controls remain usable; these handlers add cross-page prototype behavior.
  const sidebarInput = $('#sidebar-collapse'), themeInput = $('#theme-toggle');
  const wideSidebar = matchMedia('(min-width: 1280px)');
  let sidebarMode = store.get('tt-prototype-sidebar',null);
  function sidebarPreference() {
    if (!sidebarInput) return;
    sidebarInput.checked = sidebarMode ? (wideSidebar.matches ? sidebarMode==='collapsed' : sidebarMode==='expanded') : false;
  }
  sidebarPreference();
  sidebarInput?.addEventListener('change',()=>{
    sidebarMode = wideSidebar.matches ? (sidebarInput.checked?'collapsed':'expanded') : (sidebarInput.checked?'expanded':'collapsed');
    store.set('tt-prototype-sidebar',sidebarMode);
  });
  wideSidebar.addEventListener('change',sidebarPreference);
  const systemTheme = matchMedia('(prefers-color-scheme: dark)');
  function applyThemePreference() {
    const flipped = themeInput ? themeInput.checked : store.get('tt-prototype-theme-flipped', false) === true;
    document.documentElement.dataset.theme = systemTheme.matches !== flipped ? 'dark' : 'light';
  }
  if (themeInput) {
    themeInput.checked = store.get('tt-prototype-theme-flipped', false) === true;
    applyThemePreference();
    themeInput.addEventListener('change', () => { store.set('tt-prototype-theme-flipped', themeInput.checked); applyThemePreference(); });
  }
  systemTheme.addEventListener('change', applyThemePreference);
  const drawer = $('#mobile-navigation');
  const desktop = matchMedia('(min-width: 1024px)');
  const tooltip=document.createElement('div');tooltip.id='navigation-tooltip';tooltip.className='nav-tooltip';tooltip.setAttribute('role','tooltip');tooltip.setAttribute('popover','manual');document.body.append(tooltip);
  let tooltipTarget=null;
  function hideTooltip(){if(tooltip.matches(':popover-open'))tooltip.hidePopover();tooltipTarget?.removeAttribute('aria-describedby');tooltipTarget=null;}
  function showTooltip(link){
    if(!desktop.matches||$('.sidebar')?.getBoundingClientRect().width>100)return;
    hideTooltip();tooltipTarget=link;tooltip.textContent=link.getAttribute('aria-label')||link.textContent.trim();tooltip.showPopover();
    const rect=link.getBoundingClientRect(),edge=$('.sidebar').getBoundingClientRect().right;
    tooltip.style.left=Math.min(edge+12,innerWidth-tooltip.offsetWidth-12)+'px';tooltip.style.top=Math.max(8,Math.min(rect.top,innerHeight-tooltip.offsetHeight-8))+'px';link.setAttribute('aria-describedby',tooltip.id);
  }
  document.addEventListener('pointerover',event=>{const link=event.target.closest('.sidebar .nav-item');if(link&&!link.contains(event.relatedTarget))showTooltip(link);});
  document.addEventListener('pointerout',event=>{const link=event.target.closest('.sidebar .nav-item');if(link&&!link.contains(event.relatedTarget))hideTooltip();});
  document.addEventListener('focusin',event=>{const link=event.target.closest('.sidebar .nav-item');if(link)showTooltip(link);else hideTooltip();});
  document.addEventListener('keydown',event=>{if(event.key==='Escape')hideTooltip();});
  document.addEventListener('scroll',hideTooltip,true);window.addEventListener('resize',hideTooltip);
  let sidebarHadFocus = false;
  document.addEventListener('focusin', event => { sidebarHadFocus = !!event.target.closest('.sidebar'); });
  document.addEventListener('pointerdown', event => { if (!event.target.closest('.sidebar')) sidebarHadFocus = false; });
  desktop.addEventListener('change', () => {
    const wasOpen = drawer?.matches(':popover-open');
    if (wasOpen) drawer.hidePopover();
    if (desktop.matches && wasOpen) sidebarInput?.focus();
    else if (!desktop.matches && sidebarHadFocus) $('[popovertarget="mobile-navigation"]')?.focus();
  });
  drawer?.addEventListener('click', event => { if (event.target.closest('a[href]')) drawer.hidePopover(); });
  drawer?.addEventListener('toggle', () => {
    if (drawer.matches(':popover-open')) requestAnimationFrame(() => $$('#mobile-navigation [data-simplebar]').forEach(host => window.SimpleBar?.instances.get(host)?.recalculate()));
  });

  function updateOverlayInertness(event) {
    const hasOpenDialog = $$('dialog').some(d => d.open);
    let hasOpenDrawer = drawer ? drawer.matches(':popover-open') : false;
    if (event?.target === drawer && event.newState) {
      hasOpenDrawer = event.newState === 'open';
    }
    let hasOpenPopover = $$('.prototype-dialog').some(p => p.matches(':popover-open'));
    if (event?.target?.classList?.contains('prototype-dialog') && event.newState) {
      hasOpenPopover = event.newState === 'open' || $$('.prototype-dialog').some(p => p !== event.target && p.matches(':popover-open'));
    }
    const isOverlayOpen = hasOpenDialog || hasOpenDrawer || hasOpenPopover;

    const shell = $('.shell');
    const sidebar = $('.sidebar');
    if (shell) shell.inert = isOverlayOpen;
    if (sidebar && !desktop.matches) sidebar.inert = isOverlayOpen;
  }

  let activeOverlayBackdropTarget = null;
  document.addEventListener('pointerdown', event => {
    const target = event.target;
    if (target instanceof HTMLElement) {
      const isDialog = target.tagName === 'DIALOG' && target.open;
      const isDrawerOrPopover = (target.id === 'mobile-navigation' || target.classList.contains('prototype-dialog')) && target.matches(':popover-open');
      if (isDialog || isDrawerOrPopover) {
        const rect = target.getBoundingClientRect();
        const isOutside = (
          event.clientX < rect.left ||
          event.clientX > rect.right ||
          event.clientY < rect.top ||
          event.clientY > rect.bottom
        );
        if (isOutside) {
          activeOverlayBackdropTarget = target;
          return;
        }
      }
    }
    activeOverlayBackdropTarget = null;
  });

  document.addEventListener('click', event => {
    if (activeOverlayBackdropTarget && event.target === activeOverlayBackdropTarget) {
      const target = activeOverlayBackdropTarget;
      const rect = target.getBoundingClientRect();
      const isOutside = (
        event.clientX < rect.left ||
        event.clientX > rect.right ||
        event.clientY < rect.top ||
        event.clientY > rect.bottom
      );
      if (isOutside) {
        if (target.tagName === 'DIALOG' && target.open) {
          closeDialog(target);
        } else if (typeof target.hidePopover === 'function' && target.matches(':popover-open')) {
          target.hidePopover();
        }
      }
    }
    activeOverlayBackdropTarget = null;
  });

  document.addEventListener('beforetoggle', event => {
    if (event.target.id === 'navigation-tooltip') return;
    updateOverlayInertness(event);
  }, true);
  document.addEventListener('toggle', event => {
    if (event.target.id === 'navigation-tooltip') return;
    updateOverlayInertness(event);
  }, true);
  document.addEventListener('close', () => updateOverlayInertness(), true);
  document.addEventListener('cancel', () => updateOverlayInertness(), true);

  let chosenState = 'normal';
  const originalStatuses = new WeakMap();
  const scopedMonitoringPages=['health','alerts','alert-detail','request-detail','runtime-log-detail'];
  const scopedEmpty=()=>params.get('environment')==='staging'&&scopedMonitoringPages.includes(pageFile)&&![...demo.state.requests,...demo.state.probes,...demo.state.runtime].some(event=>event.environment==='staging');
  function stateView(value) {
    chosenState = value;
    const allowed = permitted(document.body.dataset.capability);
    const actual = allowed ? (value==='normal'&&scopedEmpty()?'empty':value) : 'denied';
    const messages = {
      loading: ['Memuat contoh', 'Snapshot contoh sedang dipersiapkan.'],
      empty: ['Belum ada data', 'Belum ada observasi atau resource untuk konteks contoh ini.'],
      error: ['Gagal memuat contoh', 'Simulasi timeout. Data backend tidak dihubungi.'],
      stale: ['Snapshot stale', 'Waktu observasi historis. Kondisi layanan saat ini tidak diketahui.'],
      denied: ['Akses tidak diizinkan', 'Profil izin contoh tidak memberikan akses ke modul ini. Ubah profil di Opsi pratinjau.'],
      partial: ['Cakupan parsial', 'Sebagian data belum tersedia. Nilai yang tidak diukur tidak dianggap nol.']
    };
    const panel = $('[data-state-panel]'), content = $('[data-page-content]');
    if (!panel || !content) return;
    panel.hidden = actual === 'normal';
    if (messages[actual]) {
      text('[data-state-title]', messages[actual][0]); text('[data-state-text]', messages[actual][1]);
      panel.classList.toggle('warning', ['stale','partial'].includes(actual));
    }
    const inventoryError = actual==='error' && pageFile==='endpoints';
    content.hidden = ['loading','empty','error','denied'].includes(actual) && !inventoryError;
    if(inventoryError)text('[data-state-text]','Simulasi gagal memuat OpenAPI. Inventaris contoh terakhir tetap ditampilkan sebagai snapshot historis.');
    $('[data-recover-state]').disabled = !allowed;
    $('[data-recover-state]').textContent=scopedEmpty()?'Lihat data contoh Production':'Kembali ke data contoh';
    if(actual==='empty'&&scopedEmpty())text('[data-state-text]','Belum ada data contoh Staging untuk modul ini. Data Production tidak ditampilkan sebagai hasil Staging.');
    const stale = (['stale','partial'].includes(actual)||inventoryError) && ['index','health','endpoints','alerts','requests','runtime-logs'].includes(document.body.dataset.page);
    $$('.status.success', content).forEach(el => { if (!originalStatuses.has(el)) originalStatuses.set(el, { text: el.textContent, cls: el.className }); });
    $$('.status', content).forEach(el => {
      const prior = originalStatuses.get(el);
      if (!prior) return;
      el.className = stale ? tones.neutral : prior.cls;
      el.textContent = stale ? 'Snapshot; status kini unknown' : prior.text;
    });
  }
  function applyRole() {
    $$('[data-cap]').forEach(el => { el.hidden = !permitted(el.dataset.cap); });
    $$('a[href]').forEach(link => {
      if (link.getAttribute('href').startsWith('#')) return;
      if (link.classList.contains('brand')) {
        link.href = model.role==='accounts'?'accounts.html':model.role==='auditor'?'audit.html':'index.html';
        link.hidden = false; link.setAttribute('aria-label','TonzToon Admin, beranda profil contoh'); return;
      }
      if (!permitted(linkCapability(link.href))) {
        if (!link.hidden) link.dataset.permissionHidden = 'true';
        link.hidden = true;
      } else if (link.dataset.permissionHidden === 'true') {
        link.hidden = false; delete link.dataset.permissionHidden;
      }
    });
    $$('.nav-heading').forEach(heading=>{let item=heading.nextElementSibling,visible=false;while(item&&!item.classList.contains('nav-heading')){if(item.classList.contains('nav-item')&&!item.hidden)visible=true;item=item.nextElementSibling;}heading.hidden=!visible;});
    $$('[data-role-control]').forEach(el => { el.value = model.role; });
    text('[data-role-label]', ({ all: 'Semua modul', viewer: 'Viewer monitoring', catalog: 'Operator katalog', helpdesk: 'Operator helpdesk', accounts: 'Admin akun', auditor: 'Auditor' })[model.role] || 'Semua modul');
    stateView(chosenState);
  }
  $$('[data-state-control]').forEach(control => control.addEventListener('change', () => stateView(control.value)));
  $$('[data-role-control]').forEach(control => control.addEventListener('change', () => { model.role = control.value; save(); applyRole(); }));
  $('[data-recover-state]')?.addEventListener('click', () => { if(scopedEmpty()){params.set('environment','production');setParam('environment','production');renderMonitoringContext();}text('[data-announcer]', 'Data contoh dipulihkan.'); const control = $('[data-state-control]'); if (control) control.value = 'normal'; stateView('normal'); });

  function activity(kind, id, action, diff = []) {
    const observation=demo.admin(kind,id,action);
    const entry = { id: 'demo-audit-' + (++model.revision), resource: kind + ':' + id, action, result: 'simulated', at: new Date(demo.state.now).toISOString(),requestId:observation.id,operation:observation.operation,diff: diff.filter(item => !['email','password','admin_note','identifier'].includes(item.field)) };
    model.audit.unshift(entry); model.audit = model.audit.slice(0, 100); save(); return entry;
  }
  function bindSaved() {
    $$('[data-bind]').forEach(el => {
      const [kind,id,key] = el.dataset.bind.split(':'); const value = record(kind,id)[key];
      if (value !== undefined) el.textContent = value;
    });
    $$('[data-record][data-kind]').forEach(row => {
      const data = record(row.dataset.kind, row.dataset.id);
      if (data.status) {
        row.dataset.status = data.status;
        const badge = $('.status', row); if (badge) { badge.textContent = data.status; badge.className = data.status === 'banned' ? tones.danger : data.status === 'archived' ? tones.neutral : tones.success; }
      }
      const title = data.title || data.name || data.display_name;
      if (title) { row.dataset.name = title; row.dataset.search = (row.dataset.search || '') + ' ' + title; }
      if (row.dataset.kind === 'account' && data.username) {
        const link = $('td:first-child a', row); if (link) link.textContent = data.username;
        row.dataset.search = (row.dataset.search || '') + ' ' + data.username;
      }
      if(row.dataset.kind==='comic'&&row.children[3]){row.dataset.baseGenre ||= row.dataset.genre||row.children[3].textContent;const genre=genreName(data.genre||row.dataset.baseGenre);row.dataset.genre=genre;row.children[3].textContent=genre;}
      if(row.dataset.kind==='genre'&&data.name){row.children[0].textContent=data.name;const edit=$('[data-edit-genre]',row);if(edit)edit.dataset.name=data.name;const link=$('a[href*="comics.html"]',row);if(link){const url=new URL(link.href);url.searchParams.set('genre',data.name);url.searchParams.delete('id');link.href=url;}}
    });
    $$('select[name="genre"]').forEach(select=>{[...select.options].forEach(option=>{option.dataset.originalGenre ||= option.value;const value=genreName(option.dataset.originalGenre);if(value){option.value=value;option.textContent=value;}});Object.entries(model.records).filter(([key,value])=>key.startsWith('genre:')&&value.name).forEach(([,value])=>{if(![...select.options].some(option=>option.value===value.name)){const option=document.createElement('option');option.value=value.name;option.textContent=value.name;select.append(option);}});});
    text('[data-local-activity]', '');
    $$('[data-local-activity]').forEach(list => {
      const entries = model.audit;
      if (!entries.length) { const li = document.createElement('li'); li.textContent = 'Belum ada perubahan pada sesi ini.'; list.append(li); }
      entries.forEach(entry => { const li = document.createElement('li'); li.textContent = entry.resource + ' · ' + entry.action + ' · simulasi lokal'; list.append(li); });
    });
  }

  const controllers = [];
  function initLists() {
    $$('[data-list]').forEach(root => {
      const form = $('[data-filters]', root), parent = $('[data-rows]', root);
      if (!form || !parent) return;
      let page = Math.max(1, Number(params.get('page')) || 1), timer;
      let rows = $$('[data-record]', parent);
      rows.forEach((row,index) => {
        row.dataset.initialIndex=String(index);
        row.dataset.environment ||= 'production'; row.dataset.instance ||= 'demo-api-01';
        const match = row.firstElementChild?.textContent.match(/(\d{2}):(\d{2})(?::(\d{2}))?/);
        row.dataset.timestamp ||= match ? String(Date.parse('2026-10-24T'+match[1]+':'+match[2]+':'+(match[3]||'00')+'+07:00')) : '';
        if(root.dataset.list==='audit'){row.dataset.actor=row.children[1].textContent.trim();row.dataset.request=row.lastElementChild.textContent.trim();}
        if(root.dataset.list==='endpoints'){
          row.dataset.baseCount=row.dataset.count;row.dataset.baseErrors=row.dataset.errors;row.dataset.baseP95=row.dataset.p95;
          row.dataset.lastSeen=Number(row.dataset.count)>0?String(100-index):'-1';
          const badge=$('.status',row);if(badge){row.dataset.baseBadge=badge.textContent;row.dataset.baseTone=badge.className;}
        }
      });
      const size = $('[data-page-size]', root);
      $$('input[name],select[name]', form).forEach(input => {
        const value = params.get(input.name);
        if (value !== null && (input.tagName !== 'SELECT' || [...input.options].some(option => option.value === value))) input.value = value.slice(0,200);
      });
      const initialSize = params.get('size');
      if (size && [...size.options].some(option => option.value === initialSize)) size.value = initialSize;
      function update(sync = true) {
        rows = $$('[data-record]', parent);
        rows.forEach((row,index)=>{row.dataset.initialIndex ||= String(index);});
        const fields = [...new FormData(form).entries()];
        if(root.dataset.list==='endpoints'){
          const values=Object.fromEntries(fields),environment=values.environment||'',minutes=Number(values.range||15);
          rows.forEach(row=>{
            const stats=demo.summary(environment,minutes,null,row.dataset.id),count=stats.count,errors=stats.errors,cells=$$('td',row),stale=simulationStale(environment);
            row.dataset.environment=environment;row.dataset.count=String(count);row.dataset.errors=String(errors);row.dataset.rate=stats.rate==null?'-1':String(stats.rate);row.dataset.p95=stats.p95==null?'-1':String(stats.p95);row.dataset.lastSeen=String(stats.lastSeen);row.dataset.httpClasses=[stats.statuses.success?'2xx':'',stats.statuses.client?'4xx':'',stats.statuses.server?'5xx':''].join(' ');
            cells[2].textContent=nf.format(count);cells[3].textContent=count?nf.format(errors)+' respons':'Belum tersedia';cells[4].textContent=stats.p95==null?'Belum tersedia':nf.format(stats.p95)+' ms';
            const badge=$('.status',row);if(badge){originalStatuses.delete(badge);badge.textContent=stale?'Snapshot; status unknown':!count?'Belum ada trafik':errors?'Ada 5xx':stats.p95>2000?'Latensi tinggi':'Dalam ambang';badge.className=stale||!count?tones.neutral:errors?tones.danger:stats.p95>2000?tones.warning:tones.success;}
          });
        }
        const query = String(new FormData(form).get('q') || '').trim().toLocaleLowerCase('id-ID');
        let filtered = rows.filter(row => row.dataset.excluded !== 'true' && fields.every(([key,value]) => {
          value = String(value).trim();
          if (!value || key === 'sort' || key === 'range') return true;
          if (key === 'q') return (row.dataset.search || row.textContent).toLocaleLowerCase('id-ID').includes(query);
          if (key === 'minDuration') return Number(row.dataset.duration || 0) >= Math.max(0, Number(value) || 0);
          if (key === 'httpClass') return (row.dataset.httpClasses||'').split(' ').includes(value);
          if (key === 'from' || key === 'to') { const edge=Date.parse(value+'+07:00'),observed=Number(row.dataset.timestamp);return !Number.isFinite(edge)||!observed||(key==='from'?observed>=edge:observed<=edge); }
          return String(row.dataset[key] || '') === value;
        }));
        const sort = form.elements.sort?.value;
        const feed = root.dataset.list === 'preview';
        const feedMode = $('[data-preview-feed][aria-pressed=true]')?.dataset.previewFeed || 'latest';
        filtered.sort((a,b) => {
          if (feed) return Number(a.dataset[feedMode === 'latest' ? 'rankLatest' : 'rankPopular']) - Number(b.dataset[feedMode === 'latest' ? 'rankLatest' : 'rankPopular']);
          if (sort === 'name') return (a.dataset.name || '').localeCompare(b.dataset.name || '', 'id');
          if (['count','p95','errors','rate','lastSeen'].includes(sort)) return Number(b.dataset[sort] || 0) - Number(a.dataset[sort] || 0);
          return Number(a.dataset.initialIndex) - Number(b.dataset.initialIndex);
        });
        const limit = Number(size?.value || 50), totalPages = Math.max(1, Math.ceil(filtered.length / limit));
        page = Math.min(page,totalPages);
        rows.forEach(row => { row.hidden = true; });
        filtered.forEach((row,index) => { parent.append(row); row.hidden = !(index >= (page-1)*limit && index < page*limit); });
        $('[data-list-empty]', root).hidden = filtered.length > 0;
        text('[data-list-count]', filtered.length ? ((page-1)*limit+1) + '–' + Math.min(page*limit,filtered.length) + ' dari ' + filtered.length + ' contoh' : '0 hasil contoh', root);
        text('[data-page-number]', page + ' / ' + totalPages, root);
        $('[data-page-prev]', root).disabled = page === 1;
        $('[data-page-next]', root).disabled = page === totalPages;
        if (sync) {
          fields.forEach(([name,value]) => setParam(name, value)); setParam('page', String(page)); setParam('size', String(limit));
        }
        if(chosenState!=='normal')stateView(chosenState);
      }
      function reset() { clearTimeout(timer); form.reset(); page = 1; update(); }
      form.addEventListener('submit', event => { event.preventDefault(); clearTimeout(timer); page = 1; update(); });
      form.addEventListener('keydown', event => { if(event.key==='Enter'&&event.target.matches('input')){event.preventDefault();clearTimeout(timer);page=1;update();} });
      form.addEventListener('input', () => { clearTimeout(timer); timer = setTimeout(() => { page = 1; update(); }, 300); });
      form.addEventListener('change', event => { if (event.target.tagName !== 'SELECT') return; clearTimeout(timer); page = 1; update(); });
      $$('[data-reset-filters]', root).forEach(button => button.addEventListener('click', event => { event.preventDefault(); reset(); }));
      size?.addEventListener('change', () => { page = 1; update(); });
      $('[data-page-prev]', root).addEventListener('click', () => { page--; update(); });
      $('[data-page-next]', root).addEventListener('click', () => { page++; update(); });
      const controller = { root, refresh: update, reset }; controllers.push(controller); update(false);
    });
  }

  function changeTabs(id, root = document) {
    $$('[data-tab]',root).forEach(button => button.setAttribute('aria-pressed', String(button.dataset.tab === id)));
    $$('[data-tab-panel]',root).forEach(panel => { panel.hidden = panel.dataset.tabPanel !== id; });
    requestAnimationFrame(() => window.dispatchEvent(new Event('prototype-layout')));
  }
  $$('[data-tab]').forEach(button => button.addEventListener('click', () => changeTabs(button.dataset.tab)));

  // Record selectors keep direct links and the visible HTML fixture in agreement.
  let selectedComic = params.get('id') || 'c1', selectedAccount = params.get('id') || 'u1';
  function pickerValue(picker) {
    if (!picker) return null;
    const id = params.get('id');
    if (id && [...picker.options].some(option => option.value === id)) picker.value = id;
    else if (id && !params.has('mode')) { stateView('empty'); notify('Resource contoh tidak ditemukan.'); }
    return picker.selectedOptions[0];
  }
  function comicSelected() {
    const picker = $('[data-record-picker]'); if (!picker) return;
    const option = picker.selectedOptions[0]; selectedComic = option.value;
    const data = { ...option.dataset, ...record('comic',selectedComic) };data.genre=genreName(data.genre);
    text('[data-record-field="title"]',data.title); text('[data-record-field="source"]',data.source);
    text('[data-record-field="slug"]',data.slug); text('[data-record-field="status"]',data.status); text('[data-record-field="genre"]',data.genre);
    text('[data-record-revision]',record('comic',selectedComic)._revision || 1);
    const count = (data._created ? 0 : 8) + Object.entries(model.records).filter(([key,value])=>key.startsWith('chapter:'+selectedComic+'/') && value._created).length;
    $$('.panel').forEach(panel=>dd(panel,'Total chapter',count+' metadata contoh lokal'));
    const sourceTitle = option.dataset.title;
    text('[data-source-title]',sourceTitle);
    text('[data-override-title]',data.title === sourceTitle ? 'Belum ada override' : data.title);
    $$('[data-kind-link]').forEach(link => { link.href = link.dataset.kindLink + '?id=' + encodeURIComponent(selectedComic); });
    $$('[data-reader-link]').forEach(link => { const url = new URL(link.href); url.searchParams.set('id',selectedComic); link.href = url; });
    $$('a[href]').filter(link=>['comic-detail.html','comic-edit.html','chapters.html','chapter-detail.html','chapter-edit.html','preview-detail.html','preview-reader.html'].includes(new URL(link.href).pathname.split('/').pop())).forEach(link=>{const url=new URL(link.href);url.searchParams.set('id',selectedComic);link.href=url;});
    const form = $('form[data-editor="comic"]');
    if (form && params.get('mode') !== 'create') { form.dataset.key = selectedComic; const fields={...formDefaults.get(form),...data};['title','slug','source','status','genre','alternative_titles','author','artist','type','cover_url','synopsis','simulate'].forEach(name => { if (form.elements[name]) form.elements[name].value = fields[name] || ''; }); }
    const chapterForm = $('form[data-editor="chapter"]');
    if (chapterForm?.elements.comic_id) chapterForm.elements.comic_id.value = selectedComic;
  }
  function accountSelected() {
    const picker = $('[data-account-picker]'); if (!picker) return;
    const option = picker.selectedOptions[0]; selectedAccount = option.value;
    const data = { id: option.value, username: option.dataset.username, display_name: option.dataset.displayName, email: option.dataset.email, status: option.dataset.status, ...record('account',selectedAccount) };
    Object.entries(data).forEach(([key,value]) => text('[data-account-field="'+key+'"]', value ?? 'Belum tersedia'));
    $$('[data-account-link]').forEach(link => { link.href = link.dataset.accountLink + '?id=' + selectedAccount; });
    const form = $('form[data-editor="account"]');
    if (form && params.get('mode') !== 'create') { form.dataset.key = selectedAccount; ['username','display_name','status','user_id'].forEach(name => { if (form.elements[name]) form.elements[name].value = name === 'user_id' ? selectedAccount : data[name]; }); }
  }
  const comicPicker = $('[data-record-picker]'), accountPicker = $('[data-account-picker]');
  hydrateCreated(); pickerValue(comicPicker); pickerValue(accountPicker); comicSelected(); accountSelected();
  comicPicker?.addEventListener('change', () => { setParam('id',comicPicker.value); comicSelected(); chapterContext(); initEditorBaselines(); });
  accountPicker?.addEventListener('change', () => { setParam('id',accountPicker.value); accountSelected(); initEditorBaselines(); });

  const baseChapterNumbers = ['1','2','3','10','11','12','12.5','13'];
  let chapterNumbers=[],chapter='12.5';
  function chapterContext() {
    chapterNumbers=[...new Set([...(record('comic',selectedComic)._created?[]:baseChapterNumbers),...Object.entries(model.records).filter(([key,value])=>key.startsWith('chapter:'+selectedComic+'/')&&value._created).map(([,value])=>String(value.chapter_number))])].sort((a,b)=>Number(a)-Number(b));
    const requested=new URLSearchParams(location.search).get('chapter');
    chapter=chapterNumbers.includes(requested)?requested:chapterNumbers.includes('12.5')?'12.5':chapterNumbers[0]||'';
    text('[data-chapter-number]',chapter||'Belum ada chapter');
    const saved=record('chapter',selectedComic+'/chapter-'+chapter),form=$('form[data-editor="chapter"]');
    if(form&&form.dataset.mode!=='create'&&params.get('mode')!=='create'){
      form.dataset.key=selectedComic+'/chapter-'+chapter;
      Object.entries({comic_id:selectedComic,chapter_number:chapter,title:'Chapter '+chapter,release_date:'2026-10-24',source_url:'https://example.test/chapter-'+chapter.replace('.','-'),...saved}).forEach(([key,value])=>{if(form.elements[key])form.elements[key].value=value;});
    }
    const panel=$$('h2').find(h=>h.textContent==='Identitas chapter')?.closest('.panel');
    if(panel){dd(panel,'comic_id',selectedComic+' (contoh)');dd(panel,'Source URL tetap',saved.source_url||'https://example.test/chapter-'+chapter.replace('.','-'));const parentArchived=(record('comic',selectedComic).status||comicPicker?.selectedOptions[0]?.dataset.status)==='archived',status=parentArchived?'archived (komik diarsipkan)':saved.status||(chapter==='3'?'archived':'active');let term=$$('dt',panel).find(el=>el.textContent==='Status chapter');if(!term){const dt=document.createElement('dt');dt.textContent='Status chapter';const value=document.createElement('dd');$('.key-values',panel).append(dt,value);}dd(panel,'Status chapter',status);}
  }
  chapterContext();
  const chapterForm = $('form[data-editor="chapter"]');
  if (chapterForm) { chapterForm.dataset.key = selectedComic+'/chapter-'+chapter; chapterForm.elements.chapter_number.value = chapter; chapterForm.elements.title.value = 'Chapter '+chapter; }
  $$('[data-chapter-link]').forEach(link => { const url = new URL(link.href); url.searchParams.set('chapter',params.get('chapter') || '13'); if (params.has('id')) url.searchParams.set('id',params.get('id')); link.href = url; });
  const ticketPicker = $('[data-ticket-picker]');
  function ticketSelected() {
    const option = ticketPicker?.selectedOptions[0]; if (!option) return;
    const saved = record('helpdesk',option.value);
    text('[data-ticket-field="id"]',option.value); text('[data-ticket-field="title"]',option.dataset.title); text('[data-ticket-field="type"]',option.dataset.type);
    const form = $('form[data-editor="helpdesk"]'); if (form) { form.dataset.key = option.value; form.elements.status.value = saved.status || option.dataset.status; form.elements.admin_note.value = saved.admin_note || ''; }
    const panel=ticketPicker.closest('.panel');dd(panel,'Pesan','Contoh '+option.value+': '+option.dataset.title+'. Pesan tersanitasi, tanpa data pribadi.');dd(panel,'Rating review',option.dataset.type==='review'?'4/5 (contoh review)':'Tidak berlaku untuk kategori report');
  }
  pickerValue(ticketPicker); ticketSelected();
  ticketPicker?.addEventListener('change', () => { setParam('id',ticketPicker.value); ticketSelected(); initEditorBaselines(); });
  const sourcePicker = $('[data-source-picker]');
  function sourceSelected() { const option = sourcePicker?.selectedOptions[0]; if (!option) return; text('[data-source-key]',option.value); text('[data-source-label]',option.dataset.label); text('[data-source-mode]',option.dataset.mode);linksTo('comics.html').forEach(link=>{const url=new URL(link.href);url.searchParams.set('source',option.value);link.href=url;}); }
  pickerValue(sourcePicker); sourceSelected();
  sourcePicker?.addEventListener('change', () => { setParam('id',sourcePicker.value); sourceSelected(); });

  const allowedFields = {
    comic: ['title','slug','source','status','alternative_titles','author','artist','type','cover_url','genre','synopsis'],
    chapter: ['comic_id','chapter_number','title','release_date','source_url'],
    account: ['username','display_name','status'], genre: ['name','slug'], helpdesk: ['status','admin_note']
  };
  const editors = new Map();
  let pendingEditor = null;
  function values(form) {
    const kind = form.dataset.editor, data = {};
    (allowedFields[kind] || []).forEach(name => { if (form.elements[name]) data[name] = form.elements[name].value.trim(); });
    return data;
  }
  function validate(form) {
    const errors = [];
    $$('input,select,textarea',form).forEach(input => {
      input.setCustomValidity('');
      if (input.disabled || input.closest('[hidden]')) return;
      if (input.required && !input.value.trim()) input.setCustomValidity('Field ini wajib diisi.');
      if (input.hasAttribute('data-https') && input.value) {
        try { const url=new URL(input.value);if(url.protocol!=='https:'||url.username||url.password||[...url.searchParams.keys()].some(key=>/token|secret|password|authorization|signature/i.test(key)))throw new Error(); } catch { input.setCustomValidity('Gunakan URL HTTPS contoh tanpa credential atau query sensitif.'); }
      }
      if (!input.checkValidity()) errors.push(input);
      input.setAttribute('aria-invalid',String(!input.checkValidity()));
      const message = $('[data-error-for="'+input.name+'"]',form);
      if (message) message.textContent = input.validity.valid ? '' : (input.validationMessage || 'Nilai tidak valid.');
    });
    const summary = $('[data-form-errors]',form);
    if (summary) { summary.hidden = errors.length === 0; summary.textContent = errors.length ? 'Periksa '+errors.length+' field: '+errors.map(input => input.closest('label')?.querySelector('span')?.textContent || input.name).join(', ')+'.' : ''; }
    if (errors.length) { summary?.focus(); errors[0].reportValidity(); return false; }
    return true;
  }
  function initEditorBaselines() {
    $$('form[data-editor]').forEach(form => {
      const kind = form.dataset.editor;
      if (params.get('mode') === 'create' && !form.dataset.createInitialized) {
        form.dataset.createInitialized = 'true'; form.dataset.mode = 'create'; form.dataset.key = 'new';
        $$('[data-immutable]',form).forEach(input => { input.readOnly = false; if (!['comic_id','source_url'].includes(input.name)) input.value = ''; });
        if (form.elements.title) form.elements.title.value = '';
        if (kind === 'account') { if (form.elements.username) form.elements.username.value = ''; if (form.elements.display_name) form.elements.display_name.value = ''; }
      }
      $$('[data-create-only]',form).forEach(input => { const active = form.dataset.mode === 'create'; input.closest('label').hidden = !active; input.disabled = !active; input.required = active; });
      $$('[data-edit-only]',form).forEach(input => { input.closest('label').hidden = form.dataset.mode === 'create'; });
      $$('[data-immutable-select]',form).forEach(input => { input.disabled = form.dataset.mode !== 'create'; });
      const saved = record(kind,form.dataset.key);
      Object.entries(saved).forEach(([name,value]) => { if ((allowedFields[kind] || []).includes(name) && form.elements[name]) form.elements[name].value = value; });
      editors.set(form,{ baseline: values(form), committed: false });
      if (form.dataset.bound) return; form.dataset.bound = 'true';
      form.addEventListener('input', () => { store.set('tt-draft:'+kind+':'+form.dataset.key,values(form)); });
      form.addEventListener('focusout', event => { const input = event.target; if (!input.matches('input,textarea,select')) return; input.setAttribute('aria-invalid',String(!input.checkValidity())); const message = $('[data-error-for="'+input.name+'"]',form); if (message) message.textContent = input.validity.valid ? '' : input.validationMessage; });
      form.addEventListener('submit', event => {
        event.preventDefault(); if (!validate(form)) return;
        const baseline = editors.get(form).baseline, next = values(form);
        const duplicate = form.dataset.mode === 'create' && (
          kind === 'comic' && [...(comicPicker?.options || [])].some(option => option.dataset.source === next.source && option.dataset.slug === next.slug) ||
          kind === 'chapter' && chapterNumbers.includes(String(Number(next.chapter_number))) ||
          kind === 'account' && [...(accountPicker?.options || [])].some(option => option.dataset.username === next.username)
        );
        if (duplicate) { const summary = $('[data-form-errors]',form); summary.hidden = false; summary.textContent = 'Resource contoh dengan identitas unik ini sudah ada. Tidak ada data tambahan dibuat.'; summary.focus(); return; }
        if (kind === 'genre' && form.dataset.mode === 'create' && $$('[data-list="genres"] [data-record]').some(row => row.dataset.search?.toLowerCase().split(' ').includes(next.slug.toLowerCase()))) { $('[data-form-errors]',form).hidden = false; $('[data-form-errors]',form).textContent = 'Slug genre contoh sudah digunakan.'; return; }
        const diff = Object.entries(next).filter(([name,value]) => baseline[name] !== value || form.dataset.mode === 'create').map(([name,value]) => ({ field:name,before:form.dataset.mode==='create'?'Belum ada':baseline[name],after:value }));
        if (!diff.length) { notify('Belum ada perubahan untuk disimpan.'); return; }
        pendingEditor = { form, next, diff, done:false };
        const target = $('[data-change-content]'); target.replaceChildren();
        const wrap = document.createElement('div'); wrap.className = 'table-region'; wrap.tabIndex = 0; wrap.setAttribute('role','region'); wrap.setAttribute('aria-label','Preview perubahan');
        const table = document.createElement('table'), thead = document.createElement('thead'), header = document.createElement('tr');
        ['Field','Sebelum','Sesudah'].forEach(value => { const th = document.createElement('th'); th.scope = 'col'; th.textContent = value; header.append(th); }); thead.append(header); table.append(thead);
        const tbody = document.createElement('tbody'); diff.forEach(item => { const row = document.createElement('tr'); [item.field,item.before ?? 'Belum tersedia',item.after || 'Kosong'].forEach(value => { const td = document.createElement('td'); td.textContent = value; row.append(td); }); tbody.append(row); }); table.append(tbody); wrap.append(table); target.append(wrap);
        $('[data-change-problem]').hidden = true; $('[data-commit-change]').disabled = false; openDialog($('#change-dialog'));
      });
    });
  }
  function commitEditor(force = false) {
    if (!pendingEditor || pendingEditor.done) return;
    const {form,next,diff} = pendingEditor;
    const result = form.elements.simulate?.value || 'success', problem = $('[data-change-problem]');
    if (!force && result !== 'success') {
      if(!pendingEditor.failureRecorded){demo.admin(form.dataset.editor,form.dataset.key,'update',result==='conflict'?409:result==='validation'?422:504);pendingEditor.failureRecorded=true;}
      problem.hidden = false;
      problem.setAttribute('role','alert');problem.tabIndex=-1;
      problem.textContent = result === 'conflict' ? 'Simulasi 409: versi contoh berubah. Draft dipertahankan. Kembali edit untuk muat versi terbaru atau salin draft.' : result === 'validation' ? 'Simulasi 422: server menolak payload contoh. Draft tetap tersedia.' : 'Hasil contoh belum pasti. Gunakan tombol Periksa hasil contoh untuk rekonsiliasi lokal.';
      $('[data-conflict-panel]',form)?.removeAttribute('hidden');
      if (result === 'uncertain') { const b = document.createElement('button'); b.type='button'; b.className='button mt-3'; b.textContent='Periksa hasil contoh'; b.addEventListener('click',()=>commitEditor(true),{once:true}); problem.append(b); }
      problem.focus();
      return;
    }
    pendingEditor.done = true; $('[data-commit-change]').disabled = true;
    const kind=form.dataset.editor, creating=form.dataset.mode==='create';
    const id=creating ? (kind==='chapter' ? selectedComic+'/chapter-'+next.chapter_number : 'demo-'+kind+'-'+Date.now()) : form.dataset.key;
    model.records[kind+':'+id] = { ...record(kind,id), ...next, _revision: Number(record(kind,id)._revision || 1)+1, _created:Boolean(record(kind,id)._created||creating) };
    if(kind==='genre')model.records[kind+':'+id]._originalName=record(kind,id)._originalName||editors.get(form).baseline.name;
    activity(kind,id,form.dataset.mode==='create'?'create':'update',diff); save();
    form.dataset.key=id; form.dataset.mode='edit'; editors.set(form,{baseline:{...next},committed:true});
    if(creating&&kind==='chapter'){chapter=String(next.chapter_number);if(!chapterNumbers.includes(chapter))chapterNumbers.push(chapter);params.delete('mode');setParam('mode','');setParam('chapter',chapter);}
    $$('[data-immutable]',form).forEach(input=>{input.readOnly=true;});
    $$('[data-immutable-select]',form).forEach(input=>{input.disabled=true;});
    $$('[data-create-only]',form).forEach(input=>{input.value='';input.disabled=true;input.required=false;input.closest('label').hidden=true;});
    store.set('tt-draft:'+kind+':'+id,null);
    closeDialog($('#change-dialog')); if (form.closest('#genre-dialog')) closeDialog($('#genre-dialog'));
    if (creating && (kind==='comic'||kind==='account')) {
      params.delete('mode'); params.set('id',id); setParam('mode',''); setParam('id',id); hydrateCreated();
      if(kind==='comic'&&comicPicker){comicPicker.value=id;selectedComic=id;}
      if(kind==='account'&&accountPicker){accountPicker.value=id;selectedAccount=id;}
    }
    notify(store.persistent?'Perubahan contoh disimpan di sesi browser. Backend tidak diubah.':'Perubahan hanya tersedia pada halaman ini; penyimpanan sesi tidak tersedia.');
    comicSelected(); accountSelected(); chapterContext(); bindSaved(); hydrateCreated(); hydrateChapters(); controllers.forEach(c=>c.refresh(false));
  }
  $('[data-commit-change]')?.addEventListener('click',()=>commitEditor());

  function hydrateCreated() {
    const roots={comic:'comics',account:'accounts',genre:'genres'};
    Object.entries(model.records).forEach(([key,data])=>{
      if (!data._created) return;
      const [kind,id]=key.split(':'), root=$('[data-list="'+roots[kind]+'"]'), parent=root&&$('[data-rows]',root);
      if (parent && !$$('[data-record]',parent).some(row=>row.dataset.id===id)) {
        const template=$('[data-record]',parent); if (!template) return;
        const row=template.cloneNode(true); row.dataset.id=id; row.dataset.kind=kind;
        row.dataset.search=Object.values(data).filter(v=>typeof v==='string').join(' '); row.dataset.name=data.title||data.name||data.username||data.display_name; row.dataset.status=data.status||'active';
        $$('[data-bind]',row).forEach(el=>{const field=el.dataset.bind.split(':')[2];el.dataset.bind=kind+':'+id+':'+field;if(data[field])el.textContent=data[field]});
        if(kind==='comic'){const cells=$$('td',row);$('a',cells[0]).textContent=data.title;cells[1].textContent=data.source;cells[3].textContent=data.genre;cells[4].textContent='0';}
        if(kind==='account'){const cells=$$('td',row);$('a',cells[0]).textContent=data.username;cells[1].textContent=data.display_name;cells[2].textContent='Email contoh disamarkan';cells[4].textContent='0';}
        if(kind==='genre'){const cells=$$('td',row);cells[0].textContent=data.name;cells[1].textContent=data.slug;const link=document.createElement('a');link.href='comics.html?genre='+encodeURIComponent(data.name);link.textContent='0 contoh';cells[2].replaceChildren(link);const edit=$('[data-edit-genre]',row);if(edit){edit.dataset.editGenre=id;edit.dataset.name=data.name;edit.dataset.slug=data.slug;}}
        $$('a[href]',row).forEach(link=>{const url=new URL(link.href);url.searchParams.set('id',id);link.href=url;}); parent.append(row);
      }
      const picker=kind==='comic'?comicPicker:kind==='account'?accountPicker:null;
      if(picker&&![...picker.options].some(o=>o.value===id)){const option=document.createElement('option');option.value=id;option.textContent=data.title||data.username;Object.entries(data).forEach(([k,v])=>{if(typeof v==='string')option.dataset[k]=v});if(kind==='account'){option.dataset.displayName=data.display_name;option.dataset.email='Email contoh disamarkan';}picker.append(option);}
    });
    bindSaved();
  }

  let pendingMutation=null;
  function mutate(button) {
    const kind=button.dataset.kind, id=kind==='chapter'?selectedComic+'/chapter-'+chapter:button.hasAttribute('data-use-selected')?selectedComic:button.hasAttribute('data-use-account')?selectedAccount:button.dataset.key;
    const action=button.dataset.mutate, title=kind==='comic'?$('[data-record-field="title"]')?.textContent:kind==='account'?$('[data-account-field="username"]')?.textContent:kind==='chapter'?'Chapter '+chapter+' · '+($('[data-record-field="title"]')?.textContent||selectedComic):button.dataset.title;
    pendingMutation={kind,id,action,done:false};
    text('[data-confirm-description]',(action==='archive'?'Arsipkan ':action==='restore'?'Pulihkan ':action==='ban'?'Nonaktifkan ':'Aktifkan ')+(title||id)+'? '+(kind==='comic'?'Contoh dampak: 8 chapter mengikuti arsip; relasi dan progress tidak dihapus.':'Tidak ada hard delete atau perubahan role.'));
    $('[data-confirm-apply]').disabled=false;$('[data-confirm-apply]').textContent=(action==='archive'?'Arsipkan ':action==='restore'?'Pulihkan ':action==='ban'?'Nonaktifkan ':'Aktifkan ')+(title||id);openDialog($('#confirm-dialog'));
  }
  $('[data-confirm-apply]')?.addEventListener('click',()=>{
    if(!pendingMutation||pendingMutation.done)return;pendingMutation.done=true;$('[data-confirm-apply]').disabled=true;
    const {kind,id,action}=pendingMutation;const previous=record(kind,id);model.records[kind+':'+id]={...previous,status:action==='restore'&&kind==='chapter'?'active':({archive:'archived',restore:previous._beforeArchive||'ongoing',ban:'banned',activate:'active'})[action]};
    if(action==='archive')model.records[kind+':'+id]._beforeArchive=previous.status||(kind==='chapter'?'active':comicPicker?.selectedOptions[0]?.dataset.status||'ongoing');
    activity(kind,id,action);save();bindSaved();comicSelected();accountSelected();chapterContext();hydrateChapters();controllers.forEach(c=>c.refresh(false));closeDialog($('#confirm-dialog'));notify('Status contoh diperbarui; data backend tetap.');
  });


  function endpointSelected() {
    const picker=$('[data-endpoint-picker]');if(!picker)return;
    renderSimEndpoint(picker.value);return;
    const option=picker.selectedOptions[0],factor=params.get('environment')==='staging'?0:Number(params.get('range')||15)/15,count=Math.round(Number(option.dataset.count)*factor),errors=Math.round(Number(option.dataset.errors)*factor);
    text('[data-endpoint-route] code',option.dataset.route);text('[data-endpoint-method]',option.dataset.method);
    text('[data-endpoint-count]',nf.format(count));text('[data-endpoint-samples]',nf.format(count));text('[data-endpoint-errors]',count?nf.format(errors):'Belum tersedia');text('[data-endpoint-p95]',count&&option.dataset.p95?nf.format(Number(option.dataset.p95))+' ms':'Belum tersedia');
    const values=[240,310,280,420,390,450,500,410,370,430,480,540].map(n=>Math.floor(n*count/4820));if(values.length)values[values.length-1]+=count-values.reduce((a,b)=>a+b,0);
    $$('.bar-chart > div').forEach((bar,i)=>{bar.style.height=(count?values[i]/Math.max(...values)*140:0)+'px';bar.title='Bucket '+(i+1)+': '+values[i]+' request';});
    const chartPanel=$('.bar-chart')?.closest('.panel');
    if(chartPanel){text('.chart-caption','12 bucket contoh · total '+nf.format(count)+' request · 24 Okt 2026, 10:42 UTC+7',chartPanel);$$('details tbody tr',chartPanel).forEach((row,i)=>{row.lastElementChild.textContent=values[i]});}
    const distribution=$$('h2').find(h=>h.textContent==='Distribusi status')?.closest('.panel');
    if(distribution){text('.panel-header p','Jumlah contoh: '+nf.format(count)+' respons.',distribution);const numbers=$$('dd',distribution);const client=Math.floor(count*.01);[count-errors-client,client,errors].forEach((n,i)=>{if(numbers[i])numbers[i].textContent=count?nf.format(n):'Belum tersedia'});}
    const coverage=$$('h2').find(h=>h.textContent==='Cakupan pengukuran')?.closest('.panel');
    if(coverage){dd(coverage,'p50 / p99',count&&option.value==='ep1'?'126 ms / 2.680 ms':'Belum tersedia');dd(coverage,'In-flight',count&&option.value==='ep1'?'12 pada cutoff contoh':'Belum tersedia');}
    const histogram=[1400,2000,1120,300].map(n=>Math.floor(n*count/4820));histogram[3]+=count-histogram.reduce((a,b)=>a+b,0);$$('[data-histogram-body] tr').forEach((row,i)=>{row.lastElementChild.textContent=count?nf.format(histogram[i]):'Belum tersedia';});
    linksTo('requests.html').forEach(link=>{const url=new URL(link.href);url.searchParams.set('endpoint',option.value);link.href=url;});
  }
  const endpointPicker=$('[data-endpoint-picker]');pickerValue(endpointPicker);endpointSelected();
  endpointPicker?.addEventListener('change',()=>{setParam('id',endpointPicker.value);endpointSelected();renderMonitoringContext()});
  function requestSelected(){
    const picker=$('[data-request-picker]');if(!picker)return;const option=picker.selectedOptions[0];
    const simulated=demo.state.requests.find(item=>item.id===option?.value);if(simulated){renderSimRequest(simulated);return;}
    if(!option)return;
    const fields={id:option.value,observation:option.dataset.observation,route:option.dataset.route,status:option.dataset.status,outcome:Number(option.dataset.status)>=500?'http_error':'completed',duration:nf.format(Number(option.dataset.duration))+' ms'};
    Object.entries(fields).forEach(([key,value])=>text('[data-request-field="'+key+'"]',value));
    const status=Number(option.dataset.status),panel=picker.closest('.panel');
    dd(panel,'Kode error',status===504?'gateway_timeout (contoh)':status===502?'bad_gateway (contoh)':status>=400?'http_client_error (contoh)':'Tidak ada error pada observasi contoh');
    const endpoint=option.dataset.route.includes('/images/proxy')?'ep2':option.dataset.route.includes('/search')?'ep3':option.dataset.route.includes('/chapters/')?'ep1':option.dataset.route.includes('/genres')?'ep5':option.dataset.route.includes('/helpdesk/')?'ep6':option.dataset.route.includes('/account-manager/')?'ep7':option.dataset.route.includes('/auth/login')?'ep8':'ep4';
    linksTo('endpoint-detail.html').forEach(link=>{link.href='endpoint-detail.html?id='+endpoint;});
    linksTo('runtime-logs.html').forEach(link=>{const url=new URL(link.href);url.searchParams.set('request',option.value);link.href=url;});
  }
  const requestPicker=$('[data-request-picker]');
  if(requestPicker){requestPicker.replaceChildren(...demo.state.requests.slice().reverse().map(item=>{const option=document.createElement('option');option.value=item.id;option.textContent=item.id;return option;}));}
  pickerValue(requestPicker);requestSelected();requestPicker?.addEventListener('change',()=>{setParam('id',requestPicker.value);requestSelected();renderMonitoringContext()});
  const runtimePicker=$('[data-runtime-picker]');
  if(runtimePicker){runtimePicker.replaceChildren(...demo.state.runtime.slice().reverse().map(item=>{const option=document.createElement('option');option.value=item.id;option.textContent=item.id;return option;}));}
  function runtimeSelected(){
    const option=runtimePicker?.selectedOptions[0];if(!option)return;
    const simulated=demo.state.runtime.find(item=>item.id===option.value);if(simulated){renderSimRuntime(simulated);return;}
    const data={id:option.value,...option.dataset};
    Object.entries(data).forEach(([key,value])=>text('[data-runtime-field="'+key+'"]',value||'Tidak ada ID'));
    const link=$('[data-runtime-request-link]');if(link){link.hidden=!data.request;link.href='request-detail.html?id='+encodeURIComponent(data.request||'');}
    const message=$('[data-runtime-no-request]');if(message)message.hidden=!!data.request;
    const stack=$('.safe-code')?.closest('details');if(stack)stack.hidden=data.level!=='ERROR';
  }
  pickerValue(runtimePicker);runtimeSelected();runtimePicker?.addEventListener('change',()=>{setParam('id',runtimePicker.value);runtimeSelected()});
  const alertPicker=$('[data-alert-picker]');
  if(alertPicker){alertPicker.replaceChildren(...demo.state.incidents.slice().reverse().map(item=>{const option=document.createElement('option');option.value=item.id;option.textContent=item.title+' · '+item.status;return option;}));}
  function alertSelected(){
    const option=alertPicker?.selectedOptions[0];if(!option)return;
    const simulated=demo.state.incidents.find(item=>item.id===option.value);if(simulated){renderSimIncident(simulated);return;}
    const panel=$('[data-alert-state]')?.closest('.panel');
    if(panel){text('.panel-header h2',option.dataset.title,panel);dd(panel,'Rule',option.dataset.rule);dd(panel,'Jendela / sampel',option.dataset.samples);dd(panel,'Nilai pemicu',option.dataset.value);dd(panel,'Mulai','24 Okt 2026, '+option.dataset.time+' UTC+7');}
    if(panel){
      const liveness=option.value==='inc-003',pipeline=option.value==='inc-004';
      text('.panel-header p','Contoh '+option.value+' · production / '+(liveness?'liveness':pipeline?'pipeline':'reader'),panel);
      dd(panel,'Recovery',liveness?'Dua probe sukses berturut-turut':pipeline?'Coverage pipeline kembali memadai':'60 detik di bawah threshold dengan coverage memadai');
      const primary=$('a.primary',panel),related=$$('a',panel).find(link=>link.getAttribute('href')?.startsWith('requests.html'));
      if(primary){primary.href=liveness?'health.html':pipeline?'runtime-logs.html':'endpoint-detail.html?id=ep1';primary.textContent=liveness?'Periksa probe':pipeline?'Periksa pipeline log':'Periksa endpoint chapter';primary.hidden=!permitted(linkCapability(primary.href));}
      if(related)related.hidden=liveness||pipeline;
    }
    const badge=$('[data-alert-state] .status');if(badge){badge.textContent=option.dataset.state;badge.className=option.dataset.state==='resolved'?tones.success:tones.warning;}
    const list=$('[data-alert-timeline]');if(list){list.replaceChildren();const li=document.createElement('li');li.textContent=option.dataset.time+' · '+option.dataset.state+' (contoh)';list.append(li);}
  }
  pickerValue(alertPicker);alertSelected();alertPicker?.addEventListener('change',()=>{setParam('id',alertPicker.value);alertSelected()});
  const auditPicker=$('[data-audit-picker]');
  const auditDiffTemplate=$('[data-audit-diff]')?.cloneNode(true);
  function auditSelected(){
    const selected=model.audit.find(item=>item.id===new URLSearchParams(location.search).get('id'));
    const option=auditPicker?.selectedOptions[0];if(!option&&!selected)return;
    const data=selected||{id:option.value,resource:option.dataset.resource,action:option.dataset.action,result:option.dataset.result,operation:'demo-op-'+option.value};
    text('[data-audit-field="id"]',data.id);text('[data-audit-field="resource"]',data.resource);text('[data-audit-field="action"]',data.action+' / '+data.result);text('[data-audit-field="operation"]',data.operation||data.id);
    const metadata=$('[data-audit-field="id"]')?.closest('.panel');
    if(metadata){dd(metadata,'Aktor',data.id==='audit-003'?'operator-contoh':'admin-contoh');dd(metadata,'Permission',data.resource.startsWith('account:')?'users:manage (contoh)':data.resource.startsWith('helpdesk:')?'helpdesk:manage (contoh)':'catalog:write (contoh)');dd(metadata,'Request ID',selected?selected.requestId||'Audit demo lama tanpa korelasi':'demo-req-'+String(Number(data.id.split('-')[1])+4).padStart(4,'0'));if(selected?.requestId)simRelated(metadata,[['request-detail.html',{id:selected.requestId},'Request operasi demo','monitoring'],['runtime-logs.html',{operation:selected.operation},'Runtime operasi ini','logs']]);}
    if(!selected&&data.action!=='update'){const body=$('[data-audit-diff]');body?.replaceChildren();if(body){const row=document.createElement('tr'),cell=document.createElement('td');cell.colSpan=3;cell.textContent='Hanya metadata tindakan; diff nilai tidak ditampilkan untuk event contoh ini.';row.append(cell);body.append(row);}}
    if(!selected&&data.action==='update'&&auditDiffTemplate)$('[data-audit-diff]')?.replaceChildren(...[...auditDiffTemplate.children].map(row=>row.cloneNode(true)));
    if(selected){const body=$('[data-audit-diff]');body?.replaceChildren();(selected.diff||[]).forEach(item=>{const row=document.createElement('tr');[item.field,item.before||'Belum ada',item.after||'Kosong'].forEach(value=>{const td=document.createElement('td');td.textContent=value;row.append(td)});body?.append(row)});if(!selected.diff?.length&&body){const row=document.createElement('tr');const td=document.createElement('td');td.colSpan=3;td.textContent='Hanya metadata aksi; tidak ada payload pribadi.';row.append(td);body.append(row);}}
  }
  if(auditPicker){auditPicker.replaceChildren();model.audit.forEach(entry=>{const option=document.createElement('option');option.value=entry.id;option.textContent=entry.id;auditPicker.append(option);});pickerValue(auditPicker);auditSelected();auditPicker.addEventListener('change',()=>{setParam('id',auditPicker.value);auditSelected()});}
  const auditRows=$('[data-list="audit"] [data-rows]');
  if(auditRows){auditRows.replaceChildren();model.audit.slice().reverse().forEach(entry=>{
    const row=document.createElement('tr');row.dataset.record='';row.dataset.id=entry.id;row.dataset.search=[entry.resource,entry.action,entry.id,entry.requestId,entry.operation].join(' ');row.dataset.request=entry.requestId||'';row.dataset.actor='admin-contoh';row.dataset.result='simulated';row.dataset.action=entry.action;row.dataset.timestamp=String(Date.parse(entry.at));
    [entry.at.replace('T',' ').slice(0,19)+' UTC','admin-contoh',entry.resource,entry.action,'simulated',entry.id].forEach((value,i)=>{const td=document.createElement('td');if(i===5){const link=document.createElement('a');link.href='audit-detail.html?id='+encodeURIComponent(entry.id);link.textContent=value;td.append(link);}else td.textContent=value;row.append(td);});auditRows.prepend(row);
  });}

  function simTime(at,full=false){return new Intl.DateTimeFormat('id-ID',{timeZone:'Asia/Bangkok',...(full?{day:'2-digit',month:'short',year:'numeric'}:{}),hour:'2-digit',minute:'2-digit',second:'2-digit',hourCycle:'h23'}).format(at);}
  function simExtra(panel,label,value){if(!panel)return;let dt=$$('dt',panel).find(el=>el.textContent===label);if(!dt){dt=document.createElement('dt');dt.textContent=label;const dd=document.createElement('dd');($('dl',panel)||panel).append(dt,dd);}dt.nextElementSibling.textContent=value;}
  function simRelated(panel,items){let actions=$('[data-demo-related]',panel);if(!actions){actions=document.createElement('div');actions.className='actions mt-4';actions.dataset.demoRelated='';($('.content-pad',panel)||panel).append(actions);}actions.replaceChildren();items.forEach(([file,query,label,capability])=>{if(!permitted(capability))return;const a=document.createElement('a');a.className='button';a.textContent=label;const url=new URL(file,location.href);Object.entries(query).forEach(([key,value])=>{if(value)url.searchParams.set(key,String(value));});url.searchParams.set('back',location.pathname.split('/').pop()+location.search);a.href=url;a.dataset.recordLink='';actions.append(a);});}
  function renderSimRequest(item){
    const panel=$('[data-request-picker]')?.closest('.panel');if(!panel)return;params.set('environment',item.environment);setParam('environment',item.environment);$$('.status',panel).forEach(el=>originalStatuses.delete(el));
    const values={id:item.id,observation:item.observation,route:item.route,status:item.pending?'Belum selesai':item.status==null?'Tidak ada status HTTP':String(item.status),outcome:item.outcome,duration:item.duration==null?'Belum selesai':nf.format(item.duration)+' ms'};Object.entries(values).forEach(([key,value])=>text('[data-request-field="'+key+'"]',value));
    dd(panel,'Instance / environment',item.instance+' / '+item.environment);dd(panel,'Kode error',item.status>=500?'demo_http_'+item.status:item.outcome!=='completed'?item.outcome:'Tidak ada error');simExtra(panel,'Jam demo',simTime(item.at,true)+' UTC+7');simExtra(panel,'Asal status',item.statusSource);simExtra(panel,'Scope',item.scope);simExtra(panel,'Run ID',item.run||'Tidak terkait Preview');simExtra(panel,'Operation ID',item.operation||'Tidak ada operasi admin');
    linksTo('runtime-logs.html').forEach(link=>{const url=new URL('runtime-logs.html',location.href);url.searchParams.set('request',item.id);url.searchParams.set('range','1440');link.href=url;});linksTo('endpoint-detail.html').forEach(link=>{link.hidden=!item.endpoint;if(item.endpoint)link.href='endpoint-detail.html?id='+item.endpoint+'&environment='+item.environment;});
    const related=[['runtime-logs.html',{request:item.id,range:1440},'Runtime untuk request ini','logs']];if(item.endpoint)related.push(['endpoint-detail.html',{id:item.endpoint,environment:item.environment},'Metrik endpoint','monitoring']);if(item.run)related.push(['requests.html',{run:item.run,range:1440},'Seluruh request run ini','monitoring']);if(item.operation){const audit=model.audit.find(a=>a.operation===item.operation);if(audit)related.push(['audit-detail.html',{id:audit.id},'Audit perubahan terkait','audit']);}simRelated(panel,related);
  }
  function renderSimRuntime(item){
    const panel=$('[data-runtime-picker]')?.closest('.panel');if(!panel)return;params.set('environment',item.environment);setParam('environment',item.environment);$$('.status',panel).forEach(el=>originalStatuses.delete(el));
    Object.entries({id:item.id,logger:item.logger,level:item.level,message:item.message,request:item.request||'Tidak ada request ID'}).forEach(([key,value])=>text('[data-runtime-field="'+key+'"]',value));
    text('.panel-header p',item.id+' · '+item.level+' · '+item.kind+' · demo lokal',panel);dd(panel,'Occurred / received',simTime(item.at)+' / '+simTime(item.received)+' UTC+7 (jam demo)');dd(panel,'Instance',item.instance+' / '+item.environment);dd(panel,'Redacted / truncated','Pesan dibatasi metadata aman; body/token/cookie/email tidak dikumpulkan.');simExtra(panel,'Run ID',item.run||'Tidak terkait Preview');simExtra(panel,'Operation ID',item.operation||'Tidak ada operasi admin');
    const link=$('[data-runtime-request-link]');if(link){link.hidden=!item.request;link.href='request-detail.html?id='+encodeURIComponent(item.request||'');}const notice=$('[data-runtime-no-request]');if(notice)notice.hidden=!!item.request;
    const stack=$('.safe-code',panel)?.closest('details');if(stack){stack.hidden=item.level!=='ERROR';if(item.level==='ERROR')text('.safe-code','DemoEventError: '+item.message+'\nTidak ada stack server produksi; kejadian berasal dari simulator browser.',stack);}
    simRelated(panel,[...(item.request?[['request-detail.html',{id:item.request},'Buka request terkait','monitoring']]:[]),...(item.run?[['requests.html',{run:item.run,range:1440},'Lihat run Preview','monitoring']]:[]),...(item.operation?[['audit.html',{q:item.operation},'Audit operasi ini','audit']]:[])]);
  }
  function renderSimIncident(item){
    const panel=$('[data-alert-picker]')?.closest('.panel');if(!panel)return;params.set('environment',item.environment);setParam('environment',item.environment);$$('.status',panel).forEach(el=>originalStatuses.delete(el));
    text('.panel-header h2',item.title,panel);text('.panel-header p',item.id+' · '+item.environment+' · evaluator demo',panel);const badge=$('[data-alert-state] .status');badge.textContent=item.status;badge.className=item.status==='resolved'?tones.success:item.status==='pending'?tones.neutral:tones.warning;
    dd(panel,'Rule',({latency:'p95 > 2.000 ms; minimal 100 request; hold/recovery 60 detik',errors:'5xx > 5%; minimal 100 request; hold/recovery 60 detik',liveness:'2 probe gagal; pulih setelah 2 sukses',pipeline:'Ingest berhenti selama 30 detik'})[item.rule]);dd(panel,'Jendela / sampel','5 menit jam demo / '+demo.summary(item.environment,5,'reader').count+' request');dd(panel,'Nilai pemicu',item.value);dd(panel,'Mulai',simTime(item.since,true)+' UTC+7');dd(panel,'Recovery',item.status==='resolved'?'Pulih pada '+simTime(item.updated):item.status==='unknown'?'Evaluasi unknown, tidak dianggap pulih':'Menunggu kondisi sehat sesuai rule');
    const timeline=$('[data-alert-timeline]');timeline.replaceChildren(...item.timeline.map(event=>{const li=document.createElement('li');li.textContent=simTime(event.at)+' · '+event.status+' · '+event.note;return li;}));
    const actions=$('.actions',panel);if(actions)actions.hidden=true;
    simRelated(panel,[[item.rule==='liveness'?'health.html':item.rule==='pipeline'?'runtime-logs.html':'requests.html',{environment:item.environment,range:5,...(item.rule==='latency'?{minDuration:2000}:item.rule==='errors'?{status:'5xx'}:{})},'Periksa bukti insiden','monitoring'],['endpoints.html',{environment:item.environment,range:5},'Periksa endpoint','monitoring']]);
  }

  let feedPaused=true;
  const feedRoot=$('[data-feed-bar]')?($('[data-list="runtime"]')||$('[data-list="requests"]')):null;
  function feedStatus(){const events=feedRoot?.dataset.list==='runtime'?demo.state.runtime:demo.state.requests;const cursor=Number(feedRoot?.dataset.demoCursor||0);const waiting=feedPaused?events.filter(e=>e.seq>cursor).length:0;text('[data-feed-state]',feedPaused?'Tampilan dijeda':'Tampilan mengikuti sesi demo');text('[data-feed-buffer]',waiting+' event baru menunggu');text('[data-feed-toggle]',feedPaused?'Lanjutkan tampilan':'Jeda tampilan');}
  function injectFeed(){if(feedRoot?.dataset.list==='runtime')demo.lifecycle();else demo.once();feedStatus();}
  function toggleFeed(){
    feedPaused=!feedPaused;refreshSimulation();feedStatus();
  }
  feedStatus();
  const login=$('#login-form');
  login?.addEventListener('submit',event=>{
    event.preventDefault();if(!validate(login))return;
    const result=login.elements.result.value,error=$('[data-form-errors]',login);
    demo.preview('/api/v1/auth/login','ep8','',{status:result==='success'?200:result==='403'?403:401,scope:'admin_operation'});
    if(result!=='success'){error.hidden=false;error.textContent=result==='403'?'Simulasi 403: akun contoh tidak berizin.':result==='expired'?'Simulasi sesi kedaluwarsa. Masuk ulang tanpa mengulang retry.':'Simulasi 401: identifier/password contoh tidak valid.';error.focus();return;}
    model.role=login.elements.role.value;save();login.elements.password.value='';location.href=model.role==='accounts'?'accounts.html':model.role==='auditor'?'audit.html':'index.html';
  });
  $('[data-show-password]')?.addEventListener('change',event=>{const input=$('input[name="password"]',login);if(input)input.type=event.target.checked?'text':'password';});

  document.addEventListener('click',event=>{
    const target=event.target.closest('button,a');if(!target)return;
    if(target.hasAttribute('data-close-dialog'))closeDialog(target.closest('dialog'));
    if(target.hasAttribute('data-open-dialog'))openDialog(document.getElementById(target.dataset.openDialog));
    if(target.hasAttribute('data-copy-nearest')){const root=target.closest('.panel')||target.closest('.prototype-dialog');copy(($('[data-copy-content]',root)||root).innerText);}
    if(target.hasAttribute('data-copy-draft')){const form=target.closest('form');if(form)copy(JSON.stringify(values(form),null,2));}
    if(target.hasAttribute('data-mutate'))mutate(target);
    if(target.hasAttribute('data-reset-demo')){if(confirm('Reset seluruh perubahan dan draft contoh pada sesi ini? Backend tidak terpengaruh.')){simulationResetting=true;store.clearDemo();model={records:{},audit:[],role:'all',revision:0};save();location.href=location.pathname;}}
    if(target.hasAttribute('data-logout')){model.role='all';save();location.href='login.html';}
    if(target.hasAttribute('data-restore-draft')){
      const form=target.closest('form'), draft=form&&store.get('tt-draft:'+form.dataset.editor+':'+form.dataset.key,null);
      if(!draft){notify('Belum ada draft contoh tersimpan.');return;}Object.entries(draft).forEach(([key,value])=>{if(form.elements[key])form.elements[key].value=value});notify('Draft sesi dipulihkan. Periksa sebelum menyimpan.');
    }
    if(target.hasAttribute('data-discard-draft')){const form=target.closest('form');const baseline=editors.get(form)?.baseline;Object.entries(baseline||{}).forEach(([key,value])=>{if(form.elements[key])form.elements[key].value=value});store.set('tt-draft:'+form.dataset.editor+':'+form.dataset.key,null);notify('Draft contoh dibuang.');}
    if(target.hasAttribute('data-load-latest')){
      const form=target.closest('form');store.set('tt-draft:'+form.dataset.editor+':'+form.dataset.key,values(form));
      const baseline=editors.get(form).baseline;Object.entries(baseline).forEach(([key,value])=>{if(form.elements[key])form.elements[key].value=value});
      if(form.elements.simulate)form.elements.simulate.value='success';$('[data-conflict-panel]',form).hidden=true;notify('Versi contoh dimuat. Draft sebelumnya masih dapat dipulihkan.');
    }
    if(target.hasAttribute('data-open-genre')||target.hasAttribute('data-edit-genre')){
      const form=$('#genre-dialog form'),create=target.hasAttribute('data-open-genre');
      form.dataset.key=create?'new':target.dataset.editGenre;form.dataset.mode=create?'create':'edit';
      form.elements.name.value=create?'':record('genre',form.dataset.key).name||target.dataset.name;form.elements.slug.value=create?'':target.dataset.slug;form.elements.slug.readOnly=!create;
      initEditorBaselines();const draft=store.get('tt-draft:genre:'+form.dataset.key,null);if(draft)Object.entries(draft).forEach(([key,value])=>{if(form.elements[key])form.elements[key].value=value});openDialog($('#genre-dialog'));
    }
    if(target.hasAttribute('data-reset-override')){
      delete record('comic',selectedComic)[target.dataset.resetOverride];activity('comic',selectedComic,'reset_override');save();comicSelected();notify('Override judul contoh dikembalikan ke source.');
    }
    if(target.hasAttribute('data-feed-toggle'))toggleFeed();
    if(target.hasAttribute('data-feed-inject'))injectFeed();
    if(target.hasAttribute('data-feed-clear')&&feedRoot){feedRoot.dataset.demoClear=String(demo.state.sequence);$('[data-rows]',feedRoot).replaceChildren();feedRoot.dataset.demoCursor=String(demo.state.sequence);controllers.find(c=>c.root===feedRoot)?.refresh(false);feedStatus();notify('Tampilan dibersihkan. Riwayat sesi masih ada; gunakan Tampilkan riwayat.');}
    if(target.hasAttribute('data-feed-latest'))$('[data-rows] [data-record]:not([hidden])',feedRoot)?.scrollIntoView({block:'center'});
    if(target.hasAttribute('data-probe')){demo.probe();notify('Probe demo dicatat; hasil mengikuti skenario aktif.');}
    if(target.hasAttribute('data-alert-transition')){
      const next=target.dataset.alertTransition;demo.scenario(next==='resolved'?'healthy':next==='unknown'?'gap':'errors');demo.advance(next==='resolved'?10:3);if(next==='resolved')demo.advance(3);notify('Evaluator demo dijalankan; state ditentukan observasi dan rule, bukan diubah langsung.');
    }
    if(target.hasAttribute('data-preview-feed')){
      const previewRun=store.get('tt-preview-run',null)||{id:'demo-preview-'+Date.now(),entry:target.dataset.previewFeed};store.set('tt-preview-run',previewRun);demo.preview('/api/v1/sources/{source_name}/comics','ep4',previewRun.id);
      $$('[data-preview-feed]').forEach(b=>b.setAttribute('aria-pressed',String(b===target)));setParam('feed',target.dataset.previewFeed);controllers.find(c=>c.root.dataset.list==='preview')?.refresh(false);
    }
    if(target.hasAttribute('data-start-run')){store.set('tt-preview-run',null);notify('Sesi diagnosis lokal baru siap. Pilih komik untuk melanjutkan.');}
    if(target.hasAttribute('data-run-link')){
      const url=new URL(target.href);const row=target.closest('[data-record]');const nextRun={id:'demo-preview-'+Date.now(),entry:$('[data-preview-feed][aria-pressed=true]')?.dataset.previewFeed||'search',comic:row?.dataset.id||url.searchParams.get('id'),feedBack:'comic-preview.html'+location.search};store.set('tt-preview-run',nextRun);demo.preview('/api/v1/sources/{source_name}/comics','ep4',nextRun.id);
    }
    if(target.matches('a[data-record-link]')){const url=new URL(target.href),context=new URLSearchParams(location.search);url.searchParams.set('back',location.pathname.split('/').pop()+location.search);['range','environment'].forEach(key=>{if(context.has(key))url.searchParams.set(key,context.get(key))});target.href=url;}
    if(target.matches('a[data-parent-link],a[data-reader-link]')){const url=new URL(target.href);url.searchParams.set('id',selectedComic);target.href=url;if(target.hasAttribute('data-reader-link')){const context=store.get('tt-preview-run',{});context.chapterBack=location.pathname.split('/').pop()+location.search;store.set('tt-preview-run',context);}}
  });
  if(document.body.dataset.capability==='library')$$('a[href^="account-detail.html"]').forEach(link=>{const url=new URL(link.href);url.searchParams.set('id',params.get('id')||'u1');link.href=url;});
  const back=params.get('back');
  if(back&&/^[a-z0-9-]+\.html(?:\?[^#]*)?$/i.test(back)&&!/[<>]/.test(back))$$('[data-back-link]').forEach(link=>{link.href=back;});
  let run=store.get('tt-preview-run',null);
  if($('[data-run-id]')){if(!run){run={id:'demo-preview-'+Date.now(),entry:'direct',comic:selectedComic};store.set('tt-preview-run',run);}text('[data-run-id]',run.id);text('[data-run-entry]',run.entry);}
  const currentFile=location.pathname.split('/').pop();
  if(run&&currentFile==='preview-detail.html')demo.preview('/api/v1/sources/{source_name}/comics/{slug}','ep4',run.id);
  if(run&&currentFile==='preview-reader.html')demo.preview(route,'ep1',run.id);
  const previewSearch=$('[data-list="preview"] [data-filters]');previewSearch?.addEventListener('submit',()=>{const context=store.get('tt-preview-run',null)||{id:'demo-preview-'+Date.now(),entry:'search'};store.set('tt-preview-run',context);demo.preview('/api/v1/search','ep3',context.id);});
  if(currentFile==='preview-detail.html'&&run?.feedBack&&/^comic-preview\.html(?:\?|$)/.test(run.feedBack))$$('a[href^="comic-preview.html"]').forEach(link=>{link.href=run.feedBack});
  if(currentFile==='preview-reader.html'&&run?.chapterBack&&/^preview-detail\.html(?:\?|$)/.test(run.chapterBack))$$('a[href]').filter(link=>new URL(link.href).pathname.endsWith('/preview-detail.html')).forEach(link=>{link.href=run.chapterBack});
  if(params.get('feed')){const target=$$('[data-preview-feed]').find(b=>b.dataset.previewFeed===params.get('feed'));if(target){$$('[data-preview-feed]').forEach(b=>b.setAttribute('aria-pressed',String(b===target)));}}


  function initReader(){
    const pages=$$('[data-reader-page]');if(!pages.length)return;
    const selector=$('#chapter-select'),scenario=$('[data-reader-scenario]');
    const states=new Map(pages.map(el=>[Number(el.dataset.readerPage),{el,state:'Belum diminta',attempt:0,url:el.dataset.url,http:'Belum tersedia',mime:'Belum tersedia',bytes:'Belum tersedia',duration:'Belum tersedia',decode:'Belum diuji',blob:null,controller:null,requestId:null}]));
    const queue=[];let active=0,generation=0,stopped=false,selected=1,invalidPayload=false;
    let chapterOptions=[];
    function readerChapters(requested){
      chapterOptions=[...new Set([...(record('comic',selectedComic)._created?[]:baseChapterNumbers),...Object.entries(model.records).filter(([key,value])=>key.startsWith('chapter:'+selectedComic+'/')&&value._created).map(([,value])=>String(value.chapter_number))])].sort((a,b)=>Number(a)-Number(b));
      selector.replaceChildren(...chapterOptions.map(value=>{const option=document.createElement('option');option.value=value;option.textContent='Chapter '+value;return option;}));
      selector.disabled=!chapterOptions.length;
      selector.value=chapterOptions.includes(requested)?requested:chapterOptions[chapterOptions.length-1]||'';
    }
    readerChapters(params.get('chapter'));
    function timeline(message){const li=document.createElement('li');li.textContent=message+' · contoh lokal';$('[data-reader-timeline]').append(li);while($('[data-reader-timeline]').children.length>100)$('[data-reader-timeline]').firstElementChild.remove();}
    function inspect(number){
      selected=Number(number);const page=states.get(selected);if(!page)return;
      const url=page.attempt?new URL(page.url,location.href).href:'Belum diminta';
      const fields={page:selected,state:page.state,url,http:page.http,mime:page.mime,bytes:page.bytes,duration:page.duration,decode:page.decode,attempt:page.attempt};
      Object.entries(fields).forEach(([key,value])=>text('[data-inspect="'+key+'"]',value));
      const panel=$('[data-inspect="page"]')?.closest('.panel');if(panel){simExtra(panel,'Request ID demo',page.requestId||'Belum diminta');simExtra(panel,'Run ID demo',run.id);simRelated(panel,[...(page.requestId?[['request-detail.html',{id:page.requestId},'Buka attempt di Request log','monitoring']]:[]),['runtime-logs.html',{run:run.id,range:1440},'Runtime untuk run ini','logs'],['requests.html',{run:run.id,range:1440},'Seluruh request run ini','monitoring']]);}
    }
    function summary(){
      const all=[...states.values()],success=all.filter(p=>p.state==='Berhasil').length,failed=all.filter(p=>p.state==='Gagal').length,cancelled=all.filter(p=>p.state==='Dibatalkan').length,pending=all.filter(p=>['Belum diminta','Mengantre','Memuat'].includes(p.state)).length;
      text('[data-reader-summary]',success+' berhasil · '+failed+' gagal · '+pending+' belum diuji · '+cancelled+' dibatalkan (file lokal)');
      const result=$('[data-run-result]');
      result.textContent=invalidPayload?'Gagal validasi contoh':active||queue.length?'Berjalan (lokal)':success===all.length?'Lulus untuk 3 page lokal':failed===all.length?'Gagal':success||failed||cancelled?'Parsial':'Belum diuji';
      result.className=success===all.length&&!invalidPayload?tones.success:failed||invalidPayload?tones.warning:tones.neutral;
      $('[data-reader-stop]').disabled=active===0&&queue.length===0;
      inspect(selected);
    }
    function update(page,state){
      page.state=state;const badge=$('[data-page-state]',page.el);badge.textContent=state;badge.className=state==='Berhasil'?tones.success:state==='Gagal'?tones.danger:tones.neutral;
      const image=$('[data-reader-image]',page.el),placeholder=$('[data-page-placeholder]',page.el);
      image.hidden=state!=='Berhasil';placeholder.hidden=state==='Berhasil';placeholder.textContent='Page '+page.el.dataset.readerPage+' · '+state;
      summary();
    }
    function validatePayload(){
      const kind=scenario.value;const problem=$('[data-reader-problem]');
      invalidPayload=['empty','missing','duplicate','order'].includes(kind);
      problem.hidden=!invalidPayload;
      if(invalidPayload){
        problem.textContent=({empty:'Simulasi payload images kosong.',missing:'Simulasi page hilang dari payload.',duplicate:'Simulasi nomor page duplikat.',order:'Simulasi urutan page tidak valid.'})[kind]+' Tidak ada page baru dijadwalkan. Hasil attempt sebelumnya tetap terlihat.';
        timeline(problem.textContent);summary();return false;
      }
      return true;
    }
    function delay(ms,signal){return new Promise((resolve,reject)=>{const timer=setTimeout(resolve,ms);signal.addEventListener('abort',()=>{clearTimeout(timer);reject(new DOMException('Dibatalkan','AbortError'));},{once:true});});}
    async function loadPage(page,epoch,proxy=false){
      page.attempt++;const attempt=page.attempt,controller=new AbortController();page.controller=controller;page.requestId=demo.imageStart(run.id);const requestId=page.requestId;let observedStatus=null,outcome='completed';
      page.http='Belum tersedia';page.mime='Belum tersedia';page.bytes='Belum tersedia';page.duration='Belum tersedia';page.decode='Belum diuji';update(page,'Memuat');
      timeline('Page '+page.el.dataset.readerPage+' attempt '+attempt+' dimulai'+(proxy?' · proxy simulasi':''));
      const kind=scenario.value,image=$('[data-reader-image]',page.el),start=performance.now();
      if(kind==='dimensions')timeline('Dimensi metadata tidak tersedia; validasi memakai dimensi hasil decode browser');
      try{
        let blob=null;
        if(['403','404','413','503','504'].includes(kind)){await delay(180,controller.signal);observedStatus=Number(kind);throw new Error('HTTP '+kind+' simulasi; bukan status dari backend.');}
        if(kind==='timeout'){await delay(1500,controller.signal);throw new Error('Timeout simulasi.');}
        if(kind==='html'){await delay(150,controller.signal);observedStatus=200;outcome='decode_error';page.mime='text/html (simulasi)';throw new Error('Skenario HTTP 200 dengan body HTML; bukan gambar.');}
        if(kind==='corrupt'){observedStatus=200;outcome='decode_error';blob=new Blob([new Uint8Array([0,1,2,3,4])],{type:'image/png'});}
        else if(location.protocol==='file:'){
          image.src=page.url;await image.decode();if(controller.signal.aborted)throw new DOMException('Dibatalkan','AbortError');
          if(epoch!==generation)return;page.http='Belum tersedia (file://)';page.mime='Gambar lokal';page.decode='Berhasil · '+image.naturalWidth+' × '+image.naturalHeight;update(page,'Berhasil');timeline('Page '+page.el.dataset.readerPage+' decode file lokal berhasil');return;
        }else{
          const response=await fetch(page.url,{signal:controller.signal,cache:'reload',credentials:'omit'});
          observedStatus=response.status;page.http=String(response.status)+' (file lokal)';page.mime=response.headers.get('content-type')||'Belum tersedia';
          if(!response.ok)throw new Error('HTTP file lokal '+response.status);
          if(kind==='stream')throw new Error('Simulasi body stream gagal setelah header file lokal 200; bukan HTTP 500.');
          blob=await response.blob();page.bytes=nf.format(blob.size)+' byte body lokal';page.duration=(performance.now()-start).toFixed(1)+' ms sampai body selesai';
          if(!blob.type.startsWith('image/'))throw new Error('Body lokal bukan gambar.');
        }
        if(page.blob)URL.revokeObjectURL(page.blob);page.blob=URL.createObjectURL(blob);image.src=page.blob;
        const decodeStart=performance.now();await image.decode();
        if(controller.signal.aborted)throw new DOMException('Dibatalkan','AbortError');
        if(epoch!==generation)return;
        page.decode='Berhasil · '+image.naturalWidth+' × '+image.naturalHeight+' · decode '+(performance.now()-decodeStart).toFixed(1)+' ms'+(kind==='dimensions'?' · dimensi metadata kosong; hasil decode aktual':'');
        if(!image.naturalWidth||!image.naturalHeight)throw new Error('Dimensi decode kosong.');
        update(page,'Berhasil');timeline('Page '+page.el.dataset.readerPage+' attempt '+attempt+' berhasil');
      }catch(error){
        outcome=error.name==='AbortError'?'cancelled':observedStatus>=400?'http_error':kind==='timeout'?'timeout':observedStatus===200?'decode_error':'network_error';
        if(epoch!==generation)return;
        if(error.name==='AbortError'){update(page,'Dibatalkan');timeline('Page '+page.el.dataset.readerPage+' attempt '+attempt+' dibatalkan');}
        else{page.decode=error.message;update(page,'Gagal');timeline('Page '+page.el.dataset.readerPage+' attempt '+attempt+' gagal: '+error.message);}
      }finally{demo.imageFinish(requestId,observedStatus,performance.now()-start,controller.signal.aborted?'cancelled':outcome);if(epoch===generation)page.controller=null;}
    }
    function pump(){
      while(!stopped&&active<3&&queue.length){
        const item=queue.shift(),page=states.get(item.number),epoch=generation;active++;
        loadPage(page,epoch,item.proxy).finally(()=>{if(epoch===generation){active=Math.max(0,active-1);pump();summary();}});
      }
      summary();
    }
    function enqueue(number,force=false,proxy=false){
      if(!chapterOptions.length){notify('Belum ada metadata chapter untuk diuji.');return;}
      const page=states.get(Number(number));
      if(!page||page.controller||queue.some(item=>item.number===Number(number)))return;
      if(!force&&page.state==='Berhasil')return;
      if(!validatePayload())return;
      stopped=false;queue.push({number:Number(number),proxy});update(page,'Mengantre');pump();
    }
    function stop(){
      stopped=true;queue.splice(0).forEach(item=>update(states.get(item.number),'Dibatalkan'));
      states.forEach(page=>{if(page.controller)page.controller.abort();});
      timeline('Penjadwalan dihentikan; tidak ada background prefetch backend pada prototype');summary();
    }
    function reset(newChapter=false){
      generation++;stopped=true;queue.length=0;
      states.forEach(page=>{if(page.controller)demo.imageFinish(page.requestId,null,0,'cancelled');page.controller?.abort();page.controller=null;page.requestId=null;if(page.blob)URL.revokeObjectURL(page.blob);page.blob=null;page.attempt=0;page.http='Belum tersedia';page.mime='Belum tersedia';page.bytes='Belum tersedia';page.duration='Belum tersedia';page.decode='Belum diuji';$('[data-reader-image]',page.el).removeAttribute('src');update(page,'Belum diminta');});
      invalidPayload=false;active=0;$('[data-reader-problem]').hidden=true;
      run={...run,id:'demo-preview-'+Date.now(),entry:newChapter?'chapter-navigation':'reset',comic:selectedComic,chapter:selector.value};store.set('tt-preview-run',run);text('[data-run-id]',run.id);summary();
    }
    function chapterNavigation(){
      stop();reset(true);text('[data-chapter-number]',selector.value);setParam('chapter',selector.value);
      const index=chapterOptions.indexOf(selector.value);$('[data-reader-prev]').disabled=index<=0;$('[data-reader-next]').disabled=index===chapterOptions.length-1;
      timeline('Chapter '+selector.value+' dipilih dari metadata, bukan nomor +1');
      stopped=!chapterOptions.length;states.forEach(page=>{observer.unobserve(page.el);if(!stopped)observer.observe(page.el);});
    }
    const observer=new IntersectionObserver(entries=>{entries.forEach(entry=>{if(entry.isIntersecting&&!stopped){const number=Number(entry.target.dataset.readerPage);enqueue(number);if(states.has(number+1))enqueue(number+1);}});},{rootMargin:'200px 0px'});
    stopped=!chapterOptions.length;
    if(!stopped)states.forEach(page=>observer.observe(page.el));
    const firstIndex=chapterOptions.indexOf(selector.value);$('[data-reader-prev]').disabled=firstIndex<=0;$('[data-reader-next]').disabled=firstIndex<0||firstIndex===chapterOptions.length-1;
    text('[data-chapter-number]',selector.value);
    selector.addEventListener('change',chapterNavigation);
    comicPicker?.addEventListener('change',()=>{readerChapters();chapterNavigation();if(!chapterOptions.length)notify('Komik contoh ini belum memiliki metadata chapter. Tambahkan melalui katalog.');});
    scenario.addEventListener('change',()=>{stop();invalidPayload=false;$('[data-reader-problem]').hidden=true;summary();notify('Skenario berlaku pada attempt berikutnya. Hasil sebelumnya tetap tercatat.');});
    document.addEventListener('click',event=>{
      const button=event.target.closest('button');if(!button)return;
      if(button.hasAttribute('data-inspect-page'))inspect(button.dataset.inspectPage);
      if(button.hasAttribute('data-retry-page'))enqueue(button.dataset.retryPage,true);
      if(button.hasAttribute('data-reader-all')){if(validatePayload()){stopped=false;states.forEach((page,number)=>enqueue(number,true));}}
      if(button.hasAttribute('data-reader-stop'))stop();
      if(button.hasAttribute('data-reader-reset')){stop();reset();timeline('Sesi lokal direset; cache backend tidak dihapus');}
      if(button.hasAttribute('data-reader-prev')){const i=chapterOptions.indexOf(selector.value);if(i>0){selector.value=chapterOptions[i-1];chapterNavigation();}}
      if(button.hasAttribute('data-reader-next')){const i=chapterOptions.indexOf(selector.value);if(i<chapterOptions.length-1){selector.value=chapterOptions[i+1];chapterNavigation();}}
      if(button.hasAttribute('data-jump-page')){const number=Number($('[data-page-jump]').value);states.get(number)?.el.scrollIntoView({block:'start'});inspect(number);enqueue(number);}
      if(button.hasAttribute('data-reader-reload'))enqueue(selected,true);
      if(button.hasAttribute('data-reader-proxy')){notify('Proxy simulasi; yang diunduh tetap file placeholder lokal.');enqueue(selected,true,true);}
      if(button.hasAttribute('data-reader-copy-url')&&permitted('urls'))copy(new URL(states.get(selected).url,location.href).href);
    });
    window.addEventListener('pagehide',()=>{observer.disconnect();generation++;states.forEach(page=>{if(page.controller)demo.imageFinish(page.requestId,null,0,'cancelled');page.controller?.abort();if(page.blob)URL.revokeObjectURL(page.blob);});});
    summary();
  }


  function drawGraphEdges(viewport,scene,relations,schema=false){
    const svg=$('svg.graph-lines',scene);if(!svg)return;
    const ns='http://www.w3.org/2000/svg';svg.replaceChildren();
    const width=scene.offsetWidth,height=scene.offsetHeight;svg.setAttribute('viewBox','0 0 '+width+' '+height);svg.style.width=width+'px';svg.style.height=height+'px';
    const defs=document.createElementNS(ns,'defs'),marker=document.createElementNS(ns,'marker');
    const markerId='arrow-'+(viewport.getAttribute('aria-label')||'graph').replace(/[^a-z0-9]/gi,'-');
    marker.setAttribute('id',markerId);marker.setAttribute('viewBox','0 0 10 10');marker.setAttribute('refX','9');marker.setAttribute('refY','5');marker.setAttribute('markerWidth','6');marker.setAttribute('markerHeight','6');marker.setAttribute('orient','auto-start-reverse');
    const arrow=document.createElementNS(ns,'path');arrow.setAttribute('d','M 0 0 L 10 5 L 0 10 z');arrow.setAttribute('fill','var(--control)');marker.append(arrow);defs.append(marker);svg.append(defs);
    relations.forEach((edge,index)=>{
      const selector=schema?'data-schema':'data-node';
      const a=$('['+selector+'="'+edge.from+'"]',scene),b=$('['+selector+'="'+edge.to+'"]',scene);if(!a||!b||a.hidden||b.hidden)return;
      const ax=a.offsetLeft+a.offsetWidth,ay=a.offsetTop+a.offsetHeight/2,bx=b.offsetLeft,by=b.offsetTop+b.offsetHeight/2,mid=bx>ax?(ax+bx)/2:ax+16;
      const path=document.createElementNS(ns,'path');path.setAttribute('d','M '+ax+' '+ay+' H '+mid+' V '+by+' H '+bx);path.setAttribute('fill','none');path.setAttribute('stroke','var(--control)');path.setAttribute('stroke-width','2');path.setAttribute('marker-end','url(#'+markerId+')');if(edge.proposed)path.setAttribute('stroke-dasharray','6 4');
      const title=document.createElementNS(ns,'title');title.textContent=edge.from+' → '+edge.to+' · '+edge.label;path.append(title);svg.append(path);
      if(!schema){path.dataset.graphEdge=String(index);path.style.pointerEvents='stroke';}
    });
  }
  function graphViewport(viewport,scene,label){
    const stage=scene.parentElement;let zoom=1,fitMode=false;
    function apply(){
      if(!scene.offsetWidth)return;
      stage.style.position='relative';stage.style.width=scene.offsetWidth*zoom+'px';stage.style.height=scene.offsetHeight*zoom+'px';
      scene.style.position='absolute';scene.style.inset='0 auto auto 0';scene.style.transform='scale('+zoom+')';
      label.textContent=Math.round(zoom*100)+'%';
    }
    function fit(){fitMode=true;zoom=Math.max(.25,Math.min(1,viewport.clientWidth/Math.max(1,scene.offsetWidth)));apply();viewport.scrollTo(0,0);}
    function reset(){fitMode=false;zoom=1;apply();viewport.scrollTo(0,0);}
    let drag=null;
    viewport.addEventListener('pointerdown',event=>{if(event.pointerType!=='mouse'||event.button!==0||event.target.closest('button,a,input,path[data-graph-edge]'))return;drag={x:event.clientX,y:event.clientY,left:viewport.scrollLeft,top:viewport.scrollTop};viewport.setPointerCapture(event.pointerId);viewport.dataset.dragging='true';});
    viewport.addEventListener('pointermove',event=>{if(!drag)return;viewport.scrollLeft=drag.left-(event.clientX-drag.x);viewport.scrollTop=drag.top-(event.clientY-drag.y);});
    const release=()=>{drag=null;delete viewport.dataset.dragging;};viewport.addEventListener('pointerup',release);viewport.addEventListener('pointercancel',release);
    const observer=new ResizeObserver(()=>{if(fitMode)fit();else apply();});observer.observe(viewport);
    requestAnimationFrame(reset);
    return {zoom(delta){fitMode=false;zoom=Math.max(.25,Math.min(2,zoom+delta));apply();},fit,reset,apply};
  }
  function initFlow(){
    const root=$('[data-diagram]');if(!root)return;
    const viewport=$('[data-diagram-visual]',root),scene=$('[data-diagram-scene]',root);
    const nodes=$$('[data-node]',root),edges=$$('[data-edge]',root);
    const relations=edges.map(button=>({from:button.dataset.from,to:button.dataset.to,label:button.dataset.title,button}));
    const controls=graphViewport(viewport,scene,$('[data-zoom-label]',root));
    function draw(){drawGraphEdges(viewport,scene,relations);}
    function node(id){
      const target=nodes.find(n=>n.dataset.node===id);if(!target)return;
      nodes.forEach(n=>n.setAttribute('aria-pressed',String(n===target)));text('[data-inspector-title]',target.dataset.title,root);text('[data-inspector-description]',target.dataset.description,root);
      const link=$('[data-inspector-link]',root);link.href=target.dataset.href;link.textContent='Buka modul terkait';link.hidden=!permitted(linkCapability(link.href));
      const announcer=$('[data-announcer]');if(announcer)announcer.textContent='Komponen '+target.dataset.title+' dipilih.';
    }
    function edge(index){const item=relations[index];if(!item)return;text('[data-inspector-title]',item.label,root);text('[data-inspector-description]',item.button.dataset.description,root);const link=$('[data-inspector-link]',root);link.href=item.from==='reader'&&item.to==='api'?'endpoints.html':'runtime-logs.html';link.hidden=!permitted(item.from==='reader'?'monitoring':'logs');}
    function filter(){
      const query=$('[data-node-search]',root).value.trim().toLowerCase(),domain=$('[data-domain-filter]',root).value;
      nodes.forEach(n=>{n.hidden=!!(query&&!n.textContent.toLowerCase().includes(query)||domain&&n.dataset.domain!==domain);});
      $$('[data-select-node]',root).forEach(button=>{button.closest('li').hidden=nodes.find(n=>n.dataset.node===button.dataset.selectNode)?.hidden;});
      relations.forEach(item=>{item.button.closest('tr').hidden=!!(nodes.find(n=>n.dataset.node===item.from)?.hidden||nodes.find(n=>n.dataset.node===item.to)?.hidden);});
      text('[data-diagram-result]',nodes.filter(n=>!n.hidden).length+' node cocok',root);draw();controls.apply();
    }
    function mode(value){
      viewport.hidden=value!=='diagram';$('[data-diagram-list]',root).hidden=value!=='list';
      $$('[data-diagram-mode]',root).forEach(b=>b.setAttribute('aria-pressed',String(b.dataset.diagramMode===value)));
      requestAnimationFrame(()=>{controls.apply();draw();});
    }
    root.addEventListener('click',event=>{
      const n=event.target.closest('[data-node]'),select=event.target.closest('[data-select-node]'),e=event.target.closest('[data-edge]'),path=event.target.closest('[data-graph-edge]');
      if(n)node(n.dataset.node);if(select)node(select.dataset.selectNode);if(e)edge(Number(e.dataset.edge));if(path)edge(Number(path.dataset.graphEdge));
      const button=event.target.closest('button');if(!button)return;
      if(button.hasAttribute('data-zoom'))controls.zoom(Number(button.dataset.zoom));
      if(button.hasAttribute('data-fit'))controls.fit();
      if(button.hasAttribute('data-viewport-reset'))controls.reset();
      if(button.hasAttribute('data-pan')){const [x,y]=button.dataset.pan.split(',').map(Number);viewport.scrollBy(x,y);}
      if(button.hasAttribute('data-diagram-mode'))mode(button.dataset.diagramMode);
    });
    $('[data-node-search]',root).addEventListener('input',filter);
    $('[data-node-search]',root).addEventListener('keydown',event=>{if(event.key==='Enter'){event.preventDefault();const first=nodes.find(n=>!n.hidden);if(first)node(first.dataset.node);}});
    $('[data-domain-filter]',root).addEventListener('change',filter);
    function overlay(){const enabled=$('[data-overlay]',root).checked,stats=demo.summary(demo.state.environment,15,'reader');relations.forEach(item=>{const cell=item.button.closest('tr').children[2];cell.textContent=!enabled?'Overlay dimatikan; topology tetap.':item.from==='reader'&&item.to==='api'?nf.format(stats.count)+' request reader / 15 menit · '+simPercent(stats.rate)+' HTTP 5xx · p95 '+(stats.p95??'—')+' ms (demo)':'Topologi dokumentasi; telemetry edge ini belum disimulasikan.';});}
    $('[data-overlay]',root).addEventListener('change',overlay);document.addEventListener('prototype-simulation',overlay);overlay();
    window.addEventListener('prototype-layout',()=>{controls.apply();draw();});
    mode(innerWidth<1024?'list':'diagram');filter();requestAnimationFrame(draw);
  }
  function initSchema(){
    const root=$('[data-schema-browser]');if(!root)return;
    const panels=$$('[data-schema-panel]',root),tabs=$$('[data-schema-tab]',root),search=$('[data-schema-search]',root),proposed=$('[data-schema-proposed]',root);
    let active='A';
    const viewports=new Map();
    panels.forEach(panel=>{
      const viewport=$('.diagram-viewport',panel),scene=$('[data-diagram-scene]',panel);
      const relations=$$('tbody tr',panel).map(row=>{const names=$$('[data-select-schema]',row);return{from:names[0].dataset.selectSchema,to:names[1].dataset.selectSchema,label:row.children[1].textContent,proposed:panel.dataset.proposed==='true'};});
      const controls=graphViewport(viewport,scene,$('[data-schema-zoom-label]',root));viewports.set(panel.dataset.schemaPanel,{panel,viewport,scene,relations,controls});
    });
    function draw(){const item=viewports.get(active);if(item&&!item.panel.hidden){item.controls.apply();drawGraphEdges(item.viewport,item.scene,item.relations,true);}}
    function activate(letter){active=letter;if(['C','D'].includes(letter))proposed.checked=true;panels.forEach(panel=>{panel.hidden=panel.dataset.schemaPanel!==letter});tabs.forEach(tab=>tab.setAttribute('aria-pressed',String(tab.dataset.schemaTab===letter)));requestAnimationFrame(draw);}
    const destinations={COMICS:['comics.html','catalog'],CHAPTERS:['chapters.html','catalog'],GENRES:['genres.html','catalog'],PROFILES:['accounts.html','accounts'],HELPDESK_SUBMISSIONS:['helpdesk.html','helpdesk'],REQUEST_LOGS:['requests.html','monitoring'],RUNTIME_LOG_EVENTS:['runtime-logs.html','logs'],API_ENDPOINTS:['endpoints.html','monitoring'],HEALTH_PROBES:['health.html','monitoring'],ALERT_INCIDENTS:['alerts.html','monitoring'],ADMIN_AUDIT_EVENTS:['audit.html','audit']};
    function select(name){
      const panel=panels.find(p=>!p.hidden),table=$$('[data-schema]',panel).find(n=>n.dataset.schema===name);if(!table)return;
      $$('[data-schema]',root).forEach(node=>{node.dataset.selected=String(node===table)});
      text('[data-schema-title]',name,root);const fields=$('[data-schema-fields]',root);fields.replaceChildren($('ul',table).cloneNode(true));
      const notes=name==='CHAPTERS'?'images adalah JSONB array; images_are_invalid generated dan baca saja. Unique (comic_id, chapter_number).':name==='COMICS'?'Unique (source_name, slug). Nilai efektif memakai override editorial bila tersedia.':name==='PROFILES'?'profiles.id mempunyai relasi identitas logis dengan Auth, tanpa FK auth.users yang dibuktikan oleh model.':name.startsWith('USER_')?'user_id UUID pada model library bukan bukti FK ke profiles. Lihat relasi yang didefinisikan pada diagram.':panels.find(p=>!p.hidden).dataset.proposed==='true'?'Tabel/relasi usulan memerlukan migration. UUID aktor dan sesi adalah referensi logis; tidak ada nilai token di viewer.':'PK tidak null. Nullability field lain mengikuti migration terverifikasi; subset ini tidak merinci semuanya.';
      text('[data-schema-notes]',notes,root);
      const target=destinations[name],link=$('[data-schema-data-link]',root);link.hidden=!target||!permitted(target[1]);if(target)link.href=target[0];
      text('[data-announcer]','Tabel '+name+' dipilih.');
    }
    function filter(){
      const query=search.value.trim().toLowerCase();let count=0,firstPanel=null;
      panels.forEach(panel=>{
        const allowed=proposed.checked||panel.dataset.proposed!=='true';
        $$('[data-schema]',panel).forEach(node=>{const match=allowed&&(!query||node.dataset.search.toLowerCase().includes(query));node.hidden=!match;if(match){count++;if(!firstPanel)firstPanel=panel.dataset.schemaPanel;}});
      });
      if(query&&firstPanel&&!$$('[data-schema]:not([hidden])',viewports.get(active).panel).length)activate(firstPanel);
      if(!proposed.checked&&['C','D'].includes(active))activate('A');
      $('[data-schema-empty]',root).hidden=count!==0;text('[data-schema-result]',count+' tabel cocok',root);draw();
    }
    tabs.forEach(tab=>tab.addEventListener('click',()=>{activate(tab.dataset.schemaTab);filter();}));
    search.addEventListener('input',filter);proposed.addEventListener('change',filter);
    search.addEventListener('keydown',event=>{if(event.key==='Enter'){event.preventDefault();const node=$('[data-schema]:not([hidden])',viewports.get(active).panel);if(node)select(node.dataset.schema);}});
    root.addEventListener('click',event=>{
      const node=event.target.closest('[data-schema-select]'),relation=event.target.closest('[data-select-schema]');
      if(node)select(node.dataset.schemaSelect);if(relation)select(relation.dataset.selectSchema);
      const button=event.target.closest('button');if(!button)return;const controls=viewports.get(active).controls;
      if(button.hasAttribute('data-schema-zoom'))controls.zoom(Number(button.dataset.schemaZoom));
      if(button.hasAttribute('data-schema-fit'))controls.fit();
      if(button.hasAttribute('data-schema-reset'))controls.reset();
    });
    window.addEventListener('prototype-layout',draw);activate('A');filter();
  }


  function hydrateChapters(){
    const root=$('[data-list="chapters"]')||$('[data-list="preview-chapters"]');if(!root)return;const parent=$('[data-rows]',root),preview=root.dataset.list==='preview-chapters';
    $$('[data-created-chapter]',parent).forEach(row=>row.remove());
    const rows=$$('[data-record]',parent),template=rows[0]?.cloneNode(true);
    const parentArchived=(record('comic',selectedComic).status||comicPicker?.selectedOptions[0]?.dataset.status)==='archived';
    rows.forEach(row=>{const cells=$$('td',row),number=cells[1].textContent.trim(),data=record('chapter',selectedComic+'/chapter-'+number);row.dataset.kind='chapter';row.dataset.id=selectedComic+'/chapter-'+number;row.dataset.status=parentArchived?'archived':data.status|| (number==='3'?'archived':'active');row.dataset.excluded=String(!!record('comic',selectedComic)._created);const title=$('a',cells[0]);if(title)title.textContent=data.title||'Chapter '+number;const badge=$('.status',row);if(badge){badge.textContent=row.dataset.status;badge.className=row.dataset.status==='archived'?tones.neutral:tones.success;}$$('a[href]',row).forEach(link=>{const url=new URL(link.href);url.searchParams.set('id',selectedComic);link.href=url;});});
    Object.entries(model.records).forEach(([key,data])=>{
      if(!template||!key.startsWith('chapter:'+selectedComic+'/')||!data._created)return;
      const row=template.cloneNode(true),number=String(data.chapter_number),cells=$$('td',row);row.dataset.createdChapter='true';row.dataset.excluded='false';row.dataset.id=key.slice(8);row.dataset.search='Chapter '+number+' '+data.title;row.dataset.name=data.title;row.dataset.count=number;row.dataset.status=parentArchived?'archived':data.status||'active';
      if(preview)cells[0].textContent=data.title;else $('a',cells[0]).textContent=data.title;cells[1].textContent=number;cells[2].textContent=preview?'Belum tersedia':data.release_date;if(!preview)cells[3].textContent='Belum tersedia';
      $$('a[href]',row).forEach(link=>{const url=new URL(link.href);url.searchParams.set('id',selectedComic);url.searchParams.set('chapter',number);link.href=url;});parent.append(row);
    });
  }
  comicPicker?.addEventListener('change',()=>{hydrateChapters();controllers.forEach(controller=>controller.refresh(false));});
  // Keep the active incident count visible in the collapsed navigation.
  $$('.sidebar a[href="alerts.html"],#mobile-navigation a[href="alerts.html"]').forEach(link=>{if(!$('.nav-count',link)){const count=document.createElement('span');count.className='nav-count';count.textContent='1';link.append(count);}});

  function simulationStale(environment=demo.state.environment){return (!environment||environment===demo.state.environment)&&['gap','down'].includes(demo.state.scenario);}
  function simulationRange(){const value=Number($('[data-list] select[name="range"]')?.value||params.get('range')||15);return [5,15,60,1440].includes(value)?value:15;}
  function simulationEnvironment(){return $('[data-overview-environment]')?.value||$('[data-list] select[name="environment"]')?.value||params.get('environment')||demo.state.environment;}
  function simPercent(value){return value==null?'Belum tersedia':new Intl.NumberFormat('id-ID',{maximumFractionDigits:2}).format(value*100)+'%';}
  function simAnchor(file,query,label){const a=document.createElement('a');a.textContent=label;a.dataset.recordLink='';const url=new URL(file,location.href);Object.entries(query).forEach(([key,value])=>{if(value!=null&&value!=='')url.searchParams.set(key,String(value));});a.href=url;return a;}
  function simBadge(label,tone){const el=document.createElement('span');el.className=tones[tone]||tones.neutral;el.textContent=label;return el;}
  function simCell(value){const td=document.createElement('td');td.append(value instanceof Node?value:document.createTextNode(String(value??'Belum tersedia')));return td;}
  const simulationRowCache=new WeakMap();
  function simulationRows(kind,items){
    const root=$('[data-list="'+kind+'"]');if(!root)return;
    const parent=$('[data-rows]',root);if(!simulationRowCache.has(parent)){parent.replaceChildren();simulationRowCache.set(parent,new Map());}
    const cache=simulationRowCache.get(parent),included=new Set();
    items.slice().reverse().forEach(item=>{
      included.add(item.id);let row=cache.get(item.id);const signature=item.id+'|'+item.status+'|'+item.outcome+'|'+item.pending+'|'+item.updated;
      if(!row){row=document.createElement('tr');row.dataset.record='';row.dataset.id=item.id;cache.set(item.id,row);}
      if(row.dataset.demoSignature!==signature){row.dataset.demoSignature=signature;row.replaceChildren();Object.assign(row.dataset,{environment:item.environment||'production',timestamp:String(item.at||item.since),initialIndex:String(-(item.seq||item.since||0)),status:String(item.status??''),request:item.request||item.id,run:item.run||'',operation:item.operation||'',instance:item.instance||'demo-api-01',search:[item.id,item.route,item.message,item.request,item.run,item.operation,item.title,item.rule,item.status,item.outcome,item.environment].filter(Boolean).join(' ')});
        if(kind==='requests'){
          Object.assign(row.dataset,{method:item.method,endpoint:item.endpoint||'demo-admin',status:item.status==null?'none':Math.floor(item.status/100)+'xx',outcome:item.outcome,duration:String(item.duration||0),scope:item.scope});
          const identity=document.createElement('div');identity.append(document.createTextNode(simTime(item.at)+' · '+item.environment),document.createElement('br'),simAnchor('request-detail.html',{id:item.id},item.id));
          const code=document.createElement('code');code.textContent=item.method+' '+item.route;
          [identity,code,simBadge((item.status??'Tanpa HTTP')+' · '+item.outcome,item.pending?'neutral':item.status>=500||item.outcome==='decode_error'?'danger':item.status>=400?'warning':'success'),item.duration==null?'Belum selesai':nf.format(item.duration)+' ms',item.environment+' / '+item.scope,item.run||item.operation||'Reader'].forEach(value=>row.append(simCell(value)));
        }else if(kind==='runtime'){
          Object.assign(row.dataset,{level:item.level,kind:item.kind,logger:item.logger,request:item.request||''});
          const identity=document.createElement('span');identity.textContent=simTime(item.at)+' / '+simTime(item.received);
          [identity,simBadge(item.level+' · '+item.kind,item.level==='ERROR'?'danger':item.level==='WARNING'?'warning':'neutral'),item.logger+' / '+item.environment,simAnchor('runtime-log-detail.html',{id:item.id},item.message),item.request?simAnchor('request-detail.html',{id:item.request},item.request):'Tidak ada request ID'].forEach(value=>row.append(simCell(value)));
        }else if(kind==='probes'){
          [simTime(item.at)+' · '+item.environment,simBadge(item.status,item.status==='success'?'success':item.status==='failed'?'danger':'neutral'),item.http==null?item.status==='unknown'?'Hasil tidak diterima':'Koneksi gagal / timeout':String(item.http),item.status==='unknown'?'Belum tersedia':item.duration+' ms'].forEach(value=>row.append(simCell(value)));
        }else if(kind==='alerts'){
          row.dataset.name=item.title;row.dataset.status=item.status;
          [simAnchor('alert-detail.html',{id:item.id,environment:item.environment,range:5},item.title),simBadge(item.status,item.status==='resolved'?'success':item.status==='firing'?'danger':item.status==='unknown'?'warning':'neutral'),item.rule+' / '+item.environment,simTime(item.since),simAnchor('alert-detail.html',{id:item.id,environment:item.environment,range:5},'Periksa')].forEach(value=>row.append(simCell(value)));
        }
      }
      parent.append(row);
    });
    [...cache].forEach(([id,row])=>{if(!included.has(id)){row.remove();cache.delete(id);}});
  }
  function renderSimEndpoint(endpoint){
    const definition=demo.definitions.find(d=>d.id===endpoint);if(!definition)return;
    const environment=params.get('environment')||demo.state.environment,minutes=simulationRange(),scope=params.get('scope')||null,stats=demo.summary(environment,minutes,scope,endpoint),buckets=demo.buckets(environment,minutes,12,scope,endpoint);
    text('[data-endpoint-route] code',definition.route);text('[data-endpoint-method]',definition.method);text('[data-endpoint-count]',nf.format(stats.count));text('[data-endpoint-samples]',nf.format(stats.count));text('[data-endpoint-errors]',stats.count?nf.format(stats.errors):'Belum tersedia');text('[data-endpoint-p95]',stats.p95==null?'Belum tersedia':nf.format(stats.p95)+' ms');
    $$('.bar-chart > div').forEach((bar,i)=>{bar.style.height=(buckets[i].count/Math.max(1,...buckets.map(b=>b.count))*140)+'px';bar.title=simTime(buckets[i].at)+': '+buckets[i].count+' request';});
    const panel=$('.bar-chart')?.closest('.panel');if(panel){text('.chart-caption',minutes+' menit jam demo · '+nf.format(stats.count)+' request · '+environment,panel);$$('details tbody tr',panel).forEach((row,i)=>{row.children[0].textContent=simTime(buckets[i].at);row.lastElementChild.textContent=nf.format(buckets[i].count);});}
    const distribution=$$('h2').find(h=>h.textContent==='Distribusi status')?.closest('.panel');if(distribution){text('.panel-header p',nf.format(stats.count)+' respons sesi demo',distribution);const values=[stats.statuses.success,stats.client,stats.errors];$$('dd',distribution).slice(0,3).forEach((dd,i)=>dd.textContent=stats.count?nf.format(values[i]):'Belum tersedia');simExtra(distribution,'Tanpa status HTTP',nf.format(stats.statuses.none));}
    const coverage=$$('h2').find(h=>h.textContent==='Cakupan pengukuran')?.closest('.panel');if(coverage){dd(coverage,'p50 / p99',stats.p50==null?'Belum tersedia':nf.format(stats.p50)+' ms / '+nf.format(stats.p99)+' ms');dd(coverage,'In-flight',String(stats.inFlight));}
    const histogram=[0,0,0,0];stats.rows.forEach(row=>{if(row.duration!=null)histogram[row.duration<=100?0:row.duration<=500?1:row.duration<=2000?2:3]++;});$$('[data-histogram-body] tr').forEach((row,i)=>row.lastElementChild.textContent=nf.format(histogram[i]));
    linksTo('requests.html').forEach(link=>{link.href='requests.html?endpoint='+endpoint+'&environment='+environment+'&range='+minutes+(scope?'&scope='+scope:'');});
  }
  function renderSimHealth(){
    const environment=simulationEnvironment(),minutes=simulationRange(),health=demo.health(environment,minutes);
    if(pageFile==='health'){
      $$('.mini-metric strong').forEach((el,i)=>el.textContent=[simPercent(health.availability),simPercent(health.coverage),nf.format(health.scheduled),nf.format(health.known)][i]);
      const summary=$('[data-page-content] > .notice');if(summary)summary.textContent='Jam demo: '+health.success+' sukses / '+health.known+' hasil. '+health.scheduled+' jadwal; coverage '+simPercent(health.coverage)+'. Slot unknown tidak dianggap sukses.';
      const status=$('[data-probe-result] .status');if(status){originalStatuses.delete(status);status.textContent=health.service==='up'?'Terjangkau (demo)':health.service==='down'?'Tidak terjangkau (demo)':'Unknown';status.className=health.service==='up'?tones.success:health.service==='down'?tones.danger:tones.neutral;}
      text('[data-probe-time]',health.rows.length?simTime(health.rows.at(-1).at,true)+' UTC+7 (jam demo)':'Belum ada probe');
      const dependency=$$('h2').find(h=>h.textContent==='Layanan dan dependensi')?.closest('.panel');if(dependency)dd(dependency,'Database','Belum diukur; simulator hanya menyediakan probe proses API');
      const pipeline=$$('h2').find(h=>h.textContent==='Pipeline dan batas')?.closest('.panel');if(pipeline){dd(pipeline,'Collector',health.pipeline==='up'?'Ingest demo aktif':health.pipeline==='down'?'Ingest demo terputus':'Belum ada data');dd(pipeline,'Koneksi browser','Sesi browser lokal; bukan SSE produksi');}
      simulationRows('probes',health.rows);
    }
    if(pageFile==='runtime-logs')$$('.mini-metric strong').forEach((el,i)=>el.textContent=[health.service==='up'?'Terjangkau':health.service==='down'?'Tidak terjangkau':'Unknown',health.pipeline==='up'?'Ingest aktif':health.pipeline==='down'?'Terputus':'Unknown','Demo sesi '+demo.state.id,'INFO / WARNING / ERROR'][i]);
  }
  function prepareSimulationViews(){
    for(const kind of ['requests','runtime']){
      const root=$('[data-list="'+kind+'"]');if(!root)continue;const form=$('[data-filters]',root);
      const headers=kind==='requests'?['Jam demo / request ID','Method / route template','HTTP / outcome','Durasi','Environment / scope','Run / operation']:['Occurred / received (UTC+7)','Level / jenis','Logger / environment','Pesan tersanitasi','Request terkait'];
      const head=$('thead tr',root);head.replaceChildren(...headers.map(label=>{const th=document.createElement('th');th.scope='col';th.textContent=label;return th;}));
      for(const [name,label] of [['run','Run ID'],['operation','Operation ID']]){const field=document.createElement('label');field.className='filter-field';const span=document.createElement('span');span.textContent=label;const input=document.createElement('input');input.className='numeric-filter';input.name=name;input.placeholder=label+' persis';input.maxLength=120;input.value=params.get(name)||'';field.append(span,input);form.append(field);}
      const field=document.createElement('label');field.className='filter-field';const label=document.createElement('span');label.textContent='Rentang jam demo';const select=document.createElement('select');select.name='range';[5,15,60,1440].forEach(value=>{const option=document.createElement('option');option.value=String(value);option.textContent=value+' menit';option.defaultSelected=value===15;select.append(option);});select.value=params.get('range')||'15';field.append(label,select);form.append(field);
      const options=kind==='requests'?{scope:['admin_operation'],outcome:['in_flight','cancelled','decode_error'],status:['none']}:{};
      Object.entries(options).forEach(([name,values])=>values.forEach(value=>{const option=document.createElement('option');option.value=value;option.textContent=value;form.elements[name].append(option);}));
      if(kind==='runtime'){const logger=form.elements.logger;['app.demo'].forEach(value=>{const option=document.createElement('option');option.value=value;option.textContent=value;logger.append(option);});}
      const history=document.createElement('button');history.type='button';history.className='button';history.textContent='Tampilkan riwayat';history.dataset.demoHistory='';$('[data-feed-bar] .actions').append(history);history.addEventListener('click',()=>{root.dataset.demoClear='0';root.dataset.demoRendered='';refreshSimulation();});
      form.addEventListener('change',event=>{if(event.target.name==='range'){root.dataset.demoRendered='';refreshSimulation();}});
      root.addEventListener('focusin',event=>{if(event.target.closest('[data-record]')&&!feedPaused){feedPaused=true;feedStatus();}});
      text('.panel-header p','Riwayat sesi bersama, maksimal 1.000 event. Pause hanya menahan tampilan.',root);
      text('[data-feed-inject]',kind==='runtime'?'Tambah lifecycle event':'Kirim request demo');
    }
    const ruleSelect=$('[data-list="alerts"] select[name="status"]');if(ruleSelect){const option=document.createElement('option');option.value='unknown';option.textContent='unknown';ruleSelect.append(option);}
  }
  function initSimulation(){
    if(pageFile==='login')return;
    const consolePanel=document.createElement('details');consolePanel.className='panel demo-console mb-6';consolePanel.dataset.simConsole='';consolePanel.open=innerWidth>=1024&&['monitoring','logs','preview'].includes(document.body.dataset.capability);
    const summary=document.createElement('summary');summary.className='panel-header';const title=document.createElement('strong');title.textContent='Demo lokal terhubung';const status=document.createElement('span');status.className='status neutral';status.dataset.simStatus='';summary.append(title,status);consolePanel.append(summary);
    const content=document.createElement('div');content.className='content-pad';const controls=document.createElement('div');controls.className='actions';
    function select(label,attribute,options){const field=document.createElement('label');field.className='filter-field';const span=document.createElement('span');span.textContent=label;const input=document.createElement('select');input.setAttribute(attribute,'');Object.entries(options).forEach(([value,label])=>{const option=document.createElement('option');option.value=value;option.textContent=label;input.append(option);});field.append(span,input);controls.append(field);return input;}
    const environment=select('Environment simulasi','data-sim-environment',{production:'Production',staging:'Staging'}),scenario=select('Skenario','data-sim-scenario',demo.scenarios);
    function button(label,action,primary=false){const b=document.createElement('button');b.type='button';b.className=primary?'button primary':'button';b.textContent=label;b.dataset.simAction=action;controls.append(b);return b;}
    button('Mulai demo','toggle',true);button('Jalankan skenario','scenario');button('Langkah 30 detik','step');button('Reset demo','reset');content.append(controls);
    const note=document.createElement('p');note.className='text-xs mt-3';note.dataset.simClock='';content.append(note);const warning=document.createElement('p');warning.className='notice warning mt-3';warning.dataset.simWarning='';warning.hidden=true;content.append(warning);consolePanel.append(content);
    ($('.page-heading')||$('main > .mb-6')||$('main > div')).after(consolePanel);
    if(['production','staging'].includes(params.get('environment')))demo.state.environment=params.get('environment');
    environment.value=demo.state.environment;scenario.value=demo.state.scenario;
    scenario.addEventListener('change',()=>demo.scenario(scenario.value));environment.addEventListener('change',()=>{params.set('environment',environment.value);setParam('environment',environment.value);const overview=$('[data-overview-environment]');if(overview){overview.value=environment.value;overview.dispatchEvent(new Event('change'));}else demo.environment(environment.value);});
    consolePanel.addEventListener('click',event=>{const b=event.target.closest('[data-sim-action]');if(!b)return;const action=b.dataset.simAction;if(action==='toggle')demo.running(!demo.state.running);if(action==='step')demo.advance();if(action==='scenario'){if(demo.state.scenario==='healthy'){demo.advance(10);demo.advance(3);notify('Pemulihan dijalankan 6 menit 30 detik jam demo: window gangguan berlalu dan hold recovery dievaluasi.');}else{demo.advance(3);notify('Skenario dijalankan selama 90 detik jam demo. Telusuri request, log dan insiden terkait.');}}if(action==='reset')$('[data-reset-demo]')?.click();});
    const popup=$('#request-detail');if(popup){const note=$('.dialog-note',popup);if(note)note.textContent='Snapshot dari sesi demo yang sama dengan halaman Request log. ID request membuka observasi dan runtime terkait.';const b=document.createElement('button');b.type='button';b.className='button';b.textContent='Kirim request demo';b.dataset.popupRequest='';b.addEventListener('click',()=>demo.once());const actions=document.createElement('div');actions.className='actions mt-4';const link=$('[data-overview-link="requests.html"]',popup);if(link){link.classList.remove('mt-4');actions.append(link);}actions.append(b);popup.append(actions);}
    const feedUpdate=()=>{
      if(!feedRoot)return;const events=feedRoot.dataset.list==='runtime'?demo.state.runtime:demo.state.requests;
      if(!feedPaused||!feedRoot.dataset.demoRendered){const minutes=Number($('select[name="range"]',feedRoot)?.value||15),cutoff=Number(feedRoot.dataset.demoClear||0);simulationRows(feedRoot.dataset.list,events.filter(e=>e.at>demo.state.now-minutes*60000&&e.seq>cutoff));feedRoot.dataset.demoRendered='true';feedRoot.dataset.demoCursor=String(Math.max(0,...events.map(e=>e.seq)));if($('[data-autoscroll]')?.checked&&!feedPaused)$('[data-rows] [data-record]',feedRoot)?.scrollIntoView({block:'nearest'});}
      feedStatus();
    };
    refreshSimulation=()=>{
      text('[data-sim-status]',(demo.state.running?'Berjalan':'Dijeda')+' · '+demo.scenarios[demo.state.scenario]);text('[data-sim-action="toggle"]',demo.state.running?'Jeda demo':'Mulai demo');scenario.value=demo.state.scenario;environment.value=demo.state.environment;
      text('[data-sim-clock]','Jam demo '+simTime(demo.state.now,true)+' UTC+7 · 1 tick = 30 detik simulasi / 2 detik nyata. Sesi '+demo.state.id+' · batas 1.000 event per feed · '+demo.state.retainedDrops+' event keluar dari retensi.'+(store.persistent?'':' Storage ditolak: data hanya bertahan pada halaman ini.'));
      const partial=demo.summary(demo.state.environment,5,'reader').coverage<.8;warning.hidden=!simulationStale()&&!partial;warning.textContent=demo.state.scenario==='down'?'API demo tidak terjangkau. Probe/collector independen tetap mencatat kegagalan; tidak mengarang access log API.':demo.state.scenario==='gap'?'Telemetry demo terputus. Snapshot terakhir dipertahankan; status unknown, bukan pulih.':'Coverage demo parsial; evaluator dapat menjadi unknown sampai sampel cukup.';
      feedUpdate();renderSimHealth();simulationRows('alerts',demo.state.incidents);controllers.forEach(controller=>controller.refresh(false));
      if(endpointPicker)renderSimEndpoint(endpointPicker.value);if(requestPicker){const item=demo.state.requests.find(i=>i.id===requestPicker.value);if(item)renderSimRequest(item);}if(runtimePicker){const item=demo.state.runtime.find(i=>i.id===runtimePicker.value);if(item)renderSimRuntime(item);}
      if(alertPicker){const selected=alertPicker.value;alertPicker.replaceChildren(...demo.state.incidents.slice().reverse().map(item=>{const option=document.createElement('option');option.value=item.id;option.textContent=item.title+' · '+item.status;return option;}));if([...alertPicker.options].some(o=>o.value===selected))alertPicker.value=selected;alertPicker.disabled=!alertPicker.options.length;if(alertPicker.value)renderSimIncident(demo.state.incidents.find(i=>i.id===alertPicker.value));}
      if(pageFile==='alert-detail'&&demo.state.incidents.length&&consolePanel.dataset.emptyIncident==='true'){chosenState='normal';const control=$('[data-state-control]');if(control)control.value='normal';delete consolePanel.dataset.emptyIncident;}
      overviewSimulationRefresh?.();renderMonitoringContext();stateView(chosenState);document.dispatchEvent(new Event('prototype-simulation'));
      $$('.nav-count').forEach(el=>el.textContent=String(demo.state.incidents.filter(i=>['pending','firing','unknown'].includes(i.status)).length));
    };
    feedRoot?.addEventListener('change',()=>feedStatus());
    refreshSimulation();
    if(pageFile==='alert-detail'&&!demo.state.incidents.length){consolePanel.dataset.emptyIncident='true';stateView('empty');text('[data-state-text]','Belum ada insiden pada sesi ini. Jalankan skenario gangguan melalui panel demo di atas.');}
    if(pageFile==='audit-detail'&&!model.audit.length){stateView('empty');text('[data-state-text]','Belum ada audit pada sesi demo ini. Simpan perubahan katalog, akun atau helpdesk terlebih dahulu.');}
    let timer;function resume(){clearInterval(timer);if(document.hidden)return;demo.catchUp();timer=setInterval(()=>{if(demo.state.running)demo.advance();},2000);}document.addEventListener('visibilitychange',()=>{if(document.hidden)clearInterval(timer);else resume();});window.addEventListener('pagehide',()=>{clearInterval(timer);demo.persist();});resume();
  }

  function initOverview() {
    const root=$('[data-overview]');if(!root)return;
    const environment=$('[data-overview-environment]'),search=$('[data-overview-search]'),sort=$('[data-overview-sort]');
    const table=$('.endpoint-table',root),body=$('tbody',table),graph=$('.chart svg',root),disclosure=$('.chart-data-disclosure',root);
    const endpoints=$$('tr',body).map((row,index)=>({row,index,route:$('code',row).textContent}));
    let cutoff=demo.state.now;const ranges=[5,15,60,1440];
    let range=ranges.includes(Number(params.get('range')))?Number(params.get('range')):15;
    let chart=['traffic','latency','status'].includes(params.get('chart'))?params.get('chart'):'traffic';
    environment.value=['production','staging'].includes(params.get('environment'))?params.get('environment'):demo.state.environment;
    search.value=(params.get('q')||'').slice(0,200);sort.value=['priority','count','errors','p95','name'].includes(params.get('sort'))?params.get('sort'):'priority';
    const time=stamp=>new Intl.DateTimeFormat('id-ID',{timeZone:'Asia/Bangkok',hour:'2-digit',minute:'2-digit',hourCycle:'h23'}).format(stamp).replace('.',':');
    const date=stamp=>new Intl.DateTimeFormat('id-ID',{timeZone:'Asia/Bangkok',day:'numeric',month:'short',year:'numeric'}).format(stamp);
    const percent=(value,total)=>total?new Intl.NumberFormat('id-ID',{maximumFractionDigits:2}).format(value/total*100)+'%':'Belum tersedia';
    function value(key,content,unit=''){const el=$('[data-overview-value="'+key+'"]');el.replaceChildren(document.createTextNode(content));if(unit){const small=document.createElement('small');small.textContent=unit;el.append(small);}}
    function badge(el,label,tone='neutral'){if(!el)return;originalStatuses.delete(el);el.textContent=label;el.className=tones[tone]||tones.neutral;}
    const empty=document.createElement('div');empty.className='empty-state';empty.hidden=true;empty.setAttribute('data-overview-empty','');const emptyText=document.createElement('p');emptyText.textContent='Tidak ada endpoint yang cocok. Hapus pencarian untuk melihat inventaris.';const resetSearch=document.createElement('button');resetSearch.type='button';resetSearch.className='button mt-3';resetSearch.dataset.overviewReset='';resetSearch.textContent='Reset pencarian';empty.append(emptyText,resetSearch);table.closest('.table-region').after(empty);
    function draw(buckets,total,errors,client,period,hasData){
      const labels={traffic:['Trafik & respons server','Request / bucket','5xx / bucket'],latency:['Latensi respons server','p95 / bucket (ms)',''],status:['Distribusi status HTTP','Respons / bucket','']};
      text('#traffic-title',labels[chart][0]);text('.traffic-panel .panel-header p',period+' · '+environment.value+' · data contoh lokal');
      const ns='http://www.w3.org/2000/svg';graph.replaceChildren();
      function svg(tag,attrs={},content){const el=document.createElementNS(ns,tag);Object.entries(attrs).forEach(([key,val])=>el.setAttribute(key,String(val)));if(content!==undefined)el.textContent=content;graph.append(el);return el;}
      svg('title',{id:'svg-title'},labels[chart][0]+' · '+period+' · '+environment.value+' (contoh)');svg('desc',{id:'svg-desc'},hasData?nf.format(total)+' request, '+nf.format(errors)+' respons 5xx. Tabel data grafik memuat angka contoh.':'Belum ada observasi pada environment dan rentang ini; availability serta latensi tidak diketahui.');
      const latency=buckets.map(b=>b.p95||0);
      const clients=buckets.map(b=>b.client||0);
      const max=Math.max(1,...(chart==='latency'?latency:buckets.map(b=>b.count))),top=Math.ceil(max/4/100)*400||4,right=Math.max(4,Math.ceil(Math.max(...buckets.map(b=>b.errors))/4)*4);
      for(let i=0;i<=4;i++){const y=205-i*38.5;svg('line',{class:'grid-line',x1:54,y1:y,x2:640,y2:y});svg('text',{x:45,y:y+4,'text-anchor':'end'},nf.format(top*i/4));if(chart==='traffic')svg('text',{x:653,y:y+4},nf.format(right*i/4));}
      svg('text',{x:54,y:23},labels[chart][1]);svg('text',{x:640,y:23,'text-anchor':'end'},labels[chart][2]);
      const points=[];
      buckets.forEach((bucket,i)=>{
        const x=54+i*586/Math.max(1,buckets.length-1),y=205-(chart==='latency'?latency[i]:bucket.count)/top*154;
        points.push(x+','+y);
        if(chart==='traffic'){const bar=svg('rect',{class:'error-bar',x:x-2.5,y:205-bucket.errors/right*154,width:5,height:bucket.errors/right*154});const title=document.createElementNS(ns,'title');title.textContent=nf.format(bucket.count)+' request · '+nf.format(bucket.errors)+' HTTP 5xx';bar.append(title);}
        if(chart==='status'){let offset=205;[Math.max(0,bucket.count-bucket.errors-clients[i]),clients[i],bucket.errors].forEach((n,j)=>{const h=n/top*154;offset-=h;svg('rect',{x:x-7,y:offset,width:14,height:h,fill:['var(--chart)','var(--warning)','var(--danger)'][j]});});}
        if(i===0||i===buckets.length-1||i%Math.max(1,Math.floor(buckets.length/5))===0)svg('text',{x,y:235,'text-anchor':'middle'},time(cutoff-range*60000+i*range*60000/buckets.length));
      });
      if(chart!=='status'){svg('polygon',{class:'traffic-fill',points:'54,205 '+points.join(' ')+' 640,205'});svg('polyline',{class:'traffic-line',points:points.join(' ')});if(chart==='traffic')$$('.error-bar',graph).forEach(el=>graph.append(el));}
      if(!hasData)svg('text',{x:350,y:116,'text-anchor':'middle'},'Belum ada sampel');
      const legend=$('.chart-legend',root);legend.replaceChildren();
      const names=chart==='traffic'?['Request selesai','HTTP 5xx']:chart==='latency'?['p95 per bucket (contoh)']:['2xx','4xx','5xx'];
      names.forEach((name,i)=>{const label=document.createElement('span'),mark=document.createElement('i');mark.className=chart==='traffic'&&i===1?'legend-bar':'legend-line';mark.setAttribute('aria-hidden','true');if(chart==='status')mark.style.background=['var(--chart)','var(--warning)','var(--danger)'][i];label.append(mark,document.createTextNode(name));legend.append(label);});
      const head=$('thead tr',disclosure),rows=$('tbody',disclosure);head.replaceChildren();rows.replaceChildren();
      const columns=chart==='latency'?['Waktu UTC+7','p95 (ms)']:chart==='status'?['Waktu UTC+7','2xx','4xx','5xx']:['Waktu UTC+7','Request selesai','HTTP 5xx'];
      columns.forEach(name=>{const th=document.createElement('th');th.scope='col';th.textContent=name;head.append(th);});
      buckets.forEach((bucket,i)=>{const tr=document.createElement('tr'),values=[time(cutoff-range*60000+i*range*60000/buckets.length),...(chart==='latency'?[hasData?nf.format(latency[i]):'Belum tersedia']:chart==='status'?[nf.format(Math.max(0,bucket.count-bucket.errors-clients[i])),nf.format(clients[i]),nf.format(bucket.errors)]:[nf.format(bucket.count),nf.format(bucket.errors)])];values.forEach(v=>{const td=document.createElement('td');td.textContent=v;tr.append(td);});rows.append(tr);});
      text('.chart-foot span',hasData?nf.format(total)+' request · '+nf.format(errors)+' respons 5xx · '+buckets.length+' bucket contoh':'Belum ada sampel; metrik tidak diketahui',root);
    }
    function render(sync=false,announce=false){
      cutoff=demo.state.now;
      const env=environment.value,stats=demo.summary(env,range,'reader'),health=demo.health(env,range),hasData=stats.count>0,stale=simulationStale(env),period=range===60?'1 jam':range===1440?'24 jam':range+' menit';
      const total=stats.count,errors=stats.errors,buckets=demo.buckets(env,range,range===5?5:15,'reader');
      value('count',nf.format(total));value('errors',hasData?simPercent(stats.rate).replace('%',''):'Belum tersedia',hasData?'%':'');value('p95',stats.p95==null?'Belum tersedia':nf.format(stats.p95),stats.p95==null?'':'ms');value('availability',health.availability==null?'Belum tersedia':simPercent(health.availability).replace('%',''),health.availability==null?'':'%');
      const details=$$('.metric p',root);details[0].textContent=new Intl.NumberFormat('id-ID',{maximumFractionDigits:2}).format(stats.rps)+' req/s · reader';details[1].textContent=nf.format(errors)+' dari '+nf.format(total)+' respons';details[2].textContent=hasData?'p50 '+nf.format(stats.p50)+' ms · p99 '+nf.format(stats.p99)+' ms':'Quantile belum tersedia';details[3].textContent=health.success+'/'+health.known+' probe · coverage '+simPercent(health.coverage);
      const notes=$$('.metric-notes > span');[stats.inFlight+' request in-flight','HTTP 4xx: '+(hasData?percent(stats.client,total):'Belum tersedia'),'Quantile dari event demo','Coverage metrik: '+simPercent(stats.coverage)+(stale?' · stale':'')].forEach((v,i)=>notes[i].textContent=v);
      text('.period-note > span:last-child','Zona waktu UTC+7 · jam simulasi',root);
      text('.pipeline-strip > span:last-child','Metrik berasal dari event demo yang masih tersimpan',root);
      text('[data-overview-period]',date(cutoff-range*60000)+' '+time(cutoff-range*60000)+' sampai '+time(cutoff)+' · observed_at '+(demo.state.lastReceived[env]?simTime(demo.state.lastReceived[env]):'Belum tersedia')+' UTC+7 · jam demo');
      const incident=demo.state.incidents.findLast(i=>i.environment===env&&i.status!=='resolved'),banner=$('.incident',root);banner.hidden=!incident;
      if(incident){text('#incident-title',incident.title);text('.incident-eyebrow .status',incident.status+' · Demo',banner);text('.incident-eyebrow > span:last-child','Sejak '+simTime(incident.since),banner);text('.incident-body > p',incident.value+' · '+incident.rule+' · state ditentukan evaluator sesi demo',banner);text('#incident-detail-title',incident.title);text('#incident-detail > p:first-of-type',incident.status+' · '+env+' · '+incident.id);dd($('#incident-detail'),'Rule',incident.rule);dd($('#incident-detail'),'Nilai pemicu',incident.value);dd($('#incident-detail'),'Kondisi bertahan','Sejak '+simTime(incident.since)+' jam demo');}
      badge($('.pipeline-strip .status',root),stale?'Pipeline demo: snapshot stale':'Pipeline demo: '+(hasData?'terhubung':'belum ada data'),stale||!hasData?'neutral':'success');
      const statuses=$$('.service-status .status',root);badge(statuses[0],health.service==='up'?'Terjangkau':health.service==='down'?'Tidak terjangkau':'Unknown',health.service==='up'?'success':health.service==='down'?'danger':'neutral');badge(statuses[1],'Belum diukur (demo)','neutral');badge(statuses[2],stale?'Snapshot; status unknown':hasData?'Ingest demo aktif':'Belum ada data',stale||!hasData?'neutral':'success');badge(statuses[3],demo.state.running?'Demo browser berjalan':'Demo browser dijeda','neutral');
      const q=search.value.trim().toLowerCase();
      const sorted=endpoints.map(e=>({...e,stats:demo.summary(env,range,'reader','ep'+(e.index+1))})).sort((a,b)=>sort.value==='name'?a.route.localeCompare(b.route):sort.value==='count'?b.stats.count-a.stats.count:sort.value==='errors'?b.stats.errors-a.stats.errors:sort.value==='p95'?(b.stats.p95||0)-(a.stats.p95||0):a.index-b.index);let visible=0;
      sorted.forEach(e=>{const row=e.row,cells=row.children,s=e.stats;row.hidden=!!q&&!e.route.toLowerCase().includes(q);if(!row.hidden)visible++;body.append(row);cells[1].textContent=nf.format(s.count);cells[2].replaceChildren(document.createTextNode(s.count?percent(s.errors,s.count):'Belum tersedia'));const small=document.createElement('small');small.className='muted';small.textContent=nf.format(s.errors)+' respons';cells[2].append(document.createElement('br'),small);cells[3].textContent=s.p95==null?'Belum tersedia':nf.format(s.p95)+' ms';cells[2].classList.toggle('danger-text',s.errors>0);cells[2].classList.toggle('muted',!s.count);cells[3].classList.toggle('warning-text',s.p95>2000);cells[3].classList.toggle('muted',!s.count);
        const label=stale?'Snapshot; unknown':!s.count?'Belum ada trafik':s.errors?'Ada 5xx':s.p95>2000?'Latensi tinggi':'Dalam ambang';badge($('.status',row),label,stale||!s.count?'neutral':s.errors?'danger':s.p95>2000?'warning':'success');
        const popup=$('#endpoint-'+e.index);dd(popup,'Periode contoh',period+' · '+env+' · jam demo');dd(popup,'Request selesai',nf.format(s.count));dd(popup,'Respons 5xx',s.count?nf.format(s.errors):'Belum tersedia');dd(popup,'Latensi p95',s.p95==null?'Belum tersedia':nf.format(s.p95)+' ms');dd(popup,'Kondisi contoh',label);
      });
      empty.hidden=visible!==0;text('[data-overview-results]',visible+' dari '+endpoints.length+' endpoint demo');
      const sampling=$('.pipeline-strip > span > span:not(.status)',root);if(sampling)sampling.textContent='Event demo disimpan hingga batas 1.000; bukan sampling produksi';
      $$('[data-overview-range]').forEach(button=>{const selected=Number(button.dataset.overviewRange)===range;button.classList.toggle('selected',selected);button.setAttribute('aria-pressed',String(selected));});
      $$('[data-overview-chart]').forEach(button=>{const selected=button.dataset.overviewChart===chart;button.classList.toggle('selected',selected);button.setAttribute('aria-pressed',String(selected));});
      text('#snapshot-detail > p:first-of-type',period+' · '+env+' · jam demo '+simTime(cutoff,true));
      const popup=$('#request-detail');text('p:first-of-type','Sesi '+demo.state.id+' · '+env+' · '+period+' · '+(demo.state.running?'demo berjalan':'demo dijeda'),popup);const list=$('.request-list',popup);list.hidden=false;const recent=demo.state.requests.filter(r=>r.environment===env&&r.at>cutoff-range*60000).slice(-5).reverse();list.replaceChildren(...recent.map(r=>{const li=document.createElement('li');li.append(simAnchor('request-detail.html',{id:r.id},r.id),document.createTextNode(' · '+(r.status??'Tanpa HTTP')+' · '+r.outcome));const small=document.createElement('small');small.textContent=simTime(r.at)+' · '+r.method+' '+r.route;li.append(document.createElement('br'),small);return li;}));if(!recent.length){const li=document.createElement('li');li.textContent='Belum ada request pada filter ini. Kirim request demo untuk memulai.';list.append(li);}
      draw(buckets,total,errors,stats.client,period,hasData);
      if(sync){demo.state.environment=env;demo.persist();setParam('environment',env);setParam('range',String(range));setParam('chart',chart);setParam('q',search.value);setParam('sort',sort.value);}
      if(announce)text('[data-announcer]','Filter '+env+', '+period+'. '+nf.format(total)+' request reader pada sesi demo.');
      stateView(chosenState);
    }
    function moduleLink(parent,file,label){const link=document.createElement('a');link.className='button mt-4';link.dataset.overviewLink=file;link.textContent=label;parent.append(link);return link;}
    endpoints.forEach(e=>{const link=moduleLink($('#endpoint-'+e.index),'endpoint-detail.html','Buka detail endpoint');link.dataset.endpoint='ep'+(e.index+1);});
    moduleLink($('#request-detail'),'requests.html','Buka halaman Request log');moduleLink($('#health-detail'),'health.html','Buka halaman Health');moduleLink($('#incident-detail'),'alert-detail.html','Buka detail insiden');
    function links(){$$('[data-overview-link]').forEach(link=>{const url=new URL(link.dataset.overviewLink,location.href);url.searchParams.set('environment',environment.value);url.searchParams.set('range',String(range));url.searchParams.set('back','index.html'+location.search);if(link.dataset.endpoint)url.searchParams.set('id',link.dataset.endpoint);if(link.dataset.overviewLink==='endpoint-detail.html')url.searchParams.set('scope','reader');if(link.dataset.overviewLink==='alert-detail.html'){const incident=demo.state.incidents.findLast(i=>i.environment===environment.value&&i.status!=='resolved');if(incident)url.searchParams.set('id',incident.id);else{url.pathname=url.pathname.replace('alert-detail.html','alerts.html');}}link.href=url;});}
    function update(){render(true,true);links();refreshSimulation();}
    resetSearch.addEventListener('click',()=>{clearTimeout(searchTimer);search.value='';update();search.focus();});
    environment.addEventListener('change',update);sort.addEventListener('change',update);
    let searchTimer;search.addEventListener('input',()=>{clearTimeout(searchTimer);searchTimer=setTimeout(update,300);});search.addEventListener('keydown',event=>{if(event.key==='Enter'){event.preventDefault();clearTimeout(searchTimer);update();}});
    $$('[data-overview-range]').forEach(button=>button.addEventListener('click',()=>{range=Number(button.dataset.overviewRange);update();}));
    $$('[data-overview-chart]').forEach(button=>button.addEventListener('click',()=>{chart=button.dataset.overviewChart;update();}));
    window.addEventListener('popstate',()=>{const state=new URLSearchParams(location.search);range=ranges.includes(Number(state.get('range')))?Number(state.get('range')):15;environment.value=state.get('environment')==='staging'?'staging':'production';chart=['traffic','latency','status'].includes(state.get('chart'))?state.get('chart'):'traffic';search.value=state.get('q')||'';sort.value=state.get('sort')||'priority';render();links();});
    overviewSimulationRefresh=()=>{render();links();};render();links();
  }

  function renderMonitoringContext(){
    const page=pageFile;if(![...scopedMonitoringPages,'endpoint-detail'].includes(page))return;
    const range=[5,15,60,1440].includes(Number(params.get('range')))?Number(params.get('range')):15,environment=params.get('environment')==='staging'?'staging':'production';
    let notice=$('[data-monitoring-context]');
    if(!notice){notice=document.createElement('div');notice.className='notice neutral mb-6';notice.dataset.monitoringContext='';const label=document.createElement('p');label.className='text-sm';notice.append(label);$('.page-heading').after(notice);}
    text('p','Konteks investigasi: '+environment+' · '+range+' menit · jam demo '+simTime(demo.state.now,true)+' UTC+7 · sesi '+demo.state.id,notice);
    if(params.get('back')&&/^[a-z0-9-]+\.html(?:\?[^#]*)?$/i.test(params.get('back'))&&!$('[data-context-back]',notice)){const back=document.createElement('a');back.href=params.get('back');back.className='text-button';back.dataset.contextBack='';back.textContent='Kembali ke konteks sebelumnya';notice.append(back);}
    if(page==='health')renderSimHealth();
    ['requests.html','runtime-logs.html','endpoint-detail.html','alerts.html','health.html'].forEach(file=>linksTo(file).filter(link=>!link.hasAttribute('data-context-back')).forEach(link=>{const url=new URL(link.href);url.searchParams.set('environment',environment);url.searchParams.set('range',String(range));link.href=url;}));
  }

  initEditorBaselines(); hydrateCreated(); bindSaved(); hydrateChapters(); prepareSimulationViews(); initLists(); initOverview(); renderMonitoringContext(); applyRole(); initReader(); initFlow(); initSchema(); initSimulation();
  requestAnimationFrame(() => requestAnimationFrame(() => delete document.documentElement.dataset.uiLoading));
})();

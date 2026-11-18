import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { Browser, sleep } from '../../.agents/skills/taste-skill/scripts/lib/cdp.mjs';
const base=process.env.ADMIN_QA_URL??'http://127.0.0.1:3102',out=path.resolve('../docs/screenshots/admin-phase2-complete/accessibility');fs.mkdirSync(out,{recursive:true});
const browser=await Browser.launch(),page=await browser.newPage({reducedMotion:true});
const report={layouts:[],contrast:[],special:[],errors:[]};
async function measure(){return page.eval(()=>({width:innerWidth,scrollWidth:document.documentElement.scrollWidth,h1:document.querySelector('h1')?.textContent,theme:document.documentElement.dataset.theme}));}
async function contrast(){return page.eval(()=>{
  const canvas=document.createElement('canvas');canvas.width=canvas.height=1;const context=canvas.getContext('2d',{willReadFrequently:true});
  const luminance=rgb=>rgb.slice(0,3).map(v=>{v/=255;return v<=.04045?v/12.92:((v+.055)/1.055)**2.4;}).reduce((sum,v,i)=>sum+v*[.2126,.7152,.0722][i],0);
  const rows=[],walker=document.createTreeWalker(document.querySelector('main'),NodeFilter.SHOW_TEXT);let node;
  while(node=walker.nextNode()){
    const el=node.parentElement;if(!node.textContent.trim()||!el||el.closest('svg,[aria-hidden=true],dialog:not([open]),[disabled]'))continue;
    const r=el.getBoundingClientRect(),style=getComputedStyle(el);if(!r.width||!r.height||r.bottom<0||r.top>innerHeight||r.left>=innerWidth||r.right<=0||style.visibility==='hidden')continue;
    const chain=[];let ancestor=el,hidden=false;while(ancestor){const s=getComputedStyle(ancestor);if(Number(s.opacity)<.01){hidden=true;break;}chain.unshift(s.backgroundColor);ancestor=ancestor.parentElement;}if(hidden)continue;
    context.clearRect(0,0,1,1);context.fillStyle='white';context.fillRect(0,0,1,1);for(const color of chain){context.fillStyle=color;context.fillRect(0,0,1,1);}const bg=[...context.getImageData(0,0,1,1).data];context.fillStyle=style.color;context.fillRect(0,0,1,1);const fg=[...context.getImageData(0,0,1,1).data];const a=luminance(bg),b=luminance(fg),ratio=(Math.max(a,b)+.05)/(Math.min(a,b)+.05),large=parseFloat(style.fontSize)>=24||parseFloat(style.fontSize)>=18.66&&parseInt(style.fontWeight)>=700;
    rows.push({text:node.textContent.trim().slice(0,65),ratio:+ratio.toFixed(2),size:style.fontSize,fg:bg.join(',')===fg.join(',')?style.color:fg.slice(0,3).join(','),bg:bg.slice(0,3).join(','),minimum:large?3:4.5});
  }return rows;
});}
try{
  for(const theme of ['light','dark']){
    await page.send('Page.addScriptToEvaluateOnNewDocument',{source:`try{localStorage.setItem('tt-admin-theme','${theme}')}catch{}`});
    for(const width of [375,768,1024])for(const route of ['/overview','/data/comics/c1/edit','/runtime-logs','/comic-preview/komiku/komik-contoh-a/chapters/12.5','/data-flow','/data-model']){
      await page.setViewport({width,height:900});await page.goto(base+route,{settleMs:500});const result={route,theme,...await measure()};report.layouts.push(result);if(result.scrollWidth>width+1)report.errors.push(result);
      if(width===768)await page.screenshot({path:path.join(out,`${theme}-${width}-${route.split('/')[1]}.jpg`),quality:60});
    }
    await page.setViewport({width:1440,height:900});
    for(const route of ['/overview','/data/comics','/data/comics/c1/edit','/runtime-logs','/data-model?view=list']){await page.goto(base+route,{settleMs:500});const rows=await contrast();report.contrast.push({theme,route,rows});report.errors.push(...rows.filter(row=>row.ratio<row.minimum-.02).map(row=>({theme,route,...row})));}
    await page.setViewport({width:844,height:390});await page.goto(base+'/data/comics',{settleMs:500});report.special.push({kind:'landscape',theme,...await measure()});
    await page.setViewport({width:360,height:900});await page.goto(base+'/data/comics/c1/edit',{settleMs:500});await page.eval(()=>{document.documentElement.style.fontSize='200%';});await sleep(200);report.special.push({kind:'text zoom 200%',theme,...await measure()});await page.screenshot({path:path.join(out,`${theme}-360-text200.jpg`),quality:65});
  }
  await page.goto(base+'/data/comics',{settleMs:500});await page.send('Emulation.setEmulatedMedia',{features:[{name:'forced-colors',value:'active'},{name:'prefers-reduced-motion',value:'reduce'}]});await page.eval(()=>document.querySelector('main input').focus());report.special.push({kind:'forced colors',...await page.eval(()=>({outline:getComputedStyle(document.activeElement).outlineStyle,outlineWidth:getComputedStyle(document.activeElement).outlineWidth,overflow:document.documentElement.scrollWidth>innerWidth+1}))});
  await page.send('Emulation.setEmulatedMedia',{features:[{name:'prefers-reduced-motion',value:'reduce'}]});
  const denied=await browser.newPage({width:360,height:900,reducedMotion:true});await denied.send('Page.addScriptToEvaluateOnNewDocument',{source:`Object.defineProperty(Storage.prototype,'getItem',{value(){throw new DOMException('Storage blocked','SecurityError')}});Object.defineProperty(Storage.prototype,'setItem',{value(){throw new DOMException('Storage blocked','SecurityError')}});`});await denied.goto(base+'/data/comics',{settleMs:600});report.special.push({kind:'storage denied',...await denied.eval(()=>({h1:document.querySelector('h1')?.textContent,overflow:document.documentElement.scrollWidth>innerWidth+1,errors:document.querySelector('main')?.textContent.includes('Application error')})),console:denied.consoleErrors});await denied.close();
  report.errors.push(...report.special.filter(row=>row.overflow||row.scrollWidth>row.width+1));
  fs.writeFileSync(path.join(out,'measurements.json'),JSON.stringify(report,null,2));console.log(JSON.stringify({layouts:report.layouts.length,contrastSamples:report.contrast.reduce((sum,r)=>sum+r.rows.length,0),special:report.special.length,errors:report.errors.length,examples:report.errors.slice(0,8)}));assert.equal(report.errors.length,0);
}finally{await browser.close();}

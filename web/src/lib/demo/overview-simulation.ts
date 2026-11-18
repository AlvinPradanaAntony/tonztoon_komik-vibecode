import { endpoints } from "./monitoring";
export const scenarios={healthy:"Normal / pulih",latency:"Latensi reader tinggi",errors:"HTTP 5xx meningkat",down:"API tidak terjangkau",gap:"Telemetry terputus",burst:"Lonjakan trafik"};
export type Scenario=keyof typeof scenarios;
export type Event={id:string;at:number;endpoint:number;duration:number;status:number;environment:string};
export type DemoIncident={id:string;environment:string;state:string;conditionSince:number|null;healthySince:number|null;timeline:{at:number;state:string}[]};
export type Simulation={now:number;running:boolean;scenario:Scenario;environment:string;events:Event[];probes:{at:number;ok:boolean;known:boolean;environment:string}[];lost:number;dropped:number;incidents?:DemoIncident[]};
export function createSimulation():Simulation {
  const now=Date.UTC(2026,9,28,6,19,29);
  const recent=[0,0,0,0,0,0,1,1,2,3];
  return {now,running:false,scenario:'healthy',environment:'production',lost:0,dropped:0,
    events:Array.from({length:1000},(_,i)=>({id:i<400?`historical-${i}`:`demo-req-${String(i-399).padStart(4,'0')}`,at:i<400?now-86400000+(i+1)*85500000/400:now-900000+(i-399)*899000/600,endpoint:i<400?i%8:recent[i%10],duration:90+i%17*19,status:i%37===0?404:200,environment:'production'})),
    probes:Array.from({length:180},(_,i)=>({at:now-895000+i*5000,ok:true,known:true,environment:'production'}))};
}
export function advance(s:Simulation):Simulation {
  const now=s.now+30000;const count=s.scenario==='burst'?60:25;
  const additions=['gap','down'].includes(s.scenario)?[]:Array.from({length:count},(_,i)=>({id:`demo-${now}-${i}`,at:now-29000+i*29000/count,endpoint:i%10<6?0:i%10<8?1:i%10===8?2:3,duration:s.scenario==='latency'?2400+i%7*180:s.scenario==='errors'?1500+i%6*220:85+i%9*23,status:s.scenario==='errors'?503:200,environment:s.environment}));
  const events=[...s.events,...additions];
  const next={...s,now,events:events.slice(-1000),dropped:s.dropped+Math.max(0,events.length-1000),lost:s.lost+(s.scenario==='gap'?25:0),probes:[...s.probes,...Array.from({length:6},(_,i)=>({at:now-25000+i*5000,ok:s.scenario!=='down',known:s.scenario!=='gap',environment:s.environment}))].slice(-1000)};
  const incidents=alertSamples(next,next.environment).map(sample=>{
    const previous=s.incidents?.find(incident=>incident.id===sample.id&&incident.environment===next.environment);
    let state=previous?.state??'resolved',conditionSince=previous?.conditionSince??null,healthySince=previous?.healthySince??null;
    if(!sample.known){state='unknown';conditionSince=null;healthySince=null;}
    else if(sample.bad){healthySince=null;conditionSince??=now;state=sample.id==='liveness'||now-conditionSince>=60000?'firing':'pending';}
    else{conditionSince=null;if(sample.id==='liveness')state='resolved';else if(previous&&previous.state!=='resolved'){healthySince??=now;state=now-healthySince>=60000?'resolved':previous.state==='unknown'?'unknown':previous.state;}else state='resolved';}
    const timeline=previous?.timeline??[];
    return {id:sample.id,environment:next.environment,state,conditionSince,healthySince,timeline:(!timeline.length||timeline.at(-1)?.state!==state?[...timeline,{at:now,state}]:timeline).slice(-100)};
  });
  return {...next,incidents:[...(s.incidents??[]).filter(incident=>incident.environment!==next.environment),...incidents]};
}
const quantile=(rows:Event[],q:number)=>{const sorted=rows.map(r=>r.duration).sort((a,b)=>a-b);return sorted.length?sorted[Math.max(0,Math.ceil(sorted.length*q)-1)]:null;};
export function summarize(s:Simulation,environment:string,minutes:number) {
  const lower=s.now-minutes*60000;
  const rows=s.events.filter(e=>e.endpoint<5&&e.environment===environment&&e.at>lower&&e.at<=s.now);
  const errors=rows.filter(e=>e.status>=500).length;
  const probes=s.probes.filter(p=>p.environment===environment&&p.at>lower&&p.at<=s.now&&p.known);
  const scheduledProbes=Math.max(0,Math.floor((s.now-4000)/5000)-Math.floor((lower-4000)/5000));
  const bucketCount=minutes===5?5:15;
  const buckets=Array.from({length:bucketCount},(_,i)=>{const from=lower+i*minutes*60000/bucketCount,to=from+minutes*60000/bucketCount;const bucket=rows.filter(e=>e.at>from&&e.at<=to);return {at:from,count:bucket.length,errors:bucket.filter(e=>e.status>=500).length,p95:quantile(bucket,.95)};});
  return {count:rows.length,errors,clientErrors:rows.filter(r=>r.status>=400&&r.status<500).length,statuses:[200,300,400,500].map(code=>({code,count:rows.filter(r=>r.status>=code&&r.status<code+100).length})),inFlight:0,p50:quantile(rows,.5),p95:quantile(rows,.95),p99:quantile(rows,.99),rps:rows.length/(minutes*60),scheduledProbes,probes:probes.length,success:probes.filter(p=>p.ok).length,availability:probes.length?probes.filter(p=>p.ok).length/probes.length*100:null,coverage:scheduledProbes?Math.min(100,probes.length/scheduledProbes*100):0,buckets,
    endpoints:endpoints.map((e,index)=>{const subset=rows.filter(r=>r.endpoint===index);return {...e,count:subset.length,errors:subset.filter(r=>r.status>=500).length,p95:quantile(subset,.95)};})};
}
export function demoTime(at:number,seconds=false) {return new Intl.DateTimeFormat('id-ID',{timeZone:'Asia/Bangkok',hour:'2-digit',minute:'2-digit',...(seconds?{second:'2-digit'}:{})}).format(at).replaceAll('.',':');}
export function alertSamples(s:Simulation,environment:string){
  const rows=s.events.filter(event=>event.environment===environment&&event.endpoint<5&&event.at>s.now-300000&&event.at<=s.now),reader=rows.filter(event=>event.endpoint===0),sorted=reader.map(event=>event.duration).sort((a,b)=>a-b);
  const p95=sorted.length?sorted[Math.ceil(sorted.length*.95)-1]:null,errors=rows.filter(event=>event.status>=500).length;
  const latest=rows.reduce((time,row)=>Math.max(time,row.at),0),fresh=latest>=s.now-30000&&!(s.environment===environment&&s.scenario==='gap');
  const probes=s.probes.filter(probe=>probe.environment===environment&&probe.at<=s.now).slice(-2);
  return [
    {id:'reader-latency',title:'Latensi p95 reader tinggi',scope:'reader',known:fresh&&reader.length>=100,bad:(p95??0)>2000,value:p95===null?'Belum tersedia':`${p95} ms`,threshold:'p95 > 2.000 ms',samples:reader.length,hold:'60 detik; pemulihan 60 detik'},
    {id:'http-errors',title:'HTTP 5xx meningkat',scope:'all',known:fresh&&rows.length>=100,bad:errors/Math.max(1,rows.length)>.05,value:`${(errors/Math.max(1,rows.length)*100).toFixed(2)}%`,threshold:'5xx > 5%',samples:rows.length,hold:'60 detik; pemulihan 60 detik'},
    {id:'liveness',title:'Liveness API',scope:'all',known:probes.length===2&&probes.every(probe=>probe.known)&&probes.at(-1)!.at>=s.now-10000,bad:probes.every(probe=>!probe.ok),value:`${probes.filter(probe=>probe.ok&&probe.known).length}/2 probe sukses`,threshold:'2 probe gagal berturut-turut',samples:probes.length,hold:'2 sukses untuk pulih'},
  ];
}

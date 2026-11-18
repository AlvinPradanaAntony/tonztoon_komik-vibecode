type Params={get(key:string):string|null};
export function monitoringWindow(params:Params,now:number){
  const selected=params.get('range');
  if(selected==='custom'){
    const start=Date.parse(params.get('window_from')??''),end=Date.parse(params.get('window_to')??'');
    const error=!Number.isFinite(start)||!Number.isFinite(end)?'Lengkapi awal dan akhir rentang kustom.':end<=start?'Akhir harus sesudah awal rentang.':end-start>7*86400000?'Rentang kustom maksimal tujuh hari.':end>now?'Akhir rentang melewati jam demo yang tersedia.':'';
    return {choice:'custom',label:'Rentang kustom',start:error?now-900000:start,end:error?now:end,minutes:error?15:(end-start)/60000,error};
  }
  const minutes=[5,15,60,1440].includes(Number(selected))?Number(selected):15;
  return {choice:String(minutes),label:minutes===1440?'24 jam':minutes===60?'1 jam':`${minutes} menit`,start:now-minutes*60000,end:now,minutes,error:''};
}
export function localDemoDate(at:number){return new Date(at+7*3600000).toISOString().slice(0,19);}
export function periodDate(at:number){return new Intl.DateTimeFormat('id-ID',{timeZone:'Asia/Bangkok',dateStyle:'medium',timeStyle:'short'}).format(at);}

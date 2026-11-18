"use client";
import { useState } from 'react';
import { Alert, Button, Input } from '@/components/ui';
import { localDemoDate, monitoringWindow } from '@/lib/monitoring/window';
import { useQueryState } from './demo-boundary';
export function CustomRange({now,onApply}:{now:number;onApply?:()=>void}){
  const {params,set}=useQueryState(),window=monitoringWindow(params,now);
  const [from,setFrom]=useState(localDemoDate(window.start)),[to,setTo]=useState(localDemoDate(window.end)),[error,setError]=useState('');
  return <form className="my-4 rounded-control bg-panel p-4" noValidate onSubmit={event=>{
    event.preventDefault();const start=Date.parse(`${from}+07:00`),end=Date.parse(`${to}+07:00`);
    const next=new URLSearchParams({range:'custom',window_from:Number.isFinite(start)?new Date(start).toISOString():'',window_to:Number.isFinite(end)?new Date(end).toISOString():''});
    const checked=monitoringWindow(next,now);setError(checked.error);
    if(!checked.error){onApply?.();set({range:'custom',window_from:next.get('window_from'),window_to:next.get('window_to'),page:null});}
  }}><div className="flex flex-wrap items-end gap-4"><Input label="Awal rentang UTC+7" type="datetime-local" step="1" required value={from} max={localDemoDate(now)} onChange={event=>setFrom(event.target.value)}/><Input label="Akhir rentang UTC+7" type="datetime-local" step="1" required value={to} max={localDemoDate(now)} onChange={event=>setTo(event.target.value)}/><Button type="submit" variant="primary">Terapkan rentang kustom</Button></div><p className="mt-3 text-xs/5 text-muted">Maksimal tujuh hari, dibatasi jam demo. Riwayat yang tidak tercakup tidak dianggap nol atau sehat.</p>{error&&<Alert tone="error" title="Rentang tidak valid">{error}</Alert>}</form>;
}

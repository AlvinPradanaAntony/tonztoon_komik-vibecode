"use client";
import { useEffect } from "react";
import { advance } from "@/lib/demo/overview-simulation";
import { useSimulation } from "@/lib/monitoring/demo-store";
export function MonitoringPump(){
  const [simulation,setSimulation]=useSimulation();
  useEffect(()=>{if(!simulation.running)return;const timer=setInterval(()=>{if(!document.hidden)setSimulation(advance);},2000);return()=>clearInterval(timer);},[simulation.running,setSimulation]);
  return null;
}

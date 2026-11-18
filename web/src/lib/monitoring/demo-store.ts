"use client";
import { useSyncExternalStore, type SetStateAction } from "react";
import { createSimulation, type Simulation } from "@/lib/demo/overview-simulation";
const initial = createSimulation();
let simulation = initial;
const listeners = new Set<() => void>();
export function setSimulation(update: SetStateAction<Simulation>) { simulation = typeof update === "function" ? update(simulation) : update; listeners.forEach(listener => listener()); }
export function useSimulation(): [Simulation, typeof setSimulation] { return [useSyncExternalStore(listener => { listeners.add(listener); return () => { listeners.delete(listener); }; }, () => simulation, () => initial), setSimulation]; }

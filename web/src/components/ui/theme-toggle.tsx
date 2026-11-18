"use client";
import { useSyncExternalStore } from "react";
import { Button } from "./button";
import { Icon } from "./icon";
import { iconButton } from "./styles";
function subscribe(callback:()=>void) {
  const media=matchMedia("(prefers-color-scheme:dark)");
  const observer=new MutationObserver(callback);
  observer.observe(document.documentElement,{attributes:true,attributeFilter:["data-theme"]});
  media.addEventListener("change",callback);
  return ()=>{observer.disconnect();media.removeEventListener("change",callback);};
}
function isDark() {return document.documentElement.dataset.theme?document.documentElement.dataset.theme==="dark":matchMedia("(prefers-color-scheme:dark)").matches;}
export function ThemeToggle() {
  const dark=useSyncExternalStore(subscribe,isDark,()=>false);
  return <Button variant="ghost" className={iconButton} aria-label={dark?"Gunakan tema terang":"Gunakan tema gelap"} onClick={()=>{
    const next=isDark()?"light":"dark";document.documentElement.dataset.theme=next;
    try {localStorage.setItem("tt-admin-theme",next);}catch{}
  }}><Icon name={dark?"sun":"moon"}/></Button>;
}

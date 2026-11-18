import type { ReactNode } from "react";

export const pageTitle="mb-6 flex flex-wrap items-center justify-between gap-4 [&_h1]:mb-2 [&_h1]:text-[clamp(1.6rem,2.2vw,2rem)] [&_h1]:leading-tight [&_h1]:tracking-[-.025em] [&_p]:text-sm/5 [&_p]:text-muted [&>button]:max-sm:w-full";
export const detailList="my-4 grid grid-cols-2 gap-3 text-sm";
export const numberCell="text-end tabular-nums [&_small]:block [&_small]:text-xs [&_small]:text-muted [&_button]:justify-end";
export const adminTable="min-w-185 [&_th:first-child]:min-w-55";
export const tableToolbar="mb-4 flex flex-wrap justify-between gap-3 [&>.tt-field]:flex-1 [&>.tt-field]:max-w-87.5 [&>.tt-field]:max-sm:max-w-none [&>.tt-field]:max-sm:basis-full [&>.tt-field:last-child]:flex [&>.tt-field:last-child]:flex-row [&>.tt-field:last-child]:flex-wrap [&>.tt-field:last-child]:items-center [&>.tt-field:last-child]:gap-2 [&>.tt-field:last-child]:text-xs";
export const disclosure="min-h-11 cursor-pointer py-3 text-sm";
export const hiddenLabel="[&>label]:sr-only";
export const panelHeader="px-5 py-4 max-sm:px-4 max-sm:py-4.5 [&_p]:text-[13px]/relaxed";
export function PageTitle({title,description,action}:{title:string;description:ReactNode;action?:ReactNode}) {
  return <div className={pageTitle}><div><h1>{title}</h1><p>{description}</p></div>{action}</div>;
}

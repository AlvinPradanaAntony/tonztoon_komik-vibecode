import type { UiSize, UiTone } from "./types";

// Complete class names are deliberate: Tailwind discovers these at build time.
export const focus = "focus-visible:outline-[length:var(--tt-focus-width)] focus-visible:outline-solid focus-visible:outline-accent focus-visible:outline-offset-[var(--tt-focus-offset)]";
export const controlSizes: Record<UiSize,string> = {sm:"h-(--tt-control-sm) min-h-(--tt-control-sm)",md:"h-(--tt-control-md) min-h-(--tt-control-md)",lg:"h-(--tt-control-lg) min-h-(--tt-control-lg)"};
export const toneVariables: Record<UiTone,string> = {
  neutral:"[--tt-tone-bg:var(--surface-alt)] [--tt-tone-fg:var(--muted)]",
  info:"[--tt-tone-bg:var(--accent-bg)] [--tt-tone-fg:var(--accent-ink)]",
  success:"[--tt-tone-bg:var(--success-bg)] [--tt-tone-fg:var(--success-ink)]",
  warning:"[--tt-tone-bg:var(--warning-bg)] [--tt-tone-fg:var(--warning)]",
  error:"[--tt-tone-bg:var(--danger-bg)] [--tt-tone-fg:var(--danger-ink)]",
};
export const fieldFrame="grid min-w-0 gap-2 text-sm [&>label]:font-medium";
export const fieldHint="text-xs font-normal text-muted";
export const fieldError="text-xs font-normal text-danger-text";
export const fieldControl="w-full min-w-0 rounded-field shadow-none placeholder:text-subtle placeholder:opacity-100 disabled:cursor-not-allowed disabled:border-control disabled:bg-panel disabled:text-muted disabled:opacity-100 [&[readonly]:enabled]:border-control [&[readonly]:enabled]:bg-panel [&[readonly]:enabled]:text-muted data-loading:pe-11 focus-visible:outline-[length:var(--tt-focus-width)] focus-visible:outline-solid focus-visible:outline-(--tt-field-focus) focus-visible:outline-offset-[var(--tt-focus-offset)]";
export const fieldTones:Record<UiTone,string>={
  neutral:"[--tt-field-focus:var(--accent)] [&:enabled:not([readonly])]:border-control [&:enabled:not([readonly])]:bg-surface [&:enabled:not([readonly])]:text-foreground",
  info:"[--tt-field-focus:var(--accent)]",success:"[--tt-field-focus:var(--accent)]",
  warning:"[--tt-field-focus:var(--accent)] [&:enabled:not([readonly])]:border-warning-solid",
  error:"[--tt-field-focus:var(--danger)]",
};
export const fieldProgress="pointer-events-none absolute end-3.5 top-1/2 flex -translate-y-1/2 text-muted";
export const iconButton="inline-flex size-11 min-w-11 items-center justify-center rounded-full border border-control bg-surface p-0 text-foreground hover:bg-surface-alt [&>svg]:size-5";
export const textLink="inline-flex min-h-11 items-center gap-2 text-sm underline-offset-4";
export const primaryActionLink=`btn min-h-11 h-auto max-w-full rounded-control border-0 bg-foreground px-4 py-2 text-canvas whitespace-normal wrap-anywhere shadow-none [text-shadow:none] ${focus}`;
export const wrap="flex flex-wrap items-center gap-3";
export const sectionLabel="mt-5 mb-3 text-sm font-semibold";

import type { ComponentProps, ReactNode } from "react";
import { cx, type UiTone } from "./types";
import { toneVariables } from "./styles";

const tones = { neutral: "", info: "alert-info", success: "alert-success", warning: "alert-warning", error: "alert-error" };
const icons = {
  neutral: <path d="M5 5h14v11H9l-4 3V5Zm4 4h6m-6 3h4" />,
  info: <><path d="M12 11v6" /><circle cx="12" cy="7" r="1" fill="currentColor" stroke="none" /></>,
  success: <path d="m6 12 4 4 8-8" />,
  warning: <><path d="M12 6v8" /><circle cx="12" cy="18" r="1" fill="currentColor" stroke="none" /></>,
  error: <path d="m7 7 10 10M17 7 7 17" />,
};
export type AlertProps = Omit<ComponentProps<"div">, "title"> & {
  tone?: UiTone; title?: ReactNode; announce?: boolean; action?: ReactNode;
};

export function Alert({ tone = "neutral", title, announce = false, action, role, children, className, ...props }: AlertProps) {
  return <div {...props} data-tone={tone} role={role ?? (announce ? tone === "error" ? "alert" : "status" : "note")}
    className={cx("alert alert-soft @container grid grid-flow-row grid-cols-[var(--tt-alert-icon-size)_minmax(0,1fr)] items-start gap-3 rounded-(--tt-radius-alert) border-0 border-s-4 border-s-(--tt-tone-fg) bg-(--tt-tone-bg) p-4 text-start text-sm/6 text-(--tt-tone-fg) shadow-(--tt-alert-shadow)", toneVariables[tone],tones[tone],className)}>
    <span className="grid size-(--tt-alert-icon-size) place-items-center rounded-full border-4 border-[color-mix(in_srgb,var(--tt-tone-fg)_10%,var(--tt-tone-bg))] bg-[color-mix(in_srgb,var(--tt-tone-fg)_20%,var(--tt-tone-bg))] text-(--tt-tone-fg)" aria-hidden="true">
      <svg className="size-4.5" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" focusable="false">{icons[tone]}</svg>
    </span>
    <div className="min-w-0 self-center wrap-anywhere @max-[11rem]:col-span-full">{title && <p className="mb-0.5 font-semibold">{title}</p>}<div>{children}</div></div>
    {action && <div className="col-start-2 flex min-w-0 flex-wrap gap-2 @max-[11rem]:col-span-full">{action}</div>}
  </div>;
}

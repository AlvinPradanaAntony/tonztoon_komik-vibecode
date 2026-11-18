"use client";

import type { ComponentProps, ReactNode } from "react";
import { FieldFrame, useFieldIds, type FieldOptions } from "./field";
import { Spinner } from "./spinner";
import { cx } from "./types";
import { controlSizes, fieldControl, fieldTones, fieldProgress } from "./styles";

const tones = { neutral: "", info: "select-info", success: "select-success", warning: "select-warning", error: "select-error" };
const sizes = { sm: "select-sm", md: "select-md", lg: "select-lg" };
export type SelectProps = Omit<ComponentProps<"select">, "size"> & FieldOptions & { leading?: ReactNode };

export function Select({ label, hint, error, tone = "neutral", invalid = false, loading = false,
  size = "md", id, className, fieldClassName, disabled, children, leading, ...props }: SelectProps) {
  const ids = useFieldIds(id, props["aria-describedby"], hint, error);
  const isInvalid = invalid || Boolean(error) || props["aria-invalid"] === true || props["aria-invalid"] === "true";
  const effectiveTone = isInvalid ? "error" : tone;
  return <FieldFrame label={label} hint={hint} error={error} ids={ids} className={fieldClassName}>
    <div className="relative min-w-0">
      {leading&&<span className="pointer-events-none absolute start-4 top-1/2 z-1 flex -translate-y-1/2" aria-hidden="true">{leading}</span>}
      <select {...props} id={ids.controlId} disabled={disabled || loading}
        aria-invalid={isInvalid ? true : props["aria-invalid"]} aria-describedby={ids.describedBy}
        aria-busy={loading || undefined} data-tone={effectiveTone} data-size={size} data-loading={loading || undefined}
        className={cx("select tt-control", fieldControl, fieldTones[effectiveTone], controlSizes[size], "enabled:focus:outline-[length:var(--tt-focus-width)] enabled:focus:outline-(--tt-field-focus) enabled:open:outline-[length:var(--tt-focus-width)] enabled:open:outline-(--tt-field-focus)",Boolean(leading)&&"ps-8", tones[effectiveTone], sizes[size], className)}>{children}</select>
      {loading && <span className={cx(fieldProgress,"end-10")}><Spinner decorative /></span>}
    </div>
  </FieldFrame>;
}

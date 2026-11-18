"use client";

import type { ComponentProps } from "react";
import { FieldFrame, useFieldIds, type FieldOptions } from "./field";
import { cx } from "./types";
import { Spinner } from "./spinner";
import { fieldControl, fieldTones } from "./styles";

const tones = { neutral: "", info: "textarea-info", success: "textarea-success", warning: "textarea-warning", error: "textarea-error" };
const sizes = { sm: "textarea-sm", md: "textarea-md", lg: "textarea-lg" };
export type TextareaProps = ComponentProps<"textarea"> & FieldOptions;

export function Textarea({ label, hint, error, tone = "neutral", invalid = false, loading = false,
  size = "md", id, className, fieldClassName, disabled, rows = 3, ...props }: TextareaProps) {
  const ids = useFieldIds(id, props["aria-describedby"], hint, error);
  const isInvalid = invalid || Boolean(error) || props["aria-invalid"] === true || props["aria-invalid"] === "true";
  const effectiveTone = isInvalid ? "error" : tone;
  return <FieldFrame label={label} hint={hint} error={error} ids={ids} className={fieldClassName}>
    <div className="relative min-w-0">
      <textarea {...props} id={ids.controlId} rows={rows} disabled={disabled || loading}
      aria-invalid={isInvalid ? true : props["aria-invalid"]} aria-describedby={ids.describedBy}
      aria-busy={loading || undefined} data-tone={effectiveTone} data-size={size}
        className={cx("textarea tt-control", fieldControl, fieldTones[effectiveTone], "h-auto min-h-32 resize-y rounded-(--tt-radius-textarea) py-3", tones[effectiveTone], sizes[size], className)} />
      {loading && <span className="pointer-events-none absolute end-3.5 top-3.5 flex text-muted"><Spinner decorative /></span>}
    </div>
  </FieldFrame>;
}

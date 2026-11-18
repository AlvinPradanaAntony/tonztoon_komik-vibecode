"use client";

import type { ComponentProps } from "react";
import { useFieldIds, type FieldOptions } from "./field";
import { cx } from "./types";
import { Spinner } from "./spinner";
import { fieldFrame, fieldHint, fieldError, focus } from "./styles";

const tones = { neutral: "checkbox-primary", info: "checkbox-info", success: "checkbox-success", warning: "checkbox-warning", error: "checkbox-error" };
export type CheckboxProps = Omit<ComponentProps<"input">, "size" | "type"> & FieldOptions;

export function Checkbox({ label, hint, error, tone = "neutral", invalid = false, loading = false,
  size = "md", id, className, fieldClassName, disabled, ...props }: CheckboxProps) {
  const ids = useFieldIds(id, props["aria-describedby"], hint, error);
  const isInvalid = invalid || Boolean(error) || props["aria-invalid"] === true || props["aria-invalid"] === "true";
  return <div className={cx("tt-field", fieldFrame, fieldClassName)}>
    <label className="flex min-h-11 min-w-11 cursor-pointer items-center gap-3" htmlFor={ids.controlId}>
      <input {...props} id={ids.controlId} type="checkbox" disabled={disabled || loading}
        aria-invalid={isInvalid ? true : props["aria-invalid"]} aria-describedby={ids.describedBy}
        aria-busy={loading || undefined} data-size={size} data-tone={isInvalid ? "error" : tone}
        className={cx("checkbox tt-checkbox shrink-0 transition-shadow disabled:cursor-not-allowed disabled:border-control disabled:bg-panel disabled:text-muted disabled:opacity-100",focus, tone==='neutral'&&!isInvalid&&"border-control", tone==='warning'&&!isInvalid&&"enabled:border-warning-solid", tones[isInvalid ? "error" : tone], className)} />
      <span>{label}</span>
      {loading && <Spinner decorative />}
    </label>
    {hint && <p id={ids.hintId} className={fieldHint}>{hint}</p>}
    {error && <p id={ids.errorId} className={fieldError}>{error}</p>}
  </div>;
}

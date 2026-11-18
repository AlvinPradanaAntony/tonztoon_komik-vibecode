"use client";

import type { ComponentProps } from "react";
import { FieldFrame, useFieldIds, type FieldOptions } from "./field";
import { Spinner } from "./spinner";
import { cx } from "./types";
import { controlSizes, fieldControl, fieldTones, fieldProgress } from "./styles";

const tones = { neutral: "", info: "input-info", success: "input-success", warning: "input-warning", error: "input-error" };
const sizes = { sm: "input-sm", md: "input-md", lg: "input-lg" };
export type InputProps = Omit<ComponentProps<"input">, "size"> & FieldOptions;

export function Input({ label, hint, error, tone = "neutral", invalid = false, loading = false,
  size = "md", id, className, fieldClassName, disabled, ...props }: InputProps) {
  const ids = useFieldIds(id, props["aria-describedby"], hint, error);
  const isInvalid = invalid || Boolean(error) || props["aria-invalid"] === true || props["aria-invalid"] === "true";
  const effectiveTone = isInvalid ? "error" : tone;
  return <FieldFrame label={label} hint={hint} error={error} ids={ids} className={fieldClassName}>
    <div className="relative min-w-0">
      <input {...props} id={ids.controlId} disabled={disabled || loading}
        aria-invalid={isInvalid ? true : props["aria-invalid"]} aria-describedby={ids.describedBy}
        aria-busy={loading || undefined} data-tone={effectiveTone} data-size={size} data-loading={loading || undefined}
        className={cx("input tt-control", fieldControl, fieldTones[effectiveTone], controlSizes[size], tones[effectiveTone], sizes[size], className)} />
      {loading && <span className={fieldProgress}><Spinner decorative /></span>}
    </div>
  </FieldFrame>;
}

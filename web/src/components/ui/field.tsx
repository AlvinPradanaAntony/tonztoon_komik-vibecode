"use client";

import { useId, type ReactNode } from "react";
import { cx, type UiSize, type UiTone } from "./types";
import { fieldFrame, fieldHint, fieldError } from "./styles";

export type FieldOptions = {
  label: string; hint?: ReactNode; error?: ReactNode; tone?: UiTone;
  invalid?: boolean; loading?: boolean; size?: UiSize; fieldClassName?: string;
};

export function useFieldIds(id: string | undefined, describedBy: string | undefined, hint: ReactNode, error: ReactNode) {
  const generated = useId();
  const controlId = id ?? generated;
  return {
    controlId, hintId: `${controlId}-hint`, errorId: `${controlId}-error`,
    describedBy: [describedBy, hint ? `${controlId}-hint` : null, error ? `${controlId}-error` : null].filter(Boolean).join(" ") || undefined,
  };
}

export function FieldFrame({ label, hint, error, ids, className, children }:
  Pick<FieldOptions, "label" | "hint" | "error"> & {
    ids: ReturnType<typeof useFieldIds>; className?: string; children: ReactNode;
  }) {
  return <div className={cx("tt-field", fieldFrame, className)}>
    <label htmlFor={ids.controlId}>{label}</label>
    {children}
    {hint && <p id={ids.hintId} className={fieldHint}>{hint}</p>}
    {error && <p id={ids.errorId} className={fieldError}>{error}</p>}
  </div>;
}

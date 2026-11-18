import type { ComponentProps } from "react";
import { cx, type UiSize } from "./types";

const sizes = { sm: "loading-xs", md: "loading-sm", lg: "loading-md" };

export function Spinner({ size = "md", decorative = false, label = "Memuat", className, ...props }:
  Omit<ComponentProps<"span">, "children"> & { size?: UiSize; decorative?: boolean; label?: string }) {
  return <span {...props} className={cx("loading loading-spinner", sizes[size], className)}
    role={decorative ? undefined : "status"} aria-label={decorative ? undefined : label}
    aria-hidden={decorative || undefined} />;
}

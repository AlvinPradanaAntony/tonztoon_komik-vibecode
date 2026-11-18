import type { ComponentProps } from "react";
import { Spinner } from "./spinner";
import { cx, type UiSize } from "./types";
import { controlSizes, focus, toneVariables } from "./styles";

const variants = {
  primary: "btn-primary", secondary: "", ghost: "btn-ghost",
  info: "btn-info", success: "btn-success", warning: "btn-warning", error: "btn-error",
};
const sizes = { sm: "btn-sm", md: "btn-md", lg: "btn-lg" };

export type ButtonProps = ComponentProps<"button"> & {
  variant?: keyof typeof variants; appearance?: "solid" | "soft" | "outline"; size?: UiSize; loading?: boolean;
};

export function Button({ variant = "secondary", appearance, size = "md", loading = false,
  disabled, type = "button", className, children, ...props }: ButtonProps) {
  const unavailable = disabled || loading || props["aria-disabled"] === true || props["aria-disabled"] === "true";
  const tone = variant==='info'||variant==='success'||variant==='warning'||variant==='error'?variant:'neutral';
  const look=appearance??(variant==='secondary'?'soft':'solid');
  return <button {...props} type={type} disabled={unavailable} aria-busy={loading || undefined}
    data-variant={variant} data-size={size} data-appearance={appearance ?? (variant === "secondary" ? "soft" : "solid")}
    data-tone={["info", "success", "warning", "error"].includes(variant) ? variant : "neutral"}
    className={cx("btn tt-button min-w-11 rounded-control shadow-none [text-shadow:none] transition-transform duration-150 motion-reduce:transition-none disabled:pointer-events-auto disabled:cursor-not-allowed disabled:border-control disabled:bg-panel disabled:text-muted disabled:opacity-100",focus,controlSizes[size],toneVariables[tone],variants[variant], sizes[size],
      "h-auto max-w-full py-2 whitespace-normal wrap-anywhere",
      look==='outline'&&"btn-outline enabled:border-line enabled:bg-surface enabled:text-foreground",
      look==='soft'&&"btn-soft enabled:border-transparent enabled:bg-(--tt-tone-bg) enabled:text-(--tt-tone-fg)",
      variant==='secondary'&&look==='soft'&&"enabled:bg-panel enabled:text-foreground enabled:hover:bg-surface-alt",
      variant==='primary'&&look==='solid'&&"enabled:border-transparent enabled:bg-foreground enabled:text-canvas",
      variant==='ghost'&&"enabled:text-foreground",
      tone!=='neutral'&&look==='solid'&&"enabled:hover:brightness-90 enabled:active:brightness-90",className)}>
    {loading && <Spinner size={size} decorative />}{children}
  </button>;
}

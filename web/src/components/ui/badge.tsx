import type { ComponentProps } from "react";
import { Spinner } from "./spinner";
import { cx, type UiSize, type UiTone } from "./types";
import { toneVariables } from "./styles";

const tones = { neutral: "badge-neutral", info: "badge-info", success: "badge-success", warning: "badge-warning", error: "badge-error" };
const appearances = { soft: "badge-soft", outline: "badge-outline", solid: "" };
const sizes = { sm: "badge-sm", md: "badge-md", lg: "badge-lg" };
export type BadgeProps = ComponentProps<"span"> & { tone?: UiTone; size?: UiSize; appearance?: keyof typeof appearances };

export function Badge({ tone = "neutral", size = "md", appearance = "soft", className, ...props }: BadgeProps) {
  return <span {...props} data-tone={tone} data-size={size} data-appearance={appearance}
    className={cx("badge h-auto min-h-6 whitespace-normal rounded-full",toneVariables[tone], tones[tone], sizes[size], appearances[appearance],
      size==='sm'?"text-[11px]":size==='lg'?"text-sm":"text-xs",
      appearance==='soft'&&"border-transparent bg-(--tt-tone-bg) text-(--tt-tone-fg)",
      appearance==='outline'&&"border-(--tt-tone-fg) bg-transparent text-(--tt-tone-fg)", className)} />;
}

const statuses = {
  success: { tone: "success", label: "Berhasil" }, warning: { tone: "warning", label: "Perlu perhatian" },
  error: { tone: "error", label: "Gagal" }, unknown: { tone: "neutral", label: "Belum tersedia" },
  loading: { tone: "info", label: "Memuat" }, disabled: { tone: "neutral", label: "Nonaktif" },
} satisfies Record<string, { tone: UiTone; label: string }>;

export type StatusBadgeProps = Omit<BadgeProps, "tone"> & { status: keyof typeof statuses };
export function StatusBadge({ status, children, ...props }: StatusBadgeProps) {
  const entry = statuses[status];
  return <Badge {...props} data-status={status} tone={entry.tone} aria-busy={status === "loading" || undefined}>
    {status === "loading" && <Spinner size="sm" decorative />}{children ?? entry.label}
  </Badge>;
}

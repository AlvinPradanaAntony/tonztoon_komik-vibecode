import type { ComponentProps, ReactNode } from "react";
import { cx, type UiSize } from "./types";

export type CardProps = Omit<ComponentProps<"section">, "title"> & {
  title: string; description?: ReactNode; actions?: ReactNode; size?: UiSize; surface?: "card" | "panel";
  headerClassName?: string; bodyClassName?: string;
};

export function Card({ title, description, actions, size = "md", surface = "card", children, className, headerClassName, bodyClassName, ...props }: CardProps) {
  const padding={sm:"p-(--tt-space-sm)",md:"p-(--tt-space-md)",lg:"p-(--tt-space-lg)"};
  return <section {...props} aria-label={props["aria-label"] ?? title} data-surface={surface} data-size={size}
    className={cx("card min-w-0 text-foreground shadow-none",surface==='panel'?"rounded-panel border-0 bg-panel p-(--tt-panel-inset)":"rounded-inner border border-line bg-surface p-0", className)}>
    <header className={cx("flex flex-wrap items-start justify-between gap-4",headerClassName??(surface==='panel'?"p-4":padding[size]))}>
      <div className="min-w-0 max-w-full"><h2 className="card-title text-base font-semibold wrap-anywhere">{title}</h2>
        {description && <p className="mt-1 text-sm text-muted">{description}</p>}
      </div>
      {actions && <div className="flex flex-wrap gap-2">{actions}</div>}
    </header>
    <div className={cx("card-body block bg-surface",surface==='panel'?"rounded-panel-inner":"rounded-inner",bodyClassName??padding[size])}>{children}</div>
  </section>;
}

export function Panel(props: Omit<CardProps, "surface">) {
  return <Card {...props} surface="panel" />;
}

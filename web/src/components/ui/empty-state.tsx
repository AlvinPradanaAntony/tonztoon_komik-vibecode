import type { ComponentProps, ReactNode } from "react";
import { Icon } from "./icon";
import { cx } from "./types";

export type EmptyStateProps = Omit<ComponentProps<"div">, "title" | "children"> & {
  title: string;
  description?: ReactNode;
  icon?: ComponentProps<typeof Icon>["name"];
  illustration?: ReactNode;
  action?: ReactNode;
  size?: "sm" | "md";
  announce?: boolean;
};

export function EmptyState({ title, description, icon="requests", illustration, action,
  size="md", announce=false, className, ...props }: EmptyStateProps) {
  return <div {...props} className={cx("tt-empty-state flex min-w-0 flex-col items-center justify-center text-center text-foreground",size==='sm'?"min-h-56 px-4 py-6":"min-h-64 px-5 py-8", className)} data-size={size} role={announce?"status":props.role}>
    <div className="mb-4 grid h-18 w-20 max-w-full place-items-center text-accent-ink [&>:is(svg,img)]:block [&>:is(svg,img)]:max-h-full [&>:is(svg,img)]:max-w-full [&>:is(svg,img)]:object-contain" aria-hidden="true">
      {illustration ?? <Icon name={icon} className="size-14 shrink-0" width="56" height="56"/>}
    </div>
    <p className="m-0 max-w-full text-base/6 font-semibold wrap-anywhere">{title}</p>
    {description && <div className="mt-2 max-w-[40ch] text-sm/relaxed text-muted wrap-anywhere [&>p]:m-0">{description}</div>}
    {action && <div className="mt-4 flex max-w-full flex-wrap justify-center gap-2">{action}</div>}
  </div>;
}

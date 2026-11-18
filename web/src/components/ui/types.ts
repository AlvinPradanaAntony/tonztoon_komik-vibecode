import { extendTailwindMerge } from "tailwind-merge";

const merge=extendTailwindMerge({extend:{theme:{radius:["field","control","inner","panel","panel-inner"]}}});

export type UiSize = "sm" | "md" | "lg";
export type UiTone = "neutral" | "info" | "success" | "warning" | "error";

export function cx(...values: (string | false | undefined)[]) {
  return merge(...values);
}

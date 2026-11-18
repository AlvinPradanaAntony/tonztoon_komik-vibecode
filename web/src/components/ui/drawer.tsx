"use client";

import { Dialog, type DialogProps } from "./dialog";

export type DrawerProps = Omit<DialogProps, "presentation">;

export function Drawer(props: DrawerProps) {
  return <Dialog {...props} presentation="drawer" />;
}

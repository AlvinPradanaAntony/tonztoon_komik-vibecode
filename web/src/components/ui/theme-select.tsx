"use client";

import { Select } from "./select";

const storageKey = "tt-admin-theme";

export function ThemeSelect() {
  return (
      <Select
        label="Tema"
        fieldClassName="min-w-36"
        defaultValue="system"
        ref={(select) => {
          if (!select) return;
          try {
            const saved = localStorage.getItem(storageKey);
            if (saved === "light" || saved === "dark") select.value = saved;
          } catch {
            // Storage is optional; the CSS system theme remains usable.
          }
        }}
        onChange={(event) => {
          const preference = event.currentTarget.value;
          if (preference === "system") delete document.documentElement.dataset.theme;
          else document.documentElement.dataset.theme = preference;
          try {
            localStorage.setItem(storageKey, preference);
          } catch {
            // The selected theme still works for this page when storage is blocked.
          }
        }}
      >
        <option value="system">Ikuti sistem</option>
        <option value="light">Terang</option>
        <option value="dark">Gelap</option>
      </Select>
  );
}

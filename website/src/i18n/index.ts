/**
 * The site's two languages, in one bundle.
 *
 * A static page on GitHub Pages has no server to negotiate `Accept-Language`,
 * so the choice is made in the browser: `?lang=` wins (a link someone shares
 * to the German page must open in German), then the visitor's remembered
 * choice, then the browser's own languages, then English. The choice is
 * written back to `<html lang>` so screen readers and hyphenation follow it,
 * and to `localStorage` so it survives a reload.
 *
 * Known limit, by decision: one URL. Crawlers index the English default; a
 * `/de/` prerender is a later pass.
 *
 * The catalogs are plain objects (`en.ts` is the shape, `de.ts` is typed
 * against it, so a missing German key is a type error, not an English word on
 * the German page).
 */
import { createI18n } from "vue-i18n";
import { watchEffect } from "vue";
import en from "./en";
import de from "./de";

export const LOCALES = ["en", "de"] as const;
export type Locale = (typeof LOCALES)[number];
export const DEFAULT_LOCALE: Locale = "en";
export const STORAGE_KEY = "mountie-site.locale";

function isLocale(v: unknown): v is Locale {
  return typeof v === "string" && (LOCALES as readonly string[]).includes(v);
}

export function resolveInitialLocale(): Locale {
  if (typeof window === "undefined") return DEFAULT_LOCALE;
  const fromQuery = new URLSearchParams(window.location.search).get("lang");
  if (isLocale(fromQuery)) return fromQuery;
  try {
    const stored = window.localStorage.getItem(STORAGE_KEY);
    if (isLocale(stored)) return stored;
  } catch {
    /* private mode, blocked storage — fall through */
  }
  const langs = navigator.languages?.length ? navigator.languages : [navigator.language];
  for (const l of langs) {
    const base = (l ?? "").toLowerCase().split("-")[0];
    if (isLocale(base)) return base;
  }
  return DEFAULT_LOCALE;
}

export const i18n = createI18n({
  legacy: false,
  locale: resolveInitialLocale(),
  fallbackLocale: DEFAULT_LOCALE,
  messages: { en, de }
});

export function setLocale(locale: Locale): void {
  i18n.global.locale.value = locale;
}

/** Mirror the live locale into the document and storage. Call once at boot. */
export function bindLocaleToDocument(): void {
  watchEffect(() => {
    const locale = i18n.global.locale.value;
    document.documentElement.lang = locale;
    try {
      window.localStorage.setItem(STORAGE_KEY, locale);
    } catch {
      /* best-effort */
    }
  });
}

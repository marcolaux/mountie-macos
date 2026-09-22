/// <reference types="vite/client" />

/**
 * Baked at build time by `vite.config.ts` (`define`), from `site.config.json`
 * — the file `release.sh` moves when it cuts a release. Textual substitution,
 * so no runtime cost.
 */
interface ImportMetaEnv {
  readonly SITE_VERSION: string;
  readonly SITE_BUILD_DATE: string;
}

declare module "*.vue" {
  import type { DefineComponent } from "vue";
  const component: DefineComponent<Record<string, unknown>, Record<string, unknown>, unknown>;
  export default component;
}

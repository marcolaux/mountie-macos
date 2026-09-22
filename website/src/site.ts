/**
 * `site.config.json`, plus the URL shape the download card needs. Installed
 * as `$site` on the app so a template can write `$site.latest(...)` without
 * each section importing the file. The JSON is the single source: the publish
 * script and vite.config read the same file.
 */
import config from "../site.config.json" with { type: "json" };

export const site = {
  ...config,
  /** The permanent "latest" download URL for one release asset. */
  latest(asset: string): string {
    return `https://github.com/${config.releasesRepo}/releases/latest/download/${asset}`;
  }
};

export type Site = typeof site;

declare module "vue" {
  interface ComponentCustomProperties {
    $site: Site;
  }
}

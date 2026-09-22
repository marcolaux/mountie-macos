import { defineConfig, type PluginOption } from "vite";
import vue from "@vitejs/plugin-vue";
import tailwindcss from "@tailwindcss/vite";
import { resolve } from "node:path";
import site from "./site.config.json" with { type: "json" };

// The website: a static single page, styled after hypha's site (same tokens,
// same section shapes), with no engine behind it.
//
// Mountie has no monorepo and no root package.json: the version and asset
// name are read from `site.config.json`, which `release.sh` updates when it
// cuts a release, so the download card always names the asset the latest
// release actually carries.
function pagesFiles(): PluginOption {
  return {
    name: "mountie-pages-files",
    apply: "build",
    // GitHub Pages reads `CNAME` off the branch root to name the custom
    // domain (a deploy without it forgets the domain); `.nojekyll` sits in
    // `public/` as a real file. The domain is written down exactly once.
    generateBundle() {
      this.emitFile({ type: "asset", fileName: "CNAME", source: `${site.domain}\n` });
    }
  };
}

export default defineConfig({
  base: "/",
  plugins: [vue(), tailwindcss(), pagesFiles()],
  define: {
    "import.meta.env.SITE_VERSION": JSON.stringify(site.version),
    "import.meta.env.SITE_BUILD_DATE": JSON.stringify(new Date().toISOString().slice(0, 10))
  },
  server: {
    // The screenshots are imported in place from the repo's /screenshots,
    // above this root.
    fs: { allow: [resolve(import.meta.dirname, "..")] }
  },
  build: {
    target: "es2022",
    // One page; hashed chunks are fine but a dozen of them is not. Keep the
    // graph to app + vendor so the publish script's budget stays legible.
    rollupOptions: {
      output: {
        manualChunks: (id) => (id.includes("node_modules") ? "vendor" : undefined)
      }
    }
  }
});

<script setup lang="ts">
import { useI18n } from "vue-i18n";
import AppIcon from "../components/AppIcon.vue";
import LangSwitch from "../components/LangSwitch.vue";

const { t } = useI18n();
const links = [
  { id: "why", key: "nav.why" },
  { id: "automatic", key: "nav.automatic" },
  { id: "shares", key: "nav.shares" },
  { id: "s3", key: "nav.s3" }
] as const;
</script>

<template>
  <header class="nav">
    <a class="skip" href="#main">{{ t("nav.skip") }}</a>
    <div class="wrap nav-row">
      <a href="#top" class="brand" aria-label="Mountie">
        <span class="brand-mark"><AppIcon /></span>
        <span class="brand-name">Mountie</span>
      </a>
      <nav class="links" :aria-label="t('nav.label')">
        <a v-for="l in links" :key="l.id" :href="`#${l.id}`">{{ t(l.key) }}</a>
        <a :href="`https://github.com/${$site.sourceRepo}`" rel="noopener">{{ t("nav.source") }}</a>
      </nav>
      <div class="right">
        <LangSwitch />
        <a href="#download" class="btn btn-primary nav-cta">{{ t("nav.download") }}</a>
      </div>
    </div>
  </header>
</template>

<style scoped>
.nav {
  position: sticky;
  top: 0;
  z-index: 20;
  /* The one blur on the page: content really does scroll beneath it. */
  background: color-mix(in oklab, var(--background) 72%, transparent);
  -webkit-backdrop-filter: blur(14px);
  backdrop-filter: blur(14px);
  border-bottom: 1px solid var(--hairline);
}
.skip {
  position: absolute;
  left: 1rem;
  top: -3rem;
  padding: 0.5rem 0.75rem;
  background: var(--overlay);
  color: var(--heading);
  border-radius: 8px;
}
.skip:focus {
  top: 0.75rem;
}
.nav-row {
  display: flex;
  align-items: center;
  gap: 1.5rem;
  height: 3.5rem;
}
.brand {
  display: inline-flex;
  align-items: center;
  gap: 0.5rem;
  color: var(--heading);
  font-weight: 600;
  font-size: 1.0625rem;
}
.brand-mark {
  display: inline-block;
  width: 1.7rem;
}
.links {
  display: none;
  gap: 1.25rem;
  font-size: 0.875rem;
  color: var(--paragraph);
}
.links a:hover {
  color: var(--heading);
}
.right {
  margin-left: auto;
  display: flex;
  align-items: center;
  gap: 0.75rem;
}
@media (max-width: 40rem) {
  /* Brand + language switch fill the bar; the hero's own CTA is directly
     below, so the button would only clip. */
  .nav-cta {
    display: none;
  }
}
@media (min-width: 52rem) {
  .links {
    display: flex;
  }
}
</style>

<script setup lang="ts">
import { useI18n } from "vue-i18n";

const { t } = useI18n();
const version = import.meta.env.SITE_VERSION;
const built = import.meta.env.SITE_BUILD_DATE;
</script>

<template>
  <section id="download" class="wrap section dl-sec">
    <p class="eyebrow">{{ t("download.eyebrow") }}</p>
    <h2 class="dl-title">{{ t("download.title") }}</h2>
    <p class="lede">{{ t("download.lede") }}</p>
    <div class="dl">
      <a class="card dl-card" :href="$site.latest($site.assets.mac)" rel="noopener">
        <span class="k">{{ t("download.mac") }}</span>
        <span class="v">{{ $site.assets.mac }} · {{ t("download.macNote") }}</span>
      </a>
    </div>
    <p class="meta">
      {{ t("download.version", { v: version, d: built }) }} ·
      <a :href="`https://github.com/${$site.releasesRepo}/releases`" rel="noopener">{{ t("download.releases") }}</a> ·
      <a :href="`https://github.com/${$site.sourceRepo}#readme`" rel="noopener">{{ t("download.readFirst") }}</a>
    </p>
  </section>
</template>

<style scoped>
/* The close: centred, like Linear's "Built for the future. Available today." */
.dl-sec {
  display: flex;
  flex-direction: column;
  align-items: center;
  text-align: center;
  padding-block: clamp(5rem, 12vw, 10rem);
}
.dl-title {
  font-size: clamp(2.25rem, 5vw, 4rem);
  line-height: 1.02;
  margin: 0.75rem 0 1rem;
  max-width: 14ch;
}
.lede {
  margin: 0;
}
.dl {
  width: 100%;
  max-width: 22rem;
  display: grid;
  gap: 0.75rem;
  margin-top: 2.5rem;
  text-align: left;
}
.dl-card {
  display: flex;
  flex-direction: column;
  gap: 0.25rem;
  padding: 1.1rem 1.25rem;
  transition: background-color 120ms ease;
}
.dl-card:hover {
  background: color-mix(in oklab, var(--card) 90%, var(--paragraph));
}
.k {
  color: var(--heading);
  font-weight: 510;
}
.v {
  color: var(--muted);
  font-size: 0.8125rem;
  font-family: var(--font-mono);
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.meta {
  margin: 1.5rem 0 0;
  color: var(--muted);
  font-size: 0.9rem;
}
.meta a {
  color: var(--paragraph);
  text-decoration: underline;
  text-underline-offset: 3px;
}
</style>

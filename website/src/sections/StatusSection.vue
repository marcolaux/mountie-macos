<script setup lang="ts">
import { useI18n } from "vue-i18n";

const { t } = useI18n();
</script>

<template>
  <section id="status" class="wrap section">
    <div class="card status">
      <p class="eyebrow">{{ t("status.eyebrow") }}</p>
      <h2 class="h-section">{{ t("status.title") }}</h2>
      <p class="lede">{{ t("status.body") }}</p>
      <p class="links">
        <a :href="`https://github.com/${$site.sourceRepo}#readme`" rel="noopener">{{ t("status.readme") }} →</a>
        <a :href="`https://github.com/${$site.releasesRepo}/releases`" rel="noopener">{{ t("status.releases") }} →</a>
      </p>
    </div>
  </section>
</template>

<style scoped>
.status {
  padding: clamp(1.5rem, 4vw, 3rem);
}
.links {
  display: flex;
  flex-wrap: wrap;
  gap: 1.5rem;
  margin: 1.5rem 0 0;
  font-weight: 500;
  color: var(--heading);
}
</style>

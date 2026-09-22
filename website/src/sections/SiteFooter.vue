<script setup lang="ts">
import { useI18n } from "vue-i18n";

const { t } = useI18n();
const year = new Date().getFullYear();
</script>

<template>
  <footer class="foot">
    <div class="wrap foot-row">
      <nav class="fl" :aria-label="t('footer.label')">
        <a :href="`https://github.com/${$site.releasesRepo}/releases`" rel="noopener">{{ t("footer.releases") }}</a>
        <a :href="`https://github.com/${$site.sourceRepo}#readme`" rel="noopener">{{ t("footer.readme") }}</a>
        <a :href="`https://github.com/${$site.sourceRepo}`" rel="noopener">{{ t("footer.source") }}</a>
        <a href="mailto:hi@marcolaux.com">{{ t("footer.contact") }}</a>
      </nav>
      <p class="made">{{ t("footer.made", { year }) }} · {{ t("footer.by") }} <a href="https://miniml.net" rel="noopener">miniml</a></p>
    </div>
  </footer>
</template>

<style scoped>
.foot {
  border-top: 1px solid var(--hairline);
  padding-block: 2rem 3rem;
  font-size: 0.875rem;
}
.foot-row {
  display: flex;
  flex-wrap: wrap;
  gap: 1rem 2rem;
  align-items: baseline;
  justify-content: space-between;
}
.fl {
  display: flex;
  flex-wrap: wrap;
  gap: 1.25rem;
  color: var(--paragraph);
}
.fl a:hover {
  color: var(--heading);
}
.made {
  margin: 0;
  color: var(--muted);
}
.made a:hover {
  color: var(--heading);
}
</style>

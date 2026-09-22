<script setup lang="ts">
import { useI18n } from "vue-i18n";

const { t } = useI18n();
const items = ["menubar", "sidebar", "quitUnmount", "keychain", "cli", "prefs"] as const;
</script>

<template>
  <section id="more" class="wrap section">
    <p class="eyebrow">{{ t("more.eyebrow") }}</p>
    <h2 class="h-section">{{ t("more.title") }}</h2>
    <ul class="grid">
      <li v-for="i in items" :key="i" class="cell">
        <h3>{{ t(`more.${i}.title`) }}</h3>
        <p>{{ t(`more.${i}.body`) }}</p>
      </li>
    </ul>
  </section>
</template>

<style scoped>
.grid {
  list-style: none;
  margin: 2rem 0 0;
  padding: 0;
  display: grid;
  grid-template-columns: 1fr;
  gap: 1px;
  background: var(--hairline);
  border-block: 1px solid var(--hairline);
}
@media (min-width: 40rem) {
  .grid {
    grid-template-columns: repeat(2, 1fr);
  }
}
@media (min-width: 60rem) {
  .grid {
    grid-template-columns: repeat(3, 1fr);
  }
}
.cell {
  background: var(--ground);
  padding: 1.5rem 1.5rem 1.5rem 0;
}
@media (min-width: 40rem) {
  .cell {
    padding: 1.75rem 2rem 1.75rem 1.5rem;
  }
  .cell:first-child,
  .cell:nth-child(3n + 1) {
    padding-left: 0;
  }
}
.cell h3 {
  font-size: 1rem;
  margin: 0 0 0.4rem;
  letter-spacing: -0.01em;
}
.cell p {
  margin: 0;
  color: var(--muted);
  font-size: 0.9375rem;
  line-height: 1.55;
  max-width: 22rem;
}
</style>

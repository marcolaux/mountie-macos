<script setup lang="ts">
import { useI18n } from "vue-i18n";
import { LOCALES, setLocale, type Locale } from "../i18n";

const { t, locale } = useI18n();
const pick = (l: Locale) => setLocale(l);
</script>

<template>
  <div class="lang" role="group" :aria-label="t('lang.label')">
    <button
      v-for="l in LOCALES"
      :key="l"
      class="lang-btn"
      :class="{ on: locale === l }"
      :aria-pressed="locale === l"
      :lang="l"
      @click="pick(l)"
    >
      {{ l.toUpperCase() }}
    </button>
  </div>
</template>

<style scoped>
.lang {
  display: inline-flex;
  padding: 2px;
  border-radius: 999px;
  box-shadow: var(--btn-ring);
  background: var(--btn-fill);
}
.lang-btn {
  font: inherit;
  font-size: 0.75rem;
  font-weight: 600;
  letter-spacing: 0.03em;
  color: var(--muted);
  background: none;
  border: 0;
  padding: 0.25rem 0.55rem;
  border-radius: 999px;
  cursor: pointer;
}
.lang-btn.on {
  background: var(--fill-active);
  color: var(--heading);
}
</style>

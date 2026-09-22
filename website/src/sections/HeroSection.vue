<script setup lang="ts">
import { useI18n } from "vue-i18n";
import AppIcon from "../components/AppIcon.vue";
import Shot from "../components/Shot.vue";
import mainWindow from "../../../screenshots/main-window.png";

const { t } = useI18n();
</script>

<template>
  <section id="top" class="hero">
    <div class="wrap hero-top">
      <h1 class="hero-title"><span class="hero-mark"><AppIcon /></span>{{ t("hero.title") }}</h1>
      <p class="hero-lede">{{ t("hero.lede") }}</p>
      <div class="cta">
        <a href="#download" class="btn btn-primary">{{ t("hero.ctaMac") }}</a>
        <a :href="`https://github.com/${$site.sourceRepo}`" class="btn btn-ghost" rel="noopener">{{ t("hero.ctaSource") }}</a>
      </div>
    </div>
    <!-- The stage: the frame sits in a pool of light, wider than the words,
         and is cut off before its foot — the cut is what makes the frame read
         as a window onto a running program rather than a picture of one. -->
    <div class="stage">
      <div class="wrap-wide">
        <Shot
          name="main-window"
          :src="mainWindow"
          :alt="t('shares.alt')"
          :focus="{ x: 8, y: 5, w: 84 }"
          :focus-narrow="{ x: 16, y: 8, w: 68 }"
          :ratio="16 / 9"
          :ratio-narrow="4 / 3"
          eager
        />
        <p class="hint">{{ t("hero.hint") }}</p>
      </div>
    </div>
  </section>
</template>

<style scoped>
.hero {
  padding-top: clamp(3.5rem, 9vw, 7.5rem);
}
.hero-top {
  display: flex;
  flex-direction: column;
  align-items: flex-start;
  gap: 1.25rem;
}
.hero-mark {
  display: inline-block;
  width: 0.85em;
  margin-right: 0.35em;
  vertical-align: -0.1em;
}
.hero-title {
  font-size: clamp(2.5rem, 6.4vw, 4.75rem);
  line-height: 1;
  letter-spacing: -0.03em;
  margin: 0;
  max-width: 22ch;
}
.hero-lede {
  margin: 0;
  color: var(--paragraph);
  font-size: clamp(1.0625rem, 1.5vw, 1.25rem);
  line-height: 1.5;
  max-width: 44rem;
}
.cta {
  display: flex;
  flex-wrap: wrap;
  gap: 0.75rem;
  margin-top: 0.75rem;
}
.stage {
  position: relative;
  margin-top: clamp(2.5rem, 6vw, 5rem);
  padding-bottom: 1rem;
}
.stage::before {
  content: "";
  position: absolute;
  inset: -20% 0 0;
  background: var(--pool);
  pointer-events: none;
}
.stage > * {
  position: relative;
}
.hint {
  margin: 0;
  text-align: center;
  color: var(--muted);
  font-size: 0.75rem;
}
</style>

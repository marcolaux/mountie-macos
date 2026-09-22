<script setup lang="ts">
/**
 * One capability as an image/text split: a full-width rule, then the words
 * and the product side by side, alternating sides per section (`flip`). The
 * words stay in a narrower column (eyebrow, title, body, the detail points
 * under them); the media gets its own column and keeps its natural aspect —
 * Mountie's windows are tall, so no cropping.
 *
 * The `k` prop is the catalog prefix (`shares`, `protocols`, …); points are
 * `p1`…`pN` until one is missing, so a section adds a point by adding a key.
 */
import { computed } from "vue";
import { useI18n } from "vue-i18n";

const props = defineProps<{ id: string; k: string; flip?: boolean }>();
const { t, te } = useI18n();
const points = computed(() => {
  const out: string[] = [];
  for (let i = 1; i <= 8; i++) {
    const key = `${props.k}.p${i}`;
    if (!te(key)) break;
    out.push(t(key));
  }
  return out;
});
</script>

<template>
  <section :id="id" class="feat">
    <hr class="rule" />
    <div class="wrap split section" :class="{ flip }">
      <div class="split-text">
        <p class="eyebrow">{{ t(`${k}.eyebrow`) }}</p>
        <h2 class="feat-title">{{ t(`${k}.title`) }}</h2>
        <p class="lede">{{ t(`${k}.body`) }}</p>
        <slot name="after" />
        <ul v-if="points.length" class="feat-list">
          <li v-for="p in points" :key="p"><span class="plus" aria-hidden="true">+</span><span>{{ p }}</span></li>
        </ul>
      </div>
      <div class="split-media">
        <slot />
      </div>
    </div>
  </section>
</template>

<style scoped>
.split {
  display: grid;
  grid-template-columns: 1fr;
  gap: 2.5rem;
  align-items: center;
}
@media (min-width: 56rem) {
  .split {
    grid-template-columns: 5fr 6fr;
    gap: 4rem;
  }
  /* Flipped: the media takes the left column. */
  .flip .split-text {
    order: 2;
  }
  .flip .split-media {
    order: 1;
  }
}
.split-text {
  display: flex;
  flex-direction: column;
  min-width: 0;
}
.feat-title {
  font-size: clamp(1.75rem, 3.4vw, 2.5rem);
  line-height: 1.06;
  margin: 0.75rem 0 1rem;
  max-width: 18ch;
}
.split-text .lede {
  margin: 0;
}
.feat-list {
  margin: 1.75rem 0 0;
  padding: 0;
  list-style: none;
  display: flex;
  flex-direction: column;
  gap: 0.75rem;
  max-width: 44rem;
}
.feat-list li {
  display: flex;
  gap: 0.6rem;
  align-items: flex-start;
  font-size: 0.9375rem;
  line-height: 1.5;
  color: var(--paragraph);
}
.plus {
  flex: none;
  color: var(--muted);
  font-weight: 500;
  margin-top: 0.05em;
}
.split-media {
  min-width: 0;
}
@media (min-width: 56rem) {
  /* The window shots are portrait; capped so they don't run away vertically.
     An explicit width, not max-width: with justify-self the item would size
     to its content's intrinsic width — and the Shot's img is absolutely
     positioned, so the figure would collapse to its 2px border. */
  .split-media {
    width: min(30rem, 100%);
  }
  .flip .split-media {
    justify-self: start;
  }
  .split:not(.flip) .split-media {
    justify-self: end;
  }
}
</style>

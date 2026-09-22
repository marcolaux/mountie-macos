<script setup lang="ts">
/**
 * A screenshot, as a piece of the app. Adapted from hypha's Shot.vue: mountie's
 * shots are single-scheme PNGs referenced in place from the repo's
 * /screenshots, so the dark/light and multi-format plumbing is gone; what stays
 * is the crop.
 *
 * A `focus` (percent box: the left/top of the region and its width as a share
 * of the image) shows one PART of the shot at a size where its text can be
 * read: a fragment of the real program large, not the whole program small.
 * The frame keeps its aspect and the image is scaled so the region fills the
 * frame's width; whatever falls below the frame is clipped, and `fade` melts
 * the frame's right and bottom edges into the page so the crop reads as a
 * window, not a thumbnail.
 *
 * A name with no `src` renders a labelled placeholder rather than a broken
 * image, so a missing shot is visible instead of blank.
 */
import { computed } from "vue";
import { useI18n } from "vue-i18n";

const props = withDefaults(
  defineProps<{
    name: string;
    alt: string;
    /** The image URL, imported by the caller. Missing → placeholder. */
    src?: string;
    /** The frame's aspect ratio, `w / h`. */
    ratio?: number;
    /** The region of the image to show: left and top in percent, width as a percent of the image. */
    focus?: { x: number; y: number; w: number };
    /** A tighter region for a phone, where the desktop crop shrinks past reading. */
    focusNarrow?: { x: number; y: number; w: number };
    /** The frame's aspect on a phone; defaults to a taller 4:3. */
    ratioNarrow?: number;
    fade?: boolean;
    eager?: boolean;
  }>(),
  { ratio: 16 / 9, ratioNarrow: 4 / 3, fade: true, eager: false }
);

const { t } = useI18n();
const has = computed(() => Boolean(props.src));

/* The image is `100 / w` frame-widths wide and shifted so the region's corner
   sits at the frame's corner. The two crops are custom properties on the
   frame and a media query picks one, so the switch costs no script. */
const wide = computed(() => props.focus ?? { x: 0, y: 0, w: 100 });
const narrow = computed(() => props.focusNarrow ?? wide.value);
const frameStyle = computed(() => ({
  "--ratio": String(props.ratio),
  "--ratio-n": String(props.ratioNarrow),
  "--z": String(100 / wide.value.w),
  "--x": String(wide.value.x),
  "--y": String(wide.value.y),
  "--z-n": String(100 / narrow.value.w),
  "--x-n": String(narrow.value.x),
  "--y-n": String(narrow.value.y)
}));
</script>

<template>
  <figure class="shot" :class="{ fade }" :style="frameStyle">
    <img
      v-if="has"
      :src="src"
      :alt="alt"
      :loading="eager ? 'eager' : 'lazy'"
      decoding="async"
    />
    <div v-else class="shot-pending" role="img" :aria-label="alt">
      <span class="shot-pending__k">{{ t("shot.pending") }}</span>
      <code>{{ name }}</code>
    </div>
  </figure>
</template>

<style scoped>
.shot {
  position: relative;
  margin: 0;
  width: 100%;
  aspect-ratio: var(--ratio);
  overflow: hidden;
  border-radius: 12px;
  border: 1px solid var(--hairline-strong);
  background: var(--background);
  box-shadow:
    0 0 0 1px color-mix(in oklab, black 35%, transparent),
    0 40px 100px -30px color-mix(in oklab, black 70%, transparent);
}
.shot.fade {
  -webkit-mask-image: linear-gradient(to bottom, black 55%, transparent 100%);
  mask-image: linear-gradient(to bottom, black 55%, transparent 100%);
  border-bottom-color: transparent;
  box-shadow: none;
}
.shot img {
  display: block;
  position: absolute;
  top: 0;
  left: 0;
  height: auto;
  max-width: none;
  width: calc(var(--z) * 100%);
  transform: translate(calc(var(--x) * -1%), calc(var(--y) * -1%));
  transform-origin: top left;
}
@media (max-width: 48rem) {
  .shot {
    aspect-ratio: var(--ratio-n);
  }
  .shot img {
    width: calc(var(--z-n) * 100%);
    transform: translate(calc(var(--x-n) * -1%), calc(var(--y-n) * -1%));
  }
}
.shot-pending {
  position: absolute;
  inset: 0;
  display: grid;
  place-content: center;
  gap: 0.25rem;
  text-align: center;
  color: var(--muted);
  font-size: 0.8125rem;
  background:
    repeating-linear-gradient(135deg, transparent 0 14px, var(--hairline) 14px 15px),
    var(--card);
}
.shot-pending__k {
  font-weight: 600;
}
</style>

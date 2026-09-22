<script setup lang="ts">
/**
 * The idea in three figures, in the shape Linear's "Fig 0.1–0.3" row takes:
 * a hairline between columns, a line drawing above each, a short title, a
 * short body. The drawings are hairline strokes, so they read as
 * illustrations, not icons.
 */
import { useI18n } from "vue-i18n";

const { t } = useI18n();
const cols = ["noadmin", "finder", "quit"] as const;
</script>

<template>
  <section id="why" class="why">
    <hr class="rule" />
    <div class="wrap section">
      <div class="cols">
        <div v-for="(c, i) in cols" :key="c" class="col">
          <span class="fig eyebrow">Fig. 0.{{ i + 1 }}</span>
          <svg class="art" viewBox="0 0 240 160" aria-hidden="true" fill="none" stroke="currentColor" stroke-width="1.25" stroke-linejoin="round" stroke-linecap="round">
            <!-- 0.1 No admin password: an open padlock. -->
            <template v-if="c === 'noadmin'">
              <rect x="88" y="76" width="64" height="52" rx="8" />
              <path d="M100 76V58a20 20 0 0 1 40 0" />
              <circle cx="120" cy="102" r="6" />
              <path d="M120 108v8" />
            </template>
            <!-- 0.2 Finder-native: a Finder window — sidebar to the left, and
                 one of its rows lit as the mounted share. -->
            <template v-else-if="c === 'finder'">
              <rect x="40" y="36" width="160" height="96" rx="10" />
              <circle cx="54" cy="50" r="3" />
              <circle cx="66" cy="50" r="3" />
              <circle cx="78" cy="50" r="3" />
              <path d="M40 62h160" />
              <path d="M94 62v70" />
              <path d="M104 76h72 M104 90h56 M104 104h64" opacity="0.55" />
              <rect x="48" y="72" width="38" height="14" rx="7" />
              <circle cx="55" cy="79" r="2.5" fill="currentColor" />
            </template>
            <!-- 0.3 Leaves when you do: an app window with an arrow walking
                 out of it — the clean exit. -->
            <template v-else>
              <rect x="52" y="44" width="84" height="72" rx="10" />
              <path d="M52 70h84" opacity="0.55" />
              <path d="M118 92h52" />
              <path d="M158 80l16 12-16 12" />
              <path d="M104 104h24 M104 118h32" opacity="0.55" />
            </template>
          </svg>
          <h3>{{ t(`why.${c}.title`) }}</h3>
          <p>{{ t(`why.${c}.body`) }}</p>
        </div>
      </div>
    </div>
  </section>
</template>

<style scoped>
.cols {
  display: grid;
  grid-template-columns: 1fr;
  gap: 2.5rem 0;
}
@media (min-width: 48rem) {
  .cols {
    grid-template-columns: repeat(3, 1fr);
  }
  .col + .col {
    border-left: 1px solid var(--hairline);
    padding-left: 2.5rem;
  }
  .col {
    padding-right: 2.5rem;
  }
}
.col {
  display: flex;
  flex-direction: column;
}
.fig {
  font-variant-numeric: tabular-nums;
}
.art {
  width: min(100%, 17rem);
  height: auto;
  margin: 1.75rem 0 1.5rem;
  color: var(--muted);
  opacity: 0.8;
}
h3 {
  font-size: 1rem;
  font-weight: 510;
  margin: 0 0 0.5rem;
  letter-spacing: -0.01em;
}
p {
  margin: 0;
  color: var(--muted);
  line-height: 1.6;
  font-size: 0.9375rem;
  max-width: 24rem;
}
</style>

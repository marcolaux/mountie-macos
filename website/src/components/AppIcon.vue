<script setup lang="ts">
/**
 * The app's own icon, extracted from icon/AppIcon.icns by scripts/icons.sh.
 * It fills its parent: the nav gives it 1.9rem, the hero up to 4.25rem.
 */
import icon from "../assets/app-icon.png";
</script>

<template>
  <img :src="icon" alt="" aria-hidden="true" draggable="false" />
</template>

<style scoped>
img {
  display: block;
  width: 100%;
  height: auto;
}
</style>

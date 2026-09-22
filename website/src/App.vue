<script setup lang="ts">
import { useI18n } from "vue-i18n";
import SiteNav from "./sections/SiteNav.vue";
import HeroSection from "./sections/HeroSection.vue";
import WhySection from "./sections/WhySection.vue";
import FeatureSection from "./sections/FeatureSection.vue";
import MoreGrid from "./sections/MoreGrid.vue";
import StatusSection from "./sections/StatusSection.vue";
import DownloadSection from "./sections/DownloadSection.vue";
import SiteFooter from "./sections/SiteFooter.vue";
import Shot from "./components/Shot.vue";
import mainWindow from "../../screenshots/main-window.png";
import editShare from "../../screenshots/edit-share.png";
import editAutomatic from "../../screenshots/edit-automatic.png";

const { t } = useI18n();
</script>

<template>
  <SiteNav />
  <main id="main">
    <HeroSection />
    <WhySection />

    <!-- Image/text splits, in story order: the automatic, context-aware
         mounting is the pitch and leads; manual control follows; then what
         Mountie speaks. `focus` (percent box: left/top/width of the region)
         trims the PNG's transparent margin, so the window fills its frame;
         `ratio` keeps that region's own aspect — no crop. -->
    <FeatureSection id="automatic" k="automatic">
      <Shot name="edit-automatic" :src="editAutomatic" :alt="t('automatic.alt')" :focus="{ x: 9.5, y: 6.5, w: 81 }" :ratio="1.035" :ratio-narrow="1.035" :fade="false" eager />
    </FeatureSection>

    <FeatureSection id="shares" k="shares" flip>
      <Shot name="main-window" :src="mainWindow" :alt="t('shares.alt')" :focus="{ x: 8.5, y: 5.5, w: 82.5 }" :ratio="0.975" :ratio-narrow="0.975" :fade="false" eager />
    </FeatureSection>

    <FeatureSection id="protocols" k="protocols">
      <Shot name="edit-share" :src="editShare" :alt="t('protocols.alt')" :focus="{ x: 9.5, y: 6.5, w: 81 }" :ratio="1.035" :ratio-narrow="1.035" :fade="false" eager />
    </FeatureSection>

    <FeatureSection id="s3" k="s3" flip>
      <!-- The config file is the honest artifact here. -->
      <div class="card code">
        <pre><code><span class="c-c"># name   address                            [NFS mount options]</span>
<span class="c-n">media</span>    nfs://nas.example.com/volume1/media        ro,soft
<span class="c-n">files</span>    smb://alex@nas.example.com/Time%20Machine
<span class="c-n">cloud</span>    https://dav.example.com/remote.php/dav</code></pre>
        <p class="code-note">{{ t("s3.codeNote") }}</p>
      </div>
    </FeatureSection>

    <MoreGrid />
    <StatusSection />
    <DownloadSection />
  </main>
  <SiteFooter />
</template>

<style scoped>
.code {
  padding: 1.25rem 1.5rem;
}
.code pre {
  margin: 0;
  overflow-x: auto;
  font-size: 0.8125rem;
  line-height: 1.7;
  color: var(--heading);
}
.c-n {
  color: var(--heading);
  font-weight: 600;
}
.c-c {
  color: var(--muted);
  user-select: none;
}
.code-note {
  margin: 0.75rem 0 0;
  color: var(--muted);
  font-size: 0.85rem;
}
</style>

import { createApp } from "vue";
import App from "./App.vue";
import { i18n, bindLocaleToDocument } from "./i18n";
import { site } from "./site";
import "./styles/site.css";

const app = createApp(App);
app.config.globalProperties.$site = site;
app.use(i18n).mount("#app");
bindLocaleToDocument();

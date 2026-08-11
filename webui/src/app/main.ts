import { createApp } from "vue";
import { createPinia } from "pinia";
import App from "./App.vue";
import { setupVant } from "./plugins/vant";
import router from "@/router";
import "@/styles/index.scss";

const app = createApp(App);
const pinia = createPinia();
setupVant(app);
app.use(pinia);
app.use(router);
app.mount("#app");

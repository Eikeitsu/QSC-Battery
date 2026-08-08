import { createApp } from "vue";
import App from "./App.vue";
import { setupVant } from "./plugins/vant";
import router from "@/router";
import "@/styles/index.scss";

const app = createApp(App);
setupVant(app);
app.use(router);
app.mount("#app");

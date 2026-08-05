import { createApp } from "vue";
import {
  Button,
  Cell,
  CellGroup,
  Checkbox,
  Collapse,
  CollapseItem,
  Empty,
  Field,
  NavBar,
  Popup,
  PullRefresh,
  Search,
  Slider,
  Switch,
  Tabbar,
  TabbarItem,
  Tag,
  showConfirmDialog,
  showSuccessToast,
  showToast,
} from "vant";
import "vant/lib/index.css";
import App from "./App.vue";
import "./styles/index.scss";

const app = createApp(App);
[
  Button,
  Cell,
  CellGroup,
  Checkbox,
  Collapse,
  CollapseItem,
  Empty,
  Field,
  NavBar,
  Popup,
  PullRefresh,
  Search,
  Slider,
  Switch,
  Tabbar,
  TabbarItem,
  Tag,
].forEach((c) => app.use(c));

app.config.globalProperties.$toast = showToast;
app.config.globalProperties.$success = showSuccessToast;
app.config.globalProperties.$confirm = showConfirmDialog;

app.mount("#app");

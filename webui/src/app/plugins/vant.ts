import type { App } from "vue";
import {
  Button,
  Cell,
  CellGroup,
  Checkbox,
  Collapse,
  CollapseItem,
  Empty,
  Field,
  Loading,
  NavBar,
  PickerGroup,
  Popup,
  PullRefresh,
  Search,
  Slider,
  Switch,
  Tabbar,
  TabbarItem,
  Tag,
  TimePicker,
  showConfirmDialog,
  showSuccessToast,
  showToast,
} from "vant";
import "vant/lib/index.css";

const components = [
  Button,
  Cell,
  CellGroup,
  Checkbox,
  Collapse,
  CollapseItem,
  Empty,
  Field,
  Loading,
  NavBar,
  PickerGroup,
  Popup,
  PullRefresh,
  Search,
  Slider,
  Switch,
  Tabbar,
  TabbarItem,
  Tag,
  TimePicker,
];

export function setupVant(app: App): void {
  components.forEach((c) => app.use(c));
  app.config.globalProperties.$toast = showToast;
  app.config.globalProperties.$success = showSuccessToast;
  app.config.globalProperties.$confirm = showConfirmDialog;
}

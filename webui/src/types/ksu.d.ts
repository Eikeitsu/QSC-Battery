/// <reference types="vite/client" />

declare module "*.vue" {
  import type { DefineComponent } from "vue";
  const component: DefineComponent<object, object, unknown>;
  export default component;
}

interface KsuExecCallback {
  (errno: number, stdout: string, stderr: string): void;
}

interface KsuBridge {
  exec: (cmd: string, optionsOrCb: string | KsuExecCallback, cb?: string) => void;
  listUserPackages?: () => string;
  listAllPackages?: () => string;
  getPackagesInfo?: (pkgsJson: string) => string;
  setLightStatusBars?: (light: boolean) => void;
  setLightNavigationBars?: (light: boolean) => void;
}

interface StatusBarApi {
  setLightStatusBars?: (light: boolean) => void;
  setLightNavigationBars?: (light: boolean) => void;
}

interface Window {
  ksu?: KsuBridge;
  mmrl?: StatusBarApi;
  $QSC_Battery?: StatusBarApi;
}

declare const ksu: KsuBridge | undefined;

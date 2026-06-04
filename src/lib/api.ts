import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";

export type UiDevice = {
  provider: string;
  id: string;
  name: string;
  values: Record<string, unknown>;
};
export type Snapshot = { devices: UiDevice[]; mqtt: string };
export type Settings = { host: string; port: number; username: string; interval_minutes: number };

export const getSnapshot = () => invoke<Snapshot>("get_snapshot");
export const loadSettings = () => invoke<Settings>("load_settings");
export const saveSettings = (settings: Settings, password: string) =>
  invoke<void>("save_settings", { settings, password });
export const testConnection = (settings: Settings, password: string) =>
  invoke<void>("test_connection", { settings, password });
export const quit = () => invoke<void>("quit");
export const onSnapshot = (cb: (s: Snapshot) => void) => listen<Snapshot>("snapshot", (e) => cb(e.payload));

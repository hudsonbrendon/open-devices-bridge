<script lang="ts">
  import { onMount } from "svelte";
  import { loadSettings, saveSettings, testConnection, type Settings } from "./api";

  let s = $state<Settings>({ host: "", port: 1883, username: "", interval_minutes: 5 });
  let password = $state("");
  let testMsg = $state("");
  let testing = $state(false);

  onMount(async () => { s = await loadSettings(); });

  async function runTest() {
    testing = true; testMsg = "";
    try { await testConnection($state.snapshot(s), password); testMsg = "✓ Conectado"; }
    catch (e) { testMsg = "✗ " + e; }
    finally { testing = false; }
  }
  async function save() { await saveSettings($state.snapshot(s), password); }
</script>

<form class="settings" onsubmit={(e) => { e.preventDefault(); save(); }}>
  <h1>Home Assistant — MQTT</h1>
  <label>Broker (host)<input bind:value={s.host} placeholder="192.168.31.150" /></label>
  <label>Porta<input type="number" bind:value={s.port} /></label>
  <label>Usuário<input bind:value={s.username} placeholder="opcional" /></label>
  <label>Senha<input type="password" bind:value={password} placeholder="opcional" /></label>
  <label>Intervalo (min)<input type="number" min="1" bind:value={s.interval_minutes} /></label>
  <div class="row">
    <button type="button" onclick={runTest} disabled={testing}>{testing ? "Testando…" : "Testar conexão"}</button>
    <span class="msg">{testMsg}</span>
    <span class="spacer"></span>
    <button type="submit" class="primary">Salvar</button>
  </div>
</form>

<style>
  .settings { display: flex; flex-direction: column; gap: 12px; padding: 20px; }
  h1 { font-size: 14px; margin: 0 0 4px; }
  label { display: grid; grid-template-columns: 120px 1fr; align-items: center; gap: 10px; font-size: 13px; }
  input { font: inherit; padding: 6px 8px; border-radius: 6px; border: 1px solid rgba(127,127,127,0.4); background: transparent; color: inherit; }
  .row { display: flex; align-items: center; gap: 10px; margin-top: 8px; }
  .msg { font-size: 12px; opacity: 0.7; }
  .spacer { flex: 1; }
  button { font: inherit; font-size: 13px; padding: 6px 14px; border-radius: 6px; border: none; background: rgba(127,127,127,0.18); cursor: pointer; }
  button.primary { background: #0a84ff; color: white; }
  button:disabled { opacity: 0.5; }
</style>

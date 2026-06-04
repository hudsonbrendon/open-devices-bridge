<script lang="ts">
  import { onMount } from "svelte";
  import { getSnapshot, onSnapshot, quit, type Snapshot } from "./api";

  let snap = $state<Snapshot>({ devices: [], mqtt: "disconnected" });

  onMount(async () => {
    snap = await getSnapshot();
    onSnapshot((s) => (snap = s));
  });

  function battery(d: Record<string, unknown>): number | null {
    const b = d.battery;
    return typeof b === "number" ? b : null;
  }
  function inUse(d: Record<string, unknown>): boolean {
    return d.in_use === true;
  }
  function openSettings() {
    window.location.search = "?settings";
  }
  const mqttLabel: Record<string, string> = {
    connected: "conectado",
    connecting: "conectando…",
    disconnected: "desconectado",
  };
</script>

<div class="panel">
  <header>Open Devices Bridge</header>
  {#if snap.devices.length === 0}
    <p class="empty">Nenhum dispositivo</p>
  {/if}
  <ul>
    {#each snap.devices as d (d.provider + d.id)}
      <li>
        <span class="name">{d.name}</span>
        {#if battery(d.values) !== null}
          <span class="bar"><i style="width:{battery(d.values)}%"></i></span>
          <span class="pct">{battery(d.values)}%</span>
        {:else if "in_use" in d.values}
          <span class="chip" class:on={inUse(d.values)}>{inUse(d.values) ? "em uso" : "livre"}</span>
        {/if}
      </li>
    {/each}
  </ul>
  <footer>
    <span class="mqtt" data-s={snap.mqtt}>MQTT: {mqttLabel[snap.mqtt] ?? snap.mqtt}</span>
    <span class="spacer"></span>
    <button onclick={openSettings}>Configurações</button>
    <button onclick={quit}>Sair</button>
  </footer>
</div>

<style>
  .panel { display: flex; flex-direction: column; height: 100vh; box-sizing: border-box; padding: 12px; gap: 8px; }
  header { font-weight: 600; font-size: 13px; opacity: 0.8; }
  ul { list-style: none; margin: 0; padding: 0; display: flex; flex-direction: column; gap: 8px; overflow: auto; flex: 1; }
  li { display: flex; align-items: center; gap: 8px; font-size: 13px; }
  .name { flex: 1; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .bar { width: 64px; height: 8px; background: rgba(127,127,127,0.25); border-radius: 4px; overflow: hidden; }
  .bar i { display: block; height: 100%; background: #34c759; }
  .pct { width: 36px; text-align: right; font-variant-numeric: tabular-nums; }
  .chip { font-size: 11px; padding: 2px 8px; border-radius: 10px; background: rgba(127,127,127,0.2); }
  .chip.on { background: #34c759; color: white; }
  .empty { opacity: 0.5; font-size: 13px; }
  footer { display: flex; align-items: center; gap: 6px; border-top: 1px solid rgba(127,127,127,0.2); padding-top: 8px; }
  .spacer { flex: 1; }
  .mqtt { font-size: 11px; opacity: 0.7; }
  button { font: inherit; font-size: 12px; padding: 4px 10px; border-radius: 6px; border: none; background: rgba(127,127,127,0.18); cursor: pointer; }
  button:hover { background: rgba(127,127,127,0.3); }
</style>

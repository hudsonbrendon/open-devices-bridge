<script lang="ts">
  import Popover from "./lib/Popover.svelte";
  import Settings from "./lib/Settings.svelte";
  const isSettings = window.location.search.includes("settings");
</script>

{#if isSettings}
  <Settings />
{:else}
  <Popover />
{/if}

<style>
  :global(html, body) { margin: 0; }
  :global(body) {
    font-family: -apple-system, system-ui, sans-serif;
    color: #1d1d1f;
    background: rgba(250, 250, 250, 0.96);
  }
  @media (prefers-color-scheme: dark) {
    :global(body) { color: #f5f5f7; background: rgba(30, 30, 30, 0.96); }
  }
</style>

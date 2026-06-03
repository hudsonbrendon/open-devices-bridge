# /// script
# requires-python = ">=3.10"
# dependencies = ["bleak"]
# ///
"""Recon BLE do Keychron K3: descobre, conecta, dump GATT + bateria/device-info."""
import asyncio
from bleak import BleakScanner, BleakClient

# UUIDs padrao GATT
BATTERY_LEVEL = "00002a19-0000-1000-8000-00805f9b34fb"
DEV_INFO = {
    "00002a29-0000-1000-8000-00805f9b34fb": "Manufacturer",
    "00002a24-0000-1000-8000-00805f9b34fb": "Model",
    "00002a25-0000-1000-8000-00805f9b34fb": "Serial",
    "00002a27-0000-1000-8000-00805f9b34fb": "HW rev",
    "00002a26-0000-1000-8000-00805f9b34fb": "FW rev",
    "00002a28-0000-1000-8000-00805f9b34fb": "SW rev",
    "00002a23-0000-1000-8000-00805f9b34fb": "System ID",
    "00002a50-0000-1000-8000-00805f9b34fb": "PnP ID",
}


async def main():
    print("== Scan BLE 12s (so dispositivos ANUNCIANDO) ==")
    devs = await BleakScanner.discover(timeout=12.0, return_adv=True)
    target = None
    for addr, (d, adv) in sorted(devs.items(), key=lambda x: -(x[1][1].rssi or -999)):
        name = d.name or adv.local_name or "?"
        svcs = ",".join(adv.service_uuids) if adv.service_uuids else "-"
        print(f"  RSSI {adv.rssi:>4}  {addr}  '{name}'  svc=[{svcs}]")
        if name and ("keychron" in name.lower() or "k3" in name.lower()):
            target = (addr, name)

    if not target:
        print("\n[!] K3 NAO apareceu anunciando.")
        print("    Causas: ja conectado a outro host (nao anuncia) / BT Classic 3.0 (sem BLE) / fora pairing.")
        print("    Tente: chave lateral em BT, segure Fn+1 por 4s ate LED piscar (modo pairing), reexecute.")
        return

    addr, name = target
    print(f"\n== Conectando em '{name}' ({addr}) ==")
    try:
        async with BleakClient(addr, timeout=20.0) as cli:
            print(f"  conectado={cli.is_connected}")
            print("\n-- GATT services/characteristics --")
            for s in cli.services:
                print(f"  SVC {s.uuid}  ({s.description})")
                for c in s.characteristics:
                    print(f"    CHR {c.uuid}  props={c.properties}  ({c.description})")
            # bateria
            try:
                b = await cli.read_gatt_char(BATTERY_LEVEL)
                print(f"\n[BATERIA] {int(b[0])}%")
            except Exception as e:
                print(f"\n[BATERIA] indisponivel: {e}")
            # device info
            print("\n-- Device Info --")
            for uuid, label in DEV_INFO.items():
                try:
                    v = await cli.read_gatt_char(uuid)
                    try:
                        sv = v.decode("utf-8", "replace").strip("\x00")
                    except Exception:
                        sv = v.hex()
                    print(f"  {label}: {sv}")
                except Exception:
                    pass
    except Exception as e:
        print(f"[!] Falha conexao: {e}")
        print("    HID bonded recusa conexao GATT de host nao-pareado. Esperado.")


asyncio.run(main())

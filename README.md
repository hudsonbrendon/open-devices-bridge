# HA Battery Bridge

App de barra de menus do macOS que lê a **bateria** (e firmware/status) dos seus
dispositivos Bluetooth já pareados e publica no **Home Assistant** via **MQTT
Discovery**. Testado com **Logitech MX Keys Mini** e **MX Master 3**.

![menu bar utility] — ícone na barra de menus mostrando o menor nível de bateria.

## Como funciona

O macOS já é o "host ativo" dos seus periféricos BLE e mantém a conexão HID. O
app não rouba essa conexão nem gasta um slot de pareamento: usa a API pública
`CBCentralManager.retrieveConnectedPeripherals(withServices: [180F])` para ler o
**Battery Service** (`0x2A19`) e o firmware (Device Info `0x2A26`) por cima da
conexão do sistema. A cada intervalo publica no broker MQTT; o HA cria os
dispositivos e entidades sozinho.

```
MX Keys Mini / MX Master 3  --BLE-->  Mac (host ativo)
                                        │ lê 0x2A19 / 0x2A26
                                        ▼
                                 HA Battery Bridge (.app)
                                        │ MQTT Discovery
                                        ▼
                          Mosquitto @ Home Assistant  →  device + entidades
```

## Entidades criadas no HA (por dispositivo)

- `sensor.<device>_battery` — bateria %, `device_class: battery`
- `binary_sensor.<device>_connected` — conectado a este Mac agora
- `sensor.<device>_firmware` — versão de firmware (diagnóstico)
- `binary_sensor.<device>_charging` — **só** se o dispositivo expuser via GATT (ver Limitações)

A disponibilidade é controlada por `habridge/bridge/availability` (Last-Will:
some o bridge → tudo fica indisponível no HA).

## Pré-requisitos (lado Home Assistant)

1. Add-on **Mosquitto broker** instalado e rodando.
2. Integração **MQTT** configurada no HA (descoberta automática habilitada — padrão).
3. Um usuário/senha do broker (ou anônimo, se você permitir).

## Build

Precisa do **Swift toolchain** (Command Line Tools já bastam — não exige Xcode completo).

```bash
# rodar os testes da lógica pura
swift run CoreTests

# gerar o app
bash scripts/build-app.sh      # => build/HA Battery Bridge.app

# gerar o instalador .dmg
bash scripts/build-dmg.sh      # => build/HA-Battery-Bridge.dmg
```

## Instalar

1. Copie **HA Battery Bridge.app** para `/Applications`.
2. Na **primeira execução**, o macOS pede permissão de **Bluetooth** — clique
   **Permitir** (sem isso o app não lê bateria).
3. App **não assinado** (sem conta Apple Developer). No Mac onde foi compilado
   roda direto. Em **outro** Mac, na 1ª vez: clique‑direito no app → **Abrir**, ou:
   ```bash
   xattr -dr com.apple.quarantine "/Applications/HA Battery Bridge.app"
   ```

## Configurar

Clique no ícone da barra de menus → **Configurações…**:

- **Broker (host)** — IP do HA (ex.: `192.168.31.150`)
- **Porta** — `1883`
- **Usuário / Senha** — credenciais do Mosquitto (senha guardada no Keychain)
- **Intervalo (min)** — frequência de leitura (padrão 5)
- **Iniciar no login** — registra como item de login (`SMAppService`)
- **Testar conexão** — valida o broker antes de salvar

Salve. Em segundos os dispositivos aparecem no HA.

## Limitações (por design do BLE / dos dispositivos)

- **Só lê quando o dispositivo está conectado a ESTE Mac.** BLE HID tem um host
  ativo só. Se você alternar o teclado/mouse para o iPad/celular, ele aparece
  como `offline` no HA (mantém a última % conhecida).
- **Mac dormindo** não atualiza (aceitável — bateria não muda parada).
- **Carregando**: o Battery Service padrão não tem esse campo; o estado de carga
  da Logitech é via HID++, que exige o canal HID controlado pelo sistema. O app
  tenta best-effort; se não houver, a entidade de carga é omitida.
- **Keychron K3** (não‑Pro): é Bluetooth **Classic** (não BLE) / firmware fechado
  → não é endereçável por este app nem pelo HA. Não suportado.

## Desenvolvimento

- `Sources/HABatteryCore/` — lógica (modelos, payloads HA, CoreBluetooth, MQTT).
- `Sources/HABatteryBridge/` — UI da barra de menus (AppKit + SwiftUI).
- `Sources/CoreTests/` — testes de asserção (`swift run CoreTests`); XCTest não
  está disponível sem Xcode completo, então o runner é um executável simples.
- Spec de design: `docs/superpowers/specs/2026-06-03-ha-battery-bridge-design.md`

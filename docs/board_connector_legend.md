# Creality Hi mainboard connector legend

Reference photo + numbering from https://3dprima.freshdesk.com/en/support/solutions/articles/6000278131
(applies to the **old** revision of the board, but layout is the same on the
live unit; verify before final wiring).

## Externally-accessible ports

| Port | Type | Notes |
|---|---|---|
| Front USB-A | USB host | Used by stock for USB-stick G-code load |
| Side USB-A | USB host (or OTG — TBD) | One of the two USB-A jacks is wired to `usbc0` (OTG); sniff test pending |
| Power barrel | 24V DC IN | Behind the AC inlet / fuse / power supply |
| (None) | Ethernet | **No wired Ethernet hardware** on this board |

## Internal connectors (numbered per legend)

| # | Function | Connector | Notes |
|---|---|---|---|
| 1 | 24V DC IN | Green 2-pin screw terminal | Top-right of board, main power |
| 2 | Z1 Motor | JST 6-pin (steppers are smart — no 4-wire bipolar) | RS485 to motor PCB |
| 3 | Z Motor  | JST 6-pin | RS485 to motor PCB |
| 4 | Z1 limit switch | JST 3-pin | Endstop |
| 5 | Z limit switch  | JST 3-pin | Endstop |
| 6 | Y limit switch  | JST 3-pin | Endstop |
| 7 | WiFi Antenna | u.FL / IPEX | Goes to AIC8800 module |
| 8 | Screen FFC | 30-pin FFC | GC9307 SPI LCD, 240x320 |
| 9 | X Motor | **JST 9-pin (1.5 mm ZH)** | Smart closed-loop servo, addr `0x81`. STEP/DIR/EN (pins 3/4/5) + shared RS485 (A/B pins 7/8, GND pin 9). Confirmed 2026-06. |
| 10 | Y Motor | **JST 9-pin (1.5 mm ZH)** | Same as X, addr `0x82`. Now a BTT S42C on STEP/DIR via a 9-pin ZH→6-pin XH adapter (RS485 chip fried). Confirmed 2026-06. |
| 11 | Nozzle Cable | JST multi-pin | Goes to nozzle_mcu — UART, extruder, hotend, fan |
| 12 | RS232 Bed Communication | JST 4-pin | Klipper ↔ bed_mcu, also smart-stepper bus |
| 13 | ADC BED | Pads / pins | Bed thermistor + pressure sensors |
| 14 | RFID | JST 4-pin | Filament RFID reader |
| (just left of #14) | RS485 to CFS | **JST 6-pin labeled "485"** | CFS plugs in, 230400 8N1. A=pin1(red), B=pin6(blue), GND=pin5(green); pins 2/3 (white/black)=buffer-switch GPIO, pin4(yellow)=24V. **Easiest bus-tap point.** Confirmed 2026-06. |
| 15 | Bed Power | JST 2-pin | 24V to bed heater |
| 16 | Bed AC | JST 2-pin? | Bed-to-AC contactor / SSR |

### RS485 bus — single-transceiver topology (confirmed by direct inspection 2026-06)

There is exactly **one** RS485 transceiver on the whole mainboard, so every RS485 device shares **one**
multidrop bus (`/dev/ttyS5`, 230400 8N1): X-motor `0x81`, Y-motor `0x82`, CFS boxes `0x01-0x04`,
belt-tension `0x91/0x92`, and the RFID board. Consequence: one ESD/hot-plug event on the CFS port
took out the mainboard transceiver **and** the Y-motor and RFID RS485 chips together. To sniff the
whole bus, tap A/B at any connector — the **CFS 6-pin port is easiest** (A=pin1 red, B=pin6 blue,
GND=pin5 green; no splice). Z1/Z motor pin counts above are from the old reference photo and remain
**unverified** — X/Y are confirmed 9-pin (1.5 mm ZH), so Z is likely 9-pin too.

## Debug interfaces

| Header | Where | Pinout | Notes |
|---|---|---|---|
| **SoC UART** (3-pin) | Directly above T113-S3 chip, next to AIC8800 module | GND/TX/RX (order TBC) | The actual SoC debug UART — `console=ttyS0,115200` |
| **J2 SWD** (5-pin gold) | South of bed-MCU GD32F303, near M6 sticker. Back side same holes labeled TP1-TP5. | `VCC / DIO / CLK / GND / NRST` (top to bottom on front) | **ARM Cortex-M SWD for the bed-MCU.** Wire to ST-Link V2 / J-Link / Black Magic / Pi Pico picoprobe. |
| u.FL connector | At AIC8800 module edge (ANT1) | — | WiFi antenna |

## User customizations on the live board

- X limit switch wired to the SoC's UART pins (deliberate repurpose — different from stock layout)

## Hardware identification confirmed (2026-05-24)

- **SoC**: Allwinner T113-S3 (visible silkscreen label `T113-i`)
- **WiFi/BT**: AIC8800**DC** (module label `SKLW8800DCS 2.800DL`, from "Guangzhou OnRun Electronics")
   - Firmware family: `aic8800dc/`
   - Driver: `aic8800_bsp` + `aic8800_fdrv` (vendor BSP)
   - MAC on chip label: `58:41:46:3C:FA92` (unique hardware ID)
   - MAC reported by OS: `<your-wlan0-MAC>` (the one the router knows)
- **bed_mcu**: visible large QFP near front, likely STM32F* or similar Cortex-M
- **Stepper drivers (mainboard)**: most footprints unpopulated — Hi uses smart-stepper PCBs at each motor instead

## Hardware identification still pending

- The PHY / Ethernet conclusion was wrong (no Ethernet); skip.
- Bed-MCU exact part number — read silkscreen on the central QFP if useful later
- Whether the 4-pin "M6 header" is SWD or something else

# BTT Octopus V1.1 board files

**Version:** 1.0 — 2026-05-28

Board-specific Klipper config + bring-up notes for using the BTT Octopus V1.1
mainboard as the interim printer-MCU while the Creality Hi replacement
board ships.

## Files

- `printer.cfg.example` — full Klipper config template with all sections
  (X/Y/Z/Z1 steppers, EBB42 toolhead over CAN, CFS over USB-RS485, S42C Y placeholder)
- `README.md` — this file

## Full setup guide

See `docs/octopus_v1_1_setup.md` in the project root for:
- Hardware topology diagram
- Jetson Orin Nano host prep
- Klipper firmware build for Octopus
- Wiring documentation (CFS RS485, S42C, EBB42 CAN)
- Bring-up validation sequence

## Pin assumptions in printer.cfg.example

| Function | Pin | Notes |
|---|---|---|
| Stepper X step/dir/en | PF13/PF12/PF14 | TMC2209 slot 0 |
| Stepper Y step/dir/en | PG0/PG1/PF15 | TMC2209 slot 1 (placeholder — S42C will replace) |
| Stepper Z step/dir/en | PF11/PG3/PG5 | TMC2209 slot 2 |
| Stepper Z1 step/dir/en | PG4/PC1/PA0 | TMC2209 slot 3 |
| Bed heater | PA1 | mainboard MOSFET (use SSR for higher-power beds) |
| Bed thermistor | PF3 | |
| Controller fan | PA8 | |
| Extruder + hotend + part fan + probe | EBB42 GPIOs | over CAN |

These are BTT's stock V1.1 pinouts. If you're using a different revision
or have modified the board, edit `printer.cfg.example` to match your wiring.

## TMC2209 UART pin map

The Octopus uses a separate UART pin per driver slot (it does NOT share one
UART across drivers, which means each driver is independently addressable):

| Slot | UART pin |
|---|---|
| X (M0) | PC4 |
| Y (M1) | PD11 |
| Z (M2) | PC6 |
| Z1 (M3) | PC7 |
| E0 (M4) | PF2 |

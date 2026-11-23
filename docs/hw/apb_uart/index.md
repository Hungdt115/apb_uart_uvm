---
title: APB UART Core
module: apb_dut
version: "1.0"
status: draft
updated: 2025-07-21
rtl: ../../src/apb_dut.sv
summary: APB4-compliant core that instances `apb_slave` and `apb2reg`; exposes eight UART registers on the slave interface and drives unused master ports by passthrough.
---

> **Bản biên tập nội dung** — file `.html` cùng tên là trang hiển thị chính thức (mở trực tiếp bằng trình duyệt). Sửa nội dung ở đây rồi cập nhật sang `.html`, hoặc sửa trực tiếp `.html`.

## 1. Overview

APB UART is a UART controller accessed over an APB4 slave interface. The top module `apb_dut` pairs an APB protocol FSM (`apb_slave`) with an address decoder (`apb2reg`) that exposes eight memory-mapped registers. Each register is a dual-clock slice (`rw_reg`) that synchronises the APB-written value into the UART clock domain.

This page is the specification of the top module. Every submodule has its own spec page, linked from the [Submodule Instances](#instances) table and the sidebar.

## 2. Features

- APB4 Slave Interface — two-phase setup/access handshake
- Configurable Wait States — p_wr_wait (write) and p_rd_wait (read) parameters, 4-bit counter
- Dual Clock Domains — APB ↔ UART with two-FF synchroniser per register
- 8 Memory-Mapped Registers — UART_EN, CSR, STA, MODE, BRG, IE, IF, IFCLR
- Write Masking — per-register masks protect reserved bits
- Slave Error Reporting — PSLVERR on unmapped address access
- Interrupt Support — Interrupt Enable (IE), Flag (IF), Clear (IFCLR) registers
- Baud Rate Generator — 16-bit divisor register (UART_BRG[15:0])

## 3. Block Diagram

```text
                          ┌────────────────────────────────────────────────────────┐
                          │                        apb_dut                         │
                          │                                                        │
   S_PSEL, S_PENABLE ────▶│  ┌─────────────┐   reg_addr      ┌───────────────┐     │
   S_PWRITE, S_PADDR ────▶│  │             │ ──reg_wr/rd────▶│               │     │
   S_PWDATA, S_PSTRB ────▶│  │  apb_slave  │                │    apb2reg    │     │
   S_PPROT        ───────▶│  │   (FSM)     │ ◀──rd_data─────│  (decode +    │     │
                          │  │             │ ◀──ack/err─────│   write mask) │     │
   S_PREADY        ◀──────│  └─────────────┘                └──────┬────────┘     │
   S_PSLVERR       ◀──────┴─────────────────────────────────────── │  8 slices    │
   S_PRDATA        ◀────────────────────────────────────────────── ▼              │
                                                              ┌──────────┐        │
                                                              │  rw_reg  │────────┼──▶ REG_UART_EN
                                                              │ (APB shad-│        │    REG_UART_CSR
                                                              │  ow + 2FF │        │    ... IFCLR
                                                              │ sync)    │        │
                                                              └──────────┘        │
                          └────────────────────────────────────────────────────────┘
```

## 4. Submodule Instances

| Instance | Module | Spec | Description |
|---|---|---|---|
| u_apb_slave | apb_slave | [open →](spec/apb_slave_spec.html) | Configured with p_use_ack=1'h0, p_wr_wait=4'h0, p_rd_wait=4'h1. |
| u_apb2reg | apb2reg | [open →](spec/apb2reg_spec.html) | Instantiates eight rw_reg slices, one per UART register. |

## 5. Port List

### Clocks & Resets

| Signal | Dir | Width | Clock | Active | Description |
|---|---|---|---|---|---|
| PCLK | IN | — | APB | — | APB clock. |
| PRESETN | IN | — | APB | LOW | APB reset, active low. |
| UART_CLK | IN | — | UART | — | UART clock. |
| RST_N | IN | — | UART | LOW | UART reset, active low. |

### APB4 Slave Interface

| Signal | Dir | Width | Clock | Active | Description |
|---|---|---|---|---|---|
| S_PWRITE | IN | — | APB | — | APB write (1) / read (0). |
| S_PSEL | IN | — | APB | — | APB module select. |
| S_PENABLE | IN | — | APB | — | APB enable (access phase). |
| S_PADDR | IN | [31:0] | APB | — | APB address. |
| S_PWDATA | IN | [31:0] | APB | — | APB write data. |
| S_PSTRB | IN | [3:0] | APB | — | APB byte strobes; unused by the register logic. |
| S_PPROT | IN | [2:0] | APB | — | APB protection; unused by the register logic. |
| S_PREADY | OUT | — | APB | — | APB ready. |
| S_PSLVERR | OUT | — | APB | — | APB slave error; asserted when the accessed address hits no register. |
| S_PRDATA | OUT | [31:0] | APB | — | APB read data. |

### APB4 Master Pass-through

| Signal | Dir | Width | Clock | Active | Description |
|---|---|---|---|---|---|
| M_PWRITE | OUT | — | APB | — | Pass-through of S_PWRITE. |
| M_PSEL | OUT | — | APB | — | Pass-through of S_PSEL. |
| M_PENABLE | OUT | — | APB | — | Pass-through of S_PENABLE. |
| M_PADDR | OUT | [31:0] | APB | — | Pass-through of S_PADDR. |
| M_PWDATA | OUT | [31:0] | APB | — | Pass-through of S_PWDATA. |
| M_PSTRB | OUT | [3:0] | APB | — | Pass-through of S_PSTRB. |
| M_PPROT | OUT | [2:0] | APB | — | Pass-through of S_PPROT. |
| M_PREADY | IN | — | APB | — | Master ready input; unused by the register logic. |
| M_PSLVERR | IN | — | APB | — | Master error input; unused by the register logic. |
| M_PRDATA | IN | [31:0] | APB | — | Master read data input; unused by the register logic. |

### UART Register Outputs

| Signal | Dir | Width | Clock | Active | Description |
|---|---|---|---|---|---|
| REG_UART_EN | OUT | — | UART | — | UART enable (bit 0 of UART_EN). |
| REG_UART_CSR | OUT | [31:0] | UART | — | Control & Status register value. |
| REG_UART_STA | OUT | [31:0] | UART | — | Status register value. |
| REG_UART_MODE | OUT | [31:0] | UART | — | Mode register value. |
| REG_UART_BRG | OUT | [31:0] | UART | — | Baud rate generator divisor. |
| REG_UART_IE | OUT | [31:0] | UART | — | Interrupt Enable register. |
| REG_UART_IF | OUT | [31:0] | UART | — | Interrupt Flag register. |
| REG_UART_IFCLR | OUT | [31:0] | UART | — | Interrupt Flag Clear register. |

## 6. Register Map

> **Register details** (bit fields, write masks, encodings) live on the [apb2reg spec page](spec/apb2reg_spec.html).

| Register | Offset | Access | Reset | Description |
|---|---|---|---|---|
| [UART_EN](spec/apb2reg_spec.html#reg-UART_EN) | 0x00 | rw | 0x0000_0000 | UART enable register. |
| [UART_CSR](spec/apb2reg_spec.html#reg-UART_CSR) | 0x04 | rw | 0x0000_0000 | Control & Status register. |
| [UART_STA](spec/apb2reg_spec.html#reg-UART_STA) | 0x08 | rw | 0x0000_0000 | Status register. |
| [UART_MODE](spec/apb2reg_spec.html#reg-UART_MODE) | 0x0C | rw | 0x0000_0000 | UART mode configuration. |
| [UART_BRG](spec/apb2reg_spec.html#reg-UART_BRG) | 0x10 | rw | 0x0000_0000 | Baud rate generator divisor. |
| [UART_IE](spec/apb2reg_spec.html#reg-UART_IE) | 0x14 | rw | 0x0000_0000 | Interrupt Enable register. |
| [UART_IF](spec/apb2reg_spec.html#reg-UART_IF) | 0x18 | rw | 0x0000_0000 | Interrupt Flag register (status). |
| [UART_IFCLR](spec/apb2reg_spec.html#reg-UART_IFCLR) | 0x1C | rw | 0x0000_0000 | Interrupt Flag Clear register. |

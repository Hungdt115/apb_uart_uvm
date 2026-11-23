---
title: Dual-Clock Register Slice
module: rw_reg
version: "1.2"
status: draft
updated: 2026-11-22
rtl: ../../../src/rw_reg.v
summary: Read/write register with an APB shadow copy and a strict 2-FF four-phase full handshake that forwards the value into the UART clock domain and acknowledges back to the APB domain when the data has landed.
---

> **Bản biên tập nội dung** — file `.html` cùng tên là trang hiển thị chính thức (mở trực tiếp bằng trình duyệt). Sửa nội dung ở đây rồi cập nhật sang `.html`, hoặc sửa trực tiếp `.html`.

## 1. Overview

`rw_reg` is one register slice of width `DW`. The APB domain holds the shadow register (written when `PADDR == WADDR` and `WEN`), and the UART domain receives the value through a **strict 2-FF four-phase full handshake**: REQ (level) from the APB domain, ACK (level) from the UART domain, each crossing through a two-flop synchroniser. Every accepted write completes exactly one handshake cycle — no ACK is lost and no ACK is merged. `apb2reg` instantiates eight of these, one per UART register.

The module also emits a **single-cycle ACK pulse** (`O_ACK`) in the `O_CLK` domain whenever a new value has been captured into `O_UART_REG`. This ACK can be used by downstream logic (e.g. UART transmitter/receiver, sequencer, or an interrupt generator) to know that the APB write has propagated across the clock domain and the UART-side register now holds stable data.

## 2. Clock-Domain Synchronisation

### 2.1 Handshake signals

| Signal | Domain | Type | Description |
|---|---|---|---|
| `wr_req_apb` | I_CLK | reg | REQ level — asserted when a write is accepted; held until the ACK is observed. |
| `ro_apb_reg` | I_CLK | reg | Write data, kept **stable for the whole time REQ = 1**. |
| `wr_req_sync1/2` | O_CLK | reg | 2-FF synchroniser of REQ into the UART domain. |
| `wr_req_sync3` | O_CLK | reg | Delay of `wr_req_sync2` for the capture / `O_ACK` edge detection. |
| `ro_uart_reg` | O_CLK | reg | Captures the data on the rising edge of `wr_req_sync2`. |
| `wr_ack_uart` | O_CLK | reg | ACK level — asserted at the capture, held until REQ is seen low. |
| `wr_ack_sync1/2` | I_CLK | reg | 2-FF synchroniser of ACK back into the APB domain. |

### 2.2 Four-phase protocol

| Phase | Domain | Event |
|---|---|---|
| **1. REQ assert** | I_CLK | `WEN && PADDR == WADDR` accepted → `wr_req_apb = 1`, `ro_apb_reg ← PDATA`. |
| **2. Capture + ACK assert** | O_CLK | `wr_req_sync2` rises (2-FF settled) → `ro_uart_reg` captures `ro_apb_reg` → `wr_ack_uart = 1`; `O_ACK` pulses for one `O_CLK` cycle. |
| **3. ACK detect** | I_CLK | `wr_ack_sync2` rises (2-FF settled) → `wr_req_apb = 0`. |
| **4. REQ-low detect** | O_CLK | `wr_req_sync2` falls → `wr_ack_uart = 0`. Handshake idle, ready for the next write. |

**Strict serialisation:** a write is accepted only when the handshake is fully idle (`wr_req_apb = 0` **and** the ACK has returned low, `wr_ack_sync2 = 0`). A write arriving while the handshake is pending is **not accepted**. With `apb_slave` in ACK mode (`p_use_ack = 1`) this is guaranteed by the APB handshake itself — `O_PREADY` waits for the register-side ACK, so the next access cannot start before the handshake completes. In counter mode (`p_use_ack = 0`), back-to-back writes to the same register that arrive before the handshake completes are blocked (see the editorial note at the end).

### 2.3 Timing chart

```text
APB (I_CLK) domain
I_CLK        _/‾\_/‾\_/‾\_/‾\_/‾\_/‾\_/‾\_/‾\_/‾\_
WEN & hit    ________/‾‾‾‾‾\________________________________
wr_req_apb   ________/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\___________
ro_apb_reg   ════════╳══════════ DATA (stable) ═══════════════
wr_ack_sync2 ______________________________________/‾‾‾‾\_____
                    (1)                          (3)

UART (O_CLK) domain
O_CLK          _/‾\_/‾\_/‾\_/‾\_/‾\_/‾\_/‾\_/‾\_
wr_req_sync2   ____________/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\_________
ro_uart_reg    ════════════╳══════ DATA captured ═════════════
wr_ack_uart    _________________/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\________
O_ACK          _____________________/‾‾‾\____________________
                          (2)                        (4)
```

- **(1)** REQ assert — APB domain. **(2)** REQ crosses the 2-FF synchroniser, data is captured, ACK asserts, `O_ACK` pulses. **(3)** ACK crosses the 2-FF synchroniser back, REQ deasserts. **(4)** REQ-low crosses the 2-FF synchroniser, ACK deasserts → idle.
- Handshake latency ≈ `2·T_I + 2·T_O + 2·T_I + 1·T_O` (two flops per crossing, two crossings per direction), independent of the clock ratio.

## 3. Parameters

| Parameter | Default | Description |
|---|---|---|
| DW | 32 | Register data width. All instances in apb2reg use DW=32. |
| DAT_INI | {DW{1'b0}} | Reset value. All instances in apb2reg pass 32'h0000_0000, so every UART register resets to 0. |

## 4. Port List

### APB Domain

| Signal | Dir | Width | Clock | Active | Description |
|---|---|---|---|---|---|
| I_CLK | IN | — | APB | — | APB clock for the shadow register and the handshake REQ. |
| I_RST | IN | — | APB | LOW | APB reset, active low. Resets `ro_apb_reg`, `wr_req_apb` and the ACK synchroniser. |
| PADDR | IN | [29:0] | APB | — | Current APB word address, bits [31:2]. |
| WADDR | IN | [29:0] | APB | — | Word address of this register, bits [31:2]; write hits when PADDR == WADDR. |
| PDATA | IN | [31:0] | APB | — | Write data, already masked by the per-register write mask. |
| WEN | IN | — | APB | — | Write enable from the APB slave. |

### UART Domain

| Signal | Dir | Width | Clock | Active | Description |
|---|---|---|---|---|---|
| O_CLK | IN | — | UART | — | UART clock for the REQ synchroniser, the data capture and the ACK generator. |
| O_RST | IN | — | UART | LOW | UART reset, active low. Resets the REQ synchroniser, the capture register and the ACK generator. |

### Outputs

| Signal | Dir | Width | Clock | Active | Description |
|---|---|---|---|---|---|
| O_APB_REG | OUT | [31:0] | APB | — | APB shadow register, read back on the APB bus. |
| O_UART_REG | OUT | [31:0] | UART | — | Register value captured in the UART domain; drives the REG_UART_* outputs. |
| O_ACK | OUT | — | UART | HIGH | Single-cycle pulse in the `O_CLK` domain, asserted in the cycle **after** the data capture — during this cycle `O_UART_REG` already holds the new value. |

## 5. Operation

### 5.1 APB write (I_CLK domain)

A write is accepted when `WEN && (PADDR == WADDR)` **and the handshake is idle** (`wr_req_apb == 0` and `wr_ack_sync2 == 0`):

- `ro_apb_reg` ← `PDATA` (registered on `I_CLK`, reset to `DAT_INI`).
- `wr_req_apb` ← 1 (phase 1).

`O_APB_REG` is driven directly from `ro_apb_reg` and is available for APB read-back in the same cycle as the next APB access. `ro_apb_reg` is not modified again until the handshake completes, so the data presented to the UART domain is stable.

When `wr_ack_sync2 == 1` (ACK observed through the 2-FF synchroniser, phase 3): `wr_req_apb` ← 0.

### 5.2 Four-phase transfer into the O_CLK domain

Two-flop synchroniser on REQ:

```text
wr_req_sync1 <= wr_req_apb;      // O_CLK
wr_req_sync2 <= wr_req_sync1;    // O_CLK
wr_req_sync3 <= wr_req_sync2;    // O_CLK (delay for edge detect)
```

At the rising edge of `wr_req_sync2` (phase 2):

```text
ro_uart_reg <= ro_apb_reg;       // capture (data stable during REQ)
wr_ack_uart <= 1'b1;             // ACK assert
```

`O_ACK` is a one-cycle pulse generated from the same edge:

```text
O_ACK = wr_req_sync2 & ~wr_req_sync3;    // O_CLK, 1-cycle pulse after capture
```

> `O_ACK` is high during the `O_CLK` cycle **after** the capture edge, so `O_UART_REG` is already stable on the `O_ACK` cycle. Downstream logic should sample `O_UART_REG` on the `O_ACK` cycle or later.

When `wr_req_sync2` falls (phase 4): `wr_ack_uart` ← 0. The ACK level crosses back through the two-flop synchroniser (`wr_ack_sync1/2`) into the APB domain to close the handshake.

### 5.3 Reset behaviour

- `I_RST` (active low): resets `ro_apb_reg` to `DAT_INI`, clears `wr_req_apb` and the ACK synchroniser flops.
- `O_RST` (active low): clears `wr_req_sync1/2/3`, `wr_ack_uart` and `ro_uart_reg`; forces `O_ACK = 0`.
- After reset release, the first accepted APB write starts a fresh handshake (REQ 0→1 propagates to `O_CLK`, capture + ACK, REQ 1→0, ACK 1→0).

### 5.4 Timing summary

| Event | Domain | Effect |
|---|---|---|
| `WEN && PADDR == WADDR` (handshake idle) | I_CLK | `ro_apb_reg` updates, `wr_req_apb = 1` (phase 1). |
| REQ crosses 2-FF sync | O_CLK | `wr_req_sync2` rises. |
| `wr_req_sync2` rising | O_CLK | `ro_uart_reg` captures, `wr_ack_uart = 1` (phase 2). |
| next O_CLK edge | O_CLK | `wr_req_sync3` catches up; `O_ACK` 1-cycle pulse. |
| ACK crosses 2-FF sync | I_CLK | `wr_ack_sync2` rises, `wr_req_apb = 0` (phase 3). |
| REQ-low crosses 2-FF sync | O_CLK | `wr_req_sync2` falls, `wr_ack_uart = 0` (phase 4). |

---

**Ghi chú biên tập:**
- Ghi mới khi handshake đang treo **bị chặn** (strict). Với `apb_slave` mode `p_use_ack=1` điều này tự được đảm bảo (PREADY đợi `O_REG_ACK` nên access sau không thể tới sớm). Với mode `p_use_ack=0`, nếu master ghi liên tiếp cùng một thanh ghi nhanh hơn thời gian hoàn tất handshake (UART_CLK chậm), ghi thứ hai sẽ bị chặn — cần cân nhắc nếu kịch bản này xảy ra.
- `O_ACK` là xung 1 chu kỳ `O_CLK` ngay sau chu kỳ capture (`wr_req_sync2 & ~wr_req_sync3`) — khớp quy tắc "sample `O_UART_REG` on the `O_ACK` cycle or later".
- `apb2reg` gộp 8 xung `O_ACK` bằng toggle rồi 2-FF sync sang `PCLK` để sinh `O_REG_ACK` — cơ chế này không đổi vì `O_ACK` vẫn là xung 1 chu kỳ.

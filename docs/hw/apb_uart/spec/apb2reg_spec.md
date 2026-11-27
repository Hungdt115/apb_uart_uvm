---
title: APB-to-Register Address Decoder
module: apb2reg
version: "1.1"
status: draft
updated: 2026-11-23
base: 0x0000_0000
rtl: ../../../src/apb2reg.v
summary: Decodes the APB register word address into eleven UART registers. RW registers are rw_reg slices with per-register write masks; the status (STA) and interrupt-flag (IF) registers are read-only values driven directly by uart_top and synchronised 2-FF into the APB domain.
---

> **Bản biên tập nội dung** — file `.html` cùng tên là trang hiển thị chính thức (mở trực tiếp bằng trình duyệt). Sửa nội dung ở đây rồi cập nhật sang `.html`, hoặc sửa trực tiếp `.html`.

## 1. Overview

`apb2reg` decodes the APB word address into one of eleven UART registers. Writes are masked per register (write mask in the register map below), so reserved bits can never be written. An access to an unmapped address — or a write to a read-only register — raises `O_REG_ERR`, which `apb_slave` reports on `PSLVERR`.

- **RW registers** (`UART_EN`, `UART_CSR`, `UART_MODE`, `UART_BRG`, `UART_IE`, `UART_IFCLR`, `UART_TXD`) are `rw_reg` slices: an APB shadow copy plus the CDC transfer into the UART clock domain.
- **RO registers** (`UART_STA`, `UART_IF`) are **not** register slices — their values are **registered outputs of `uart_top`** (shadow registers) connected **directly** to the APB read mux; no 2-FF synchroniser is used, so reads are answered immediately on request.
- `UART_RXD` is read-only FIFO data: the RX FIFO head registered in `uart_top`, connected directly to the APB read mux; each read also issues a pop pulse (`REG_UART_RX_REN`).

## 2. Port List

### Clocks & Resets

| Signal | Dir | Width | Clock | Active | Description |
|---|---|---|---|---|---|
| PCLK | IN | — | APB | — | APB clock. |
| PRESETN | IN | — | APB | LOW | APB reset, active low. |
| UART_CLK | IN | — | UART | — | UART clock. |
| RST_N | IN | — | UART | LOW | UART reset, active low. |

### Register interface (from apb_slave)

| Signal | Dir | Width | Clock | Active | Description |
|---|---|---|---|---|---|
| I_REG_ADDR | IN | [31:0] | APB | — | Word address from the APB access phase. |
| I_REG_WR | IN | — | APB | — | Register write strobe. |
| I_REG_RD | IN | — | APB | — | Register read strobe. |
| I_REG_WR_DATA | IN | [31:0] | APB | — | Write data, masked by the per-register write mask. |
| I_REG_ERR_ACK | IN | — | APB | — | Access-done pulse used to clear the error condition. |

### Register interface (to apb_slave)

| Signal | Dir | Width | Clock | Active | Description |
|---|---|---|---|---|---|
| O_REG_RD_DATA | OUT | [31:0] | APB | — | Read data of the selected register. |
| O_REG_ACK | OUT | — | APB | — | Register access acknowledge. |
| O_REG_ERR | OUT | — | APB | — | Error: accessed address hits no register, or write to a read-only register. |

### UART register outputs (to uart_top)

| Signal | Dir | Width | Clock | Active | Description |
|---|---|---|---|---|---|
| REG_UART_EN | OUT | — | UART | — | UART enable (bit 0 of UART_EN). |
| REG_UART_CSR | OUT | [31:0] | UART | — | Control & Status register value. |
| REG_UART_MODE | OUT | [31:0] | UART | — | Mode register value. |
| REG_UART_BRG | OUT | [15:0] | UART | — | Baud-rate divisor (BRG_DIV) for uart_baud_gen. |
| REG_UART_BRG_WEN | OUT | — | UART | HIGH | 1-cycle pulse when the divisor has landed in the UART domain. |
| REG_UART_DBITS | OUT | [2:0] | UART | — | Data-bits count select (UART_DBITS). |
| REG_UART_IE | OUT | [31:0] | UART | — | Interrupt Enable register. |
| REG_UART_IFCLR | OUT | [31:0] | UART | — | Interrupt Flag Clear register. |
| REG_UART_TXD | OUT | [7:0] | UART | — | TX byte landed in the UART domain; stable on the TX_WEN pulse. |
| REG_UART_TX_WEN | OUT | — | UART | HIGH | 1-cycle pulse to push REG_UART_TXD into the TX FIFO. |
| REG_UART_RX_REN | OUT | — | UART | HIGH | 1-cycle pulse per APB read of UART_RXD — pops the RX FIFO. |

### UART inputs (from uart_top)

| Signal | Dir | Width | Clock | Active | Description |
|---|---|---|---|---|---|
| REG_UART_RXD | IN | [7:0] | UART | — | RX FIFO head — registered (shadow) output of uart_top, connected directly to the read mux. |
| REG_UART_STA | IN | [31:0] | UART | — | Status register value — registered (shadow) output of uart_top, connected directly to the read mux (read-only). |
| REG_UART_IF | IN | [31:0] | UART | — | Interrupt flag register value — registered (shadow) output of uart_top, connected directly to the read mux (read-only). |

## 3. Register Map

| Register | Offset | Access | Reset | Description |
|---|---|---|---|---|
| UART_EN | 0x00 | rw | 0x0000_0001 | UART enable register (enabled by default). |
| UART_CSR | 0x04 | rw | 0x0000_0000 | Control & Status register. |
| UART_STA | 0x08 | **ro** | 0x0000_0000 | Status register — driven by uart_top. |
| UART_MODE | 0x0C | rw | 0x0000_0000 | UART mode configuration. |
| UART_BRG | 0x10 | rw | 0x0000_0146 | Baud rate generator divisor (326 = 9600 bps @ 50 MHz). |
| UART_DBITS | 0x20 | rw | 0x0000_0000 | Data-bits count select (000 = 8 bits). |
| UART_IE | 0x14 | rw | 0x0000_0000 | Interrupt Enable register. |
| UART_IF | 0x18 | **ro** | 0x0000_0000 | Interrupt Flag register — driven by uart_top. |
| UART_IFCLR | 0x1C | rw | 0x0000_0000 | Interrupt Flag Clear register. |
| UART_TXD | 0x100 | wo | 0x0000_0000 | TX data — write pushes a byte into the TX FIFO. |
| UART_RXD | 0x200 | ro | 0x0000_0000 | RX data — read returns the RX FIFO head and pops it. |

## 4. Register Details

### UART_EN

| Offset | Width | Access | Reset | Write mask |
|---|---|---|---|---|
| 0x00 | 32 | rw | 0x0000_0001 | 0x0000_0001 |

UART enable register. Reset = enabled (normal operation right after reset).

| Bits | Field | Access | Reset | Description |
|---|---|---|---|---|
| 0 | EN | rw | 0x1 | UART enable. Also exposed directly on the `REG_UART_EN` output. |
| 1 | — | rw | 0x0 | Reserved. |

**EN encoding:**

| Value | Name | Description |
|---|---|---|
| 0x0 | DISABLE | UART logic disabled. |
| 0x1 | ENABLE | UART logic enabled. |

### UART_CSR

| Offset | Width | Access | Reset | Write mask |
|---|---|---|---|---|
| `0x04` | 32 | rw | `0x0000_0000` | `0x0000_00FF` |

Control & Status register. Each bit represents a distinct register field type (`w1s` self-clearing pulse vs. `rw` level):

| Bits | Field | Access | Reset | Description |
|---|---|---|---|---|
| `0` | `TX_FIFO_CLR` | w1s | `0x0` | TX FIFO flush. Write 1 → triggers a **1-cycle `UART_CLK` pulse** on `REG_UART_CSR[0]` to flush the TX FIFO; auto-clears (reads back as `0`). |
| `1` | `RX_FIFO_CLR` | w1s | `0x0` | RX FIFO flush. Write 1 → triggers a **1-cycle `UART_CLK` pulse** on `REG_UART_CSR[1]` to flush the RX FIFO; auto-clears (reads back as `0`). |
| `2` | `TX_EN` | rw | `0x0` | Individual TX enable level. `1`: enable transmitter; `0`: stop starting new frames. |
| `3` | `RX_EN` | rw | `0x0` | Individual RX enable level. `1`: enable receiver start-bit detection and sampling; `0`: stop receiving new frames. |
| `4` | `LOOPBACK_EN` | rw | `0x0` | Internal loopback enable level. `1`: route internal TXD to RX input for self-test; `0`: receive from external `I_RXD`. Toggling this bit (0 → 1 or 1 → 0) automatically triggers an RX FIFO flush and resets the receiver to `S_IDLE` to prevent stale bytes and switching glitches. |
| `5` | `ERR_CLR` | w1s | `0x0` | Clear sticky error flags (`PARITY_ERR`, `FRAME_ERR`, `OVF`). Write 1 → triggers a **1-cycle `UART_CLK` pulse** on `REG_UART_CSR[5]`; auto-clears (reads back as `0`). |
| `6` | `IRQ_EN` | rw | `0x0` | Global UART interrupt enable level. `1`: allow interrupt output when enabled `IE` & `IF` flags assert; `0`: mask interrupt output. |
| `7` | `AUTO_FLOW_EN` | rw | `0x0` | Optional auto flow control enable level. |
| `31:8` | — | ro | `0x0` | Reserved (reads as `0`). |

### UART_STA (read-only)

| Offset | Width | Access | Reset | Write mask |
|---|---|---|---|---|
| 0x08 | 32 | **ro** | 0x0000_0000 | 0x0000_0000 |

Status register. **Read-only** — the value is a registered (shadow) output of `uart_top` driven on the `REG_UART_STA` input and connected **directly** to the APB read mux (no 2-FF synchroniser). The read is acknowledged immediately on request. `uart_top` must drive this signal from a register and keep it quasi-static (changes only at UART-event rate); this removes the formal metastability protection on the path — the sampling flop is the APB-side read-data register.

Writing this register raises `O_REG_ERR` (write mask = 0).

| Bits | Field | Access | Reset | Description |
|---|---|---|---|---|
| 0 | TX_BUSY | ro | 0x0 | TX shifter active (from `uart_tx`). |
| 1 | TX_IDLE | ro | 0x0 | TX FIFO empty and shifter idle (from `uart_tx`). |
| 2 | TX_OVF | ro | 0x0 | TX overflow: write while the TX FIFO was full (sticky, cleared by flush/reset). |
| 8:3 | TX_FIFO_COUNT | ro | 0x0 | TX FIFO occupancy count (0..32, from `uart_tx`). |
| 9 | TX_FIFO_FULL | ro | 0x0 | TX FIFO full flag (from `uart_tx`). |
| 10 | TX_FIFO_EMPTY | ro | 0x0 | TX FIFO empty flag (from `uart_tx`). |
| 11 | TX_FIFO_ALMOST_FULL | ro | 0x0 | TX FIFO almost-full flag (from `uart_tx`). |
| 15:12 | — | ro | 0x0 | Reserved (reads as 0). |
| 16 | RX_BUSY | ro | 0x0 | RX receiver active receiving a frame (from `uart_rx`). |
| 17 | RX_IDLE | ro | 0x0 | RX receiver idle waiting for start bit (from `uart_rx`). |
| 18 | RX_OVF | ro | 0x0 | RX FIFO overflow: receive when FIFO was full (sticky, from `uart_rx`). |
| 19 | RX_PARITY_ERR | ro | 0x0 | RX parity error detected (sticky, from `uart_rx`). |
| 20 | RX_FRAME_ERR | ro | 0x0 | RX framing error: stop bit missing/invalid (sticky, from `uart_rx`). |
| 26:21 | RX_FIFO_COUNT | ro | 0x0 | RX FIFO occupancy count (0..32, from `uart_rx`). |
| 27 | RX_FIFO_FULL | ro | 0x0 | RX FIFO full flag (from `uart_rx`). |
| 28 | RX_FIFO_EMPTY | ro | 0x0 | RX FIFO empty flag (from `uart_rx`). |
| 29 | RX_FIFO_ALMOST_FULL | ro | 0x0 | RX FIFO almost-full flag (from `uart_rx`). |
| 31:30 | — | ro | 0x0 | Reserved (reads as 0). |

Assembly is done in `apb_dut` (integration level):
```verilog
REG_UART_STA = {
    2'b00,
    rx_fifo_almost_full, rx_fifo_empty, rx_fifo_full, rx_fifo_count,
    rx_frame_err, rx_parity_err, rx_ovf, rx_idle, rx_busy,
    4'b0000,
    tx_fifo_almost_full, tx_fifo_empty, tx_fifo_full, tx_fifo_count,
    tx_ovf, tx_idle, tx_busy
};
```

### UART_MODE

| Offset | Width | Access | Reset | Write mask |
|---|---|---|---|---|
| 0x0C | 32 | rw | 0x0000_0000 | 0x0000_000F |

UART mode configuration.

| Bits | Field | Access | Reset | Description |
|---|---|---|---|---|
| 0 | STOP_BITS | rw | 0x0 | 0 = 1 stop bit, 1 = 2 stop bits. |
| 1 | PARITY_EN | rw | 0x0 | 0 = no parity, 1 = parity enabled. |
| 2 | PARITY_ODD | rw | 0x0 | 0 = even, 1 = odd (only when PARITY_EN = 1). |
| 3 | — | rw | 0x0 | Reserved (0). |

Encoding consumed by `uart_tx` at frame load (see `uart_tx_spec.md` section 6); `MODE = 0` = 8N1.

### UART_BRG

| Offset | Width | Access | Reset | Write mask |
|---|---|---|---|---|
| 0x10 | 32 | rw | 0x0000_0146 | 0x0000_FFFF |

Baud rate generator divisor. Reset = 326 → 9600 bps @ 50 MHz (usable without configuration).

| Bits | Field | Access | Reset | Description |
|---|---|---|---|---|
| 15:0 | BRG | rw | 0x0146 | 16-bit baud divisor (`BRG_DIV`) — exposed on `REG_UART_BRG[15:0]`; `REG_UART_BRG_WEN` pulses when the value lands in the UART domain (see uart_baud_gen_spec.md). |

### UART_DBITS

| Offset | Width | Access | Reset | Write mask |
|---|---|---|---|---|
| 0x20 | 32 | rw | 0x0000_0000 | 0x0000_0007 |

Data-bits count select. Reset = 8 bits.

| Bits | Field | Access | Reset | Description |
|---|---|---|---|---|
| 2:0 | DBITS | rw | 0x0 | Number of data bits per frame — exposed on `REG_UART_DBITS[2:0]`. |
| 31:3 | — | ro | 0x0 | Reserved (reads as 0). |

**DBITS encoding:**

| DBITS[2:0] | Data bits |
|---|---|
| 3'b000 | 8 (default) |
| 3'b001 | 5 |
| 3'b010 | 6 |
| 3'b011 | 7 |
| 3'b100 | 9 |
| 3'b101..111 | Reserved — treated as 8 |

> `uart_tx` / `uart_rx` currently use the compile-time `DATA_BITS = 8`; wiring `REG_UART_DBITS` into their shifter widths is a follow-up step.

### UART_IE

| Offset | Width | Access | Reset | Write mask |
|---|---|---|---|---|
| 0x14 | 32 | rw | 0x0000_0000 | 0x0000_00FF |

Interrupt Enable register. Enables individual interrupt sources to assert the global interrupt request (gated by `UART_CSR[6]` IRQ_EN).

| Bits | Field | Access | Reset | Description |
|---|---|---|---|---|
| 0 | TX_EMPTY_IE | rw | 0x0 | Enable interrupt when TX FIFO is empty and transmitter is idle (`TX_EMPTY_IF`). |
| 1 | RX_READY_IE | rw | 0x0 | Enable interrupt when RX data is available in RX FIFO (`RX_READY_IF`). |
| 2 | TX_OVF_IE | rw | 0x0 | Enable interrupt on TX FIFO overflow (`TX_OVF_IF`). |
| 3 | RX_OVF_IE | rw | 0x0 | Enable interrupt on RX FIFO overflow (`RX_OVF_IF`). |
| 4 | RX_PARITY_ERR_IE | rw | 0x0 | Enable interrupt on RX parity error (`RX_PARITY_ERR_IF`). |
| 5 | RX_FRAME_ERR_IE | rw | 0x0 | Enable interrupt on RX framing error (`RX_FRAME_ERR_IF`). |
| 6 | TX_ALMOST_FULL_IE | rw | 0x0 | Enable interrupt on TX FIFO almost full (`TX_ALMOST_FULL_IF`). |
| 7 | RX_ALMOST_FULL_IE | rw | 0x0 | Enable interrupt on RX FIFO almost full (`RX_ALMOST_FULL_IF`). |
| 31:8 | — | ro | 0x0 | Reserved (reads as 0). |

### UART_IF (read-only)

| Offset | Width | Access | Reset | Write mask |
|---|---|---|---|---|
| 0x18 | 32 | **ro** | 0x0000_0000 | 0x0000_0000 |

Interrupt Flag register. **Read-only** — the value is a registered (shadow) output of `uart_top` driven on the `REG_UART_IF` input and connected **directly** to the APB read mux (no 2-FF synchroniser). The read is acknowledged immediately on request. Same quasi-static requirement as `UART_STA`.

Writing this register raises `O_REG_ERR` (write mask = 0). Flags are cleared through `UART_IFCLR`, not by writing this register.

| Bits | Field | Access | Reset | Description |
|---|---|---|---|---|
| 0 | TX_EMPTY_IF | ro | 0x0 | TX empty & idle interrupt flag (`TX_FIFO_EMPTY & TX_IDLE`). |
| 1 | RX_READY_IF | ro | 0x0 | RX data ready interrupt flag (`~RX_FIFO_EMPTY`). |
| 2 | TX_OVF_IF | ro | 0x0 | TX FIFO overflow interrupt flag. |
| 3 | RX_OVF_IF | ro | 0x0 | RX FIFO overflow interrupt flag. |
| 4 | RX_PARITY_ERR_IF | ro | 0x0 | RX parity error interrupt flag. |
| 5 | RX_FRAME_ERR_IF | ro | 0x0 | RX framing error interrupt flag. |
| 6 | TX_ALMOST_FULL_IF | ro | 0x0 | TX FIFO almost full interrupt flag. |
| 7 | RX_ALMOST_FULL_IF | ro | 0x0 | RX FIFO almost full interrupt flag. |
| 31:8 | — | ro | 0x0 | Reserved (reads as 0). |

### UART_IFCLR

| Offset | Width | Access | Reset | Write mask |
|---|---|---|---|---|
| 0x1C | 32 | rw | 0x0000_0000 | 0x0000_00FF |

Interrupt Flag Clear register. Write-1-to-clear (W1C) register for clearing interrupt flags.

| Bits | Field | Access | Reset | Description |
|---|---|---|---|---|
| 7:0 | IFCLR | rw | 0x0 | Clear bits corresponding to `UART_IF[7:0]`. Writing 1 clears the corresponding interrupt flag. |
| 31:8 | — | ro | 0x0 | Reserved (reads as 0). |

### UART_TXD (write-only)

| Offset | Width | Access | Reset | Write mask |
|---|---|---|---|---|
| 0x100 | 32 | wo | 0x0000_0000 | 0x0000_00FF |

TX data. Writing pushes the byte through the `rw_reg` CDC; when it lands in the UART domain, `REG_UART_TXD[7:0]` holds the byte and `REG_UART_TX_WEN` pulses for one UART clock — `uart_top` pushes it into the TX FIFO on that pulse. No read-back (reading this address raises `O_REG_ERR`).

| Bits | Field | Access | Reset | Description |
|---|---|---|---|---|
| 7:0 | TX_DATA | wo | 0x0 | Transmit data byte. |
| 31:8 | — | wo | 0x0 | Reserved (writes masked out). |

### UART_RXD (read-only)

| Offset | Width | Access | Reset | Write mask |
|---|---|---|---|---|
| 0x200 | 32 | ro | 0x0000_0000 | 0x0000_0000 |

RX data. `uart_top` presents the RX FIFO **head** on `REG_UART_RXD` from a register (shadow/peek) connected **directly** to the APB read mux (no 2-FF synchroniser); the read is acknowledged immediately on request. Each APB read of this address also issues a one-cycle `REG_UART_RX_REN` pulse in the UART domain (edge → toggle → 2-FF sync → edge detect), which makes `uart_top` pop the FIFO.

| Bits | Field | Access | Reset | Description |
|---|---|---|---|---|
| 7:0 | RX_DATA | ro | 0x0 | Received data byte (RX FIFO head). |
| 31:8 | — | ro | 0x0 | Reserved (reads return 0x000000). |

> Consecutive back-to-back reads within one UART_CLK period after the pop may return the same byte (the head register updates on the next UART_CLK edge).

## 5. Read-only status path (STA / IF / RXD)

```text
uart_top ──▶ [ REG_UART_STA / REG_UART_IF / REG_UART_RXD ] ──▶ read mux ──▶ O_REG_RD_DATA ──▶ APB
             (UART domain, registered outputs)
```

- The status, interrupt-flag and RX-head values are **not** stored in `rw_reg` slices; no write path exists for them.
- The values are registered (shadow) outputs of `uart_top` and are connected **directly** to the read mux — **no 2-FF synchroniser**. Reads are acknowledged immediately on request (`O_REG_ACK` rises with the read request).
- **Caveat:** the sampling flop for these signals is the APB-side read-data register. `uart_top` must keep these signals quasi-static (registered, changing only at UART-event rate, far below PCLK) so the direct sample is reliable. This removes the formal metastability protection from this path — the design decision is documented here; restore the 2-FF stage if strict CDC compliance is required for these reads.
- `O_REG_ERR` is address-based: a write to a read-only register (write mask = 0) is reported as a decode error on `PSLVERR`.

---

**Ghi chú biên tập:**
- `UART_EN` chuyển về **bit 0** (mask `0x0000_0001`), reset **0x1** (enable sẵn sau reset). Test phải ghi `EN = 0x1` thay vì `0x2` (đã cập nhật `apb_simple_test.sv`).
- Thêm thanh ghi **`UART_DBITS` (0x20, mask 0x7)** chọn số bit dữ liệu (5/6/7/8/9); `uart_tx`/`uart_rx` hiện vẫn dùng tham số `DATA_BITS=8` — nối runtime vào shifter là bước tiếp theo.
- Reset để **chạy được ngay ở chế độ bình thường**: `UART_EN = 1`, `UART_BRG = 326` (9600 @ 50 MHz), `UART_MODE = 0` (8N1), `UART_DBITS = 0` (8 bit).
- `UART_STA`/`UART_IF` đã chuyển từ rw (qua `rw_reg`) sang **ro** — giá trị do `uart_top` điều khiển trực tiếp trên 2 input mới `REG_UART_STA`/`REG_UART_IF` (UART domain). Đã bỏ 2 instance `rw_reg` (`u_uart_sta`, `u_uart_if`) và bỏ 2 ACK tương ứng khỏi tổ hợp write-ACK.
- Đường đọc RO (STA/IF/RXD) **không dùng 2-FF sync** — nối trực tiếp từ output có register của `uart_top` vào read mux, ACK đọc trả về ngay khi có request (quyết định thiết kế theo yêu cầu). Điều này bỏ lớp bảo vệ metastability chính thức trên đường đọc; điều kiện an toàn thực tế là `uart_top` phải drive các tín hiệu này từ thanh ghi và chỉ thay đổi ở tốc độ sự kiện UART (quasi-static).
- Ghi vào thanh ghi RO sẽ báo `O_REG_ERR` (mask = 0) — hành vi cố ý, khác với trước (trước đây STA/IF ghi được với mask 0x1/0x7).
- `apb_dut.sv` / wrapper / `top.sv` cần đổi hướng 2 port `REG_UART_STA`/`REG_UART_IF` từ output sang input khi tích hợp — chưa sửa trong lần này (ngoài phạm vi yêu cầu).

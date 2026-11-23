---
title: Synchronous FIFO
module: sync_fifo
version: "1.0"
status: draft
updated: 2025-07-21
rtl: ../../../src/sync_fifo.v
summary: Parameterisable single-clock FIFO used as the TX and RX data buffer inside uart_tx and uart_rx. Supports synchronous clear, full/empty flags, and optional almost-full/almost-empty thresholds.
---


> **Bản biên tập nội dung** — file `.html` cùng tên là trang hiển thị chính thức (mở trực tiếp bằng trình duyệt). Sửa nội dung ở đây rồi cập nhật sang `.html`, hoặc sửa trực tiếp `.html`.

## 1. Overview

`sync_fifo` is a **single-clock (synchronous) FIFO** used as the data buffer inside `uart_tx` and `uart_rx`. Both producer and consumer operate on the same clock (`I_CLK`), so no clock-domain-crossing logic is required; the FIFO is built from a dual-port RAM (or register file) plus read/write pointers and flag generation.

- In `uart_tx`: the APB domain writes bytes into the FIFO; the UART baud-rate engine pops bytes out and shifts them onto `TXD`.
- In `uart_rx`: the baud-rate engine pushes received bytes into the FIFO; the APB domain pops them out on read.

The FIFO is **parameterisable** in width (`DW`) and depth (`DEPTH`, power of two), and provides `FULL`, `EMPTY`, `ALMOST_FULL`, `ALMOST_EMPTY` flags for flow control and interrupt generation.

## 2. Architecture

```text
                  ┌──────────────────────────────┐
    I_WR_DATA ───▶│                              │
    I_WR_EN   ───▶│        Dual-port RAM         │───▶ O_RD_DATA
    I_RD_EN   ───▶│        (DEPTH x DW)          │
                  │                              │
                  │   wptr  ──▶  full  logic     │───▶ O_FULL
                  │   rptr  ──▶  empty logic     │───▶ O_EMPTY
                  │   count ──▶  almost logic    │───▶ O_ALMOST_FULL
                  └──────────────────────────────┘───▶ O_ALMOST_EMPTY
```

- **Write pointer `wptr`** and **read pointer `rptr`** are `$clog2(DEPTH)+1` bits wide (extra MSB for wrap detection).
- **Occupancy counter `count`** tracks the number of valid entries (0 … DEPTH).
- Flags are derived combinationally from `count` (or from pointer comparison) and registered if timing requires.

## 3. Parameters

| Parameter | Default | Description |
|---|---|---|
| DW | 8 | Data width in bits. `uart_tx`/`uart_rx` use DW=8. |
| DEPTH | 16 | Number of entries (must be a power of two). |
| ALMOST_FULL_TH | DEPTH-2 | Assert `O_ALMOST_FULL` when `count >= ALMOST_FULL_TH`. |
| ALMOST_EMPTY_TH | 2 | Assert `O_ALMOST_EMPTY` when `count <= ALMOST_EMPTY_TH`. |
| AW | $clog2(DEPTH) | Address width (derived). |

> All parameters are compile-time; `DEPTH` must be a power of two so that pointer wrap is a simple MSB toggle.

## 4. Port List

### Clock & Reset

| Signal | Dir | Width | Clock | Active | Description |
|---|---|---|---|---|---|
| I_CLK | IN | — | — | — | Single clock for both write and read sides. |
| I_RST | IN | — | — | LOW | Synchronous reset, active low. Clears pointers and count; RAM contents are not cleared (don't-care). |
| I_CLR | IN | — | — | HIGH | Synchronous flush; when 1, pointers and count reset to 0 on the next `I_CLK` edge. |

### Write Interface (producer)

| Signal | Dir | Width | Clock | Active | Description |
|---|---|---|---|---|---|
| I_WR_EN | IN | — | I_CLK | HIGH | Write enable. Ignored when `O_FULL = 1`. |
| I_WR_DATA | IN | [DW-1:0] | I_CLK | — | Data to write. Captured on `I_CLK` when `I_WR_EN && !O_FULL`. |

### Read Interface (consumer)

| Signal | Dir | Width | Clock | Active | Description |
|---|---|---|---|---|---|
| I_RD_EN | IN | — | I_CLK | HIGH | Read enable. Ignored when `O_EMPTY = 1`. |
| O_RD_DATA | OUT | [DW-1:0] | I_CLK | — | Data at the current read pointer. Valid on the cycle **after** `I_RD_EN && !O_EMPTY` (registered output). |
| O_PEEK | OUT | [DW-1:0] | I_CLK | — | Combinational FIFO head (`mem[rptr]`) — for consumers that need the data immediately (e.g. `uart_rx` read-back through the APB). Updates as soon as the head changes; no pop required. |

### Status Flags

| Signal | Dir | Width | Clock | Active | Description |
|---|---|---|---|---|---|
| O_FULL | OUT | — | I_CLK | HIGH | FIFO is full (`count == DEPTH`). Further writes are ignored. |
| O_EMPTY | OUT | — | I_CLK | HIGH | FIFO is empty (`count == 0`). Reads return undefined data. |
| O_ALMOST_FULL | OUT | — | I_CLK | HIGH | `count >= ALMOST_FULL_TH`. Use for back-pressure / TX interrupt. |
| O_ALMOST_EMPTY | OUT | — | I_CLK | HIGH | `count <= ALMOST_EMPTY_TH`. Use for RX interrupt / refill. |
| O_COUNT | OUT | [AW:0] | I_CLK | — | Current occupancy (0 … DEPTH). Optional, for debug/status registers. |

## 5. Operation

### 5.1 Write

- On each `I_CLK` edge, if `I_WR_EN && !O_FULL`:
  - `mem[wptr[AW-1:0]]` ← `I_WR_DATA`
  - `wptr` ← `wptr + 1`
  - `count` ← `count + 1`
- If `I_WR_EN && O_FULL`, the write is **silently dropped**; `O_FULL` remains 1. Caller must check `O_FULL` before asserting `I_WR_EN`.
- Simultaneous read+write when FIFO is full: the read frees a slot, so the write can be accepted in the same cycle (standard "read-before-write" behaviour).

### 5.2 Read

- On each `I_CLK` edge, if `I_RD_EN && !O_EMPTY`:
  - `O_RD_DATA` ← `mem[rptr[AW-1:0]]` (registered)
  - `rptr` ← `rptr + 1`
  - `count` ← `count - 1`
- If `I_RD_EN && O_EMPTY`, the read is ignored; `O_RD_DATA` retains its previous value.
- `O_PEEK` is the **combinational head** (`mem[rptr]`): valid immediately, no pop required — used where a registered 1-cycle read latency is not acceptable (e.g. APB read-back in `uart_rx`).
- Simultaneous read+write when FIFO is empty: the write fills a slot, so the read can be serviced in the same cycle.

### 5.3 Flags

Flags are derived from `count` (registered or combinational, depending on timing budget):

| Flag | Condition |
|---|---|
| `O_FULL` | `count == DEPTH` |
| `O_EMPTY` | `count == 0` |
| `O_ALMOST_FULL` | `count >= ALMOST_FULL_TH` |
| `O_ALMOST_EMPTY` | `count <= ALMOST_EMPTY_TH` |

`O_COUNT` is exposed for status registers; it is not required for FIFO operation.

### 5.4 Reset and flush

- `I_RST` (active low, synchronous): on the next `I_CLK` edge, `wptr`, `rptr`, `count` reset to 0; `O_FULL`/`O_EMPTY`/`O_ALMOST_*` update accordingly. RAM contents are **not** cleared.
- `I_CLR` (active high, synchronous): same effect as reset but without requiring the reset tree; used by software via a control register (e.g. `UART_CTRL.FIFO_FLUSH`).

### 5.5 Simultaneous read/write

The FIFO supports concurrent `I_WR_EN` and `I_RD_EN` in the same cycle:

| `O_FULL` | `O_EMPTY` | Behaviour |
|---|---|---|
| 0 | 0 | Write accepted, read accepted; `count` unchanged. |
| 1 | 0 | Read accepted, write accepted (slot freed by read); `count` unchanged. |
| 0 | 1 | Write accepted, read accepted (slot filled by write); `count` unchanged. |
| 1 | 1 | Impossible (cannot be full and empty simultaneously unless `DEPTH = 0`). |

## 6. Usage in `uart_tx` and `uart_rx`

### 6.1 `uart_tx` (APB → TXD)

```text
APB write ──▶ [ sync_fifo (DW=8) ] ──▶ [ baud engine ] ──▶ TXD
              I_WR_EN = apb_wr && addr_hit
              I_RD_EN = tx_ready && !O_EMPTY
              O_ALMOST_FULL ──▶ TX FIFO full interrupt
              O_EMPTY       ──▶ TX idle
```

- APB writes push bytes into the FIFO.
- The baud engine pops a byte when it is ready to start a new frame (start bit + 8 data bits + stop bit).
- `O_ALMOST_FULL` can be routed to an interrupt so software stops writing before overflow.

### 6.2 `uart_rx` (RXD → APB)

  ```text
  RXD ──▶ [ baud engine ] ──▶ [ sync_fifo (DW=8) ] ──▶ APB read
                                I_WR_EN = rx_valid
                                I_RD_EN = apb_rd && addr_hit
                                O_ALMOST_EMPTY ──▶ RX data available interrupt
                                O_FULL         ──▶ RX overflow (drop)
  ```

- The baud engine pushes a received byte into the FIFO after the stop bit is sampled.
- APB reads pop bytes out.
- `O_ALMOST_EMPTY` (or `!O_EMPTY`) is used as the "RX data available" interrupt.
- `O_FULL` indicates RX overflow; the incoming byte is dropped and an overrun error flag should be set in the UART status register.

## 7. Timing

  ```text
  I_CLK     _/‾\_/‾\_/‾\_/‾\_/‾\_/‾\_
  I_WR_EN   __/‾‾‾\___________________
  I_WR_DATA X==D0=X==D1=X=============
  O_FULL    __________________________ (count < DEPTH)
  O_EMPTY   ‾‾‾‾‾‾‾\___________________
  I_RD_EN   ________/‾‾‾\_____________
  O_RD_DATA XXXXXXXX==D0=X============
            | WR D0 | WR D1 | RD D0 |
  ```

- Write: `O_RD_DATA` is updated one cycle after `I_RD_EN && !O_EMPTY`.
- If the consumer needs combinational read (same-cycle), replace the registered output with a direct `mem[rptr]` read — note that this changes the timing path.

---

**Ghi chú biên tập:**
- Cần xác nhận với RTL `src/sync_fifo.v`: `O_RD_DATA` là **registered** (1-cycle latency, như mô tả trên) hay **combinational** (same-cycle). Nếu combinational, sửa mục 5.2 và 7.
- `I_CLR` là tuỳ chọn; nếu RTL không có, xoá khỏi port list và mục 5.4.
- `O_COUNT` là tuỳ chọn; nếu không expose ra ngoài, xoá khỏi port list.
- `ALMOST_FULL_TH` / `ALMOST_EMPTY_TH` phải là hằng số compile-time; nếu RTL cho phép cấu hình runtime qua thanh ghi, chuyển thành input port và cập nhật mục 3/4/5.3.
- Với `uart_tx`/`uart_rx`, `DW=8`, `DEPTH` thường là 16 hoặc 32; ghi rõ trong instantiation nếu cần.
- Nếu cần hỗ trợ **byte strobe** hoặc **parity** trong FIFO, thêm bit phụ (ví dụ `DW+1` với parity bit) — spec này giả định FIFO thuần data.

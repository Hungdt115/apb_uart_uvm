```
title: UART Baud-Rate Generator
module: uart_baud_gen
version: "1.0"
status: draft
updated: 2026-11-23
rtl: ../../../src/uart_baud_gen.v
summary: Programmable baud-rate generator with a runtime divisor loaded from reg_uart_brg (REG_UART_BRG_WEN pulse), producing a 16x oversampling tick and a 1x bit tick. uart_tx uses tick_1x, uart_rx uses tick_16x; both run only while reg_uart_en = 1.
```
---

> **Bản biên tập nội dung** — file `.html` cùng tên là trang hiển thị chính thức (mở trực tiếp bằng trình duyệt). Sửa nội dung ở đây rồi cập nhật sang `.html`, hoặc sửa trực tiếp `.html`.

## 1. Overview

`uart_baud_gen` is the UART baud-rate generator. The divisor is **programmed at runtime** through the `reg_uart_brg` register: `apb2reg` delivers the divisor value (`REG_UART_BRG[15:0]`, already synchronised into the UART clock domain by `rw_reg`) together with a one-cycle write pulse (`REG_UART_BRG_WEN`). The module is instantiated twice: once for TX and once for RX, each with its own enable/restart inputs.

- TX instance: consumes `O_TICK_1X` to shift out one bit per bit-period.
- RX instance: consumes `O_TICK_16X` to oversample each bit 16 times (the RX FSM counts the 16x ticks and samples at the middle tick).

Both instances run on `UART_CLK` and are enabled **only while `reg_uart_en = 1`**.

## 2. Divisor configuration

```
BRG_DIV = round( UART_CLK / (BAUD_RATE × 16) )
```

The project's `UART_CLK` is **50 MHz** (top.sv: `#10` toggle → 20 ns period).

| Baud rate | BRG_DIV | Hex |
|---|---|---|
| 9600 (reset default) | 326 | 0x0146 |
| 19200 | 163 | 0x00A3 |
| 57600 | 54 | 0x0036 |
| 115200 | 27 | 0x001B |
| 921600 | 3 | 0x0003 |

- Constraint: `BRG_DIV ≥ 1`. A write of `0` is **ignored** — the shadow divisor keeps its previous value.
- Reset default: `326` (9600 bps @ 50 MHz). Recompute `P_DIV_RST` if `UART_CLK` changes.
- The CPU should write `reg_uart_brg` only while the UART is idle (`tx_busy = 0`, `rx_busy = 0`) — see section 7.

## 3. Port List

| Signal | Dir | Width | Clock | Active | Description |
|---|---|---|---|---|---|
| I_CLK | IN | — | UART | — | UART clock (50 MHz in this project). |
| I_RST_N | IN | — | UART | LOW | **Asynchronous** reset, active low (project convention, same as `rw_reg`). |
| I_BRG_DIV | IN | [15:0] | UART | — | Divisor value from `REG_UART_BRG[15:0]` (already synchronised into the UART domain). |
| I_BRG_WR_EN | IN | — | UART | HIGH | One-cycle pulse (`REG_UART_BRG_WEN`): load `I_BRG_DIV` into the shadow divisor. |
| I_ENABLE | IN | — | UART | HIGH | Run enable. TX: `tx_busy \| reg_uart_en`; RX: `rx_busy \| reg_uart_en`. When 0 the counters are reset and no tick is generated. |
| I_RESTART | IN | — | UART | HIGH | Highest priority: clear both counters (start bit / start of TX). |
| O_TICK_16X | OUT | — | UART | HIGH | One-cycle pulse, frequency `16 × BAUD_RATE` (one per `BRG_DIV` clocks). |
| O_TICK_1X | OUT | — | UART | HIGH | One-cycle pulse, frequency `BAUD_RATE`, asserted **1 clock after** the 16th `O_TICK_16X` pulse of each bit-period. |

## 4. Architecture

```text
                       +--------------------------------------+
  I_BRG_DIV[15:0] ───▶ │  shadow divisor div_val (P_DIV_RST)  │
  I_BRG_WR_EN     ───▶ │  load when WEN && DIV != 0           │
                       +------------------+-------------------+
                                          | div_val
                                          v
                       +--------------------------------------+
  I_CLK ─────────────▶ │  main counter cnt [15:0]             │──▶ O_TICK_16X
  I_RST_N ──────────▶  │  restart: cnt <= 0                   │
  I_ENABLE ─────────▶  │  enable=0: reset counters           │
                       +------------------+-------------------+
                                          | O_TICK_16X
                                          v
                       +--------------------------------------+
                       │  phase counter os_cnt [3:0] (0..15)  │──▶ O_TICK_1X
                       │  os_cnt==15: tick_1x, os_cnt <= 0    │
                       │  restart: os_cnt <= 0                │
                       +--------------------------------------+
```

### 4.1 Shadow divisor

- Loaded on `I_BRG_WR_EN` **only when `I_BRG_DIV != 0`**; otherwise the old value is kept.
- Reset value: `P_DIV_RST = 16'd326` (9600 bps @ 50 MHz).
- Using a shadow register keeps a mid-frame divisor change from corrupting the on-going frame; the CPU is still advised to write only when idle.

### 4.2 Main counter (`O_TICK_16X`)

Priority order: `I_RESTART` > `!I_ENABLE` (reset) > divisor write (restart) > counting.

```text
I_RESTART = 1            : cnt <= 0,                     tick_16x <= 0
I_ENABLE  = 0            : cnt <= 0,                     tick_16x <= 0
divisor write valid      : cnt <= 0,                     tick_16x <= 0
cnt == div_val - 1       : cnt <= 0,                     tick_16x <= 1
otherwise                : cnt <= cnt + 1,               tick_16x <= 0
```

`cnt` is 16 bits (max divisor 65535). `O_TICK_16X` is a registered one-cycle pulse in the cycle **after** `cnt` reaches `div_val - 1`.

### 4.3 Phase counter (`O_TICK_1X`)

Counts the `O_TICK_16X` pulses within one bit-period (16 ticks per bit):

```text
I_RESTART = 1            : os_cnt <= 0,                  tick_1x <= 0
tick_16x = 1, os_cnt=15  : os_cnt <= 0,                  tick_1x <= 1
tick_16x = 1, otherwise  : os_cnt <= os_cnt + 1,         tick_1x <= 0
otherwise                :                                tick_1x <= 0
```

- `O_TICK_1X` is derived **from** `O_TICK_16X` (never counted independently), so the two ticks always stay phase-locked.
- `O_TICK_1X` appears 1 clock after the 16th `O_TICK_16X` pulse of each bit-period (registered `tick_1x`).
- Bit-period = `16 × BRG_DIV` UART clocks.

## 5. Reset behaviour

- `I_RST_N` (asynchronous, active low): `div_val <= P_DIV_RST`, both counters cleared, both tick outputs 0.
- After reset release the generator is idle until `I_ENABLE` is asserted (requires `busy = 1` or `reg_uart_en = 1`).

## 6. Integration with uart_tx / uart_rx

| Attribute | TX instance | RX instance |
|---|---|---|
| I_BRG_DIV / I_BRG_WR_EN | chung: `REG_UART_BRG[15:0]` / `REG_UART_BRG_WEN` từ `apb2reg` | chung như TX |
| I_ENABLE | `tx_busy \| reg_uart_en` | `rx_busy \| reg_uart_en` |
| I_RESTART | `tx_start` | `start_bit_detect` |
| O_TICK_16X | không dùng | dùng — FSM RX đếm 0..15, lấy mẫu tại tick thứ 8 (giữa bit) |
| O_TICK_1X | dùng — dịch bit mỗi bit-period | tùy chọn |

> **Bắt buộc:** cả hai instance chỉ chạy khi `reg_uart_en = 1` hoặc đang bận — `I_ENABLE` phải bằng `busy | reg_uart_en` như bảng trên (idle + disabled → reset counters, không phát tick).

## 7. Register-block interface (apb2reg)

- `REG_UART_BRG[15:0]` — giá trị divisor đã được `rw_reg` (4-phase CDC) đồng bộ vào UART domain.
- `REG_UART_BRG_WEN = uart_brg_ack` — xung 1 chu kỳ `UART_CLK`, xuất hiện **1 chu kỳ sau** khi giá trị divisor đã ổn định ở `REG_UART_BRG` → việc nạp shadow register trong `uart_baud_gen` luôn lấy đúng giá trị mới.
- Write mask của `reg_uart_brg` trong `apb2reg` là `0xFFFF` — đúng độ rộng `BRG_DIV` 16 bit.

## 8. Timing chart (BRG_DIV = 4, rút gọn)

```text
I_CLK     : _/‾\_/‾\_/‾\_/‾\_/‾\_/‾\_/‾\_/‾\_/‾\_/‾\_
cnt       :  0  1  2  3  0  1  2  3  0  1  2  3  0 ...
tick_16x  :  0  0  0  0  1  0  0  0  1  0  0  0  1 ...
os_cnt    :  0  0  0  0  0  1  1  1  1  2  2  2  2 ...
tick_1x   :  (xung 1 clk, sau xung tick_16x thứ 16 của mỗi bit-period)
```

- `O_TICK_16X` là xung đã đăng ký: xuất hiện ở chu kỳ **sau** khi `cnt` đạt `div_val-1`.
- `O_TICK_1X` trễ đúng 1 clk so với xung `O_TICK_16X` thứ 16 — chọn phương án "trễ 1 clk" để `tick_1x` hoàn toàn từ thanh ghi, đường timing sạch.

---

**Ghi chú biên tập:**
- Tần số `UART_CLK` = **50 MHz** lấy theo `top.sv` hiện tại (`#10`). Nếu đổi clock thì phải tính lại `P_DIV_RST` và bảng baud ở mục 2.
- Reset mặc định 9600 bps → `div_val = 326 (0x0146)` — chọn theo yêu cầu; giá trị này cũng là `P_DIV_RST`.
- Kiểu reset **bất đồng bộ** active-low theo convention của `rw_reg`/`apb_slave` trong project (spec gốc gợi ý đồng bộ — đã đổi theo quyết định).
- `uart_tx`/`uart_rx` chưa thiết kế; mục 6 là ràng buộc tích hợp bắt buộc khi thiết kế 2 khối đó (kèm điều kiện `reg_uart_en = 1`).

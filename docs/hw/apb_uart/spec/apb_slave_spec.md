---
title: APB4 Slave FSM
module: apb_slave
version: "1.0"
status: draft
updated: 2025-07-21
rtl: ../../../src/apb_slave.v
summary: Implements the APB setup/access phases with configurable wait-state counters, optional register-level ACK handshake, and PSLVERR error reporting.
---

> **Content editing source** — the `.html` file of the same name is the official display page (open it directly in a browser). Edit the content here and then update the `.html`, or edit the `.html` directly.

## 1. Overview

`apb_slave` implements the APB transfer state machine: it decodes the two-phase handshake (`PSEL` setup, `PENABLE` access), counts configurable wait states, and produces the register-side control signals (`O_REG_ADDR`, `O_REG_WR`, `O_REG_RD`, …) that `apb2reg` consumes.

## 2. APB Protocol

| Phase | PSEL | PENABLE | PREADY | Note |
|---|---|---|---|---|
| IDLE | 0 | 0 | 0 | No transfer. |
| SETUP | 1 | 0 | 0 | Address and write data are sampled at the PSEL rising edge. |
| ACCESS | 1 | 1 | 0 → 1 | Wait-state counter counts up to `p_wr_wait` / `p_rd_wait`. |

## 3. Timing

```text
PCLK      _/‾\_/‾\_/‾\_/‾\_/‾\_/‾\_/‾\_
PSEL      ________/‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾\________
PENABLE   _______________/‾‾‾‾‾‾‾‾‾‾\________
PREADY    ______________________/‾‾‾‾‾\______
          |  IDLE  |  SETUP  |  ACCESS  |
```

> PREADY is a **held level**: it stays high after the ACCESS phase (through idle and the next SETUP) and only re-arms when the next transfer's SETUP begins — the simplified chart above shows only the rise inside the ACCESS phase.

## 4. Parameters

| Parameter | Default | Description |
|---|---|---|
| p_use_ack | 0 | 0: PREADY from wait-state timing; 1: PREADY from register ACK (I_REG_ACK). Configured 1'h0 in apb_dut. |
| p_wr_wait | 4'h0 | Write wait cycles during the access phase. Configured 4'h0 in apb_dut. |
| p_rd_wait | 4'h1 | Read wait cycles during the access phase. Configured 4'h1 in apb_dut. |

## 5. Port List

### Clock & Reset

| Signal | Dir | Width | Clock | Active | Description |
|---|---|---|---|---|---|
| I_PCLK | IN | — | APB | — | APB clock. |
| I_PRESET | IN | — | APB | LOW | APB reset, active low. |

### APB Master Interface

| Signal | Dir | Width | Clock | Active | Description |
|---|---|---|---|---|---|
| I_PADDR | IN | [31:0] | APB | — | APB address, sampled at the PSEL rising edge. |
| I_PPROT | IN | [2:0] | APB | — | APB protection; unused by this module. |
| I_PSEL | IN | — | APB | — | APB module select. |
| I_PENABLE | IN | — | APB | — | APB enable (access phase). |
| I_PWRITE | IN | — | APB | — | APB write (1) / read (0). |
| I_PWDATA | IN | [31:0] | APB | — | APB write data, sampled at the write setup edge. |
| I_PSTRB | IN | [3:0] | APB | — | APB byte strobes; unused by this module. |

### Register Interface (from apb2reg)

| Signal | Dir | Width | Clock | Active | Description |
|---|---|---|---|---|---|
| I_REG_RD_WAIT | IN | [3:0] | APB | — | Extra read wait cycles requested by the register block. |
| I_REG_RD_DATA | IN | [31:0] | APB | — | Read data from the register block, forwarded to O_PRDATA. |
| I_REG_ACK | IN | — | APB | — | Register access acknowledge (used when p_use_ack=1). |
| I_REG_ERR | IN | — | APB | — | Register decode error, reported on O_PSLVERR. |

### APB Outputs

| Signal | Dir | Width | Clock | Active | Description |
|---|---|---|---|---|---|
| O_PREADY | OUT | — | APB | — | APB ready. Held high from the ready point until the next transfer's SETUP begins (level, not a pulse). |
| O_PRDATA | OUT | [31:0] | APB | — | APB read data. |
| O_PSLVERR | OUT | — | APB | — | APB slave error, held until the access completes. |

### Register Interface (to apb2reg)

| Signal | Dir | Width | Clock | Active | Description |
|---|---|---|---|---|---|
| O_REG_ADDR | OUT | [31:0] | APB | — | Registered address for the register block. |
| O_REG_WR | OUT | — | APB | — | Register write strobe. |
| O_REG_RD | OUT | — | APB | — | Register read strobe. |
| O_REG_WR_DATA | OUT | [31:0] | APB | — | Registered write data. |
| O_REG_ERR_ACK | OUT | — | APB | — | Access-done pulse (PENABLE & PREADY) to clear the error flag. |


## 6. Operation Principle

The module **does not use an FSM/state register**. All behavior is described by parallel `always` blocks. Instead of inferring the phase from `I_PSEL`/`I_PENABLE`, the module uses the following **combinational decode signals** as control conditions:

### Input decode signals

| Signal | Condition | Meaning |
|---|---|---|
| `w_psel` | `I_PSEL & ~I_PENABLE` | In the SETUP phase. |
| `w_penable` | `I_PSEL & I_PENABLE` | In the ACCESS phase. |
| `w_pwrite` | `I_PWRITE & I_PENABLE` | Write access in the ACCESS phase. |
| `w_pread` | `~I_PWRITE & I_PENABLE` | Read access in the ACCESS phase. |
| `w_pdone` | `I_PENABLE & O_PREADY` | Access completes in this cycle. |

### 6.1 Internal flags and counters

| Internal signal | Type | Meaning |
|---|---|---|
| `wr_d` | flag (reg) | Latches `I_PWRITE` at `w_psel`. |
| `access_d` | flag (reg) | ACCESS entered (set by `w_penable`, cleared by `w_pdone`). |
| `wait_cnt` | counter (reg) | Counter that **counts up** from 0 to `wait_target`, then resets to 0. |
| `wait_target` | combinational flag | `wr_d ? p_wr_wait : p_rd_wait`. |
| `wait_done` | flag (reg) | Set when `wait_cnt` reaches `wait_target`; cleared at `w_pdone`. |
| `err_d` | flag (reg) | Holds `O_PSLVERR` until `w_pdone`. |

**Wait-state counter (counts up):**

- When `access_d = 1` and `wait_done = 0`: `wait_cnt` ← `wait_cnt + 1`.
- When `wait_cnt == wait_target`: `wait_done` ← 1 and `wait_cnt` ← 0.
- When `w_pdone = 1`: `wait_done` ← 0, `wait_cnt` ← 0.

---

### 6.2 Write access (`w_pwrite = 1`)

**Latched at `w_psel`:**

- `O_REG_ADDR` ← `I_PADDR`.
- `wr_d` ← 1.
- `O_REG_WR_DATA` ← `I_PWDATA` **byte-filtered by `I_PSTRB`**:

    ```verilog
    O_REG_WR_DATA[ 7: 0] <= I_PSTRB[0] ? I_PWDATA[ 7: 0] : O_REG_WR_DATA[ 7: 0];
    O_REG_WR_DATA[15: 8] <= I_PSTRB[1] ? I_PWDATA[15: 8] : O_REG_WR_DATA[15: 8];
    O_REG_WR_DATA[23:16] <= I_PSTRB[2] ? I_PWDATA[23:16] : O_REG_WR_DATA[23:16];
    O_REG_WR_DATA[31:24] <= I_PSTRB[3] ? I_PWDATA[31:24] : O_REG_WR_DATA[31:24];
    ```
- Bytes with strobe = 0 keep their previous value; `I_PSTRB = 4'h0` keeps everything unchanged; `I_PSTRB = 4'hF` = `I_PWDATA`.

**During ACCESS (`access_d = 1`, `wr_d = 1`):**

- `wait_target = p_wr_wait` (default `4'h0`).
- `wait_cnt` counts up to `p_wr_wait` → sets `wait_done`, resets `wait_cnt` to 0 (no counting when `wait_target = 0`).
- `O_REG_RD = 0` (not active for writes).
- `O_REG_WR`:
  - Mode `p_use_ack = 0`: **1-cycle pulse** at `w_penable_pos & PWRITE`.
  - Mode `p_use_ack = 1`: **level 1** held until the transaction completes (`I_REG_ACK = 1`).

**Access completion (`w_pdone = 1`):**

- Mode 0: `O_PREADY` rises when the wait counter reaches the target and is **held at 1** afterwards (level, not a pulse).
- Mode 1: `O_PREADY` rises one cycle after `I_REG_ACK` (registered) and is **held at 1** afterwards.
- In both modes `O_PREADY` stays asserted through the completion and the following idle/setup cycles, and re-arms (drops) only when the next transfer's SETUP begins — matching the ARM APB FSM style.
- `O_REG_ERR_ACK` issues a 1-cycle pulse (see 6.4).
- `O_PRDATA` is not updated (held — write).
- `O_PSLVERR` follows `err_d` (see 6.4).

---

### 6.3 Read access (`w_pread = 1`)

**Latched at `w_psel`:**

- `O_REG_ADDR` ← `I_PADDR`.
- `wr_d` ← 0.
- `O_REG_WR_DATA` is meaningless for reads (still updated per strobe or held — matches the RTL).

**During ACCESS (`access_d = 1`, `wr_d = 0`):**

- `wait_target = p_rd_wait` (default `4'h1`).
- `wait_cnt` counts up to `p_rd_wait` → sets `wait_done`, resets `wait_cnt` to 0.
- `O_REG_WR = 0` (not active for reads).
- `O_REG_RD`:
  - Mode `p_use_ack = 0`: **1-cycle pulse** at `w_penable_pos & ~PWRITE` — `O_REG_RD <= w_penable_pos & ~PWRITE`.
  - Mode `p_use_ack = 1`: **level 1** held until the transaction completes — `O_REG_RD <= access_d & ~wr_d & ~w_pdone`.

**Access completion (`w_pdone = 1`):**

- Mode 0: `O_PREADY` rises when the wait counter reaches the target and is **held at 1** afterwards (level, not a pulse).
- Mode 1: `O_PREADY` rises one cycle after `I_REG_ACK` (registered) and is **held at 1** afterwards.
- In both modes `O_PREADY` stays asserted through the completion and the following idle/setup cycles, and re-arms (drops) only when the next transfer's SETUP begins — matching the ARM APB FSM style.
- `O_PRDATA` ← `I_REG_RD_DATA` latched at `w_pdone`.
- `O_REG_ERR_ACK` issues a 1-cycle pulse (see 6.4).
- `O_PSLVERR` follows `err_d` (see 6.4).

---

### 6.4 Error handling

**Error source:** `I_REG_ERR` from `apb2reg` (address decode failure).

**Error capture:**

- When `access_d = 1` and `I_REG_ERR = 1`: `err_d` ← 1.
- `O_PSLVERR` ← `err_d`, **held** throughout the ACCESS phase until `w_pdone` (not cleared in between).

**Clearing the error flag:**

- `w_pdone = I_PENABLE & O_PREADY` is a 1-cycle pulse in the completion cycle.
- `O_REG_ERR_ACK` ← `w_pdone`, sent to `apb2reg` to clear the error flag on the register-block side.
- `err_d` is cleared at `w_pdone`; `O_PSLVERR` returns to 0 in the following cycle.

**Relationship with wait-states / ACK:**

- Mode `p_use_ack = 0`: the error is reported in the `wait_done` cycle (when `O_PREADY` goes high, `w_pdone` = 1).
- Mode `p_use_ack = 1`: the error is reported in the `I_REG_ACK` cycle (when `O_PREADY` goes high, `w_pdone` = 1); without an ACK, `O_PSLVERR` is held and the access hangs intentionally.

---

### 6.5 Output behavior summary

| Output | `p_use_ack = 0` | `p_use_ack = 1` |
|---|---|---|
| `O_PREADY` | Rises at wait-done, **held at 1** until the next SETUP | Rises 1 cycle after ACK, **held at 1** until the next SETUP |
| `O_REG_ADDR` | Latched at `w_psel` | Latched at `w_psel` |
| `O_REG_WR_DATA` | Latched at `w_psel`, byte-filtered by `I_PSTRB` | Latched at `w_psel`, byte-filtered by `I_PSTRB` |
| `O_REG_WR` | 1-cycle pulse at `w_penable_pos & PWRITE` (writes only) | Level 1 held until the transaction completes (writes only) |
| `O_REG_RD` | 1-cycle pulse at `w_penable_pos & ~PWRITE` (reads only) | Level 1 held until the transaction completes (reads only) |
| `O_REG_ERR_ACK` | 1-cycle pulse at `w_pdone` | 1-cycle pulse at `w_pdone` |
| `O_PRDATA` | Latches `I_REG_RD_DATA` at `w_pdone` | Latches `I_REG_RD_DATA` at `w_pdone` |
| `O_PSLVERR` | `err_d`, held until `w_pdone` | `err_d`, held until `w_pdone` |

---

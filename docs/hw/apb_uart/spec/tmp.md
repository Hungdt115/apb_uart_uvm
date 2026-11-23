# Refactor UART TX into 8 Functional Blocks

## 1. Objective

Refactor the internal structure of `src/uart_tx.v` into **8 functional blocks**, with each block organized as a separate `always` or `assign` section.

The purpose is to improve RTL readability, maintainability, and functional separation without changing the module interface or intended behavior.

## 2. Scope

### A. `src/uart_tx.v`

Reorganize the internal RTL into 8 functional blocks.

**Requirements:**
- Keep the existing port list unchanged.
- Preserve the existing behavior and timing.
- Keep the declarations grouped at the beginning of the file:
  - `LOCALPARAMS`
  - `REGS`
  - `WIRES`
  - `CONTINUOUS ASSIGNS`
- Organize the implementation into 8 clearly labeled functional sections.
- Each functional block must be implemented using separate `always` and/or `assign` logic within the same module.
- Do not create additional submodules for these functional blocks.

### 3. Functional Block Organization

| # | Functional block | Internal organization | Logic changes |
|---|---|---|---|
| 1 | Baud enable generation | Dedicated section containing `uart_baud_gen` instance and `w_cken` wire | None |
| 2 | Bit counter | Separate `always` blocks for `bit_cnt` and `stop_cnt`; generate `w_data_done` and `w_stop_done` flags | Refactor counting convention to 0–8 while preserving tick timing |
| 3 | FSM control | FSM `always` block manages state transitions using `r_tx_start`, `w_cken`, `w_data_done`, `w_stop_done`, and `I_MODE[1]` | Remove TXD, shift register, and bit counter assignments from FSM |
| 4 | Send data generation (FIFO write) | Group flush edge detection (`r_clr_d`, `w_tx_fifo_clr`), `fifo_wen` assignment, and sticky overflow flag (`r_tx_ovf`) | None |
| 5 | Data buffer pop | Group `sync_fifo` instance and 3-phase TX controller (`ctrl_phase`, `r_tx_data_hold`, `fifo_ren`, `r_tx_start`) | None |
| 6 | Start/parity/stop generation | Combinational logic for `w_parity_next` based on `I_MODE[2:1]`, `w_stop_target_next` based on `I_MODE[0]`, and start bit = 0; latch `parity_bit` and `stop_target` on `w_ld_frame` | Separate from FSM |
| 7 | Transmit data generation | Dedicated `always` block for `txd` and `shift_reg`; `w_ld_frame` loads start bit and data, `w_cken` shifts during START/DATA or outputs parity/stop, `S_STOP` holds `txd = 1` | Separate from FSM |
| 8 | Status flags | Assignments for `w_tx_busy`, `O_TX_BUSY`, `O_TX_IDLE`, `O_TX_OVF`, and `FIFO_*` status outputs | None |

### 4. Shared Internal Signal

Use the following shared signal:

```verilog
w_ld_frame = r_tx_start;
```

`w_ld_frame` is the common frame-load event used by functional blocks 2, 3, 6, and 7.

Ensure that the signal is used consistently across the relevant blocks.

### 5. Behavior and Timing Requirements

The refactoring must preserve the following behaviors:

- **FIFO pop sequence:** Pop at cycle N → hold data at cycle N+1 → start transmission at cycle N+2.
- **Flush behavior:** Flush cancels any pending FIFO pop operation.
- **Stop-bit timing:** Stop counter must count exactly 1 or 2 stop-bit periods, according to the configured mode.
- **Busy behavior:** `TX_BUSY` remains asserted throughout the stop-bit period and deasserts only when the frame is fully completed.
- **Bit counter convention:** Use the 0–8 counting convention for data bits while preserving the original tick timing.
- **Frame-load synchronization:** `w_ld_frame = r_tx_start` must remain consistent across all blocks that depend on frame loading.

Do not introduce unintended latency, early `TX_BUSY` deassertion, or changes to FIFO handshake timing.

---

## 6. UART TX Specification Update

Update `uart_tx_spec.md` to reflect the refactored internal architecture.

### 6.1 Block Diagram — Section 9

Replace the existing Section 9 block diagram with one reflecting the new 8-functional-block organization.

### 6.2 Internal Architecture — 8 Functional Blocks

Add a new section titled:

**Internal Architecture — 8 Functional Blocks**

Include a table describing all 8 blocks, their internal signals, and their responsibilities.

Clarify that each functional block is a separate `always` and/or `assign` section within the same `uart_tx` module, not a separate submodule.

### 6.3 FSM — Sections 4 and 5

Update Sections 4 and 5 to reflect the new FSM responsibilities.

- FSM only handles state transitions.
- State transitions use `data_done` and `stop_done` flags.
- Bit shifting, parity generation, and TXD output logic are handled by Functional Blocks 6 and 7.
- Remove descriptions implying that the FSM directly controls the shift register, bit counter, or TXD output.

### 6.4 Frame Generation

Update the specification to describe the separation of responsibilities:

- Functional Block 6: Start, parity, and stop configuration generation.
- Functional Block 7: TXD and shift register operation.
- `w_ld_frame`: shared frame-load event used to synchronize frame-related logic.

---

## 7. Baud Generator Specification Update

Update `uart_baud_gen_spec.md` to align with the latest RTL implementation.

### 7.1 Section 4.2 — Enable Behavior

Update the description of `I_ENABLE = 0`.

The counter no longer holds its previous value when disabled. Instead:

- Main counter is reset to 0.
- Phase counter is reset to 0.
- Tick outputs are deasserted.
- Enabling again starts a new baud period from the beginning.

Remove any description stating that the counters pause or hold their previous values while disabled.

### 7.2 Shadow Divisor Behavior

Update the shadow-divisor note to reflect the latest behavior:

- Writing a valid new divisor restarts baud timing phase.
- Main counter and phase counter are reset when the divisor is updated.
- The new divisor takes effect for the subsequent baud-counting period.
- Recommend updating the divisor only when UART is idle to avoid disrupting an active frame.

### 7.3 UART TX Section 7.6 — Enable Behavior

Update the note regarding `I_ENABLE = 0`.

The previous description stating that the frame pauses while disabled is no longer valid.

Instead, clarify that disabling the baud generator resets its counters and phase. If `I_ENABLE` is deasserted during an active frame, the frame is not paused and resumed seamlessly; the baud timing is restarted when enabled again, which may disrupt the ongoing frame.

Remove any pause/resume behavior descriptions.

---

## 8. Constraints

- Do not change the `uart_tx` port list.
- Do not change the intended external behavior or timing.
- Do not add new submodules for the 8 functional blocks.
- Preserve FIFO pop/hold/start timing.
- Preserve flush cancellation behavior.
- Preserve stop-bit duration.
- Preserve `TX_BUSY` coverage through the stop period.
- Keep declarations grouped at the beginning of `uart_tx.v`.
- Make the RTL structure correspond to the 8 functional blocks described above.
- Ensure the specifications match the actual RTL behavior after refactoring.

## 9. Deliverables

1. Refactored `src/uart_tx.v` organized into 8 functional blocks.
2. Updated `uart_tx_spec.md`:
   - Updated Section 9 block diagram.
   - Added 8-functional-block architecture section.
   - Updated Sections 4 and 5 to describe FSM-only state transition control.
   - Updated frame generation descriptions for Functional Blocks 6 and 7.
3. Updated `uart_baud_gen_spec.md`:
   - Updated Section 4.2 enable behavior.
   - Updated shadow-divisor behavior.
4. Updated `uart_tx_spec.md` Section 7.6 to remove the incorrect pause/resume description.

## 10. Verification

After refactoring, verify that:

- Port list remains identical.
- No unintended behavior or timing changes are introduced.
- FIFO pop → hold → start sequence remains N → N+1 → N+2.
- Flush cancels pending FIFO pop.
- Stop-bit duration is correct for both 1-stop-bit and 2-stop-bit configurations.
- `TX_BUSY` remains asserted throughout the stop-bit period.
- Baud enable deassertion resets timing counters and phase.
- Divisor write restarts baud timing phase.
- RTL and specifications are consistent.

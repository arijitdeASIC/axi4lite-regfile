# axi4lite_regfile

A synthesizable **AXI4-Lite slave register file** (16 × 32-bit) with a
full self-verified SystemVerilog testbench.

- Full 5-channel AXI4-Lite handshaking (AW / W / B / AR / R)
- RW, RO, and W1C (write-1-to-clear) register types
- Aggregated interrupt output driven by `|(IRQ_STATUS & IRQ_ENABLE)`
- SLVERR responses on reserved-address writes and reads
- 5 SVA protocol assertions enforced continuously against every transaction

Verified in **Questa 2024.3** with a class-based SystemVerilog master BFM.
**84 checks pass**, **100% functional coverage**, **zero SVA violations**.

---

## Register map

| Offset | Name        | Type | Notes                                          |
| ------ | ----------- | ---- | ---------------------------------------------- |
| 0x00   | SCRATCH0    | RW   | General-purpose scratch                        |
| 0x04   | SCRATCH1    | RW   |                                                |
| 0x08   | SCRATCH2    | RW   |                                                |
| 0x0C   | SCRATCH3    | RW   |                                                |
| 0x10   | CTRL        | RW   |                                                |
| 0x14   | CONFIG      | RW   |                                                |
| 0x18   | MODE        | RW   |                                                |
| 0x1C   | *reserved*  | -    | Access returns SLVERR                          |
| 0x20   | STATUS      | RO   | Mirrors `hw_status_i` port                     |
| 0x24   | VERSION     | RO   | Constant `0x0001_0000`                         |
| 0x28   | COUNTER_LO  | RO   | Free-running 64-bit counter, low word          |
| 0x2C   | COUNTER_HI  | RO   | Free-running 64-bit counter, high word         |
| 0x30   | IRQ_STATUS  | W1C  | HW sets from `irq_set_i`; SW writes 1 to clear |
| 0x34   | IRQ_ENABLE  | RW   | Per-bit interrupt enable mask                  |
| 0x38   | IRQ_RAW     | RO   | Raw view of `irq_set_i`                        |
| 0x3C   | *reserved*  | -    | Access returns SLVERR                          |

Byte-strobed writes are supported on all RW registers and on the SW-clear
path of IRQ_STATUS.

---

## Architecture

Two independent FSMs share a common register bank.

### Write channel FSM (AW / W / B) — 4 states

Decouples AW and W arrival ordering. Either channel can arrive first; the
FSM waits for the counterpart before emitting the B response.

```
                ┌──────────┐
                │  W_IDLE  │  awready=1, wready=1
                └────┬─────┘
        AWVALID+WVALID │  AWVALID   │  WVALID
                ↓     ↓             ↓
          ┌─────────┐ ┌──────────┐ ┌──────────┐
          │ W_RESP  │ │W_WAIT_W  │ │W_WAIT_AW │
          │bvalid=1 │ │wready=1  │ │awready=1 │
          └────┬────┘ └────┬─────┘ └────┬─────┘
        BREADY │      WVALID│      AWVALID│
               ↓            ↓            ↓
             W_IDLE       W_RESP       W_RESP
```

### Read channel FSM (AR / R) — 2 states, registered RDATA

One-cycle read latency. Registering RDATA keeps the read mux out of the
AXI output timing path, which pays off in synthesis.

### Register-bank commit trick

The write commit uses a same-cycle mux (`aw_hs ? s_axi_awaddr : awaddr_q`,
same for wdata/wstrb) to avoid an NBA hazard on the transition into
`W_RESP`. No extra flops needed; the simultaneous, AW-first, and W-first
paths all fall out of a single case statement.

### W1C semantics

```
new_IRQ_STATUS <= (IRQ_STATUS & ~sw_clear_mask) | hw_set_mask
```

Hardware-set wins over software-clear on same-cycle conflicts — no
interrupts lost. `sw_clear_mask` honors byte strobes.

---

## Verification summary

| Category            | Coverage                                              |
| ------------------- | ----------------------------------------------------- |
| Directed tests      | 34 checks (writes, reads, byte strobes, channel ordering, RO, counter, W1C, IRQ aggregation, SLVERR) |
| Randomized stress   | 50 iterations with per-address shadow-model compare   |
| SVA properties      | 5 (AW / W / B / AR / R VALID + payload stability)     |
| Functional coverage | 100% (all 16 write and read addresses + all byte-strobe classes) |

Total: **84 checks pass, 0 errors, 0 SVA violations, 100% coverage.**

---

## Simulation

Requires Questa/ModelSim 2020+ with SystemVerilog assertion support.

```
cd sim
make          # compile + run in batch (default)
make wave     # open GUI, add all waves, run
make clean    # remove work library
```

Expected tail of transcript:

```
=============================================================
  RESULT: PASS   (84 checks, 0 errors)
  Functional coverage: 100.00%
=============================================================
```

---

## File map

```
axi4lite_regfile/
├── rtl/
│   ├── axi4lite_regfile_pkg.sv   # address map + AXI response codes
│   └── axi4lite_regfile.sv       # synthesizable slave RTL
├── tb/
│   ├── axi_lite_if.sv            # AXI-Lite interface bundle
│   ├── axi_lite_master_bfm.sv    # class-based master BFM
│   └── tb_axi4lite_regfile.sv    # top-level testbench
├── sim/
│   └── Makefile                  # Questa targets
└── README.md
```

---

## Design decisions worth calling out

- **Registered RDATA over combinational** — one-cycle read latency, but the
  read mux stays inside a flop-to-flop path. Synthesis-friendly.
- **Same-cycle mux for write commit** — the FSM enters `W_RESP` on the same
  edge that latches AW and W into `_q` flops. A naive read of `_q` on that
  edge would see stale values. The `aw_hs ? direct : _q` mux avoids the
  hazard without adding a one-cycle penalty flop.
- **W1C runs every cycle** — the update expression evaluates
  unconditionally, so hardware `irq_set_i` pulses accumulate even during
  quiet bus periods, and hardware-set beats software-clear on same-cycle
  conflicts.
- **Assertions gated by `` `ifndef SYNTHESIS ``** — SVA participates in
  simulation but disappears cleanly for downstream Design Compiler runs.

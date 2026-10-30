# Practice: current plan

Author: Maharshi Oza

- **Detailed plan (phases, files, steps):** [`ROADMAP.md`](ROADMAP.md)
- **Earlier full backlog (archived, for reference only):** [`archive/practice_backlog_v1.md`](archive/practice_backlog_v1.md)

**Status key:** ✅ done · 🟡 in progress · ⬜ to do

## Status

| Task | Status |
|---|---|
| D1 back-to-back CPU requests (`cache_b2b_test`) | ✅ |
| T1 set-7 eviction stream (`cache_thrash_test`) | ✅ |
| U1 reset-aware CPU driver | 🟡 |
| everything else in ROADMAP.md | ⬜ |

## Minimum path (complete picture)

**A1 → U1 → U3 → F1 → F2 → S3 → F8 → S4 → 3.2 → 3.3 → Phase 4**

All other tasks (U2, U4, F5, C2, F6, D3, A2–A4, Phase 5) are valuable but optional; do them once their prerequisite is done.

## Dependencies: what must be done first

| Task | Must be done first | Can you skip it? | If skipped |
|---|---|---|---|
| A1 SVA fails the test | nothing | yes, not recommended | you must search logs for `ENV:`/`DUT:` by hand |
| U1 reset-aware driver | nothing | yes | mid-test reset hangs; Phase 4 harder |
| U2 self-checking monitor | U1 recommended (reuses its reset-pulse hook) | yes | protocol checks only in SVA, no latency stats |
| U3 programmable memory | nothing | **no** (for Phase 4/6) | NB responder (4.6) and L2 env build on it |
| U4 flush race triggers | **U2** (same file, `cpu_mon`) | yes | flush-race coverage stays luck-based |
| F1, F2 run all + merge coverage | nothing (F2 after F1) | **no** | no "100% coverage" claim |
| S3 corrupt-memory validation | nothing | not recommended | no proof the scoreboard catches bugs |
| F5 LFU test | nothing | yes | LFU untested |
| C2 strobe coverage | F2 | yes | |
| F8 merge to `main` | F1, F2, A1 | **no** | finished blocking project not on `main` |
| S4 shadow model | U1 (shadow must reset too) | **no** | 3.2, 3.3 and Phase 4 cannot work |
| 3.2 victim / writeback checks | S4 | not recommended | writeback bugs only caught at a flush |
| 3.3 address-based matching | S4 | **no** | non-blocking gives false scoreboard errors |
| Phase 4 non-blocking | Phase 3 + U3 (U1 strongly advised) | | |
| Phase 5 prefetch | Phase 4 + S4 | yes (optional) | |
| Phase 6 L2 | Phase 3 + U3 (Phase 4 not required) | | L2 can start on the blocking L1 |

When a task is finished, change its status here and in ROADMAP.md, and commit.

## Quick reference

#### Cache line and address (defaults: 16 B line, 64 sets, 4 ways, 32-bit word)

```
 ONE CACHE LINE = 16 bytes = 4 words x 4 bytes
 word:      word 0      |      word 1      |      word 2      |      word 3
        +----+----+----+----+----+----+----+----+----+----+----+----+----+----+----+----+
 byte:  | B0 | B1 | B2 | B3 | B4 | B5 | B6 | B7 | B8 | B9 |B10 |B11 |B12 |B13 |B14 |B15 |
        +----+----+----+----+----+----+----+----+----+----+----+----+----+----+----+----+
 offset: 0x0                0x4                 0x8                 0xC

 ADDRESS (32 bits):  [31 ........ 10][9 ...... 4][3  2][1  0]
                          tag (22b)    set (6b)   word  byte(=0)
 mk_addr(tag, set, word) = (tag << 10) | (set % 64 << 4) | (word % 4 << 2)
 e.g. mk_addr(1, 1, 2) = 0x418      word = POSITION (0..3), not a count
 wstrb[3:0] picks bytes inside the word (4'b0001 = lowest byte only)
```

#### Who does what

| Piece | Job |
|---|---|
| Sequence | decides WHAT to send (items) |
| Driver | turns items into pin wiggles (valid/ready timing) |
| Monitor | watches pins, builds transactions, `write()`s them out; never drives |
| Responder seq (memory) | waits on `dut_req_fifo`, decides the answer, hands it to `mem_drv` |
| Scoreboard | matches memory trips to CPU accesses, checks err/echo/data |
| Reference model | "perfect memory with no cache", built only from CPU stores |
| Virtual sequence | script that calls `ld()`, `st()`, `do_flush()`, `rand_ops()` |
| Test | picks config (factory override) and starts a virtual sequence |

#### Useful run options (EDA Playground)

```
+UVM_TESTNAME=<test>  +RUN_ID=seed1  +UVM_VERBOSITY=UVM_HIGH
+uvm_set_verbosity=uvm_test_top.env.cpu_agt.drv,_ALL_,UVM_HIGH,time,0
```
Pass = `*** TEST PASSED ***` **and** no `ENV:` / `DUT:` messages in the log.

#### Adding a new test (checklist)
1. New file `uvm_tb_split/tb/tests/<name>.sv`: rename **both** the `class` line and `` `uvm_component_utils(<name>) ``.
2. Config change: subclass `cache_cfg`, then in the test's `build_phase` **before** `super.build_phase()`:
   `set_type_override_by_type(cache_cfg::get_type(), <my_cfg>::get_type());`
3. New vseq: add it to `tb/seq/vseq_lib.sv` (declarations at the top of `body()`).
4. Register: `` `include "tests/<name>.sv" `` in `tb/pkg/cache_tb_pkg.sv` (with `.sv`).
5. Commit & Push to `dev`, wait for the green tick in **Actions**, copy `uvm_tb_single/testbench.sv`.

---


# Practice backlog: UVM testbench user stories

Author: Maharshi Oza

Hands-on exercises built on this testbench. Each story says **what** to build, **where** (files), a **hint**, and how you know it is **done**.
Work on the `dev` branch, one commit per story. After each push, the `make-single (dev)` Action regenerates `uvm_tb_single/testbench.sv` for EDA Playground.

**Status key:** ✅ done · ⬜ to do · ⭐ do before starting the non-blocking cache

---

## 0. Quick reference

### Cache line and address (defaults: 16 B line, 64 sets, 4 ways, 32-bit word)

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

### Who does what

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

### Useful run options (EDA Playground)

```
+UVM_TESTNAME=<test>  +RUN_ID=seed1  +UVM_VERBOSITY=UVM_HIGH
+uvm_set_verbosity=uvm_test_top.env.cpu_agt.drv,_ALL_,UVM_HIGH,time,0
```
Pass = `*** TEST PASSED ***` **and** no `ENV:` / `DUT:` messages in the log.

### Adding a new test (checklist)
1. New file `uvm_tb_split/tb/tests/<name>.sv`: rename **both** the `class` line and `` `uvm_component_utils(<name>) ``.
2. Config change: subclass `cache_cfg`, then in the test's `build_phase` **before** `super.build_phase()`:
   `set_type_override_by_type(cache_cfg::get_type(), <my_cfg>::get_type());`
3. New vseq: add it to `tb/seq/vseq_lib.sv` (declarations at the top of `body()`).
4. Register: `` `include "tests/<name>.sv" `` in `tb/pkg/cache_tb_pkg.sv` (with `.sv`).
5. Commit & Push to `dev`, wait for the green tick in **Actions**, copy `uvm_tb_single/testbench.sv`.

---

## 1. Must-do: finish the blocking project ⭐

| # | Task | Why | Done when |
|---|---|---|---|
| F1 | Run every v2.1 test on Questa | only some have run on v2.1 | every test row in `regression/testplan.csv` has a Status |
| F2 | Merge coverage (see section 7) | single runs show flush 83%, mem 93% | `merge_cov.py` lists no holes (or each hole is explained) |
| F3 | Make SVA failures fail the test (= A1) | `$error` is not counted by UVM | a forced assertion makes the test FAIL |
| F4 | VCS run: select UVM 1.2 | VCS failed only because UVM was not selected | clean VCS run |
| F5 | Test the LFU policy | RTL has `REPL_POLICY`, only LRU is tested | directed LFU test passes with LFU-expected victims |
| F6 | Try another cache shape (e.g. 2 ways, 32 B line) | prove parameters work | smoke + directed pass with new `DUT_*` values |
| F7 | Polish: `cpu_b2b_only` in `convert2string()`, comments, README status | | log shows `b2b=1` in the config line |
| F8 | Merge `dev` → `main` (pull request), update resume line | | `main` has all tests, README status updated |

Suggested order: F1 → F3 → F2 → F5 → S3 → S2 → F6 → F4 → F7 → F8

---

## 2. Driver stories

### D1: Back-to-back CPU requests ✅
**Goal:** a knob that removes the random idle gap between CPU requests.
**Files:** `tb/common/cache_cfg.sv` (`bit cpu_b2b_only`, subclass `cache_cfg_b2b`), `tb/agents/cpu_agent/cpu_drv.sv`, `tests/cache_b2b_test.sv`.
**Done when:** the test passes; with UVM_HIGH the next `accepted` follows the previous `answered` on the next edge; sim time is shorter than `cache_rand_test` with the same seed.
**Note:** the cache is blocking, so requests still wait for each answer; only the idle time between them goes away.

### D2: Long memory stalls ⬜
**Goal:** memory sometimes stalls for a long time.
**Files:** `mem_resp_seq.sv` (or a subclass + factory override).
**Hint:** with 5% probability add 50 to `rsp.latency`.
**Done when:** `cache_bp_test` still passes and a 50+ cycle gap is visible in the waves.

### D3: Protocol-violation driver (negative test) ⬜
**Goal:** prove the `ENV_` assertions catch a bad driver.
**Files:** `cpu_drv.sv`, `cache_cfg.sv`.
**Hint:** knob that changes `req_addr` while `req_valid=1` and `req_ready=0`.
**Done when:** log shows `ENV: CPU request changed or dropped before it was accepted`. Turn the knob off afterwards.

### D4: Request withdrawn before acceptance ⬜
**Goal:** knob that drops `req_valid` before the handshake (illegal).
**Done when:** the hold assertion fires. Explain why this is a protocol violation.

### D5: Memory answers out of order ⬜
**Goal:** behind a knob, answer two memory requests in reverse order.
**Why:** the blocking DUT never has two outstanding, so this never triggers. Write a comment explaining why. Preparation for non-blocking.

### D6: Transaction recording ⬜
**Goal:** `begin_tr()` / `end_tr()` in `cpu_drv` so transactions show in the Questa wave window.
**Done when:** transaction bars are visible next to the signals.

---

## 3. Monitor stories

### M1: Latency statistics ⬜
**Goal:** min / max / average `lat_cycles` printed at the end.
**Files:** `cpu_mon.sv` (`report_phase`).
**Done when:** smoke test prints e.g. `latency min=2 max=14 avg=5.3`.

### M2: Hang detector check ⬜
**Goal:** see the monitor's "no response after N cycles" error.
**Hint:** throwaway cfg subclass with `mem_req_ready_pct = 0`.
**Done when:** monitor error, then UVM timeout FATAL. Write down which `// WAIT:` was stuck.

### M3: Writebacks per flush ⬜
**Goal:** each `flush_item` carries how many writebacks the flush caused.
**Hint:** count memory writes between `flush_busy` rising and `flush_done`.
**Done when:** `cache_flush_test` prints the count; the second flush in a row shows 0.

### M4: Protocol check inside the monitor ⬜
**Goal:** `` `uvm_error `` in `cpu_mon` if `rsp_valid` drops before `rsp_ready`.
**Done when:** you can explain when to use SVA vs. a monitor check.

### M5: Handshake-wait histogram ⬜
**Goal:** count cycles each request waited for `req_ready` (0, 1, 2-5, >5); print in `report_phase`.
**Done when:** `cache_bp_test` shows a much wider spread than the smoke test.

### M6: End-of-test checks ⬜
**Goal:** in `check_phase`: `pending` empty in `cpu_mon`, `pend_q` empty in `mem_mon`.
**Done when:** ending a test early on purpose makes the check fire.

---

## 4. Assertion (SVA) stories

### A1: SVA failures fail the test ⬜ ⭐ (= F3)
**Goal:** assertion failures become UVM errors.
**Files:** `design/sva/cache_ctrl_sva.sv`.
**Hint:** action block `else `uvm_error("SVA", "...")` (import uvm_pkg in the checker), or count `$error`s and fail in `report_phase`.
**Done when:** a forced violation makes the summary say TEST FAILED.

### A2: New DUT rule ⬜
**Goal:** "`mem_req_valid` only in `WB_REQ` / `RF_REQ`".
**Done when:** passes normally; fires when you break the RTL on purpose.

### A3: Liveness ⬜
**Goal:** every accepted CPU request gets a response within N cycles (`##[1:N]` or `s_eventually`).
**Done when:** fires when memory is never ready (M2 setup).

### A4: Cover properties ⬜
**Goal:** `cover property` for "dirty miss with refill error" and "flush while a CPU request waits".
**Done when:** the cover hits show in the log / coverage report.

---

## 5. Scoreboard and reference model stories

What a scoreboard can check: data, error flags, ordering/IDs, completeness, latency, memory traffic, end-of-test state.

### S1: Per-set statistics ⬜
**Goal:** hits / misses per set.
**Hint:** `int unsigned hits[int]` indexed by `t.addr[9:4]`; print in `report_phase`.
**Done when:** the thrash test shows set 7 with 0 hits.

### S2: Writeback address check ⬜ ⭐
**Goal:** a dirty miss must write back a line from the **same set** as the CPU access.
**Files:** `cache_scoreboard.sv`, matching loop in `write_sb_cpu`.
**Done when:** all tests pass; breaking the writeback address in the RTL makes your new error fire.

### S3: Corrupt-memory checker validation ⬜ ⭐
**Goal:** prove the scoreboard catches bad data.
**How:** `mem_resp_corrupt_seq extends mem_resp_seq`, flip `rsp.rdata[0]`; in the test: `set_type_override_by_type(mem_resp_seq::get_type(), mem_resp_corrupt_seq::get_type());`
**Done when:** `LOAD DATA MISMATCH` errors. Bonus: a `uvm_report_catcher` turns them into a pass ("expected errors seen").

### S4: Shadow cache model ⬜
**Goal:** predict hit / clean miss / dirty miss in random tests.
**How:** new class with tag / valid / dirty per set and way + true LRU; compare its prediction with `t.outcome`.
**Done when:** `cache_rand_test` passes with 0 prediction mismatches.

### S5: Response completeness / ID check ⬜
**Goal:** every accepted ID gets exactly one response; no duplicates, none missing at the end.

### S6: Latency bounds ⬜
**Goal:** a hit answers in <= H cycles; a miss in <= memory latency + K.

### S7: Writeback data check ⬜
**Goal:** when a writeback happens, its `wdata` must equal the reference model's bytes for that line (skip unknown bytes).
**Why:** catches wrong eviction data immediately, not only at the next flush.

### S8: Read-after-write on the miss path ⬜
**Goal:** a store miss then a load to the same word returns the stored data (store merged into the refilled line).

### S9: Shadow model upgrade (S4+) ⬜
**Goal:** also predict the victim way and writeback address; compare with real traffic. Needed for the non-blocking cache.

### S10: Smarter coverage from the scoreboard ⬜
**Goal:** sample "outcome x error x op" crosses from the scoreboard (`cov_ap`) instead of raw items.

### S11: End-of-test report table ⬜
**Goal:** one table: totals, mismatches, skipped checks and why.

---

## 6. Sequence, coverage and test stories

### T1: Thrash / eviction-stream test ✅
**Files:** `cache_thrash_vseq` in `vseq_lib.sv`, `tests/cache_thrash_test.sv`.
Fill set 7 (4 cold misses), stream 20 loads to new tags (clean misses), 20 stores to new tags (first 4 clean misses, then dirty misses).
**Next step (optional):** reuse loop with N_WAYS+1 tags `10 + (N_WAYS + i) % (N_WAYS + 1)`, which also proves LRU picks the right victim.

### C1: Read-after-write sequence ⬜
**Goal:** store then immediately load the same address, 100 times on random addresses.

### C2: Strobe coverage hole ⬜ ⭐
**Goal:** find unhit `cp_wstrb` bins in `merged_coverage.csv`; directed vseq that hits every strobe pattern.

### C3: Cover the flush race ⬜
**Goal:** merge `cache_flush_race_test` + others; flush coverage reaches 100%.

---

## 7. How to merge coverage

1. Run each test on EDA Playground with `+UVM_TESTNAME=<test> +RUN_ID=seed1`, tick **Download files after run**.
2. Put each run in its own folder:
   ```
   regression/results/cache_smoke_test_seed1/   cov_cache_smoke_test_seed1.csv  summary_cache_smoke_test_seed1.txt
   regression/results/cache_rand_test_seed1/    ...
   ```
3. `cd regression && python3 merge_cov.py`
4. Read the output: PASS/FAIL per run, merged coverage per coverpoint, **holes** (bins no run hit). It also writes `regression/results/merged_coverage.csv`.
5. Each hole becomes a new directed test or sequence.

No Python available? Send the files to Claude, or let a GitHub Action run it.

---

## 8. Recommended overall order

1. **Finish blocking:** F1 → A1/F3 → F2 → F5 → S3 → S2 → C2
2. **Depth practice:** M1 → S7 → M6 → S5 → A2 → D4 → S6 → M4 → A3 → S1 → C1 → M3 → D2 → D3 → D6
3. **Prepare non-blocking:** S4 → S9 → D5
4. **Non-blocking cache (v3):** spec → `cache_ctrl_nb` RTL → `max_outstanding > 1` → response-handler sequences → `cache_scoreboard_nb` (match by line address) → new tests via factory overrides. Keep every blocking test green throughout.

# Roadmap: blocking cache → robust TB → non-blocking → prefetch → L1 + L2

Author: Maharshi Oza

Detailed plan, phase by phase. For each task: **what exists today**, **the problem**, **what we solve**, **files to touch**, **steps**, **done when**.
Status, dependencies and quick reference: [`README.md`](README.md). Earlier full backlog (archived): [`archive/practice_backlog_v1.md`](archive/practice_backlog_v1.md).

**Status key:** ✅ done · 🟡 in progress · ⬜ to do

| Phase | Goal | Status | Time (part-time) |
|---|---|---|---|
| 1 | Harden the testbench (A1, U1–U4) | 🟡 D1 ✅, T1 ✅, U1 🟡 | 3–4 weeks |
| 2 | Close the blocking project | ⬜ | 1 week |
| 3 | Make the checks complexity-proof | ⬜ | 2–3 weeks |
| 4 | Non-blocking L1 | ⬜ | 4–6 weeks |
| 5 | Prefetcher | ⬜ | 2–3 weeks |
| 6 | L2 + L1/L2 subsystem | ⬜ | 6–8 weeks |

### Rules for every task
1. **New knob, default off.** New behaviour = new `cache_cfg` field whose default keeps today's behaviour.
2. **Extend, don't edit.** Prefer a subclass + factory override over changing shared code.
3. **One owner per decision.** Timing → driver, content → sequence, checking → scoreboard / SVA.
4. **Regression before every commit:** your test + `cache_smoke_test` + `cache_directed_test` + `cache_rand_test`.
5. **Prove a new check can fail.** Break something once on purpose, see the check fire, restore it.
6. **Register new files** in `tb/pkg/cache_tb_pkg.sv` (in compile order, with `.sv`); new RTL files also in `make_single.py` → `DESIGN_ORDER`.

All paths below are under `uvm_tb_split/`.

---

## Already done

| Task | What | Files |
|---|---|---|
| ✅ D1 | Back-to-back CPU requests knob (`cpu_b2b_only`), `cache_cfg_b2b`, `cache_b2b_test` | `tb/common/cache_cfg.sv`, `tb/agents/cpu_agent/cpu_drv.sv`, `tb/tests/cache_b2b_test.sv` |
| ✅ T1 | Set-7 eviction-stream test (`cache_thrash_vseq`, `cache_thrash_test`) | `tb/seq/vseq_lib.sv`, `tb/tests/cache_thrash_test.sv` |

---

## Phase 1: Harden the testbench

### 1.1 A1: SVA failures must fail the test ⬜ (do this first, ~2 h)
- **Today:** `design/sva/cache_ctrl_sva.sv` reports with `$error("ENV: ...")` / `$error("DUT: ...")`. UVM does not count `$error`, so a run can print `*** TEST PASSED ***` while assertions fired.
- **Problem:** "PASSED" cannot be trusted; you must search the log by hand.
- **Solve:** every assertion failure becomes a UVM error.
- **Files:** `design/sva/cache_ctrl_sva.sv` (and `make_single.py` rebuilds `design.sv` only if it is missing: delete `uvm_tb_single/design.sv` or regenerate it).
- **Steps:**
  1. In the checker module add `import uvm_pkg::*;` and `` `include "uvm_macros.svh" ``.
  2. Change each `else $error("ENV: ...")` to `` else `uvm_error("SVA", "ENV: ...") `` (same for `DUT:`).
  3. Alternative if the RTL file must stay UVM-free: keep `$error`, and in `cache_base_test::report_phase` count errors with a `uvm_report_catcher`, or use `$assertcontrol` / a global counter incremented in the action block.
- **Done when:** normal tests still pass; D3 (protocol-violation driver) or a one-line RTL break makes the summary say **TEST FAILED**.

### 1.2–1.5 U1–U4: major upgrades
Step-by-step instructions (files, explicit steps, done-when) are in **[`UPGRADES.md`](UPGRADES.md)**.

| # | Upgrade | Main files | Time |
|---|---|---|---|
| U1 🟡 | Reset-aware CPU driver + mid-test reset test | `cpu_drv.sv`, `cpu_item.sv`, `cpu_seq_lib.sv`, `cache_if.sv`, `tb_top.sv`, `vseq_lib.sv` | ~8 h |
| U2 ⬜ | Self-checking, reset-aware CPU monitor + stats | `cpu_mon.sv`, `cache_cfg.sv`, `cache_scoreboard.sv` | ~8 h |
| U3 ⬜ | Programmable memory model + memory-side reset | `mem_policy.sv` (new), `mem_resp_seq.sv`, `mem_drv.sv`, `mem_mon.sv`, `mem_seqr.sv`, `cache_cfg.sv` | ~10 h |
| U4 ⬜ | Targeted flush races | `flush_item.sv`, `flush_drv.sv`, `flush_seq_lib.sv`, `cpu_mon.sv`, `cache_cfg.sv`, `cache_tb_defs.sv`, `vseq_lib.sv` | ~8 h |

---

## Phase 2: Close the blocking project

| Task | Today / problem | Files | Steps | Done when |
|---|---|---|---|---|
| **F1** Run all tests | only some tests ran on v2.1 | `regression/testplan.csv` | run each test on Questa with `+RUN_ID=seed1`, fill the Status column | every row has PASS/FAIL |
| **F2** Merge coverage | per-run coverage only | `regression/results/*`, `merge_cov.py` | one folder per run, `python3 merge_cov.py` | holes list empty or each hole explained |
| **S3** Corrupt-memory checker validation | nothing proves the scoreboard catches bad data | new `mem_resp_corrupt_seq` (extends `mem_resp_seq`), new test | flip `rsp.rdata[0]`; `set_type_override_by_type(mem_resp_seq::get_type(), mem_resp_corrupt_seq::get_type())` | `LOAD DATA MISMATCH` appears (optional: report catcher turns it into a pass) |
| **F5** LFU test | RTL has `REPL_POLICY`, only LRU tested | `tb/common/cache_tb_defs.sv` (`DUT_REPL_POLICY`), `tb/top/tb_top.sv` (pass `.REPL_POLICY`), new directed vseq + test | compile-time switch; directed sequence where LFU and LRU pick different victims | LFU victims match expectations |
| **C2** Strobe coverage | `cp_wstrb` bins may be unhit | new directed vseq | store every strobe pattern, read back | bins 100% in merged coverage |
| **F4/F7/F8** chores | VCS needs UVM 1.2; small polish; `main` outdated | README, `cache_cfg::convert2string()` | select UVM 1.2; add `b2b`; PR `dev` → `main` | `main` = finished blocking project, README + resume updated |

---

## Phase 3: Make the checks complexity-proof (key step before any DUT change)

- **Today:** `cache_scoreboard::write_sb_cpu` matches memory trips to a CPU access by **time window** (`t_accept < t_req`, `t_rsp < t.t_rsp`). Hit/miss is derived from the trip count. Writebacks are only checked at the next flush.
- **Problem:** non-blocking, prefetch and L2 all put several memory trips in the same time window → false errors. The data check (flat reference model) is fine and stays.
- **Solve:** predict what the cache *should* do (shadow model), match trips by **line address**, check writebacks immediately.

### 3.1 S4: Shadow cache model ⬜ (~8 h)
- **Files:** new `tb/env/cache_shadow.sv` (register before `cache_scoreboard.sv`), `cache_scoreboard.sv`, `cache_cfg.sv` (`bit use_shadow = 0`), `cache_tb_defs.sv` (`get_set(addr)`, `get_tag(addr)` functions).
- **Steps:** per set and way keep `valid`, `dirty`, `tag`, LRU age. `predict(addr, we)` returns `{outcome, victim_way, victim_addr, victim_dirty}` and updates state. Scoreboard compares `outcome` with `t.outcome`. Reset and flush update the shadow (flush: clear dirty; flush+inv: clear valid). Errors: refill error → line not installed.
- **Done when:** `cache_rand_test` with `use_shadow=1` has 0 prediction mismatches.

### 3.2 S9 + S2 + S7: Victim, writeback address and data ⬜ (~8 h)
- **Steps:** when the shadow predicts a dirty victim, the next writeback trip must have `addr == victim_addr` (S2) and `wdata` == reference-model bytes of that line, skipping unknown bytes (S7).
- **Done when:** passes normally; breaking the writeback address in RTL (debug-guide E7) fires immediately, not only at the flush.

### 3.3 Address-based matching ⬜ (~4 h)
- **Steps:** new `cache_scoreboard_v2 extends cache_scoreboard`, override `write_sb_cpu`: claim the refill whose `addr == line_base(t.addr)` and the writeback whose `addr == predicted victim_addr`, instead of the time window. Select it with a factory override; keep the old one as default.
- **Done when:** all tests pass with both scoreboards.

---

## Phase 4: Non-blocking L1 (cache_ctrl_nb)

- **Today:** `cache_ctrl` accepts a CPU request only in IDLE; one miss at a time; responses in order.
- **Goal:** hit-under-miss, miss-under-miss with N MSHRs, out-of-order responses by ID.

| Step | Files | What |
|---|---|---|
| 4.1 Spec | `docs/nb_spec.md` (new) | MSHR count, same-line merge, ordering, memory interface (one or several outstanding), flush with pending misses, error behaviour |
| 4.2 RTL | `design/rtl/cache_ctrl_nb.sv` (+ `cache_mshr.sv`), `make_single.py` `DESIGN_ORDER` | MSHR table, lookup pipeline that keeps accepting, refill return path that answers by ID |
| 4.3 DUT select | `tb/top/tb_top.sv` | `` `ifdef NB_CACHE `` instantiate `cache_ctrl_nb` else `cache_ctrl` |
| 4.4 SVA | `design/sva/cache_ctrl_nb_sva.sv` | drop "ready only in IDLE" style rules; add MSHR / ordering rules |
| 4.5 Driver / monitor | `cache_cfg` `max_outstanding > 1` | nothing else: already ID-based (U1/U2 make them robust) |
| 4.6 Memory side | new `mem_resp_seq_nb` (override) | hold several requests, answer in order or out of order (policy from U3) |
| 4.7 Sequences | `tb/seq/cpu_seq_lib.sv`, `vseq_lib.sv` | new sequences with `use_response_handler(1)` + `response_handler()`; keep `ld()`/`st()` for blocking tests |
| 4.8 Scoreboard | `cache_scoreboard_nb` (override) | address-based matching (Phase 3), MSHR-aware shadow model, predict loads at accept time via `cpu_mon.req_ap` |
| 4.9 Tests | `tests/cache_nb_*_test.sv` | factory overrides for cfg, scoreboard, responder; blocking tests stay green |
| 4.10 Coverage | `tb/env/cache_cov.sv` | outstanding count, hit-under-miss, same-line merge, MSHR full |

- **Done when:** all blocking tests still pass with `cache_ctrl`; all NB tests pass with `+define+NB_CACHE`.

---

## Phase 5: Prefetcher

- **Today:** every refill is caused by a CPU miss.
- **Goal:** next-line (then stride) prefetch on the non-blocking L1.
- **Files:** `design/rtl/cache_prefetch.sv`, `cache_ctrl_nb.sv` (prefetch request into an MSHR), `cache_shadow.sv` (knows prefetch refills), `cache_scoreboard_nb` (unclaimed refills allowed if predicted as prefetch), `cache_cov.sv` (useful / useless prefetch), parameter `PREFETCH_EN`.
- **Watch out:** data checks are unaffected (flat reference model); only traffic counting changes.
- **Done when:** with `PREFETCH_EN=0` all NB tests unchanged; with `=1` 0 mismatches and a streaming test shows fewer demand misses.

---

## Phase 6: L2 and the L1 + L2 subsystem

- **Today:** one cache; the memory agent plays main memory.
- **Goal:** verify an L2 on its own, then L1 + L2 together.

| Step | What |
|---|---|
| 6.1 L2 spec + RTL | `l2_cache` (bigger, more ways, inclusive or not), same valid/ready memory-style interface on both sides |
| 6.2 L2 unit environment | new env: an **L1-side agent** (active, reuses the memory-interface item style, issues line refills/writebacks) + the existing memory agent behind L2 + L2 scoreboard using the same flat reference model |
| 6.3 Subsystem environment | L1 + L2 wired; CPU agent active; **L1↔L2 interface agent passive** (monitor only); memory agent behind L2; reuse the L1 and L2 scoreboards |
| 6.4 Subsystem tests | inclusion checks, back-invalidate (if inclusive), writeback through two levels, flush through both |

- **Why this order:** unit first keeps bugs local; the subsystem reuses everything (vertical reuse).
- **Done when:** L1 unit, L2 unit and subsystem regressions all pass.

---

## Risks and how this plan avoids them

| Risk | Avoided by |
|---|---|
| Non-blocking / prefetch / L2 flood the scoreboard with false errors | Phase 3 before Phase 4 |
| A change silently breaks old tests | knobs default off + regression before every commit |
| A new check never actually works | "prove it can fail" step in each task |
| Too many new things at once | one DUT feature per phase; L2 unit-tested before the subsystem |
| PASSED does not mean passed | A1 first |

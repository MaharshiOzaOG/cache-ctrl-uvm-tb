# CLAUDE.md: rules and context for this repo

Owner: Maharshi Oza. Repo: cache-ctrl-uvm-tb (UVM 1.2 testbench for a blocking, N-way set-associative,
write-back / write-allocate data cache controller). Work happens on the `dev` branch.

## How to work with me
- I write the code. You review and explain. **Do not edit files unless I explicitly ask.**
- Review **only the lines I reference** (e.g. `@cpu_drv.sv#164-190`) plus what they directly depend on
  (declarations, callers, `include` order). Do not review whole files unless I ask.
- Report: compile errors, logic bugs, UVM / SystemVerilog pitfalls, anything that breaks existing tests.
- Answers short and structured (steps / bullets), not paragraphs. Explain "why" when I ask.
- Ask before assuming anything that changes behaviour.
- Git: work only on `dev`, never touch `main`. Commits only under my name
  (Maharshi Mukeshkumar Oza <maharshi.oza.00@gmail.com>), no Claude co-author or trailer lines.

## Project map
- `uvm_tb_split/`: the source (one file per class). Edit only here.
  - `design/rtl/*`: DUT (`cache_ctrl` + submodules), `design/sva/cache_ctrl_sva.sv`: bound SVA (`ENV_*` = testbench broke protocol, `DUT_*` = design broke rules).
  - `tb/common/`: `cache_tb_defs.sv` (DUT shape, `mk_addr`, `line_base`, `init_byte`), `cache_cfg.sv` (all knobs; variants `cache_cfg_quiet/_bp/_err/_b2b` chosen by factory override).
  - `tb/top/`: `cache_if.sv` (clocking blocks: `drv_cb` drives, `mon_cb` samples), `tb_top.sv` (clock, reset, DUT, `run_test`).
  - `tb/agents/`: `cpu_agent` (2-thread driver), `flush_agent`, `mem_agent` (reactive: `mem_mon` → `dut_req_fifo` in `mem_seqr` → `mem_resp_seq` → `mem_drv`).
  - `tb/env/`: `cache_scoreboard.sv` (time-window matching of memory trips to CPU accesses, err/echo/data checks), `cache_ref_model.sv` (flat "memory with no cache" image built from CPU stores), `cache_cov.sv`, `cache_vseqr.sv`, `cache_env.sv`.
  - `tb/seq/`: `cpu_seq_lib.sv` (`do_op`, `cpu_op_seq`, `cpu_rand_seq`), `flush_seq_lib.sv`, `vseq_lib.sv` (`cache_base_vseq` helpers `ld/st/do_flush/rand_ops/wait_cycles/mark/expect_traffic/pulse_reset` + scenario vseqs).
  - `tb/tests/`: `cache_base_test` + one file per test. **Every test must be `include`d in `tb/pkg/cache_tb_pkg.sv`.**
  - `make_single.py`: builds `uvm_tb_single/testbench.sv` for EDA Playground (`make single`).
- `regression/`: `testplan.csv`, `merge_cov.py` (merges per-run `cov_*.csv`), `run_regression.sh`.
- `practice/`: `README.md` (status + dependencies + quick reference), `ROADMAP.md` (phases 1–6), `upgrades/U1..U4.md` (workbook: questions, hidden answers, waveform checks), `UPGRADES.md` (compact steps), `archive/` (old backlog).
- `results/U<n>/`: my logs, waveform screenshots and `.gtkw` layouts per upgrade.
- When I ask about a workbook question, give a hint first unless I ask for the answer.
- `.github/workflows/make_single.yml`: on push to `dev`, regenerates `uvm_tb_single/testbench.sv` (pull afterwards).

## Key design facts
- Address (defaults): `[31:10] tag | [9:4] set | [3:2] word | [1:0] byte(=0)`; line = 16 B = 4 words x 4 B.
- Blocking DUT: `max_outstanding = 1`. Driver/monitor are already ID-based (`inflight[]`, `pending[]`) for non-blocking later.
- Pass rule today: `*** TEST PASSED ***` AND no `ENV:` / `DUT:` messages (SVA uses `$error`; A1 will fix this).
- Rules for changes: new behaviour = new cfg knob with default off, or subclass + factory override
  (`set_type_override_by_type` before `super.build_phase`); regression (smoke, directed, rand + new test) before every commit.

## Status
- Done: D1 (`cache_b2b_test`), T1 (`cache_thrash_test`).
- U1 (reset-aware CPU driver): implementation done (A–G); `cache_reset_test` ran with 1 UVM_ERROR (expected until U2/U3). W1 waveform check in progress (`results/U1/`).
  Design: `aborted` in `cpu_item`; `cur_req` (set after `get`, cleared on accept); `reset_state()` puts back `inflight[]` + `cur_req` with `aborted=1`; `run_phase` = `forever { wait rst_n=1; fork join_none; wait rst_n=0; disable fork; reset_state(); }`; `tb_reset_req` + `pulse_reset()` trigger mid-test reset.
- Reset test plan: random ops → flush → loads only (`store_pct = 0`) → idle `pulse_reset()` → `fork { rand_ops | wait_cycles(rand) + pulse_reset }` → `store_pct = 50` → rand ops.
  Expected until U2/U3: `cpu_mon`, memory agent or scoreboard may still report errors around the reset.
- Next: U2 (self-checking reset-aware CPU monitor), U3 (programmable memory + memory-side reset), U4 (targeted flush races). See `practice/UPGRADES.md`.
- Later: Phase 2 close blocking (run all tests, merge coverage, S3, LFU), Phase 3 shadow model + address-based matching, Phase 4 non-blocking L1, Phase 5 prefetch, Phase 6 L2.

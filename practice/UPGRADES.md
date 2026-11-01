# Upgrades U1–U4: step-by-step instructions

> **New workbook:** [`upgrades/`](upgrades/README.md) has one page per upgrade with understanding questions, hidden hints/answers/why, checklists and waveform checks (W1–W4). Use it as the main working page; this file stays as the compact reference.

Author: Maharshi Oza

Plain, explicit steps for the four major upgrades. No code: each step says **which file**, **what to add or change**, and **why**.
Tick a box when the step is done. All paths are under `uvm_tb_split/`.

**Order:** U1 → U2 → U3 → U4. U4 touches `cpu_mon`, so do it after U2.

**Before every commit** run: your new test + `cache_smoke_test` + `cache_directed_test` + `cache_rand_test`. All must still pass.

---

## U1: Reset-aware CPU driver

### Purpose
- Today the CPU driver waits for reset **once**, at time 0. If `rst_n` goes low later, the cache forgets every request it had, but the driver keeps waiting for answers that will never come, and the sequence waits forever in `get_response()`. The test hangs.
- After U1: on reset the driver gives up on everything unfinished, tells the sequence "this request was cancelled", cleans its own state, and starts again with fresh handshakes when reset ends.
- Not needed: a per-request timeout in the driver. `cpu_mon` already reports "no response after `rsp_timeout` cycles".

### What exists today
| File | Current behaviour |
|---|---|
| `tb/agents/cpu_agent/cpu_drv.sv` | `run_phase`: wait for reset once → start request and response threads with `fork … join` → they run forever. `inflight[]`, `outstanding`, `next_id` are never cleared. |
| `tb/agents/cpu_agent/cpu_item.sv` | no field to say "cancelled" |
| `tb/seq/cpu_seq_lib.sv` | `do_op()` waits in `get_response()` for every item |
| `tb/top/tb_top.sv` | drives `rst_n` once in an `initial` block; nothing can pulse it later |

### Steps

**A. Item: `tb/agents/cpu_agent/cpu_item.sv`**
- [ ] Add a plain (not `rand`) 1-bit field `aborted`, default 0.
- [ ] Add it to the field macros (no compare) and print it in `convert2string()`.

**B. Driver state: `tb/agents/cpu_agent/cpu_drv.sv`**
- [ ] Add a member handle `cur_req` (type `cpu_item`), default null. It holds the item the request thread has taken from the sequence but the cache has **not yet accepted**.
- [ ] In the request thread: right after `get(req)`, set `cur_req` to that item.
- [ ] In the request thread: on the accept edge, right where the item is stored into `inflight[]`, set `cur_req` back to null. (From here on the item lives in `inflight[]`, so it must not be returned twice.)
- [ ] In the response thread: keep "delete from `inflight`" and "`put()` to the sequence" **directly after each other**, with no wait between them.

**C. Driver reset clean-up: new task `reset_state()` in `cpu_drv.sv`**
It must be a **task** (it calls `put()`, which is a task). In this order:
- [ ] Drive `req_valid` to 0 and `rsp_ready` to 0 through the clocking block.
- [ ] Loop over every entry of `inflight[]`: set its `aborted` to 1, then `put()` that same handle back to the sequence. Do **not** delete inside the loop.
- [ ] After the loop: delete all entries of `inflight[]` at once (delete with no index).
- [ ] If `cur_req` is not null: set its `aborted` to 1, `put()` it, then set `cur_req` to null.
- [ ] Set `outstanding` to 0 and `next_id` to 0.
- [ ] Print one `uvm_info` saying how many requests were aborted.

**D. Driver main loop: `run_phase` in `cpu_drv.sv`**
Replace "wait for reset once, then fork…join" with a `forever` loop that does, in order:
- [ ] Wait until `rst_n` is 1 (out of reset).
- [ ] Start the request thread and the response thread with `fork … join_none` (so `run_phase` keeps going).
- [ ] Wait until `rst_n` is 0 (a reset arrived).
- [ ] `disable fork` (stops both threads wherever they were waiting).
- [ ] Call `reset_state()`.
- [ ] Loop back to the top.

**E. Sequence: `tb/seq/cpu_seq_lib.sv`**
- [ ] In `do_op()` of `cpu_base_seq`, after `get_response()`: if the returned item has `aborted` = 1, print a `uvm_info` ("aborted by reset" + the item). Nothing else.
- [ ] Optional, in `cpu_rand_seq`: count only non-aborted operations toward `n_ops` (loop until enough completed).

**F. A way to pulse reset in the middle of a test**
- [ ] `tb/top/cache_if.sv`, in `cache_cpu_if`: add one testbench-only signal, `tb_reset_req`, default 0. It is not connected to the DUT.
- [ ] `tb/top/tb_top.sv`: add an `always` block that, on every rising edge of `cpu_if.tb_reset_req`, drives `rst_n` to 0, waits 5 rising clock edges, then on a falling clock edge drives `rst_n` back to 1 (same style as the initial reset).
- [ ] `tb/seq/vseq_lib.sv`, in `cache_base_vseq`: add a helper task `pulse_reset()` that sets `p_sequencer.cfg.cpu_vif.tb_reset_req` to 1, waits one clock, sets it back to 0, then waits until `rst_n` is 1 again.

**G. Test: `cache_reset_test`**
- [ ] New vseq `cache_reset_vseq` in `vseq_lib.sv`. In `body()`:
  1. Run random operations (with stores).
  2. `do_flush` without invalidate, so memory holds all stored data. (A reset loses dirty lines; flushing first keeps the reference model correct.)
  3. Set `p_sequencer.cfg.store_pct` to 0, then in parallel (`fork … join`): run random operations (loads only), and after a random 20–200 cycles call `pulse_reset()`.
  4. Set `store_pct` back to 50 and run random operations again.
- [ ] New file `tb/tests/cache_reset_test.sv`: extends `cache_base_test`, `run_scenario()` creates and starts the vseq on `env.vseqr`. Rename both the class line and the `uvm_component_utils` line.
- [ ] Register the test in `tb/pkg/cache_tb_pkg.sv`.

### Done when
- [ ] All old tests pass unchanged.
- [ ] `cache_reset_test`: log shows "aborted" messages, traffic continues after the reset, the test **ends** (no hang, no UVM timeout FATAL).
- [ ] Expected for now: `cpu_mon`, the memory agent or the scoreboard may still report errors around the reset moment. They are not reset-aware yet; U2 and U3 fix them. Note which ones appear.

---

## U2: Self-checking, reset-aware CPU monitor

### Purpose
- Protocol rules are checked today only by SVA. If the SVA is not bound (another DUT, gate-level), a broken handshake goes unnoticed.
- A reset leaves stale entries in `pending[]`, so the next responses look like errors.
- There is no latency summary.
- After U2: the monitor checks the handshake rules itself, survives reset, and prints statistics. The scoreboard also forgets unmatched memory traffic on reset.

### What exists today (`tb/agents/cpu_agent/cpu_mon.sv`)
- Already there: response with unknown id → error; id reused while in flight → error; no response after `rsp_timeout` cycles → error; `check_phase` checks `pending` is empty.
- Missing: "held request / response must stay stable" checks, reset handling, statistics.

### Steps

**A. Config: `tb/common/cache_cfg.sv`**
- [ ] Add a 1-bit knob `mon_checks_en`, default 1 (lets a test switch the new checks off).

**B. Stability check, request channel (`cpu_mon.sv`)**
- [ ] Add member variables that remember **last cycle's** request pins: `req_valid`, `req_ready`, `req_id`, `req_we`, `req_addr`, `req_wdata`, `req_wstrb`.
- [ ] Each cycle (only if `mon_checks_en`): if last cycle had `req_valid` = 1 and `req_ready` = 0, then this cycle `req_valid` must still be 1 and all request fields must be equal to last cycle's. If not → `uvm_error` with id `CPU_MON_PROTO` and both values.
- [ ] At the end of each cycle, copy this cycle's pins into the "last cycle" variables.

**C. Stability check, response channel (`cpu_mon.sv`)**
- [ ] Same idea for `rsp_valid`, `rsp_ready`, `rsp_id`, `rsp_we`, `rsp_rdata`, `rsp_err`: a response that was valid but not accepted must stay valid and unchanged.

**D. Reset handling (`cpu_mon.sv`)**
- [ ] Change the start of `run_phase`: instead of waiting for reset once, check `rst_n` every cycle.
- [ ] On a cycle where `rst_n` is 0: count the entries in `pending[]` (add to a counter `n_aborted`), delete all of `pending[]` and `reported_hang[]`, clear the "last cycle" variables, skip all other checks, go to the next cycle.

**E. Statistics (`cpu_mon.sv`)**
- [ ] Add counters: number of completed accesses, sum / min / max of `lat_cycles`, number of protocol errors, `n_aborted`.
- [ ] Update them at each response handshake.
- [ ] Add `report_phase`: print one `uvm_info` line with count, min, max, average latency, protocol errors and aborted requests.

**F. Scoreboard reset handling: `tb/env/cache_scoreboard.sv`**
- [ ] Add a small `run_phase` that waits for each falling edge of `rst_n` (vif from `cfg.cpu_vif`) and then empties `mem_hist`. (Memory trips that were in progress when the cache was reset belong to no access.)

**G. Prove the new checks can fail**
- [ ] Temporarily make the CPU driver change `req_addr` while a request is waiting (or do story D3). Expected: the SVA **and** `CPU_MON_PROTO` both report it. Then undo.

### Done when
- [ ] All old tests pass; each prints the latency statistics line.
- [ ] The step G experiment is caught by the monitor.
- [ ] `cache_reset_test` (from U1): no `cpu_mon` errors around the reset any more.

---

## U3: Programmable memory model

### Purpose
- Today memory latency is uniform random over one range for every address, and errors are a random percentage. `force_rd_err` / `force_wr_err` can only fail "the next N" requests.
- You cannot say "fail exactly the 3rd refill", "fail any writeback to this address", or "addresses below 0x1000 are fast".
- After U3: a small policy in `cache_cfg` makes memory behaviour deterministic and realistic, and the memory side survives reset. Default settings = exactly today's behaviour.

### What exists today
| File | Current behaviour |
|---|---|
| `tb/agents/mem_agent/mem_resp_seq.sv` | `body()`: get request from `dut_req_fifo` → latency random `mem_lat_min..max` → error from `force_*_err` or random % → read/write `cfg.mem` → send to driver |
| `tb/agents/mem_agent/mem_drv.sv` | waits for reset once; holds the answer until `rsp_ready` |
| `tb/agents/mem_agent/mem_mon.sv` | waits for reset once; `pend_q` of accepted requests |

### Steps

**A. Policy data: new file `tb/agents/mem_agent/mem_policy.sv`**
(register it in `cache_tb_pkg.sv` **before** `mem_resp_seq.sv`)
- [ ] A small class `mem_region` with: `addr_lo`, `addr_hi`, `lat_min`, `lat_max`.
- [ ] A small class `mem_err_rule` with: `kind` (read or write), `nth` (fail the n-th request of that kind, 0 = unused), `addr` + `use_addr` (fail requests to this line address).

**B. Config: `tb/common/cache_cfg.sv`**
- [ ] Add a queue of `mem_region` handles, empty by default.
- [ ] Add a queue of `mem_err_rule` handles, empty by default.
- [ ] Add `mem_bw_max` (answers allowed per window, 0 = no limit) and `mem_bw_window` (window length in cycles).
- [ ] Print the number of regions and rules in `convert2string()`.

**C. Responder: `tb/agents/mem_agent/mem_resp_seq.sv`**
Split `body()` into small functions so each decision lives in one place:
- [ ] Counters `n_rd_seen`, `n_wr_seen` (increment for every request).
- [ ] Function `pick_latency(addr)`: if a region contains `addr`, random in that region's range; otherwise random in `mem_lat_min..max` (today's behaviour).
- [ ] Function `pick_error(req)`: 1 if any rule matches (same kind and `nth` equals this request's count, or `use_addr` and the line address matches); otherwise today's logic (`force_*_err`, then random %).
- [ ] Function `build_rdata(req, err)`: today's data logic (error → junk, write → store into `cfg.mem`, read → read from `cfg.mem`).
- [ ] Bandwidth: keep a queue of the times of recent answers; if `mem_bw_max` > 0 and the last window already has `mem_bw_max` answers, add enough extra latency to fall outside the window.
- [ ] `body()` now only calls these functions in order, then `start_item` / `finish_item` as today.

**D. Memory side reset**
- [ ] `mem_drv.sv`: same pattern as U1: a `forever` loop of wait out of reset → `fork` ready thread and response thread `join_none` → wait for reset → `disable fork` → drive `req_ready`, `rsp_valid`, `rsp_err` to 0 → if the response thread was holding an item from `get_next_item`, call `item_done()` for it (keep it in a member handle, like `cur_req` in U1).
- [ ] `mem_mon.sv`: on reset, empty `pend_q` and skip checks (same as U2 step D).
- [ ] `mem_seqr.sv` / responder: on reset, empty `dut_req_fifo` (its `flush()` method) so old requests are not answered after reset. Simplest place: a small `run_phase` in `mem_seqr` that waits for each falling edge of `rst_n` and flushes the FIFO.

**E. Directed test: `cache_mem_script_test`**
- [ ] New vseq: a few cold loads, then a load whose refill is the 3rd refill overall.
- [ ] New test: in `build_phase`, after `super.build_phase()`, add one `mem_err_rule` (read, `nth` = 3) to `cfg`; start the vseq.
- [ ] Register the test in `cache_tb_pkg.sv`.

### Done when
- [ ] All old tests pass unchanged (empty policy = today's behaviour).
- [ ] `cache_mem_script_test`: exactly the 3rd refill fails, every run, and that CPU access returns `err` = 1 (the scoreboard already checks this).
- [ ] A test with one slow region shows long latencies only for those addresses.
- [ ] `cache_reset_test` (from U1) now passes with **no** errors.

---

## U4: Targeted flush races

### Purpose
- The hardest flush case is "a flush arrives while a CPU request is waiting". `cache_flush_race_vseq` fires flushes at random times and hopes to hit it; single runs reached only 83% flush coverage.
- After U4: the flush driver can wait for that exact moment and start the flush then, every time.

### What exists today
| File | Current behaviour |
|---|---|
| `tb/agents/flush_agent/flush_item.sv` | `inv` (rand), results `err`, `cycles`, `race` |
| `tb/agents/flush_agent/flush_drv.sv` | raises `flush_req` as soon as it gets an item |
| `tb/seq/flush_seq_lib.sv` | `flush_seq`: sets `inv`, sends one item |
| `tb/agents/flush_agent/flush_mon.sv` | sets `race` = 1 when a CPU request was waiting as the flush started (coverage) |

### Steps

**A. Trigger type**
- [ ] `tb/common/cache_tb_defs.sv`: add an enum `flush_trig_e` with values `TRIG_NOW`, `TRIG_DELAY`, `TRIG_ON_CPU_WAIT`.

**B. Item: `flush_item.sv`**
- [ ] Add fields `trigger` (type `flush_trig_e`, default `TRIG_NOW`) and `delay` (cycles, default 0). Not `rand`. Add them to `convert2string()`.

**C. Shared event: `tb/common/cache_cfg.sv`**
- [ ] Add a `uvm_event` handle `cpu_wait_ev`, created in the cfg constructor. Both the CPU monitor and the flush driver already have `cfg`, so both can reach it.

**D. Raise the event: `cpu_mon.sv`**
- [ ] On every cycle where `req_valid` = 1 and `req_ready` = 0 (a CPU request is waiting), call `trigger()` on `cfg.cpu_wait_ev`.

**E. Wait for it: `flush_drv.sv`**
Before raising `flush_req`, look at the item's `trigger`:
- [ ] `TRIG_NOW`: as today.
- [ ] `TRIG_DELAY`: wait `delay` clock edges, then raise.
- [ ] `TRIG_ON_CPU_WAIT`: wait for `cfg.cpu_wait_ev` (`wait_trigger()`), then raise `flush_req` on the next clock edge.
- [ ] Add a safety limit: if the event has not come after `cfg.rsp_timeout` cycles, print a warning and raise the flush anyway (so the test never hangs if no CPU request ever waits).

**F. Sequence: `tb/seq/flush_seq_lib.sv` and `vseq_lib.sv`**
- [ ] `flush_seq`: add `trigger` and `delay` fields set before `start()`, copied into the item (defaults keep today's behaviour).
- [ ] `cache_base_vseq`: add a helper `do_flush_on(inv, trigger, delay, err)` like `do_flush()` but passing the trigger.
- [ ] New `cache_flush_target_vseq`: in parallel, run random operations, and repeat 10 times: `do_flush_on(random inv, TRIG_ON_CPU_WAIT, 0, err)`.

**G. Test**
- [ ] New `cache_flush_target_test` (extends `cache_base_test`, starts the new vseq). Register it in `cache_tb_pkg.sv`.

### Done when
- [ ] All old tests pass unchanged (default trigger is `TRIG_NOW`).
- [ ] `cache_flush_target_test`: every `FLUSH_DRV finished` / flush monitor item shows `race=1`.
- [ ] Flush coverage reaches 100% in this single run (check the `[COV]` line).

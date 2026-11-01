# Upgrades U1–U4: workbook

Author: Maharshi Oza

One page per upgrade. Each page has:
1. **Goal & why**
2. **Understand first**: questions to answer before coding
3. **Implementation checklist**
4. **Waveform checks** (W1–W4)
5. **Results**: where your logs and waves go (`results/U<n>/`)

Answers are **hidden**. Click a line to open it:
- 💡 **Hint**: a nudge only
- ✅ **Answer**: the answer / implementation sketch
- ❓ **Why**: the reasoning and alternatives

Try first, then open. Tick a box by changing `[ ]` to `[x]` and committing (in vscode.dev or locally).

## Status

| Upgrade | Page | Implementation | Waveform check | Result folder |
|---|---|---|---|---|
| U1 Reset-aware CPU driver | [U1.md](U1.md) | ✅ done | 🟡 W1 in progress | [`results/U1/`](../../results/U1/) |
| U2 Self-checking, reset-aware CPU monitor | [U2.md](U2.md) | ⬜ | ⬜ W2 | [`results/U2/`](../../results/U2/) |
| U3 Programmable memory model | [U3.md](U3.md) | ⬜ | ⬜ W3 | [`results/U3/`](../../results/U3/) |
| U4 Targeted flush races | [U4.md](U4.md) | ⬜ | ⬜ W4 | [`results/U4/`](../../results/U4/) |

## How to do a waveform check
1. Run the test on EDA Playground. Add `+DUMP_ALL` for DUT internals, `+DUMP_FROM=<ns> +DUMP_TO=<ns>` to keep the file small. Tick **Download files after run**.
2. In the log, find the time of interest (every UVM message starts with `@ <time>`).
3. Open `dump.vcd` in GTKWave, load your layout (**File → Read Save File**), jump to that time.
4. Answer the check, save a screenshot (**File → Print To File** or Win+Shift+S) into `results/U<n>/`.

## Signal ownership (read before any wave check)

| Signal | Driven by | Meaning |
|---|---|---|
| `req_valid` (+ id, we, addr, wdata, wstrb) | CPU driver (TB) | "I have a request" |
| `req_ready` | DUT | "I can take a request" (`state == IDLE && !flush_req`) |
| `rsp_valid` (+ id, we, rdata, err) | DUT | "I have an answer" (`state == RESP`) |
| `rsp_ready` | CPU driver (TB) | "I can take an answer" |
| `mem_req_valid` (+ we, addr, wdata) | DUT | cache asks memory |
| `mem_req_ready` | memory driver (TB) | memory can take it |
| `mem_rsp_valid` (+ rdata, err) | memory driver (TB) | memory answers |
| `mem_rsp_ready` | DUT | cache can take the answer |
| `flush_req`, `flush_inv` | flush driver (TB) | start a flush |
| `flush_busy`, `flush_done`, `flush_err` | DUT | flush status |

A handshake happens on a rising edge where **valid and ready are both 1**.

## Waveform debugging drills (no code changes)

- [ ] **WD1: Hit vs miss latency.** Pick one hit and one miss from a UVM_HIGH log. Count cycles from the request handshake to the response handshake.
<details><summary>💡 Hint</summary>

Use `cache_smoke_test` with `+UVM_VERBOSITY=UVM_HIGH`. `CPU_DRV accepted` and `CPU_DRV answered` lines give you the two times; the scoreboard line says HIT / CLEAN_MISS.
</details>
<details><summary>✅ Answer</summary>

A hit takes a few cycles (IDLE → LOOKUP → RESP, plus any `rsp_ready` backpressure). A miss adds the memory round trip: RF_REQ handshake + memory latency + RF_WAIT/refill write, so typically 5–15+ cycles depending on `mem_lat` and `mem_req_ready`.
</details>

- [ ] **WD2: Trace a dirty miss end to end.** CPU request → LOOKUP → writeback (`mem_req we=1`, old line address) → refill (`we=0`, new line address) → CPU response.
<details><summary>💡 Hint</summary>

Find `DIRTY_MISS` in the scoreboard UVM_HIGH lines (`cache_directed_test`, step T5). Use `+DUMP_ALL` to see `state_q`.
</details>
<details><summary>✅ Answer</summary>

Order on the memory interface: first `mem_req_valid` with `we=1` and the **evicted** line's address (writeback), its response, then `mem_req_valid` with `we=0` and the **requested** line's address (refill), its response, then the CPU `rsp_valid`. `state_q` walks IDLE → LOOKUP → WB_REQ → WB_WAIT → RF_REQ → RF_WAIT → … → RESP.
</details>

- [ ] **WD3: Backpressure hold.** In `cache_bp_test`, find a CPU response held for several cycles (`rsp_valid=1`, `rsp_ready=0`). Check `rsp_id`, `rsp_rdata`, `rsp_err` stay stable until `rsp_ready=1`.
<details><summary>❓ Why</summary>

Valid/ready rule: once valid is raised, the sender must hold valid and all fields steady until the handshake. If the DUT changed data while waiting, the CPU would read the wrong value. The SVA checks this too; here you see it with your own eyes.
</details>

- [ ] **WD4: Find an injected bug from waves only.** Apply debug-guide edit E6 or E7 in the RTL (keep a clean copy). Run, take the **first** error time, find the root cause in the waves before reading the RTL.
<details><summary>💡 Hint</summary>

E6: watch whether a store hit ever sets the dirty bit (`+DUMP_ALL`). E7: compare the writeback `mem_req_addr` with the line that was actually evicted.
</details>

- [ ] **WD5: Build three layouts:** `cpu_view.gtkw`, `mem_view.gtkw`, `reset_view.gtkw`. Save them in `results/` (or a `waves/` folder) and reuse them every run.

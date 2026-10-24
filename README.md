# Cache Controller UVM Testbench (v2.1)

UVM 1.2 verification environment for a parameterized **N-way set-associative, write-back / write-allocate, blocking data cache controller**.

Author: Maharshi Oza

## Design under test

| Parameter | Default | Meaning |
|---|---|---|
| `ADDR_W` | 32 | byte address width |
| `DATA_W` | 32 | CPU word width |
| `LINE_BYTES` | 16 | cache line size |
| `NUM_SETS` | 64 | number of sets |
| `N_WAYS` | 4 | associativity |
| `REPL_POLICY` | LRU | LRU or LFU replacement |
| `ID_W` | 4 | CPU request ID width |

Interfaces: CPU request/response (valid/ready, byte strobes, IDs, error), flush (`flush_req`, `flush_inv`, `flush_busy`, `flush_done`, `flush_err`), and a memory request/response port (valid/ready, error).
A bound SVA checker splits assertions into `ENV_*` (testbench broke the protocol) and `DUT_*` (design broke its rules).

## Testbench architecture

```
                         +--------------------- cache_env ----------------------+
  cpu_seq  -> cpu_agent  (2-thread driver, monitor) ---+                        |
  flush_seq-> flush_agent(driver, monitor) ------------+--> scoreboard          |
                                                       |     (ref model +       |
  mem_agent (REACTIVE): monitor -> TLM analysis FIFO --+      comparator)       |
            -> mem_resp_seq -> driver (plays memory)   +--> coverage            |
                         +-- virtual sequencer coordinates CPU + flush ---------+
```

- **CPU agent**: two-thread driver (request / response) so requests and responses overlap; IDs set by the driver.
- **Flush agent**: drives only the flush pins, so a flush can race a waiting CPU request.
- **Memory agent (reactive)**: the monitor sees each DUT memory request, pushes it into a `uvm_tlm_analysis_fifo`, and a responder sequence answers with latency, backpressure and optional errors.
- **Scoreboard**: reference model (predictor) kept separate from the comparator; checks load data, response errors, refill/writeback addresses, and memory contents after every flush.
- **Coverage**: covergroups for CPU, memory and flush traffic, plus per-run CSV export for tool-free merging.
- **Config**: `cache_cfg` and variants `cache_cfg_quiet`, `cache_cfg_bp`, `cache_cfg_err`, selected per test by **factory override**.

## Tests

Each test is its own simulation and starts from reset.

| Test | What it does | Config |
|---|---|---|
| `cache_smoke_test` | 30 random accesses, no backpressure (default) | `cache_cfg_quiet` |
| `cache_directed_test` | T1–T9: hits, store merge, write-allocate, LRU order, dirty eviction, errors, flush | default |
| `cache_rand_test` | 2000 random accesses, flush + memory compare every 500 | default |
| `cache_bp_test` | heavy backpressure on both sides, slow memory | `cache_cfg_bp` |
| `cache_flush_test` | flush, flush again, flush + invalidate | default |
| `cache_flush_race_test` | flushes at random moments during CPU traffic | default |
| `cache_err_test` | 5% refill and writeback errors | `cache_cfg_err` |

Full test plan: [`regression/testplan.csv`](regression/testplan.csv) (opens in Excel) and [`uvm_tb_split/docs/uvm_testplan.md`](uvm_tb_split/docs/uvm_testplan.md).

## Repository layout

```
uvm_tb_split/      source: one file per class
  design/rtl/      cache controller RTL
  design/sva/      bound SVA checker
  tb/              interfaces, top, agents, env, sequences, tests
  docs/            testbench spec and test plan
  filelist.f       compile order (VCS)
  make_single.py   builds the two-file EDA Playground version
uvm_tb_single/     design.sv + testbench.sv for EDA Playground
regression/        test plan CSV, coverage merge script, regression script
Makefile           helper commands
```

## Running

**EDA Playground** (no local simulator needed)
1. Paste `uvm_tb_single/design.sv` and `uvm_tb_single/testbench.sv`, choose UVM 1.2 and Questa or VCS.
2. Run options: `+UVM_TESTNAME=<test> +RUN_ID=seed1`
3. Tick *Download files after run*, unzip into `regression/results/<test>_seed1/`.

**Local VCS / Questa**
```
cd uvm_tb_split
vcs -f filelist.f && ./simv +UVM_TESTNAME=cache_smoke_test
```
or the whole regression: `make regress-vcs SEEDS="1 2 3"` / `make regress-questa`.

**Pass rule:** the log ends with `*** TEST PASSED ***` **and** has no `ENV:` / `DUT:` assertion messages (the SVA uses `$error`, which UVM does not count).

Each run writes `summary_<test>_<id>.txt` (result, error count, config, scoreboard totals) and `cov_<test>_<id>.csv` (coverage bins).

## Coverage merge (Python only)

```
make merge          # = cd regression && python3 merge_cov.py
```
Prints PASS/FAIL per run, merged coverage per covergroup/coverpoint, the bins no run hit, and writes `regression/results/merged_coverage.csv`. Details: [`regression/README.md`](regression/README.md).

## Make targets

| Command | What it does |
|---|---|
| `make single` | regenerate `uvm_tb_single/testbench.sv` after editing `uvm_tb_split/` |
| `make merge` | merge coverage of all runs in `regression/results/` |
| `make regress-vcs` / `make regress-questa` | run every test (needs a local simulator) |
| `make clean` | delete regression results |

## Status

- `cache_err_test` passes on Questa 2025.2: 0 UVM errors, 0 data mismatches, 1000 accesses with injected memory errors, memory checks after 5 flushes all clean.
- A full combined run (all scenarios) passed on Questa in the previous version (v2): 4271 accesses, 0 mismatches.
- Remaining v2.1 tests and VCS runs: in progress.

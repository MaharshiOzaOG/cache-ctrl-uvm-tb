//==============================================================================
//  File    : cache_reset_test.sv
//  Author  : Maharshi Oza  (mmoza@ncsu.edu)
//  Project : cache_ctrl UVM testbench v2.1
//------------------------------------------------------------------------------
//  WHAT    : Reset in the middle of traffic (cache_reset_vseq): random accesses,
//            flush, loads only, then a reset pulse at a random moment during loads.
//            The driver must abort what is unfinished and the test must end.
//  CONFIG  : cache_cfg   (default timing, no factory override)
//  START   : always from reset (own simulation): cache empty, memory = initial
//            pattern, scoreboard empty.
//  RUN     : +UVM_TESTNAME=cache_reset_test   (+RUN_ID=<tag> to name its result files)
//==============================================================================
class cache_reset_test extends cache_base_test;

  `uvm_component_utils(cache_reset_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  // Factory override: register it BEFORE super.build_phase(), because the base
  // test creates cfg there with cache_cfg::type_id::create().
  function void build_phase(uvm_phase phase);
    // uvm_factory::get().set_type_override_by_type(cache_cfg::get_type(), cache_cfg_b2b::get_type());
    super.build_phase(phase);
  endfunction

  task run_scenario();
    cache_reset_vseq v = cache_reset_vseq::type_id::create("v");
    v.start(env.vseqr);
  endtask

endclass

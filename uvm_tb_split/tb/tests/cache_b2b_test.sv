//==============================================================================
//  File    : cache_b2b_test.sv
//  Author  : Maharshi Oza  (mmoza@ncsu.edu)
//  Project : cache_ctrl UVM testbench v2.1
//------------------------------------------------------------------------------
//  WHAT    : 2000 random loads/stores on a conflict-heavy address pool, with a flush
//            (and full memory compare) every 500 accesses.
//  CONFIG  : cache_cfg_b2b      (overridden: that means that we are runnign BACK TO BACK OPERATIONS)
//  START   : always from reset (own simulation): cache empty, memory = initial
//            pattern, scoreboard empty.
//  RUN     : +UVM_TESTNAME=cache_b2b_test   (+RUN_ID=<tag> to name its result files)
//==============================================================================
class cache_b2b_test extends cache_base_test;

  `uvm_component_utils(cache_b2b_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    uvm_factory::get().set_type_override_by_type(cache_cfg::get_type(), cache_cfg_b2b::get_type());
    // set_type_override_by_type(cache_cfg::get_type(), cache_cfg_b2b::get_type());      // In the base test we are creating the object.
    super.build_phase(phase);
  endfunction

  task run_scenario();
    cache_rand_vseq v = cache_rand_vseq::type_id::create("v");
    v.n_ops = 2000; v.flush_every = 500;
    v.start(env.vseqr);
  endtask

endclass

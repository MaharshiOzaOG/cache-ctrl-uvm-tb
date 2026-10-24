# Cache Controller UVM testbench - helper commands
# Author: Maharshi Oza
SEEDS ?= 1

.PHONY: help single merge regress-vcs regress-questa clean

help:
	@echo "make single          - regenerate uvm_tb_single/testbench.sv from uvm_tb_split/"
	@echo "make merge           - merge per-run coverage CSVs in regression/results/"
	@echo "make regress-vcs     - run all tests with VCS     (SEEDS=\"1 2 3\")"
	@echo "make regress-questa  - run all tests with Questa  (SEEDS=\"1 2 3\")"
	@echo "make clean           - remove regression results"

single:
	python3 uvm_tb_split/make_single.py

merge:
	cd regression && python3 merge_cov.py

regress-vcs:
	bash regression/run_regression.sh vcs $(SEEDS)

regress-questa:
	bash regression/run_regression.sh questa $(SEEDS)

clean:
	find regression/results -mindepth 1 -maxdepth 1 -type d -exec rm -rf {} +
	rm -f regression/results/merged_coverage.csv

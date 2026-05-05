<!-- SPDX-License-Identifier: CC-BY-SA-4.0 -->

# MAST verification harness

Verilator + cocotb testbenches for MAST RTL. Mandatory for every RTL change
(see contributor feedback in MAST commit history).

## Setup (one-time)

A local Python venv is required because system pip is locked down on
Manjaro/Arch and because `cocotb` 2.x needs Python 3.12 or 3.13 (not 3.14):

```bash
~/.pyenv/versions/3.12.10/bin/python3 -m venv verif/.venv
source verif/.venv/bin/activate
pip install cocotb cocotb-bus pytest
deactivate
```

Verilator must be on the system path (Manjaro: `sudo pacman -S verilator`).

## Run a testbench

```bash
source verif/.venv/bin/activate
cd verif/axi4_mem_model
make
```

To produce VCD waves:

```bash
make WAVES=1
gtkwave sim_build/dump.vcd
```

To clean:

```bash
make clean
```

## Layout

```
verif/
├── .venv/                          # Python venv (gitignored)
├── README.md                       # this file
├── .gitignore                      # excludes .venv, sim_build, etc.
└── <module_name>/                  # one directory per module under test
    ├── Makefile                    # cocotb makefile pointing at cocotb-config
    └── test_<module_name>.py       # cocotb tests
```

Each module's testbench is independent. Add a new module test by creating a
new directory and following the existing pattern.

## Conventions

- **Test naming:** `test_<module_name>.py` with multiple `@cocotb.test()`
  functions inside, named `test_<scenario>`.
- **Fixtures:** Helpers shared across testbenches go in
  `verif/_lib/<helper>.py` (module discovery extended via `PYTHONPATH`).
- **Failure policy:** Tests must fail loudly. Use `assert` with descriptive
  messages. Do not catch and suppress exceptions.

# Case1354 Electricity-Market Analysis with MATPOWER

This repository is a learning-oriented MATLAB project for analysing the Case1354 power system with MATPOWER 8.1 and MOST. It builds a 24-hour electricity-market model from an Excel workbook and supports energy dispatch, generator offers, demand response, ancillary services, and optional screened N-1 security constraints.

## Requirements

- MATLAB R2023a or a compatible release
- MATPOWER 8.1, including MOST
- The Case1354 Excel input workbook

The input workbook is deliberately not included in this repository. Configure its local path through `config.dataFile` before running the model.

## Project Structure

| Directory / file | Purpose |
| --- | --- |
| `src/market/` | Main 24-hour SCED/SCUC market model, ancillary services, demand response, N-1 contingencies, and settlement. |
| `src/ac_opf/` | Hour-by-hour AC-OPF validation, warm start, and feasibility-recovery utilities. |
| `src/model/` | Excel reading, MATPOWER case construction, bid building, schedules, and input checks. |
| `src/constraints/` | Ramping, transmission, and market-flow constraint functions. |
| `src/results/` | Excel/MAT/JSON/CSV result tables and traceability artifacts. |
| `config/` | A portable configuration example. |
| `tests/` | Focused regression tests for market-model functions. |
| `data/` | Local input Excel location; data files are intentionally not version controlled. |
| `results/` | Local generated outputs; ignored by Git. |
| `docs/` | Project organization and modelling notes. |
| `startup_case1354.m` | Adds all source and test directories to the MATLAB path. |

## Quick Start

```matlab
addpath(genpath('D:\\Program Files\\MATLAB\\matpower8.1'));
startup_case1354;

config = struct();
config.dataFile = 'D:\\path\\to\\case1354cdf-V2.9和说明2.xlsx';
config.outDir = fullfile(pwd, 'results');
config.outFile = fullfile(config.outDir, 'case1354_multiperiod_sced.xlsx');
config.mode = 'SCED';

results = case1354_multiperiod_market(config);
```

`config/case1354_config_example.m` contains the same portable configuration pattern. For tests, set the environment variable `CASE1354_DATA_FILE` to the absolute path of the input workbook, then run `run_case1354_regression_suite`.

To enable the screened N-1 model, set `config.useSecurityConstraints = true`. The default market model is a DC multi-period dispatch; use `case1354cljs` separately to assess AC feasibility, voltage, and reactive-power behaviour.

## Important Limitations

- SCED is not the same as a full AC security-constrained unit-commitment model.
- SCUC requires a supported MILP solver such as `intlinprog`, CPLEX, Gurobi, GLPK, or MOSEK.
- The model assumes the meaning, units, and quality of the supplied Excel tables are correct. Review bid segments, branch ratings, and time-series data before treating results as operational decisions.
- Generated Excel, MAT, JSON, and CSV results are excluded from version control.

## Feedback

This is a learning and sharing project. Issues, corrections, and suggestions are very welcome, especially regarding the interpretation of the Case1354 source data and the market-model assumptions.

# Case1354 Electricity-Market Analysis with MATPOWER

This repository is a learning-oriented MATLAB project for analysing the Case1354 power system with MATPOWER 8.1 and MOST. It builds a 24-hour electricity-market model from an Excel workbook and supports energy dispatch, generator offers, demand response, ancillary services, and optional screened N-1 security constraints.

## Requirements

- MATLAB R2023a or a compatible release
- MATPOWER 8.1, including MOST
- The Case1354 Excel input workbook

The input workbook is deliberately not included in this repository. Configure its local path through `config.dataFile` before running the model.

## Main Programs

| File | Purpose |
| --- | --- |
| `case1354_multiperiod_market.m` | Main 24-hour joint DC market model. Use `mode = "SCED"` for fixed commitment or `mode = "SCUC"` when a MILP solver is available. |
| `case1354cljs.m` | Hour-by-hour AC optimal-power-flow validation and reactive-power check. |
| `build_matpower_case.m` | Converts the Excel tables to a MATPOWER case structure. |
| `build_gencost_matrix.m` | Builds generator bid/cost curves and performs bid validation. |
| `add_auxiliary_services_to_most.m` | Adds regulation and reserve co-optimization. |
| `add_demand_response_to_most.m` | Adds price-responsive demand and interruption variables. |
| `build_n1_contingencies.m` | Creates screened N-1 line, transformer, and generator contingencies. |

## Quick Start

```matlab
addpath(genpath('D:\\Program Files\\MATLAB\\matpower8.1'));

config = struct();
config.dataFile = 'D:\\path\\to\\case1354cdf-V2.9和说明2.xlsx';
config.outDir = 'D:\\path\\to\\results';
config.outFile = fullfile(config.outDir, 'case1354_multiperiod_sced.xlsx');
config.mode = 'SCED';

results = case1354_multiperiod_market(config);
```

To enable the screened N-1 model, set `config.useSecurityConstraints = true`. The default market model is a DC multi-period dispatch; use `case1354cljs` separately to assess AC feasibility, voltage, and reactive-power behaviour.

## Important Limitations

- SCED is not the same as a full AC security-constrained unit-commitment model.
- SCUC requires a supported MILP solver such as `intlinprog`, CPLEX, Gurobi, GLPK, or MOSEK.
- The model assumes the meaning, units, and quality of the supplied Excel tables are correct. Review bid segments, branch ratings, and time-series data before treating results as operational decisions.
- Generated Excel, MAT, JSON, and CSV results are excluded from version control.

## Feedback

This is a learning and sharing project. Issues, corrections, and suggestions are very welcome, especially regarding the interpretation of the Case1354 source data and the market-model assumptions.

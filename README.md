# Case1354 Electricity Market Analysis

MATLAB, MATPOWER 8.1, and MOST based learning project for a 1354-bus electricity-market study. The project reads a Case1354 Excel workbook, builds a MATPOWER network, and produces a reproducible 24-hour market-dispatch result package.

The repository is intended for study and discussion. It is not an operational market-clearing system and its results must not be used directly for real dispatch decisions.

## What This Project Studies

The model connects the following pieces of a power-market calculation:

1. Network data: buses, branches, transformers, generators, loads, and zones.
2. Market data: generator energy offers, load bids, reserve bids, and transmission constraints.
3. Time series: 24-hour load schedule and generator availability/schedule.
4. Joint optimization: energy dispatch, optional ancillary-service procurement, demand response, and screened N-1 scenarios.
5. Validation: a separate AC OPF workflow checks voltage, reactive power, and AC feasibility hour by hour.

## Read This First

There are two different main programs. They answer different questions.

| Program | Main purpose | Mathematical scope |
| --- | --- | --- |
| `case1354_multiperiod_market` | Main 24-hour market result | Joint DC SCED or SCUC using MOST |
| `case1354cljs` | Network feasibility validation | Sequential hourly AC OPF using MATPOWER |

Start with `case1354_multiperiod_market` for market dispatch and prices. Then use `case1354cljs` to inspect the AC network behaviour. A successful DC market solve does not by itself prove AC voltage and reactive-power feasibility.

The Chinese learning guide is available at [docs/LEARNING_GUIDE_ZH.md](docs/LEARNING_GUIDE_ZH.md). The detailed folder map is at [docs/PROJECT_STRUCTURE.md](docs/PROJECT_STRUCTURE.md).

## Project Structure

| Directory / file | Purpose |
| --- | --- |
| `src/market/` | 24-hour SCED/SCUC, ancillary services, demand response, N-1 model, and settlement. |
| `src/ac_opf/` | AC OPF validation, warm start, ramp logic, and feasibility diagnostics. |
| `src/model/` | Excel reader, case construction, bids, schedules, and input validation. |
| `src/constraints/` | Ramping, transmission, and custom market-flow constraints. |
| `src/results/` | Result-table, Excel, MAT, JSON, and CSV output functions. |
| `config/` | Portable configuration example. |
| `tests/` | Regression tests for the major modelling features. |
| `data/` | Local input workbook location. Workbook files are not version controlled. |
| `results/main/` | Versioned result snapshot from the primary 24-hour model run. |
| `startup_case1354.m` | Adds source and test folders to the MATLAB path. |

## Requirements

- MATLAB R2023a or a compatible release.
- MATPOWER 8.1, including MOST.
- A local Case1354 Excel input workbook with all expected sheets.
- A MILP solver such as `intlinprog`, CPLEX, Gurobi, GLPK, or MOSEK only when using `mode = 'SCUC'`.

The source workbook is not included. Its path must be supplied through `config.dataFile`, or it can be placed under `data/` for local use.

## Quick Start

```matlab
% 1. Open MATLAB in the cloned repository folder.
addpath(genpath('D:\\Program Files\\MATLAB\\matpower8.1'));
startup_case1354;

% 2. Create a portable run configuration.
config = case1354_config_example();
config.dataFile = 'D:\\your-data-folder\\case1354-input.xlsx';
config.outDir = fullfile(pwd, 'results', 'local_run');
config.outFile = fullfile(config.outDir, 'case1354_multiperiod_sced.xlsx');
config.mode = 'SCED';

% 3. Run the 24-hour market model.
results = case1354_multiperiod_market(config);
```

The returned `results` structure contains the solve status, output paths, summary tables, run ID, and the MOST result structure. The Excel workbook is the easiest place to begin inspecting a run.

## Important Configuration Choices

| Setting | Typical value | Meaning |
| --- | --- | --- |
| `mode` | `'SCED'` | Fixed commitment, continuous multi-period economic dispatch. |
| `mode` | `'SCUC'` | Adds commitment decisions, startup/shutdown, and minimum up/down time; needs a MILP solver. |
| `targetHours` | `1:24` | Hours jointly optimized in one MOST model. |
| `useAuxiliaryServices` | `true` | Co-optimizes regulation and reserve products with energy. |
| `useDemandBids` | `true` | Allows demand-response/load-bid segments. |
| `useSecurityConstraints` | `false` | Enables screened N-1 DC security scenarios. |
| `marketMode` | `'production'` | Requires valid ordinary generator offers; use `'debug'` only for controlled diagnostics. |

## Input Workbook

The reader expects sheets including `Bus`, `Branch`, `Generator`, `Initial`, `GenBid`, `LoadBid`, `LoadEntity`, `LoadSchedule`, `GeneratorSchedule`, `ASRequirement`, `ASBid`, `TransmissionConstr`, `Zone`, and several unit-commitment or transfer-constraint support sheets.

The most important checks are performed before solving: generator limits, bid segments, generator-name matching, load-distribution factors, ramp data, transmission constraints, and numerical scaling. Read the `DataValidation` and audit sheets in the output workbook whenever a run fails or produces unexpected prices.

## Output and Result Reading

Each market run writes an Excel workbook and MAT file, plus a configuration JSON, manifest JSON, and run log CSV. Important workbook sheets include:

- `MultiPeriodSummary` and `MultiPeriodDispatch`: hourly objective, dispatch, and generator status.
- `NodalEnergyPrice`: bus-level energy prices/LMPs for valid solves.
- `GeneratorSettlement` and `MarketSettlementSummary`: energy revenue, load payment, and settlement reconciliation.
- `AuxiliaryServiceAwards` and `AuxiliaryServiceSummary`: reserve procurement and shortage information when enabled.
- `DemandResponse` and `DemandMarketSummary`: served load, curtailment, and demand-side welfare when enabled.
- `SecurityContingencyAudit`, `SecurityContingencyResults`, and `ACN1PostCheck`: screened N-1 information when enabled.
- `RunConfiguration`, `RunManifest`, and `RunLog`: settings, input/code hashes, and traceability information.

`results/main/` contains the shared example result snapshot. Its README explains each file in that snapshot.

## Tests

Set `CASE1354_DATA_FILE` to the local workbook path, then run:

```matlab
startup_case1354;
setenv('CASE1354_DATA_FILE', 'D:\\your-data-folder\\case1354-input.xlsx');
report = run_case1354_regression_suite();
```

The suite covers auxiliary services, demand response, N-1 constraints, settlement identities, combined-market invariants, and result traceability. It is a regression suite, not a substitute for independent engineering validation.

## Important Limitations

- The main market model is DC. It does not replace a full AC security-constrained unit-commitment model.
- `case1354cljs` is sequential hourly AC OPF, not a single joint 24-hour AC optimization.
- Reserve deliverability and N-1 constraints are screened approximations based on the configured scenarios.
- Input units and the interpretation of bid or transmission columns must be verified against the original workbook documentation.
- A feasible optimization result is not automatically a credible market result: inspect audit sheets, prices, active limits, and numerical diagnostics.

## Feedback

Corrections and suggestions are welcome, especially for Case1354 data interpretation, market assumptions, unit conventions, and validation methods.

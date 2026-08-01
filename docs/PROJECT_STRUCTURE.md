# Project Structure

`case1354_multiperiod_market` is the main entry point for a 24-hour MOST DC market model. It can operate as SCED or SCUC and optionally includes ancillary services, demand response, and screened N-1 contingencies.

`case1354cljs` is deliberately separated in `src/ac_opf`: it runs sequential AC OPF checks and should be used to validate voltage and reactive-power feasibility after a DC market study.

Source functions are grouped by responsibility rather than copied between workflows. Start a MATLAB session with `startup_case1354`, then configure `dataFile` and `outDir` explicitly. This keeps the repository portable and prevents generated data from entering version control.

The Excel input workbook is expected in `data/` only for local use. It is ignored by Git because it is source data rather than project code.

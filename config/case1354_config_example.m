function config = case1354_config_example()
%CASE1354_CONFIG_EXAMPLE Portable starting configuration for the market model.
projectRoot = fileparts(fileparts(mfilename('fullpath')));
config = struct();
config.dataFile = fullfile(projectRoot, 'data', 'case1354cdf-V2.9和说明2.xlsx');
config.outDir = fullfile(projectRoot, 'results');
config.outFile = fullfile(config.outDir, 'case1354_multiperiod_sced.xlsx');
config.mode = 'SCED';
config.targetHours = 1:24;
end

function setup = case1354_test_setup()
%CASE1354_TEST_SETUP Configure portable paths for Case1354 regression tests.
projectRoot = fileparts(fileparts(mfilename('fullpath')));
addpath(genpath(fullfile(projectRoot, 'src')));
dataFile = string(getenv('CASE1354_DATA_FILE'));
if strlength(dataFile) == 0
    dataFile = fullfile(projectRoot, 'data', 'case1354cdf-V2.9和说明2.xlsx');
end
if exist(dataFile, 'file') ~= 2
    error('case1354:TestDataMissing', ...
        'Set CASE1354_DATA_FILE or place the Case1354 workbook in the repository data folder.');
end
outDir = fullfile(projectRoot, 'results', 'tests');
if exist(outDir, 'dir') ~= 7, mkdir(outDir); end
setup = struct('projectRoot', projectRoot, 'dataFile', char(dataFile), 'outDir', outDir);
end

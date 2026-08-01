function projectRoot = startup_case1354()
%STARTUP_CASE1354 Add project source and test folders to the MATLAB path.
projectRoot = fileparts(mfilename('fullpath'));
addpath(genpath(fullfile(projectRoot, 'src')));
addpath(fullfile(projectRoot, 'tests'));
end

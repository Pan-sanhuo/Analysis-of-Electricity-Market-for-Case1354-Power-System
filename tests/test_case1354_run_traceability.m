function test_case1354_run_traceability
%TEST_CASE1354_RUN_TRACEABILITY Focused Stage 12 reproducibility regression.
setup=case1354_test_setup();
outDir=setup.outDir;
base=fullfile(outDir,'case1354_stage12_trace.xlsx');
c=struct('targetHours',1,'mode','SCED','useIntertemporalRamp',false, ...
 'useAuxiliaryServices',false,'useDemandBids',false,'useSecurityConstraints',false, ...
 'marketMode','debug','missingBidPolicy','warning_and_default','outFile',base, ...
 'preserveExistingResults',false,'writeRunSidecars',true);
r=case1354_multiperiod_market(c);assert(r.success,'Traceability regression did not solve.');
assert(strcmpi(r.outputExcel,base),'Traceability result file name was changed.');
assert(exist(r.outputExcel,'file')==2,'Expected result file is missing.');
m=readtable(r.outputExcel,'Sheet','RunManifest','VariableNamingRule','preserve');
cfg=readtable(r.outputExcel,'Sheet','RunConfiguration','VariableNamingRule','preserve');
log=readtable(r.outputExcel,'Sheet','RunLog','VariableNamingRule','preserve');
assert(strlength(string(m.RunId))>0&&strlength(string(m.InputSHA256))==64&&strlength(string(m.CodeSHA256))==64,'Run hashes/ID are invalid.');
assert(height(cfg)>10&&height(log)==1&&log.Hour==1,'Run configuration or hourly log is incomplete.');
assert(exist(r.sidecars.configJson,'file')==2&&exist(r.sidecars.manifestJson,'file')==2&&exist(r.sidecars.logCsv,'file')==2,'Run sidecars are missing.');
disp('RUN_TRACEABILITY_TEST_PASS');
end

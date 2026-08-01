function report=run_case1354_regression_suite(config)
%RUN_CASE1354_REGRESSION_SUITE Layered market-model regression runner.
if nargin<1,config=struct();end
setup=case1354_test_setup();
runFull24=value(config,'runFull24',false);minimumSuccess=value(config,'minimumSuccessfulHours',18);
tests={@test_case1354_auxiliary_services,@test_case1354_demand_response, ...
 @test_case1354_security_constraints,@test_case1354_market_settlement, ...
 @test_case1354_regression_invariants,@test_case1354_run_traceability};
names=["AuxiliaryServices","DemandResponse","N1Security","MarketSettlement","CombinedInvariants","RunTraceability"];
passed=false(numel(tests),1);message=strings(numel(tests),1);seconds=zeros(numel(tests),1);
for k=1:numel(tests)
 tic;
 try,tests{k}();passed(k)=true;message(k)="PASS";catch ME,message(k)=string(getReport(ME,'basic','hyperlinks','off'));end
 seconds(k)=toc;
end
report=table(names(:),passed,message,seconds,'VariableNames',{'TestName','Passed','Message','DurationSeconds'});
if ~all(passed),error('case1354:RegressionFailed','One or more staged regressions failed.');end
if runFull24
 c=struct('targetHours',1:24,'runPowerFlowBeforeOPF',false, ...
  'dataFile',setup.dataFile,'outDir',setup.outDir, ...
  'outFile',fullfile(setup.outDir,'case1354cljs_full_regression.xlsx'));
 r=case1354cljs(c);successCount=sum(r.successByHour);
 if successCount<minimumSuccess,error('case1354:BaselineRegression','Only %d/24 hours succeeded; baseline is %d.',successCount,minimumSuccess);end
 if any(~isfinite(r.summary.Objective(r.successByHour)))||any(~isnan(r.summary.Objective(~r.successByHour)))
  error('case1354:InvalidResultMask','Successful/failed-hour objective validity regression failed.');
 end
end
end
function v=value(s,name,d),if isfield(s,name),v=s.(name);else,v=d;end,end

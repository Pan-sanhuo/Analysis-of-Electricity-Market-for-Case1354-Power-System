function tests = test_case1354cljs()
case1354_test_setup();
%TEST_CASE1354CLJS 运行基础输入校验和 Hour1/24 小时冒烟测试。
% 运行前请确认 dataFile 路径及 MATPOWER 路径可用：results = runtests('test_case1354cljs')。
tests = functiontests(localfunctions);
end

function testHour1(testCase)
c=caseConfig(1); r=case1354cljs(c);
verifyGreaterThan(testCase,size(r.mpcByHour{1}.bus,1),0);
verifyGreaterThan(testCase,r.summary.InputTotalLoadMW,0);
if r.successByHour(1)
 verifyTrue(testCase,isfinite(r.summary.TotalLoadMW));
 verifyTrue(testCase,isfinite(r.summary.TotalGenerationMW));
 verifyTrue(testCase,isfinite(r.summary.Objective));
else
 verifyNotEqual(testCase,strlength(r.summary.FailureStage),0);
 verifyTrue(testCase,isnan(r.summary.TotalLoadMW));
 verifyTrue(testCase,isnan(r.summary.TotalGenerationMW));
 verifyTrue(testCase,isnan(r.summary.Objective));
end
end
function test24Hours(testCase)
c=caseConfig(1:24);c.runPowerFlowBeforeOPF=false;r=case1354cljs(c);
verifyEqual(testCase,numel(r.successByHour),24);
verifyGreaterThanOrEqual(testCase,sum(r.successByHour),18);
ok=r.successByHour;verifyTrue(testCase,all(isfinite(r.summary.Objective(ok))));
verifyTrue(testCase,all(isnan(r.summary.Objective(~ok))));
verifyTrue(testCase,all(strlength(r.summary.FailureStage(~ok))>0));
end
function testMissingLoadHour(testCase)
d=read_case1354_excel(caseConfig(1).dataFile); d.LoadSchedule.Hour24=[]; v=validate_case1354_input(d,struct()); verifyTrue(testCase,any(v.Severity=="Error"));
end
function testLdfSum(testCase)
d=read_case1354_excel(caseConfig(1).dataFile); d.LoadEntity.LDF(1)=d.LoadEntity.LDF(1)+0.1; v=validate_case1354_input(d,struct()); verifyTrue(testCase,any(v.CheckType=="LDF" & v.Severity=="Error"));
end
function testInitialRowKeyMismatch(testCase)
d=read_case1354_excel(caseConfig(1).dataFile); d.Initial=d.Initial(1:end-1,:);
v=validate_case1354_input(d,struct());
verifyTrue(testCase,any(v.CheckType=="GeneratorMapping" & v.ObjectName=="Initial" & v.Severity=="Error"));
end
function testInvalidLimits(testCase)
d=read_case1354_excel(caseConfig(1).dataFile); d.Generator.('Pmin（MW）')(1)=d.Generator.('Pmax（MW）')(1)+1; v=validate_case1354_input(d,struct()); verifyTrue(testCase,any(v.CheckType=="GeneratorLimit" & v.Severity=="Error"));
end
function testUnorderedBid(testCase)
d=read_case1354_excel(caseConfig(1).dataFile); d.GenBid.SegPrc2(1)=d.GenBid.SegPrc1(1)-1; v=validate_case1354_input(d,struct()); verifyTrue(testCase,any(v.CheckType=="GenBid"));
end
function testUnmatchedTransmission(testCase)
d=read_case1354_excel(caseConfig(1).dataFile);
d.TransmissionConstr.('TransmissionID(Branch,BranchGroup,Nomogram)')(1)={'Branch 999999-999998'};
[m,~]=build_matpower_case(d,1,caseConfig(1)); verifyNotEmpty(testCase,m.branch);
end
function testWarmStartComparison(testCase)
c=caseConfig(1:2);c.runPowerFlowBeforeOPF=false;c.useWarmStart=false;a=case1354cljs(c);
c.useWarmStart=true;b=case1354cljs(c);both=a.successByHour&b.successByHour;
verifyEqual(testCase,a.successByHour,b.successByHour);
verifyEqual(testCase,a.summary.Objective(both),b.summary.Objective(both),'RelTol',1e-5,'AbsTol',1e-3);
end
function testOPFNonconvergenceDiagnostic(testCase)
mpc=struct('bus',zeros(0,13),'gen',zeros(0,21),'branch',zeros(0,13));
opf=mpc; opf.success=0; opf.f=nan; raw=struct('error','人为构造的不收敛测试','initUsed','test');
d=diagnose_opf_failure(mpc,opf,raw,1); verifyFalse(testCase,d.Success); verifyEqual(testCase,d.SolverError,"人为构造的不收敛测试");
end
function testFixedScheduleThermalDiagnosis(testCase)
mpc=struct('bus',zeros(2,13),'gen',zeros(1,21),'branch',zeros(1,13));
mpc.bus(:,1)=[1001;516]; mpc.bus(:,12)=1.1; mpc.bus(:,13)=0.9;
mpc.gen(1,8)=1; mpc.gen(1,9)=1000;
mpc.branch(1,[1 2 6 11])=[1001 516 529 1];
opf=mpc; opf.success=0; opf.branch(1,14:17)=[550 0 -545 0];
raw=struct('error','', 'initUsed','test','pf',struct('success',1));
meta.generatorSchedule=table(true,'VariableNames',{'FixedBySchedule'});
d=diagnose_opf_failure(mpc,opf,raw,15,meta);
verifyTrue(testCase,d.PFSuccess);
verifyEqual(testCase,d.FixedScheduleGeneratorCount,1);
verifyEqual(testCase,d.WorstBranchIndex,1);
verifyTrue(testCase,contains(d.LikelyFailureCause,"固定计划出力与线路热限额冲突"));
end
function testMissingBidDefaultKeepsStatus(testCase)
c=caseConfig(1); c.missingBidPolicy='warning_and_default';
d=read_case1354_excel(c.dataFile); [~,meta]=build_matpower_case(d,1,c);
verifyGreaterThan(testCase,height(meta.bidIssues),0);
verifyEqual(testCase,meta.bidIssues.FinalStatus,meta.bidIssues.OriginalStatus);
scheduled=meta.bidIssues.FailureCategory=="ScheduledNoEnergyBid";
verifyEqual(testCase,sum(scheduled),66);
verifyTrue(testCase,all(meta.bidIssues.HourMatchedRowCount(scheduled)==1));
verifyTrue(testCase,all(meta.bidIssues.BidSource(scheduled)=="GeneratorScheduleTechnologyModel"));
verifyTrue(testCase,all(meta.bidIssues.MissingBidPolicy(scheduled)=="technology_specific_schedule"));
verifyTrue(testCase,all(meta.bidIssues.DefaultMarginalPrice(scheduled)>0));
end
function testExcludeGeneratorRequiresExplicitPolicy(testCase)
c=caseConfig(1); c.missingBidPolicy='exclude_generator';
d=read_case1354_excel(c.dataFile); [~,meta]=build_matpower_case(d,1,c);
verifyGreaterThan(testCase,height(meta.bidIssues),0);
verifyTrue(testCase,all(meta.bidIssues.FinalStatus==0));
verifyTrue(testCase,all(meta.bidIssues.MissingBidPolicy=="exclude_generator"));
end
function testZeroRampSkipsConstraint(testCase)
c=caseConfig(1:2);
d=read_case1354_excel(c.dataFile);
[mpc1,~]=build_matpower_case(d,1,c);
[mpc2,~]=build_matpower_case(d,2,c);
[mpc2Applied,check]=apply_ramp_constraints(mpc2,mpc1,d,2);
zeroRamp=check.MissingOrZeroRamp;
verifyGreaterThan(testCase,sum(zeroRamp),0);
verifyFalse(testCase,any(check.RampConstraintApplied(zeroRamp)));
verifyFalse(testCase,any(check.ConstraintConflict(zeroRamp)));
verifyEqual(testCase,mpc2Applied.gen(zeroRamp,10),mpc2.gen(zeroRamp,10),'AbsTol',1e-12);
verifyEqual(testCase,mpc2Applied.gen(zeroRamp,9),mpc2.gen(zeroRamp,9),'AbsTol',1e-12);
end
function testPowerBalanceFormula(testCase)
bus=zeros(1,13); bus(3)=100; bus(4)=20; bus(5)=2; bus(6)=-1; bus(8)=1.05;
gen=zeros(1,25); gen(2)=106.205; gen(3)=24.1025; gen(8)=1;
branch=zeros(1,21); branch(14)=60; branch(15)=12; branch(16)=-58; branch(17)=-10;
b=calculate_power_balance(bus,gen,branch);
verifyEqual(testCase,b.BranchLossMW,2,'AbsTol',1e-12);
verifyEqual(testCase,b.BusShuntMW,2.205,'AbsTol',1e-12);
verifyEqual(testCase,b.PowerBalanceErrorMW,2,'AbsTol',1e-12);
verifyEqual(testCase,b.BusShuntQMVAr,1.1025,'AbsTol',1e-12);
verifyEqual(testCase,b.ReactiveBalanceErrorMVAr,1,'AbsTol',1e-12);
end
function testHour1PowerBalance(testCase)
c=caseConfig(1); c.runPowerFlowBeforeOPF=false;
d=makeValidLoadData(read_case1354_excel(c.dataFile));
[mpc,~]=build_matpower_case(d,1,c);
[opf,success]=run_case1354_opf(mpc,c);
verifyTrue(testCase,success);
b=calculate_power_balance(opf.bus,opf.gen,opf.branch);
verifyLessThan(testCase,b.PowerBalanceAbsErrorMW,1e-4);
end
function testLoadAllocationPreservesBaseOnInvalidLdf(testCase)
c=caseConfig(1);d=read_case1354_excel(c.dataFile);
[mpc,meta]=build_matpower_case(d,1,c);
basePd=double(d.Bus.Pd);
verifyFalse(testCase,meta.loadAllocationSummary.AllocationSuccess);
verifyGreaterThan(testCase,meta.loadAllocationSummary.InvalidValueCount,0);
verifyEqual(testCase,mpc.bus(:,3),basePd,'AbsTol',1e-12);
end
function testLoadAllocationCommitsAfterValidation(testCase)
c=caseConfig(1);d=makeValidLoadData(read_case1354_excel(c.dataFile));
[mpc,meta]=build_matpower_case(d,1,c);
verifyTrue(testCase,meta.loadAllocationSummary.AllocationSuccess);
verifyLessThanOrEqual(testCase,abs(meta.loadAllocationSummary.AllocationErrorMW),1e-4);
verifyEqual(testCase,sum(mpc.bus(:,3)),meta.loadAllocationSummary.ScheduledTotalLoadMW,'AbsTol',1e-4);
end
function testGeneratorNormalizationAndMatrixLayout(testCase)
c=caseConfig(1);c.useGeneratorSchedule=false;d=read_case1354_excel(c.dataFile);
[mpc,meta]=build_matpower_case(d,1,c);
verifyEqual(testCase,normalize_generator_names("GenABCGen"),"ABCGen");
verifyEqual(testCase,normalize_generator_names("gen123"),"123");
verifyEqual(testCase,max(abs(mpc.gen(:,11:16)),[],'all'),0);
verifyEqual(testCase,numel(unique(meta.generatorKey)),height(d.Generator));
verifyEqual(testCase,meta.generatorRow,(1:height(d.Generator)).');
verifyEqual(testCase,mpc.gen(1,2),double(d.Initial.('Pg（MW）')(1)),'AbsTol',1e-12);
end
function testPfInitializationCopiesOnlyState(testCase)
mpc=syntheticCase(); pf=mpc;
pf.bus(:,8:9)=[1.03 2;0.98 -3];
pf.gen(:,1:8)=[2 120 80 999 -999 1.04 777 0;1 -20 -30 888 -888 0.97 666 0];
original=mpc;
[updated,info]=apply_pf_initialization(mpc,pf);
verifyEqual(testCase,updated.bus(:,8:9),pf.bus(:,8:9));
verifyEqual(testCase,updated.gen(:,[1 4 5 7 8]),original.gen(:,[1 4 5 7 8]));
verifyEqual(testCase,updated.gen(:,2),[60;40],'AbsTol',1e-12);
verifyEqual(testCase,updated.gen(:,3),[-20;30],'AbsTol',1e-12);
verifyEqual(testCase,updated.gen(:,6),[0.97;1.04],'AbsTol',1e-12);
verifyEqual(testCase,info.FixedPgRestoredCount,1);
end
function testWarmStartMatchesGeneratorKeys(testCase)
mpc=syntheticCase(); previous=mpc;
previous.gen=previous.gen([2 1],:);previous.gen(:,2:3)=[33 -9;88 11];
previous.gen(:,6)=[0.96;1.02];previous.bus=previous.bus([2 1],:);
previous.bus(:,8:9)=[0.97 -4;1.01 3];
meta.generatorKey=["G1";"G2"];
previousMeta.generatorKey=["G2";"G1"];
[updated,info]=apply_warm_start(mpc,previous,meta,previousMeta,7);
verifyEqual(testCase,updated.bus(:,8:9),[1.01 3;0.97 -4]);
verifyEqual(testCase,updated.gen(:,2),[60;33],'AbsTol',1e-12);
verifyEqual(testCase,updated.gen(:,3),[11;-9],'AbsTol',1e-12);
verifyEqual(testCase,updated.gen(:,6),[1.02;0.96],'AbsTol',1e-12);
verifyEqual(testCase,info.SourceHour,7);
verifyEqual(testCase,info.MatchedGeneratorCount,2);
end
function testFeasibilityAndScalingDiagnostics(testCase)
mpc=syntheticCase();
f=check_case_feasibility(mpc,1);s=build_scaling_diagnostics(mpc,1);
verifyFalse(testCase,f.HardFailure);
verifyTrue(testCase,all(ismember({'ParameterType','MinimumValue','MaximumValue', ...
    'Ratio','PotentialIssueCount'},s.Properties.VariableNames)));
verifyTrue(testCase,any(s.ParameterType=="FixedActivePower"));
end
function testScheduledGeneratorTechnologyModels(testCase)
c=caseConfig(1);d=makeValidLoadData(read_case1354_excel(c.dataFile));
[mpc,meta]=build_matpower_case(d,1,c);s=meta.generatorSchedule;
verifyEqual(testCase,sum(s.MarketModel=="RenewableAvailability"),58);
verifyEqual(testCase,sum(s.MarketModel=="NuclearScheduleDeviation"),8);
verifyFalse(testCase,any(s.FixedBySchedule));
renew=s.MarketModel=="RenewableAvailability";
verifyEqual(testCase,mpc.gen(s.GeneratorRow(renew),10),zeros(sum(renew),1),'AbsTol',1e-12);
verifyEqual(testCase,mpc.gen(s.GeneratorRow(renew),9),s.AvailablePowerMW(renew),'AbsTol',1e-12);
verifyFalse(testCase,any(all(abs(mpc.gencost(:,5:end))<eps,2)));
end
function testFeasibilityRecoveryUsesExplicitSoftActions(testCase)
addpath(genpath('D:\Program Files\MATLAB\matpower8.1'));
mpc=syntheticCase();mpc.bus(2,3)=50;mpc.gen(1,9)=100;mpc.gen(1,10)=0;
mpc.gen(2,8)=0;mpc.branch(1,6)=10;
meta.generatorSchedule=table();
c=struct('valueOfLostLoad',10000,'externalPurchaseMaxMW',0, ...
    'branchViolationPenalty',100,'renewableCurtailmentPenalty',800, ...
    'nuclearScheduleDeviationPenalty',1000);
[recovery,context]=build_feasibility_recovery_case(mpc,meta,c);
opt=mpoption('verbose',0,'out.all',0,'opf.softlims.default',0);
result=runopf(recovery,opt);
tables=summarize_feasibility_recovery(result,context,1,c);
verifyTrue(testCase,tables.summary.RecoverySuccess);
verifyGreaterThan(testCase,tables.summary.BranchLimitRelaxationMVA,0);
verifyLessThan(testCase,tables.summary.LoadSheddingMW,1e-4);
end
function testMarketSettingsProductionAndDebugPolicies(testCase)
s=market_settings(struct());
verifyEqual(testCase,s.marketMode,"production");
verifyEqual(testCase,s.missingBidPolicy,"error");
verifyEqual(testCase,s.bidMWMode,"breakpoint");
verifyError(testCase,@() market_settings(struct('marketMode','production', ...
    'missingBidPolicy','warning_and_default')),'case1354:ProductionMissingBidPolicy');
s=market_settings(struct('marketMode','debug','missingBidPolicy','warning_and_default'));
verifyEqual(testCase,s.missingBidPolicy,"warning_and_default");
end
function testBidMWModesAndNegativePrices(testCase)
[data,gen,names]=miniBidData([10 20],[-50 10]);
c=struct('marketMode','debug','missingBidPolicy','error','bidMWMode','breakpoint', ...
    'marketPriceFloor',-100,'marketPriceCap',100);
[cost,~,curves,issues]=build_gencost_matrix(data,gen,names,1,c);
verifyEmpty(testCase,issues);
verifyTrue(testCase,curves.BidValid);
verifyEqual(testCase,cost(1,[5 7 9 11]),[0 10 20 100],'AbsTol',1e-12);
[data,gen,names]=miniBidData([10 20],[-50 10]);
c.bidMWMode='segment_capacity';
[cost,~,~,issues]=build_gencost_matrix(data,gen,names,1,c);
verifyEmpty(testCase,issues);
verifyEqual(testCase,cost(1,[5 7 9 11]),[0 10 30 100],'AbsTol',1e-12);
end
function testBidPriceBandAndProductionMissingBid(testCase)
[data,gen,names]=miniBidData([10 20],[-200 10]);
c=struct('marketMode','debug','missingBidPolicy','warning_and_default', ...
    'bidMWMode','breakpoint','marketPriceFloor',-100,'marketPriceCap',100);
[~,~,~,issues]=build_gencost_matrix(data,gen,names,1,c);
verifyEqual(testCase,issues.FailureCategory,"PriceOutOfRangeOrUnit");
data.GenBid=data.GenBid([],:);
c=struct('marketMode','production','missingBidPolicy','error','bidMWMode','breakpoint', ...
    'marketPriceFloor',-100,'marketPriceCap',100);
verifyError(testCase,@() build_gencost_matrix(data,gen,names,1,c),'case1354:MissingBid');
end
function [data,gen,names]=miniBidData(mw,price)
data=struct();
data.Generator=table("Gen1","B","Thermal",0,100, ...
    'VariableNames',{'GenName','MarketType','GenType','Pmin（MW）','Pmax（MW）'});
data.GeneratorSchedule=table();
data.GenBid=table(1,"Gen1",2,mw(1),price(1),mw(2),price(2), ...
    'VariableNames',{'Hour','GenName','Tseg','SegMW1','SegPrc1','SegMW2','SegPrc2'});
gen=zeros(1,21);gen(1,[1 8 9 10])=[1 1 100 0];names="1";
end
function mpc=syntheticCase()
mpc=struct('version','2','baseMVA',100);
mpc.bus=zeros(2,13);mpc.bus(:,1)=[1;2];mpc.bus(:,2)=[3;1];
mpc.bus(:,8)=1;mpc.bus(:,12)=1.1;mpc.bus(:,13)=0.9;
mpc.gen=zeros(2,21);mpc.gen(:,1)=[1;2];mpc.gen(:,2)=[60;20];
mpc.gen(:,3)=0;mpc.gen(:,4)=30;mpc.gen(:,5)=-20;mpc.gen(:,6)=1;
mpc.gen(:,7)=100;mpc.gen(:,8)=1;mpc.gen(:,9)=[60;40];mpc.gen(:,10)=[60;0];
mpc.branch=zeros(1,13);mpc.branch(1,[1 2 3 4 6 9 11])=[1 2 0.01 0.1 100 1 1];
mpc.gencost=[2 0 0 2 10 0;2 0 0 2 20 0];
end
function c=caseConfig(hours)
c=struct('dataFile','D:\桌面\潮流\资料\case1354cdf-V2.9和说明2.xlsx', ...
 'outDir','D:\桌面\潮流\结果\case1354\Test','outFile','D:\桌面\潮流\结果\case1354\Test\case1354cljs_test.xlsx', ...
 'matpowerPath','D:\Program Files\MATLAB\matpower8.1','targetHours',hours, ...
 'missingBidPolicy','warning_and_default','saveMatFile',false, ...
 'marketMode','debug','bidMWMode','breakpoint','marketPriceFloor',-1000, ...
 'marketPriceCap',10000, ...
 'useLoadSchedule',true,'useGeneratorSchedule',true, ...
 'scheduledGeneratorModel','technology_specific');
s=case1354_test_setup();
c.dataFile=s.dataFile;
c.outDir=s.outDir;
c.outFile=fullfile(s.outDir,'case1354cljs_test.xlsx');
end
function d=makeValidLoadData(d)
names=strtrim(string(d.LoadEntity.LoadEntityName));
ldf=double(d.LoadEntity.LDF);ldf=max(ldf,0);
entities=unique(names,'stable');
for i=1:numel(entities)
    rows=names==entities(i);ldf(rows)=ldf(rows)/sum(ldf(rows));
end
d.LoadEntity.LDF=ldf;
end

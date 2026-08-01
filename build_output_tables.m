function tables = build_output_tables(mpc, opf, raw, meta, hour, config)
%BUILD_OUTPUT_TABLES 将输入模型与有效求解结果分开整理。
success=isfield(opf,'success') && logical(opf.success);
ib=mpc.bus; ig=mpc.gen; ibr=mpc.branch;
failureStage=raw_string(raw,'failureStage',"");
lastCompleted=raw_string(raw,'lastCompletedStep',"");
solverError=raw_string(raw,'error',"");
if success, failureStage=""; solverError=""; end

inputLoad=sum_or_nan(ib,3);
inputPmax=nan;
if ~isempty(ig), online=ig(:,8)>0; inputPmax=sum(ig(online,9)); end

%% 母线：输入负荷始终保留，失败小时的电压、价格和越限结果写 NaN。
nb=size(ib,1);
busNo=column_or_nan(ib,1); busType=column_or_nan(ib,2);
pd=column_or_nan(ib,3); qd=column_or_nan(ib,4);
vm=nan(nb,1); va=vm; lmp=vm; lq=vm; mvmax=vm; mvmin=vm; vv=vm;
if success
    b=opf.bus; vm=b(:,8); va=b(:,9);
    if size(b,2)>=17, lmp=b(:,14);lq=b(:,15);mvmax=b(:,16);mvmin=b(:,17); end
    vv=max([b(:,8)-b(:,12),b(:,13)-b(:,8),zeros(nb,1)],[],2);
end
tables.bus=table(repmat(hour,nb,1),repmat(success,nb,1),busNo,busType,pd,qd, ...
    vm,va,lmp,lq,mvmax,mvmin,vv, ...
    'VariableNames',{'Hour','ResultValid','BusNo','BusType','PdMW','QdMVAr', ...
    'Vm','VaDegree','LMP_P','Lambda_Q','Mu_Vmax','Mu_Vmin','VoltageViolation'});

%% 机组：GeneratorRow/GeneratorKey 是永久内部主键，失败小时 Pg/Qg 等为 NaN。
ng=size(ig,1);
names=meta_vector(meta,'genName',ng,"Gen"+string((1:ng).'));
genRow=meta_vector(meta,'generatorRow',ng,(1:ng).');
genKey=meta_vector(meta,'generatorKey',ng,"G"+string((1:ng).'));
pg=nan(ng,1);qg=pg;muPmax=pg;muPmin=pg;muQmax=pg;muQmin=pg;
atPmax=false(ng,1);atPmin=atPmax;atQmax=atPmax;atQmin=atPmax;
abovePmax=false(ng,1);belowPmin=abovePmax;aboveQmax=abovePmax;belowQmin=abovePmax;
if success
    g=opf.gen; pg=g(:,2);qg=g(:,3);
    if size(g,2)>=25,muPmax=g(:,22);muPmin=g(:,23);muQmax=g(:,24);muQmin=g(:,25);end
    atPmax=abs(pg-ig(:,9))<1e-5;atPmin=abs(pg-ig(:,10))<1e-5;
    atQmax=abs(qg-ig(:,4))<1e-5;atQmin=abs(qg-ig(:,5))<1e-5;
    abovePmax=pg>ig(:,9)+1e-5;belowPmin=pg<ig(:,10)-1e-5;
    aboveQmax=qg>ig(:,4)+1e-5;belowQmin=qg<ig(:,5)-1e-5;
end
tables.generator=table(repmat(hour,ng,1),repmat(success,ng,1),genRow,genKey,names, ...
    column_or_nan(ig,1),pg,qg,column_or_nan(ig,9),column_or_nan(ig,10), ...
    column_or_nan(ig,4),column_or_nan(ig,5),muPmax,muPmin,muQmax,muQmin, ...
    atPmax,atPmin,atQmax,atQmin,abovePmax,belowPmin,aboveQmax,belowQmin, ...
    'VariableNames',{'Hour','ResultValid','GeneratorRow','GeneratorKey','GenName', ...
    'BusNo','PgMW','QgMVAr','PmaxMW','PminMW','QmaxMVAr','QminMVAr', ...
    'Mu_Pmax','Mu_Pmin','Mu_Qmax','Mu_Qmin','AtPmax','AtPmin','AtQmax','AtQmin', ...
    'AbovePmaxViolation','BelowPminViolation','AboveQmaxViolation','BelowQminViolation'});

%% 支路：失败小时仅保留端点和输入 RateA，流量与负载率写 NaN。
nl=size(ibr,1);pf=nan(nl,1);qf=pf;pt=pf;qt=pf;lp=pf;muSf=pf;muSt=pf;
overloaded=false(nl,1);atRateLimit=false(nl,1);
if success
    br=opf.branch;
    if size(br,2)>=17,pf=br(:,14);qf=br(:,15);pt=br(:,16);qt=br(:,17);end
    s=max(hypot(pf,qf),hypot(pt,qt));rate=ibr(:,6);lp(rate>0)=100*s(rate>0)./rate(rate>0);
    if size(br,2)>=21,muSf=br(:,20);muSt=br(:,21);end
    overloaded=lp>100+config.branchLoadingTolerance;
    atRateLimit=abs(lp-100)<=config.branchLoadingTolerance;
end
tables.branch=table(repmat(hour,nl,1),repmat(success,nl,1), ...
    column_or_nan(ibr,1),column_or_nan(ibr,2),pf,qf,pt,qt,column_or_nan(ibr,6), ...
    muSf,muSt,lp,atRateLimit,overloaded, ...
    'VariableNames',{'Hour','ResultValid','FromBus','ToBus','PfMW','QfMVAr', ...
    'PtMW','QtMVAr','RateA','Mu_Sf','Mu_St','LoadingPercent','AtRateLimit','Overloaded'});

%% 汇总：失败小时的所有求解指标均为 NaN，输入量另列保存。
pb=calculate_power_balance([],[],[]);objective=nan;maxV=nan;maxL=nan;
overloadedCount=nan;generatorBoundaryCount=nan;generatorViolationCount=nan;branchBoundaryCount=nan;resultLoad=nan;resultGeneration=nan;
if success
    pb=calculate_power_balance(opf.bus,opf.gen,opf.branch);
    resultLoad=pb.TotalLoadMW;resultGeneration=pb.TotalGenerationMW;
    objective=get_objective(opf);maxV=max(vv);maxL=max(lp,[],'omitnan');
    overloadedCount=sum(overloaded);branchBoundaryCount=sum(atRateLimit);
    generatorBoundaryCount=sum(atPmax|atPmin|atQmax|atQmin);
    generatorViolationCount=sum(abovePmax|belowPmin|aboveQmax|belowQmin);
end
tables.summary=table(hour,success,failureStage,lastCompleted,solverError,inputLoad,inputPmax, ...
    resultLoad,resultGeneration,objective,maxV,maxL,branchBoundaryCount,overloadedCount,generatorBoundaryCount,generatorViolationCount, ...
    pb.GenerationLoadDifferenceMW,pb.BranchLossMW,pb.BusShuntMW, ...
    pb.PowerBalanceErrorMW,pb.PowerBalanceAbsErrorMW,pb.ReactiveBalanceErrorMVAr, ...
    'VariableNames',{'Hour','Success','FailureStage','LastCompletedStep','SolverError', ...
    'InputTotalLoadMW','InputOnlinePmaxMW','TotalLoadMW','TotalGenerationMW','Objective', ...
    'MaxVoltageViolation','MaxBranchLoadingPercent','BranchAtLimitCount','OverloadedBranchCount', ...
    'GeneratorAtLimitCount','GeneratorLimitViolationCount','GenerationLoadDifferenceMW','BranchLossMW', ...
    'BusShuntMW','PowerBalanceErrorMW','PowerBalanceAbsErrorMW','ReactiveBalanceErrorMVAr'});
tables.RunStatus=tables.summary(:,{'Hour','Success','FailureStage','LastCompletedStep', ...
    'SolverError','InputTotalLoadMW','InputOnlinePmaxMW','Objective'});
tables.HourlyViolationSummary=tables.summary(:,{'Hour','Success','MaxVoltageViolation', ...
    'MaxBranchLoadingPercent','BranchAtLimitCount','OverloadedBranchCount','GeneratorAtLimitCount','GeneratorLimitViolationCount', ...
    'GenerationLoadDifferenceMW','BranchLossMW','BusShuntMW', ...
    'PowerBalanceErrorMW','PowerBalanceAbsErrorMW','ReactiveBalanceErrorMVAr'});
tables.OPFDiagnostics=diagnose_opf_failure(mpc,opf,raw,hour,meta);
tables.AppliedTransmissionConstraints=meta.appliedTransmissionConstraints;
tables.MarketTransmissionResults=build_market_transmission_results(meta.appliedTransmissionConstraints,opf,hour);
tables.RampConstraintCheck=meta.rampCheck;
tables.BidValidation=meta.bidIssues;
if isfield(meta,'costCurve'),tables.CostCurveAudit=meta.costCurve;end
tables.CostModelScope=build_cost_model_scope(hour,config);
tables.MarketSchedulePerformance=build_market_schedule_performance(opf,meta,hour,success);
if isfield(meta,'loadAllocation'),tables.LoadAllocation=meta.loadAllocation;end
if isfield(meta,'loadAllocationSummary'),tables.LoadAllocationSummary=meta.loadAllocationSummary;end
if isfield(meta,'feasibilityCheck'),tables.FeasibilityCheck=meta.feasibilityCheck;end
if isfield(meta,'scalingDiagnostics'),tables.ScalingDiagnostics=meta.scalingDiagnostics;end
if isfield(meta,'rampContinuity'),tables.RampContinuity=meta.rampContinuity;end
if isfield(meta,'warmStartCheck'),tables.WarmStartCheck=meta.warmStartCheck;end
if isfield(raw,'solverAttempts'),tables.SolverAttempts=raw.solverAttempts;else,tables.SolverAttempts=empty_attempts();end
if isfield(raw,'numericalDiagnostics'),tables.NumericalDiagnostics=raw.numericalDiagnostics;else,tables.NumericalDiagnostics=empty_numerical(hour);end
if isfield(raw,'recoveryTables')
    tables.FeasibilityRecoverySummary=raw.recoveryTables.summary;
    tables.FeasibilityRecoveryLoad=raw.recoveryTables.load;
    tables.FeasibilityRecoveryGenerator=raw.recoveryTables.generator;
    tables.FeasibilityRecoveryBranch=raw.recoveryTables.branch;
else
    recovery=empty_feasibility_recovery_tables(hour);
    tables.FeasibilityRecoverySummary=recovery.summary;
    tables.FeasibilityRecoveryLoad=recovery.load;
    tables.FeasibilityRecoveryGenerator=recovery.generator;
    tables.FeasibilityRecoveryBranch=recovery.branch;
end
end

function value=sum_or_nan(matrix,column)
if isempty(matrix)||size(matrix,2)<column,value=nan;else,value=sum(matrix(:,column));end
end
function value=column_or_nan(matrix,column)
if isempty(matrix),value=zeros(0,1);elseif size(matrix,2)<column,value=nan(size(matrix,1),1);else,value=matrix(:,column);end
end
function value=raw_string(raw,name,defaultValue)
if isfield(raw,name),value=string(raw.(name));else,value=string(defaultValue);end
if isempty(value),value=string(defaultValue);else,value=value(1);end
end
function value=meta_vector(meta,name,n,defaultValue)
if isfield(meta,name)&&numel(meta.(name))==n,value=meta.(name)(:);else,value=defaultValue(:);end
end
function value=get_objective(opf)
if isfield(opf,'f')&&isscalar(opf.f),value=opf.f;else,value=nan;end
end
function t=empty_attempts()
t=table(zeros(0,1),strings(0,1),strings(0,1),strings(0,1),false(0,1), ...
    zeros(0,1),zeros(0,1),zeros(0,1),zeros(0,1),strings(0,1),zeros(0,1),zeros(0,1), ...
    'VariableNames',{'Hour','Attempt','Stage','Solver','Success','IterationCount', ...
    'FeasibilityResidual','OptimalityResidual','StepSize','TerminationReason', ...
    'NearSingularWarningCount','MinimumRCOND'});
end
function t=empty_numerical(hour)
t=table(hour,0,nan,"",nan,nan,nan,nan,"","","NotRun", ...
    'VariableNames',{'Hour','NearSingularWarningCount','MinimumRCOND','Solver', ...
    'IterationCount','FeasibilityResidual','OptimalityResidual','StepSize', ...
    'TerminationReason','SelectedAttempt','NumericalReliability'});
end

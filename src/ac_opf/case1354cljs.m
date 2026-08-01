function results = case1354cljs(config)
%CASE1354CLJS 读取 case1354 Excel 并逐小时执行 MATPOWER AC 最优潮流。
% 这是给定机组分段报价下的交流 OPF 市场调度原型，不包含 SCUC、启停或结算。
% 用法：results = case1354cljs(); 或 results = case1354cljs(config)。
if nargin<1 || isempty(config), config=default_config(); else, config=merge_config(default_config(),config); end
try
    check_environment(config); data=read_case1354_excel(config.dataFile);
catch ME
    write_output_excel(config.outFile,input_failure_tables("输入校验失败","程序启动",ME.message));
    rethrow(ME);
end
validation=validate_case1354_input(data,config);
if any(validation.Severity=="Error")
    messages=validation.Message(validation.Severity=="Error");
    failureTables=input_failure_tables("输入校验失败","输入文件读取完成",strjoin(messages,"；"));
    failureTables.DataValidation=validation;
    write_output_excel(config.outFile,failureTables);
    error('case1354:InvalidInput','输入校验失败；详见 %s 的 DataValidation 工作表。',config.outFile);
end
allTables=struct('DataValidation',validation); nH=numel(config.targetHours); success=false(nH,1); opfs=cell(nH,1); mpcs=cell(nH,1);
previousChronological=[]; previousSuccessful=[];
for k=1:nH
    hour=config.targetHours(k); fprintf('Hour %d/%d: 构造并运行 OPF...\n',hour,config.targetHours(end));
    mpc=empty_mpc(); opf=mpc; opf.success=0; opf.f=nan;
    meta=empty_meta(hour); raw=base_raw(); ok=false; modelBuilt=false; modelReady=false;
    try
        [mpc,meta]=build_matpower_case(data,hour,config); modelBuilt=true;
        meta.rampCheck=emptyRamp(); meta.rampContinuity=emptyRampContinuity();
        meta.warmStartCheck=emptyWarmStart(); raw.lastCompletedStep="基础模型构造完成";
        if isfield(meta,'modelValid') && ~meta.modelValid
            raw.failureStage="模型构造失败"; raw.error=string(meta.modelError);
        else
            modelReady=true;
        end
    catch ME
        raw.failureStage="模型构造失败"; raw.error=string(ME.message);
    end
    if modelReady
      try
        if config.useRampConstraint
            [mpc,meta,modelReady,raw]=apply_chronological_ramp( ...
                mpc,meta,previousChronological,data,hour,config,raw);
        end
        if modelReady && config.useWarmStart && ~isempty(previousSuccessful)
            [mpc,meta.warmStartCheck]=apply_warm_start(mpc,previousSuccessful.opf, ...
                meta,previousSuccessful.meta,previousSuccessful.hour);
        end
        if modelReady
            raw.lastCompletedStep="当前小时约束构造完成";
            [opf,ok,raw]=run_case1354_opf(mpc,meta,config);
        end
      catch ME
        raw.failureStage="模型构造失败"; raw.error=string(ME.message);
        raw.lastCompletedStep="基础模型构造完成"; ok=false;
      end
    end
    if ~modelBuilt && strlength(raw.failureStage)==0
        raw.failureStage="模型构造失败"; raw.error="模型未建立";
    end
    try
        tabs=build_output_tables(mpc,opf,raw,meta,hour,config);
    catch ME
        raw.failureStage="结果整理失败"; raw.error=string(ME.message);
        ok=false;
        tabs=emergency_failure_tables(mpc,hour,raw);
    end
    allTables=appendTables(allTables,tabs); success(k)=ok;mpcs{k}=mpc;opfs{k}=opf;
    currentState=struct('hour',hour,'mpc',mpc,'opf',opf,'meta',meta,'success',ok);
    previousChronological=currentState;
    if ok,previousSuccessful=currentState;end
end
write_output_excel(config.outFile,allTables);
if config.saveMatFile
    matFile=replace(config.outFile,'.xlsx','.mat'); save(matFile,'data','config','validation','allTables','success','mpcs','opfs');
else
    matFile='';
end
results=struct('success',all(success),'successByHour',success,'summary',allTables.summary, ...
    'solverAttempts',table_field(allTables,'SolverAttempts'), ...
    'numericalDiagnostics',table_field(allTables,'NumericalDiagnostics'), ...
    'feasibilityCheck',table_field(allTables,'FeasibilityCheck'), ...
    'scalingDiagnostics',table_field(allTables,'ScalingDiagnostics'), ...
    'rampContinuity',table_field(allTables,'RampContinuity'), ...
    'warmStartCheck',table_field(allTables,'WarmStartCheck'), ...
    'marketSchedulePerformance',table_field(allTables,'MarketSchedulePerformance'), ...
    'feasibilityRecoverySummary',table_field(allTables,'FeasibilityRecoverySummary'), ...
    'costModelScope',table_field(allTables,'CostModelScope'), ...
    'outputExcel',config.outFile,'outputMat',matFile,'validation',validation, ...
    'mpcByHour',{mpcs},'opfByHour',{opfs});
fprintf('完成：成功小时 %d/%d。结果文件：%s\n',sum(success),nH,config.outFile);
end

function c=default_config()
c=struct('dataFile','D:\桌面\潮流\资料\case1354cdf-V2.9和说明2.xlsx', ...
 'outDir','D:\桌面\潮流\结果\case1354\New','outFile','', ...
 'matpowerPath','D:\Program Files\MATLAB\matpower8.1','targetHours',1:24, ...
 'opfModel','AC','useLoadSchedule',true,'useGeneratorSchedule',true, ...
 'fixMarketTypeASchedule',false,'scheduledGeneratorModel','technology_specific', ...
 'renewableCurtailmentPenalty',800,'nuclearScheduleDeviationPenalty',1000, ...
 'hydroScheduleDeviationPenalty',300,'scheduleDeviationPenalty',1000, ...
 'enableFeasibilityRecovery',true,'valueOfLostLoad',10000, ...
 'externalPurchasePrice',8000,'externalPurchaseMaxMW',20000, ...
 'branchViolationPenalty',5000, ...
 'useWarmStart',true,'useRampConstraint',true,'runPowerFlowBeforeOPF',true, ...
 'rampOnPreviousFailure','skip_and_flag','runDcOpfDiagnostic',true, ...
 'enableSolverFallbacks',true,'mipsMaxIterations',300, ...
 'saveMatFile',true,'voltageTolerance',1e-6,'branchLoadingTolerance',1e-6, ...
 'loadAllocationToleranceMW',1e-4,'loadLdfTolerance',1e-6, ...
 'marketMode','production','missingBidPolicy','error','bidMWMode','breakpoint', ...
 'marketPriceFloor',-1000,'marketPriceCap',10000,'defaultBidPrice',nan);
% FlowMin/FlowMax in the supplied workbook have no unit annotation. Their
% default is therefore an explicit active-power (MW) market constraint.
% MVA may only be selected for symmetric, single-branch limits; CURRENT is
% rejected until the source workbook supplies current units/base conversion.
c.branchLimitType='MW';
c.outFile=fullfile(c.outDir,'case1354cljs_New.xlsx');
projectRoot=fileparts(fileparts(fileparts(mfilename('fullpath'))));
c.dataFile=fullfile(projectRoot,'data','case1354cdf-V2.9和说明2.xlsx');
c.outDir=fullfile(projectRoot,'results');
c.outFile=fullfile(c.outDir,'case1354cljs.xlsx');
c.matpowerPath='';
end
function c=merge_config(c,u), f=fieldnames(u);for i=1:numel(f),c.(f{i})=u.(f{i});end;if isempty(c.outFile)|| (isfield(u,'outDir') && ~isfield(u,'outFile')),c.outFile=fullfile(c.outDir,'case1354cljs.xlsx');end,end
function check_environment(c)
if exist(c.matpowerPath,'dir')==7,addpath(genpath(c.matpowerPath));end
if exist('runopf','file')~=2,error('case1354:MatpowerNotFound','未找到 MATPOWER 8.1，请检查 config.matpowerPath。');end
end
function all=appendTables(all,new)
f=fieldnames(new);for i=1:numel(f),n=f{i};if ~isfield(all,n),all.(n)=new.(n);else,all.(n)=[all.(n);new.(n)];end,end
end
function m=empty_mpc(),m=struct('version','2','baseMVA',100,'bus',zeros(0,13),'gen',zeros(0,21),'branch',zeros(0,13),'gencost',zeros(0,0));end
function meta=empty_meta(hour)
meta=struct('targetHour',hour,'genName',strings(0,1),'generatorRow',zeros(0,1), ...
    'generatorKey',strings(0,1),'appliedTransmissionConstraints',emptyTrans(), ...
    'rampCheck',emptyRamp(),'bidIssues',emptyBid(),'loadAllocation',table(), ...
    'loadAllocationSummary',table(),'generatorSchedule',table(), ...
    'rampContinuity',emptyRampContinuity(),'warmStartCheck',emptyWarmStart(), ...
    'feasibilityCheck',table(),'scalingDiagnostics',table());
end
function raw=base_raw()
raw=struct('error',"",'pf',[],'pfAttempted',false,'pfSuccess',false, ...
    'failureStage',"",'lastCompletedStep',"输入校验完成", ...
    'initUsed',"",'opfAttempted',false);
end
function tables=input_failure_tables(stage,last,errorText)
tables=struct();
tables.RunStatus=table(nan,false,string(stage),string(last),string(errorText), ...
    nan,nan,nan,'VariableNames',{'Hour','Success','FailureStage', ...
    'LastCompletedStep','SolverError','InputTotalLoadMW','InputOnlinePmaxMW','Objective'});
end
function tables=emergency_failure_tables(mpc,hour,raw)
inputLoad=nan; inputPmax=nan;
if ~isempty(mpc.bus),inputLoad=sum(mpc.bus(:,3));end
if ~isempty(mpc.gen),on=mpc.gen(:,8)>0;inputPmax=sum(mpc.gen(on,9));end
nanv=nan;
tables.summary=table(hour,false,string(raw.failureStage),string(raw.lastCompletedStep),string(raw.error), ...
    inputLoad,inputPmax,nanv,nanv,nanv,nanv,nanv,nanv,nanv,nanv,nanv,nanv,nanv,nanv,nanv,nanv,nanv, ...
    'VariableNames',{'Hour','Success','FailureStage','LastCompletedStep','SolverError', ...
    'InputTotalLoadMW','InputOnlinePmaxMW','TotalLoadMW','TotalGenerationMW','Objective', ...
    'MaxVoltageViolation','MaxBranchLoadingPercent','BranchAtLimitCount','OverloadedBranchCount', ...
    'GeneratorAtLimitCount','GeneratorLimitViolationCount','GenerationLoadDifferenceMW','BranchLossMW', ...
    'BusShuntMW','PowerBalanceErrorMW','PowerBalanceAbsErrorMW','ReactiveBalanceErrorMVAr'});
tables.RunStatus=tables.summary(:,{'Hour','Success','FailureStage','LastCompletedStep', ...
    'SolverError','InputTotalLoadMW','InputOnlinePmaxMW','Objective'});
end
function t=emptyRamp()
t=table(zeros(0,1),strings(0,1),zeros(0,1),zeros(0,1),zeros(0,1), ...
    zeros(0,1),zeros(0,1),zeros(0,1),zeros(0,1),false(0,1),false(0,1), ...
    strings(0,1),false(0,1), ...
    'VariableNames',{'Hour','GenName','OriginalPminMW','OriginalPmaxMW', ...
    'PreviousPgMW','RampUpMW','RampDownMW','AppliedPminMW','AppliedPmaxMW', ...
    'MissingOrZeroRamp','RampConstraintApplied','SkipReason','ConstraintConflict'});
end
function t=emptyRampContinuity()
t=table(zeros(0,1),zeros(0,1),false(0,1),false(0,1),false(0,1), ...
    strings(0,1),strings(0,1), ...
    'VariableNames',{'Hour','PreviousHour','AdjacentStateAvailable', ...
    'PreviousHourSuccess','RampConstraintApplied','Policy','Message'});
end
function t=emptyWarmStart()
t=table(zeros(0,1),zeros(0,1),zeros(0,1),zeros(0,1), ...
    'VariableNames',{'SourceHour','MatchedBusCount','MatchedGeneratorCount','FixedPgRestoredCount'});
end
function [mpc,meta,ready,raw]=apply_chronological_ramp(mpc,meta,previousState,data,hour,config,raw)
ready=true;previousHour=nan;adjacent=false;previousSuccess=false;applied=false;
policy=get_ramp_policy(config);message=""; %#ok<NASGU>
if isempty(previousState)
    message="没有紧邻上一小时状态，未施加爬坡约束";
else
    previousHour=previousState.hour;adjacent=previousHour==hour-1;
    previousSuccess=logical(previousState.success);
    if ~adjacent
        message="目标小时不连续，未跨小时施加爬坡约束";
    elseif previousSuccess
        [mpc,meta.rampCheck]=apply_ramp_constraints(mpc,previousState.opf,data,hour);
        applied=true;message="使用紧邻上一小时成功 OPF 施加爬坡约束";
    else
        switch policy
            case "use_schedule"
                [mpc,meta.rampCheck]=apply_ramp_constraints(mpc,previousState.mpc,data,hour);
                applied=true;message="上一小时 OPF 失败，显式使用上一小时计划/输入状态";
            case "stop"
                ready=false;raw.failureStage="模型构造失败";
                raw.error="紧邻上一小时 OPF 失败，按 rampOnPreviousFailure=stop 停止当前小时";
                message=raw.error;
            otherwise
                message="上一小时 OPF 失败，爬坡约束无法验证，已跳过且未跨小时引用旧成功解";
        end
    end
end
meta.rampContinuity=table(hour,previousHour,adjacent,previousSuccess,applied,policy,message, ...
    'VariableNames',{'Hour','PreviousHour','AdjacentStateAvailable', ...
    'PreviousHourSuccess','RampConstraintApplied','Policy','Message'});
end
function policy=get_ramp_policy(config)
policy=lower(string(config.rampOnPreviousFailure));
end
function value=table_field(source,name)
if isfield(source,name),value=source.(name);else,value=table();end
end
function t=emptyTrans(),t=table(zeros(0,1),strings(0,1),strings(0,1),strings(0,1),zeros(0,1),zeros(0,1),zeros(0,1),zeros(0,1),zeros(0,1),false(0,1),strings(0,1),strings(0,1),strings(0,1),strings(0,1),false(0,1),false(0,1),'VariableNames',{'Hour','TransmissionID','Type','LimitUnit','FlowMin','FlowMax','OriginalRateA','FinalAppliedRateA','BranchIndex','Matched','EnforcementModel','LimitSource','ConstraintModel','Message','LowerLimitBinding','UpperLimitBinding'});end
function t=emptyBid()
t=table(zeros(0,1),zeros(0,1),strings(0,1),strings(0,1), ...
    strings(0,1),strings(0,1),strings(0,1),strings(0,1),strings(0,1),zeros(0,1),zeros(0,1), ...
    zeros(0,1),zeros(0,1),strings(0,1),strings(0,1),zeros(0,1), ...
    strings(0,1),strings(0,1),strings(0,1),zeros(0,1),zeros(0,1), ...
    zeros(0,1),strings(0,1),strings(0,1),zeros(0,1),zeros(0,1),false(0,1), ...
    'VariableNames',{'Hour','GeneratorRow','GeneratorName', ...
    'NormalizedGeneratorName','GenType','MarketModel','FailureCategory','MarketMode', ...
    'BidMWMode','PriceFloor','PriceCap','NameMatchedRowCount','HourMatchedRowCount', ...
    'MatchedGenBidRowIndices','MatchedGenBidNames','ValidSegmentCount', ...
    'FailureReason','MissingBidPolicy','Action','OriginalStatus','FinalStatus', ...
    'DefaultMarginalPrice','DefaultPriceSource','BidSource','ScheduledPgMW', ...
    'AppliedScheduledPgMW','ScheduleClipped'});
for k=1:12
    t.("SegMW"+k)=zeros(0,1);
    t.("SegPrc"+k)=zeros(0,1);
end
end

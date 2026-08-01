function [opf, success, raw] = run_case1354_opf(mpc, meta, config)
%RUN_CASE1354_OPF 分阶段执行可行性检查、DC诊断、AC PF、AC OPF和备用方案。
if nargin<3, config=meta; meta=struct(); end
hour=get_meta_hour(meta);
if isnan(hour)&&isfield(config,'targetHours')&&isscalar(config.targetHours)
    hour=double(config.targetHours);
end
raw=base_raw(hour);success=false;opf=mpc;opf.success=0;opf.f=nan;
if isfield(meta,'feasibilityCheck'),raw.feasibilityCheck=meta.feasibilityCheck;end
if ~isempty(raw.feasibilityCheck) && any(raw.feasibilityCheck.HardFailure)
    raw.failureStage="输入可行性检查失败";
    raw.error=raw.feasibilityCheck.Message(1);
    raw.numericalDiagnostics=make_numerical_summary(raw.solverAttempts,hour,"");
    return;
end

work=mpc;
%% 1) DC OPF 诊断，并用其有功结果初始化 AC 模型。
if get_config(config,'runDcOpfDiagnostic',true)
    dcopt=mpoption('verbose',0,'out.all',0,'model','DC','opf.start',2, ...
        'mips.max_it',get_config(config,'mipsMaxIterations',300));
    [dc,attempt]=captured_opf(work,dcopt,hour,"DC_OPF","MIPS-DC");
    raw.solverAttempts=[raw.solverAttempts;attempt];raw.dc=dc;
    raw.dcSuccess=isfield(dc,'success')&&logical(dc.success);
    if raw.dcSuccess
        work=apply_dc_initialization(work,dc);
        raw.lastCompletedStep="DC OPF诊断完成";
    end
end
if isfield(config,'opfModel')&&strcmpi(config.opfModel,'DC')
    opf=raw.dc;success=raw.dcSuccess;
    if success,raw.lastCompletedStep="DC OPF求解完成";raw.selectedAttempt="DC_OPF";
    else,raw.failureStage="DC OPF诊断失败";raw.error="DC OPF未收敛";end
    raw.numericalDiagnostics=make_numerical_summary(raw.solverAttempts,hour,raw.selectedAttempt);
    return;
end

%% 2) AC PF，只复制状态变量并投影，不覆盖模型参数和机组状态。
if get_config(config,'runPowerFlowBeforeOPF',true)
    raw.pfAttempted=true;
    pfopt=mpoption('verbose',0,'out.all',0);
    [pf,pfAttempt]=captured_pf(work,pfopt,hour,"AC_PF");
    raw.solverAttempts=[raw.solverAttempts;pfAttempt];raw.pf=pf;
    raw.pfSuccess=isfield(pf,'success')&&logical(pf.success);
    if raw.pfSuccess
        [work,raw.pfInitialization]=apply_pf_initialization(work,pf);
        raw.initUsed="DC/当前小时 AC PF";raw.lastCompletedStep="AC潮流完成";
    else
        raw.pfError="AC潮流未收敛";
    end
end

%% 3) 主 AC OPF。
maxIt=get_config(config,'mipsMaxIterations',300);
primary=mpoption('verbose',0,'out.all',0,'model','AC','opf.ac.solver','MIPS', ...
    'opf.start',2,'mips.max_it',min(150,maxIt),'mips.step_control',0);
[candidate,attempt]=captured_opf(work,primary,hour,"AC_OPF_Primary","MIPS");
raw.solverAttempts=[raw.solverAttempts;attempt];
[opf,success,raw]=accept_candidate(candidate,attempt,opf,success,raw);

%% 4) 显式备用策略，不静默替换；每次尝试均记录。
if ~success && get_config(config,'enableSolverFallbacks',true)
    stepOpt=mpoption(primary,'mips.max_it',maxIt,'mips.step_control',1,'opf.start',2);
    [candidate,attempt]=captured_opf(work,stepOpt,hour,"AC_OPF_StepControl","MIPS-SC");
    raw.solverAttempts=[raw.solverAttempts;attempt];
    [opf,success,raw]=accept_candidate(candidate,attempt,opf,success,raw);
end
if ~success && get_config(config,'enableSolverFallbacks',true)
    luOpt=mpoption(primary,'mips.max_it',maxIt,'mips.step_control',1, ...
        'mips.linsolver','LU5','opf.start',2);
    [candidate,attempt]=captured_opf(work,luOpt,hour,"AC_OPF_LU5","MIPS-SC-LU5");
    raw.solverAttempts=[raw.solverAttempts;attempt];
    [opf,success,raw]=accept_candidate(candidate,attempt,opf,success,raw);
end
if ~success && get_config(config,'enableSolverFallbacks',true)
    flat=make_flat_start(mpc);
    [flatPf,attempt]=captured_pf(flat,mpoption('verbose',0,'out.all',0),hour,"AC_PF_FlatStart");
    raw.solverAttempts=[raw.solverAttempts;attempt];
    if attempt.Success
        [flat,~]=apply_pf_initialization(flat,flatPf);
        flatOpt=mpoption(primary,'mips.max_it',maxIt,'mips.step_control',1, ...
            'mips.linsolver','LU5','opf.start',2);
        [candidate,attempt]=captured_opf(flat,flatOpt,hour,"AC_OPF_FlatStart","MIPS-SC-LU5");
        raw.solverAttempts=[raw.solverAttempts;attempt];
        [opf,success,raw]=accept_candidate(candidate,attempt,opf,success,raw);
    end
end
if ~success && get_config(config,'enableSolverFallbacks',true)
    [continuation,continuationAttempts,continuationOk]=load_continuation_initialization( ...
        make_flat_start(mpc),hour);
    raw.solverAttempts=[raw.solverAttempts;continuationAttempts];
    if continuationOk
        continuationOpt=mpoption(primary,'mips.max_it',maxIt,'mips.step_control',1, ...
            'mips.linsolver','LU5','opf.start',2);
        [candidate,attempt]=captured_opf(continuation,continuationOpt,hour, ...
            "AC_OPF_LoadContinuation","MIPS-SC-LU5");
        raw.solverAttempts=[raw.solverAttempts;attempt];
        [opf,success,raw]=accept_candidate(candidate,attempt,opf,success,raw);
    end
end

%% 5) 原始硬约束仍失败时，单独运行带高惩罚的可行性恢复诊断。
if ~success && get_config(config,'enableFeasibilityRecovery',true)
    raw.recoveryAttempted=true;
    try
        [recoveryCase,recoveryContext]=build_feasibility_recovery_case(mpc,meta,config);
        recoveryOpt=mpoption(primary,'mips.max_it',maxIt,'mips.step_control',1, ...
            'mips.linsolver','LU5','opf.start',2,'opf.softlims.default',0);
        [recoveryResult,attempt]=captured_opf(recoveryCase,recoveryOpt,hour, ...
            "AC_OPF_FeasibilityRecovery","MIPS-Recovery");
        raw.solverAttempts=[raw.solverAttempts;attempt];
        raw.recoveryResult=recoveryResult;
        raw.recoveryTables=summarize_feasibility_recovery(recoveryResult,recoveryContext,hour,config);
    catch ME
        raw.recoveryError=string(ME.message);
        raw.recoveryTables.summary.RecoveryMessage="恢复模型构造/求解异常："+string(ME.message);
    end
end

if success
    raw.failureStage="";raw.error="";raw.lastCompletedStep="OPF求解完成";
else
    if raw.recoveryTables.summary.RecoverySuccess
        raw.failureStage="原始OPF求解失败（恢复方案成功）";
        raw.error=raw.recoveryTables.summary.RecoveryMessage;
    elseif raw.pfAttempted&&~raw.pfSuccess
        raw.failureStage="AC潮流失败";raw.error=join_errors(raw.pfError,"所有AC OPF方案均未收敛");
    else
        raw.failureStage="OPF求解失败";raw.error="所有AC OPF方案及可行性恢复模型均未收敛";
    end
end
raw.numericalDiagnostics=make_numerical_summary(raw.solverAttempts,hour,raw.selectedAttempt);
if raw.numericalDiagnostics.NearSingularWarningCount>0
    warning('case1354:NumericalCondition', ...
        'Hour%d: 捕获到%d次近奇异警告，最小RCOND=%.3g，可信度=%s。', ...
        hour,raw.numericalDiagnostics.NearSingularWarningCount, ...
        raw.numericalDiagnostics.MinimumRCOND,raw.numericalDiagnostics.NumericalReliability);
end
end

function raw=base_raw(hour)
raw=struct('error',"",'pf',[],'pfAttempted',false,'pfSuccess',false, ...
    'pfError',"",'pfInitialization',table(),'dc',[],'dcSuccess',false, ...
    'failureStage',"",'lastCompletedStep',"模型构造完成", ...
    'initUsed',"Excel Initial/GeneratorSchedule",'selectedAttempt',"", ...
    'feasibilityCheck',table(),'solverAttempts',empty_attempts(), ...
    'recoveryAttempted',false,'recoveryResult',[],'recoveryError',"", ...
    'recoveryTables',empty_feasibility_recovery_tables(hour), ...
    'numericalDiagnostics',empty_numerical(hour));
end

function [result,attempt]=captured_opf(mpc,opt,hour,name,solver) %#ok<INUSD>
result=mpc;result.success=0;result.f=nan;errorText="";logText="";
try
    logText=evalc('result=runopf(mpc,opt);');
catch ME
    errorText=string(ME.message);
end
attempt=attempt_row(result,logText,errorText,hour,name,"OPF",solver);
end

function [result,attempt]=captured_pf(mpc,opt,hour,name) %#ok<INUSD>
result=mpc;result.success=0;errorText="";logText="";
try
    logText=evalc('result=runpf(mpc,opt);');
catch ME
    errorText=string(ME.message);
end
attempt=attempt_row(result,logText,errorText,hour,name,"PF","Newton");
end

function attempt=attempt_row(result,logText,errorText,hour,name,stage,solver)
[warningCount,minRcond]=parse_rcond(logText);
iterations=nan;feasibility=nan;optimality=nan;stepSize=nan;termination=errorText;
if isfield(result,'raw')&&isfield(result.raw,'output')
    output=result.raw.output;
    if isfield(output,'iterations'),iterations=last_numeric(output.iterations);end
    if isfield(output,'message')
        messages=string(output.message);termination=messages(end);
    end
    if isfield(output,'hist')&&~isempty(output.hist)
        last=output.hist(end);
        if isfield(last,'feascond'),feasibility=last_numeric(last.feascond);end
        if isfield(last,'gradcond'),optimality=last_numeric(last.gradcond);end
        if isfield(last,'stepsize'),stepSize=last_numeric(last.stepsize);end
    end
end
if strlength(termination)==0
    if isfield(result,'success')&&result.success,termination="Converged";else,termination="Did not converge";end
end
if isfield(result,'success')&&~isempty(result.success)
    ok=all(logical(result.success(:)));
else
    ok=false;
end
termination=string(termination);termination=termination(end);
attempt=table(hour,string(name),string(stage),string(solver),ok,iterations, ...
    feasibility,optimality,stepSize,string(termination),warningCount,minRcond, ...
    'VariableNames',attempt_variable_names());
end

function value=last_numeric(input)
input=double(input);
if isempty(input),value=nan;else,value=input(end);end
end

function [count,minimum]=parse_rcond(logText)
tokens=regexp(char(logText),'RCOND\s*=\s*([0-9.eE+\-]+)','tokens');
count=numel(tokens);minimum=nan;
if count>0
    values=cellfun(@(x)str2double(x{1}),tokens);minimum=min(values);
end
end

function [opf,success,raw]=accept_candidate(candidate,attempt,opf,success,raw)
if ~success,opf=candidate;end
if attempt.Success
    opf=candidate;success=true;raw.selectedAttempt=attempt.Attempt;
end
end

function mpc=apply_dc_initialization(mpc,dc)
[busMatched,busSource]=ismember(mpc.bus(:,1),dc.bus(:,1));
mpc.bus(busMatched,9)=dc.bus(busSource(busMatched),9);
count=min(size(mpc.gen,1),size(dc.gen,1));
mpc.gen(1:count,2)=dc.gen(1:count,2);
mpc.gen(:,2)=min(max(mpc.gen(:,2),mpc.gen(:,10)),mpc.gen(:,9));
end

function [mpc,attempts,success]=load_continuation_initialization(target,hour)
attempts=empty_attempts();mpc=target;success=true;
targetPd=target.bus(:,3);targetQd=target.bus(:,4);alphas=[0.5 0.7 0.85 1.0];
for i=1:numel(alphas)
    mpc.bus(:,3)=targetPd*alphas(i);mpc.bus(:,4)=targetQd*alphas(i);
    opt=mpoption('verbose',0,'out.all',0);
    [pf,attempt]=captured_pf(mpc,opt,hour,"AC_PF_Load_"+string(alphas(i)));
    attempts=[attempts;attempt]; %#ok<AGROW>
    if ~attempt.Success,success=false;break;end
    [mpc,~]=apply_pf_initialization(mpc,pf);
end
mpc.bus(:,3)=targetPd;mpc.bus(:,4)=targetQd;
end

function mpc=make_flat_start(mpc)
% 清除跨小时/前序求解状态，同时保留所有模型参数和固定计划边界。
mpc.bus(:,8)=1;mpc.bus(:,9)=0;
online=mpc.gen(:,8)>0;fixed=online&abs(mpc.gen(:,9)-mpc.gen(:,10))<=1e-9;
free=online&~fixed;
mpc.gen(free,2)=(mpc.gen(free,9)+mpc.gen(free,10))/2;
mpc.gen(fixed,2)=mpc.gen(fixed,9);
mpc.gen(online,3)=min(max(zeros(sum(online),1),mpc.gen(online,5)),mpc.gen(online,4));
mpc.gen(online,6)=1;mpc.gen(~online,2:3)=0;
end

function summary=make_numerical_summary(attempts,hour,selected)
if isempty(attempts)
    summary=empty_numerical(hour);return;
end
count=sum(attempts.NearSingularWarningCount);r=attempts.MinimumRCOND;
if all(isnan(r)),minimum=nan;else,minimum=min(r,[],'omitnan');end
chosen=find(attempts.Attempt==string(selected),1,'last');
if isempty(chosen),chosen=height(attempts);end
reliability="High";
if count>=5||(isfinite(minimum)&&minimum<1e-18),reliability="Low";
elseif count>0||(isfinite(minimum)&&minimum<1e-12),reliability="Medium";end
summary=table(hour,count,minimum,attempts.Solver(chosen),attempts.IterationCount(chosen), ...
    attempts.FeasibilityResidual(chosen),attempts.OptimalityResidual(chosen), ...
    attempts.StepSize(chosen),attempts.TerminationReason(chosen),attempts.Attempt(chosen), ...
    reliability,'VariableNames',numerical_variable_names());
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
    'VariableNames',numerical_variable_names());
end
function names=attempt_variable_names()
names={'Hour','Attempt','Stage','Solver','Success','IterationCount', ...
    'FeasibilityResidual','OptimalityResidual','StepSize','TerminationReason', ...
    'NearSingularWarningCount','MinimumRCOND'};
end
function names=numerical_variable_names()
names={'Hour','NearSingularWarningCount','MinimumRCOND','Solver', ...
    'IterationCount','FeasibilityResidual','OptimalityResidual','StepSize', ...
    'TerminationReason','SelectedAttempt','NumericalReliability'};
end

function value=get_config(config,name,defaultValue)
if isfield(config,name),value=config.(name);else,value=defaultValue;end
end
function hour=get_meta_hour(meta)
if isfield(meta,'targetHour'),hour=double(meta.targetHour);else,hour=nan;end
end
function message=join_errors(a,b)
a=string(a);b=string(b);if strlength(a)==0,message=b;elseif strlength(b)==0,message=a;else,message=a+"；"+b;end
end

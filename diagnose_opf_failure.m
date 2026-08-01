function diag = diagnose_opf_failure(mpc, opf, raw, hour, meta)
%DIAGNOSE_OPF_FAILURE 无论 OPF 成功与否都输出可定位的运行诊断。
if nargin<5, meta=struct(); end
online=mpc.gen(:,8)>0; load=sum(mpc.bus(:,3)); pmin=sum(mpc.gen(online,10)); pmax=sum(mpc.gen(online,9));
vm=nan; loading=nan; if isfield(opf,'bus')&&~isempty(opf.bus),vm=max([max(opf.bus(:,8)-opf.bus(:,12)),max(opf.bus(:,13)-opf.bus(:,8)),0]);end
worstIndex=nan; worstFrom=nan; worstTo=nan; worstRate=nan;
if isfield(opf,'branch')&&size(opf.branch,2)>=17
    rate=opf.branch(:,6);
    s=max(hypot(opf.branch(:,14),opf.branch(:,15)), ...
        hypot(opf.branch(:,16),opf.branch(:,17)));
    good=find(rate>0);
    if ~isempty(good)
        values=100*s(good)./rate(good);
        [loading,pos]=max(values);
        worstIndex=good(pos); worstFrom=opf.branch(worstIndex,1);
        worstTo=opf.branch(worstIndex,2); worstRate=rate(worstIndex);
    end
end
islands=estimate_islands(mpc); err=""; if isfield(raw,'error'),err=string(raw.error);end
init="";if isfield(raw,'initUsed'),init=string(raw.initUsed);end
success=logical(isfield(opf,'success')&&opf.success);
pfSuccess=false;
if isfield(raw,'pf') && ~isempty(raw.pf) && isfield(raw.pf,'success')
    pfSuccess=logical(raw.pf.success);
end
fixedScheduleCount=0;
if isfield(meta,'generatorSchedule') && ...
        ismember('FixedBySchedule',meta.generatorSchedule.Properties.VariableNames)
    fixedScheduleCount=sum(meta.generatorSchedule.FixedBySchedule);
end
cause=classify_failure(success,load>pmax,islands,any(mpc.gen(:,10)>mpc.gen(:,9)), ...
    any(mpc.gen(:,5)>mpc.gen(:,4)),pfSuccess,fixedScheduleCount,loading,vm,err,worstIndex);
diag=table(hour,success,load,pmin,pmax,vm,loading, ...
    worstIndex,worstFrom,worstTo,worstRate,pfSuccess,fixedScheduleCount, ...
    any(mpc.gen(:,10)>mpc.gen(:,9)),any(mpc.gen(:,5)>mpc.gen(:,4)), ...
    islands,load>pmax,err,init,cause, ...
    'VariableNames',{'Hour','Success','TotalLoadMW','OnlinePminMW','OnlinePmaxMW', ...
    'MaxVoltageViolation','MaxBranchLoadingPercent','WorstBranchIndex', ...
    'WorstBranchFromBus','WorstBranchToBus','WorstBranchRateA','PFSuccess', ...
    'FixedScheduleGeneratorCount','PminPmaxConflict','QminQmaxConflict', ...
    'IslandCount','LoadExceedsCapacity','SolverError','InitializationUsed','LikelyFailureCause'});
end
function cause=classify_failure(success,capacityShort,islands,pConflict,qConflict,pfSuccess,fixedCount,loading,vm,err,worstIndex)
if success, cause="OPF收敛"; return; end
if strlength(err)>0, cause="求解器异常: "+err; return; end
if capacityShort, cause="在线机组最大有功容量低于负荷"; return; end
if islands>1, cause="网络存在多个电气岛"; return; end
if pConflict||qConflict, cause="机组上下限存在冲突"; return; end
if pfSuccess && fixedCount>0 && isfinite(loading) && loading>100
    cause=sprintf('固定计划出力与线路热限额冲突候选：支路%d负载率%.3f%%',worstIndex,loading);
elseif isfinite(loading) && loading>100
    cause=sprintf('线路热限额冲突候选：支路%d负载率%.3f%%',worstIndex,loading);
elseif isfinite(vm) && vm>0
    cause=sprintf('电压约束冲突候选：最大越限%.6g pu',vm);
else
    cause="AC OPF未收敛，现有诊断未定位唯一约束";
end
cause=string(cause);
end
function n=estimate_islands(mpc)
b=mpc.bus(:,1);
if isempty(b), n=0; return; end
on=mpc.branch(:,11)>0;
[fromFound,fromIndex]=ismember(mpc.branch(on,1),b);
[toFound,toIndex]=ismember(mpc.branch(on,2),b);
valid=fromFound & toFound;
network=graph(fromIndex(valid),toIndex(valid),[],numel(b));
n=max(conncomp(network));
end

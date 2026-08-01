function tables = summarize_feasibility_recovery(result,context,hour,config)
%SUMMARIZE_FEASIBILITY_RECOVERY 分解恢复方案中的弃电、计划偏差、失负荷和线路松弛。
ok=isfield(result,'success')&&logical(result.success);

%% 可中断负荷结果。
loadRows=context.loadBusRows;n=numel(loadRows);
served=nan(n,1);shed=nan(n,1);reactiveShed=nan(n,1);
if ok&&n>0
    pg=result.gen(context.loadGenRows,2);qg=result.gen(context.loadGenRows,3);
    served=max(0,-pg);shed=max(0,context.originalPd-served);
    reactiveShed=max(0,context.originalQd+qg);
end
tables.load=table(repmat(hour,n,1),repmat(ok,n,1),result.bus(loadRows,1), ...
    context.originalPd,served,shed,context.originalQd,reactiveShed, ...
    'VariableNames',{'Hour','RecoverySuccess','BusNo','OriginalLoadMW', ...
    'ServedLoadMW','LoadSheddingMW','OriginalLoadMVAr','ReactiveSheddingMVAr'});

%% 计划机组恢复动作。
tables.generator=build_market_schedule_performance(result,context.meta,hour,ok);
renew=tables.generator.MarketModel=="RenewableAvailability";
nuclear=tables.generator.MarketModel=="NuclearScheduleDeviation";
renewableCurtailment=sum_valid(tables.generator.CurtailmentMW(renew));
nuclearDeviation=sum_valid(abs(tables.generator.ScheduleDeviationMW(nuclear)));

%% 线路软限额结果。
idx=context.softBranchRows;overload=nan(numel(idx),1);cost=overload;
if ok&&isfield(result,'softlims')&&isfield(result.softlims,'RATE_A')
    s=result.softlims.RATE_A;
    [matched,loc]=ismember(idx,s.idx);
    overload(matched)=s.overload(loc(matched));
    cost(matched)=s.ovl_cost(loc(matched));
end
tables.branch=table(repmat(hour,numel(idx),1),repmat(ok,numel(idx),1),idx, ...
    result.branch(idx,1),result.branch(idx,2),result.branch(idx,6),overload,cost, ...
    'VariableNames',{'Hour','RecoverySuccess','BranchRow','FromBus','ToBus', ...
    'OriginalRateA','RequiredRelaxationMVA','ViolationCost'});

externalPurchase=nan;
if ok&&isfinite(context.externalGeneratorRow)
    externalPurchase=max(0,result.gen(context.externalGeneratorRow,2));
end
loadShedding=sum_valid(shed);branchRelaxation=sum_valid(overload);
objective=nan;if ok&&isfield(result,'f'),objective=result.f;end
message="恢复模型未收敛";
if ok
    message=sprintf(['恢复方案：新能源弃电 %.3f MW，核电计划绝对偏差 %.3f MW，' ...
        '负荷削减 %.3f MW，外购电 %.3f MW，线路限额松弛合计 %.3f MVA。'], ...
        renewableCurtailment,nuclearDeviation,loadShedding,externalPurchase,branchRelaxation);
end
tables.summary=table(hour,ok,"WeightedFeasibilityRecovery",objective, ...
    renewableCurtailment,nuclearDeviation,loadShedding,externalPurchase, ...
    branchRelaxation,config_value(config,'renewableCurtailmentPenalty',800), ...
    config_value(config,'nuclearScheduleDeviationPenalty',1000), ...
    config_value(config,'valueOfLostLoad',10000), ...
    config_value(config,'externalPurchasePrice',8000), ...
    config_value(config,'branchViolationPenalty',5000),string(message), ...
    'VariableNames',{'Hour','RecoverySuccess','RecoveryModel','RecoveryObjective', ...
    'RenewableCurtailmentMW','NuclearAbsoluteDeviationMW','LoadSheddingMW', ...
    'ExternalPurchaseMW','BranchLimitRelaxationMVA','CurtailmentPenalty', ...
    'NuclearDeviationPenalty','ValueOfLostLoad','ExternalPurchasePrice', ...
    'BranchViolationPenalty','RecoveryMessage'});
end

function value=sum_valid(x)
if isempty(x),value=0;elseif all(isnan(x)),value=nan;else,value=sum(x,'omitnan');end
end
function value=config_value(config,name,defaultValue)
if isfield(config,name)&&isscalar(config.(name))&&isfinite(config.(name))&&config.(name)>=0
    value=double(config.(name));
else
    value=defaultValue;
end
end

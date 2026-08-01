function [recovery, context] = build_feasibility_recovery_case(mpc,meta,config)
%BUILD_FEASIBILITY_RECOVERY_CASE 为失败诊断添加可中断负荷、外购电和线路软限额。
context=struct('originalGeneratorCount',size(mpc.gen,1),'loadBusRows',zeros(0,1), ...
    'loadGenRows',zeros(0,1),'originalPd',zeros(0,1),'originalQd',zeros(0,1), ...
    'externalGeneratorRow',nan,'softBranchRows',zeros(0,1),'meta',meta);
recovery=mpc;

%% 负荷削减：MATPOWER 官方 load2disp 将固定负荷转换为可调度负发电机。
loadRows=find(mpc.bus(:,3)>0);
context.loadBusRows=loadRows;
context.originalPd=mpc.bus(loadRows,3);
context.originalQd=mpc.bus(loadRows,4);
if ~isempty(loadRows)
    voll=config_value(config,'valueOfLostLoad',10000);
    recovery=load2disp(recovery,'',loadRows,voll);
    context.loadGenRows=(context.originalGeneratorCount+(1:numel(loadRows))).';
end

%% 外部购电：接在参考母线，使用高于常规报价的线性成本。
purchaseMax=config_value(config,'externalPurchaseMaxMW',20000);
if purchaseMax>0
    ref=find(recovery.bus(:,2)==3,1);
    if isempty(ref),ref=1;end
    row=zeros(1,size(recovery.gen,2));
    row(1:10)=[recovery.bus(ref,1),0,0,purchaseMax,-purchaseMax,1, ...
        recovery.baseMVA,1,purchaseMax,0];
    recovery.gen=[recovery.gen;row];
    context.externalGeneratorRow=size(recovery.gen,1);
    cost=zeros(1,size(recovery.gencost,2));
    cost(1:6)=[2,0,0,2,config_value(config,'externalPurchasePrice',8000),0];
    recovery.gencost=[recovery.gencost;cost];
end

%% 线路热限额软化：只软化原本有 RATE_A 的在线支路，其余约束保持硬约束。
softRows=find(recovery.branch(:,11)>0&recovery.branch(:,6)>0);
context.softBranchRows=softRows;
if ~isempty(softRows)
    recovery.softlims.RATE_A=struct('idx',softRows, ...
        'cost',config_value(config,'branchViolationPenalty',5000)*ones(numel(softRows),1), ...
        'hl_mod','remove');
    recovery=toggle_softlims(recovery,'on');
end
end

function value=config_value(config,name,defaultValue)
if isfield(config,name)&&isscalar(config.(name))&&isfinite(config.(name))&&config.(name)>=0
    value=double(config.(name));
else
    value=defaultValue;
end
end

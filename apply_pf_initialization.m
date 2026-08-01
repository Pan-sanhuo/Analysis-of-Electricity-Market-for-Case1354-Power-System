function [mpc, info] = apply_pf_initialization(mpc, pf)
%APPLY_PF_INITIALIZATION 仅复制 AC PF 的状态变量并重新投影到 OPF 边界。
[busMatched,busSource]=ismember(mpc.bus(:,1),pf.bus(:,1));
if ~all(busMatched)
    error('case1354:PFBusMapping','AC PF 结果缺少 %d 个当前母线。',sum(~busMatched));
end
[genSource,genMatched]=match_by_bus_occurrence(mpc.gen(:,1),pf.gen(:,1));
if ~all(genMatched)
    error('case1354:PFGeneratorMapping','AC PF 结果缺少 %d 台当前机组。',sum(~genMatched));
end

mpc.bus(:,8)=pf.bus(busSource,8);
mpc.bus(:,9)=pf.bus(busSource,9);
mpc.gen(:,2)=pf.gen(genSource,2);
mpc.gen(:,3)=pf.gen(genSource,3);
mpc.gen(:,6)=pf.gen(genSource,6);
mpc=project_generator_state(mpc);

fixed=mpc.gen(:,8)>0 & abs(mpc.gen(:,9)-mpc.gen(:,10))<=1e-9;
info=table(all(busMatched),all(genMatched),sum(fixed), ...
    'VariableNames',{'AllBusesMatched','AllGeneratorsMatched','FixedPgRestoredCount'});
end

function [sourceRows,matched]=match_by_bus_occurrence(targetBus,sourceBus)
sourceRows=zeros(numel(targetBus),1);matched=false(numel(targetBus),1);
uniqueBus=unique(targetBus,'stable');
for i=1:numel(uniqueBus)
    target=find(targetBus==uniqueBus(i));source=find(sourceBus==uniqueBus(i));
    count=min(numel(target),numel(source));
    sourceRows(target(1:count))=source(1:count);matched(target(1:count))=true;
end
end

function mpc=project_generator_state(mpc)
online=mpc.gen(:,8)>0;
mpc.gen(online,2)=min(max(mpc.gen(online,2),mpc.gen(online,10)),mpc.gen(online,9));
mpc.gen(online,3)=min(max(mpc.gen(online,3),mpc.gen(online,5)),mpc.gen(online,4));
mpc.gen(~online,2:3)=0;
end

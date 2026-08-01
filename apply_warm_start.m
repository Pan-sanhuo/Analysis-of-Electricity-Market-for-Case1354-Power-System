function [mpc, info] = apply_warm_start(mpc, previousOpf, meta, previousMeta, sourceHour)
%APPLY_WARM_START 按母线号和永久机组键复制上一成功小时的完整状态初值。
if nargin<5, sourceHour=nan; end
[busMatched,busSource]=ismember(mpc.bus(:,1),previousOpf.bus(:,1));
if any(busMatched)
    mpc.bus(busMatched,8)=previousOpf.bus(busSource(busMatched),8);
    mpc.bus(busMatched,9)=previousOpf.bus(busSource(busMatched),9);
end

currentKeys=string(meta.generatorKey);
previousKeys=strings(0,1);
if isfield(previousMeta,'generatorKey'),previousKeys=string(previousMeta.generatorKey);end
[genMatched,genSource]=ismember(currentKeys,previousKeys);
if ~all(genMatched)
    [fallbackSource,fallbackMatched]=match_by_bus_occurrence(mpc.gen(:,1),previousOpf.gen(:,1));
    useFallback=~genMatched & fallbackMatched;
    genSource(useFallback)=fallbackSource(useFallback);
    genMatched(useFallback)=true;
end
if any(genMatched)
    mpc.gen(genMatched,2)=previousOpf.gen(genSource(genMatched),2);
    mpc.gen(genMatched,3)=previousOpf.gen(genSource(genMatched),3);
    mpc.gen(genMatched,6)=previousOpf.gen(genSource(genMatched),6);
end
mpc=project_generator_state(mpc);
fixed=mpc.gen(:,8)>0 & abs(mpc.gen(:,9)-mpc.gen(:,10))<=1e-9;
info=table(sourceHour,sum(busMatched),sum(genMatched),sum(fixed), ...
    'VariableNames',{'SourceHour','MatchedBusCount','MatchedGeneratorCount','FixedPgRestoredCount'});
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

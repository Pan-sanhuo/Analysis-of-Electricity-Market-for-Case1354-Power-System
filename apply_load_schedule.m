function [mpc, allocation, summary] = apply_load_schedule(mpc,data,hour,config)
%APPLY_LOAD_SCHEDULE 在临时数组中校验并分配负荷，成功后才提交到 mpc.bus。
basePd=mpc.bus(:,3);
baseQd=mpc.bus(:,4);
allocation=empty_allocation();

if ~isfield(config,'useLoadSchedule') || ~config.useLoadSchedule
    summary=make_summary(hour,sum(basePd),sum(basePd),0,0,0,0,true, ...
        "未启用负荷时序，保留 Bus 基准负荷");
    return;
end

mwTolerance=get_config(config,'loadAllocationToleranceMW',1e-4);
ldfTolerance=get_config(config,'loadLdfTolerance',1e-6);
col="Hour"+hour;
sch=data.LoadSchedule;
le=data.LoadEntity;
requiredLoadColumns={'LoadEntityName','BusNo','LDF'};
if ~ismember(col,sch.Properties.VariableNames) || ...
        ~all(ismember(requiredLoadColumns,le.Properties.VariableNames)) || ...
        ~ismember('LoadEntityName',sch.Properties.VariableNames)
    summary=make_summary(hour,nan,sum(basePd),nan,1,0,1,false, ...
        "负荷时序缺少 Hour/LoadEntityName/BusNo/LDF 必要列，保留 Bus 基准负荷");
    warning('case1354:InvalidLoadAllocation','Hour%d: %s',hour,summary.Message);
    return;
end

scheduleNames=strtrim(string(sch.('LoadEntityName')));
entityNames=strtrim(string(le.('LoadEntityName')));
scheduleMW=to_numeric(sch.(col));
busNo=to_numeric(le.('BusNo'));
ldf=to_numeric(le.('LDF'));
scheduledTotal=sum(scheduleMW(isfinite(scheduleMW)));
newPd=zeros(size(basePd));
newQd=zeros(size(baseQd));
unmatchedEntities=strings(0,1);
unmatchedBusCount=0;
invalidValueCount=sum(~isfinite(scheduleMW) | scheduleMW<0) + ...
    sum(~isfinite(busNo)) + sum(~isfinite(ldf) | ldf<0);
rows=cell(0,7);

uniqueEntities=unique(entityNames,'stable');
for i=1:numel(uniqueEntities)
    entity=uniqueEntities(i);
    entityRows=find(entityNames==entity);
    scheduleRows=find(scheduleNames==entity);
    entityValid=true;
    message="";
    total=nan;
    if strlength(entity)==0 || numel(scheduleRows)~=1
        entityValid=false;
        message="LoadSchedule 必须唯一匹配该负荷实体";
        unmatchedEntities(end+1,1)=entity; %#ok<AGROW>
    else
        total=scheduleMW(scheduleRows);
    end
    entityLdf=ldf(entityRows);
    ldfTotal=sum(entityLdf,'omitnan');
    if any(~isfinite(entityLdf) | entityLdf<0) || abs(ldfTotal-1)>ldfTolerance
        entityValid=false;
        message=join_message(message,sprintf('LDF之和%.12g超出容差%.3g',ldfTotal,ldfTolerance));
    end
    mappedBus=zeros(numel(entityRows),1);
    for j=1:numel(entityRows)
        busIndex=find(mpc.bus(:,1)==busNo(entityRows(j)),1);
        if isempty(busIndex)
            entityValid=false;
            unmatchedBusCount=unmatchedBusCount+1;
            message=join_message(message,"母线编号不存在");
        else
            mappedBus(j)=busIndex;
        end
    end
    if ~isfinite(total) || total<0
        entityValid=false;
        message=join_message(message,"计划负荷为负值、NaN或Inf");
    end
    if entityValid
        for j=1:numel(entityRows)
            allocated=total*entityLdf(j);
            newPd(mappedBus(j))=newPd(mappedBus(j))+allocated;
            rows(end+1,:)={hour,entity,busNo(entityRows(j)),total,entityLdf(j),allocated,"已分配"}; %#ok<AGROW>
        end
    else
        for j=1:numel(entityRows)
            rows(end+1,:)={hour,entity,busNo(entityRows(j)),total,entityLdf(j),nan,message}; %#ok<AGROW>
        end
    end
end

scheduleOnly=unique(scheduleNames(~ismember(scheduleNames,uniqueEntities) & strlength(scheduleNames)>0));
unmatchedEntities=[unmatchedEntities;scheduleOnly];
allocatedTotal=sum(newPd);
allocationError=allocatedTotal-scheduledTotal;
allocationSuccess=scheduledTotal>0 && isempty(unmatchedEntities) && ...
    unmatchedBusCount==0 && invalidValueCount==0 && ...
    abs(allocationError)<=mwTolerance;

if allocationSuccess
    baseBusPd=to_numeric(data.Bus.('Pd'));
    baseBusQd=to_numeric(data.Bus.('Qd'));
    for i=1:numel(newPd)
        if isfinite(baseBusPd(i)) && baseBusPd(i)~=0 && isfinite(baseBusQd(i))
            newQd(i)=newPd(i)*baseBusQd(i)/baseBusPd(i);
        end
    end
    if any(~isfinite(newPd)) || any(~isfinite(newQd)) || any(newPd<0)
        allocationSuccess=false;
        invalidValueCount=invalidValueCount+1;
    end
end

if allocationSuccess
    mpc.bus(:,3)=newPd;
    mpc.bus(:,4)=newQd;
    message="负荷时序分配校验通过并已提交";
else
    mpc.bus(:,3)=basePd;
    mpc.bus(:,4)=baseQd;
    message="负荷时序分配失败，已保留 Bus 基准 Pd/Qd";
    warning('case1354:InvalidLoadAllocation', ...
        'Hour%d: %s；计划=%.6f MW，临时分配=%.6f MW，误差=%.6f MW。', ...
        hour,message,scheduledTotal,allocatedTotal,allocationError);
end

if isempty(rows)
    allocation=empty_allocation();
else
    allocation=cell2table(rows,'VariableNames',{'Hour','LoadEntityName','BusNo', ...
        'ScheduledEntityLoadMW','LDF','AllocatedBusLoadMW','Status'});
end
summary=make_summary(hour,scheduledTotal,allocatedTotal,allocationError, ...
    numel(unique(unmatchedEntities)),unmatchedBusCount,invalidValueCount, ...
    allocationSuccess,message);
end

function summary=make_summary(hour,scheduled,allocated,errorMW,unmatchedEntity,unmatchedBus,invalidCount,success,message)
summary=table(hour,scheduled,allocated,errorMW,unmatchedEntity,unmatchedBus, ...
    invalidCount,logical(success),string(message), ...
    'VariableNames',{'Hour','ScheduledTotalLoadMW','AllocatedTotalLoadMW', ...
    'AllocationErrorMW','UnmatchedEntityCount','UnmatchedBusCount', ...
    'InvalidValueCount','AllocationSuccess','Message'});
end

function allocation=empty_allocation()
allocation=table(zeros(0,1),strings(0,1),zeros(0,1),zeros(0,1), ...
    zeros(0,1),zeros(0,1),strings(0,1), ...
    'VariableNames',{'Hour','LoadEntityName','BusNo','ScheduledEntityLoadMW', ...
    'LDF','AllocatedBusLoadMW','Status'});
end

function value=get_config(config,name,defaultValue)
if isfield(config,name), value=double(config.(name)); else, value=defaultValue; end
end

function values=to_numeric(values)
if ~isnumeric(values), values=str2double(string(values)); end
values=double(values);
end

function message=join_message(message,part)
if strlength(message)==0, message=string(part); else, message=message+"；"+string(part); end
end

function [mpc, scheduleInfo] = apply_generator_schedule(mpc,data,hour,config)
%APPLY_GENERATOR_SCHEDULE 使用 GeneratorSchedule 设置机组计划。
% MarketType=A 的无能量报价机组按 GenType 建模；普通竞价机组只把计划作为初值。

scheduleInfo=empty_schedule_table();
if ~isfield(config,'useGeneratorSchedule') || ~config.useGeneratorSchedule
    return;
end

scheduleModel="technology_specific";
if isfield(config,'scheduledGeneratorModel')
    scheduleModel=lower(string(config.scheduledGeneratorModel));
elseif isfield(config,'fixMarketTypeASchedule')&&logical(config.fixMarketTypeASchedule)
    scheduleModel="legacy_fixed";
end

tbl=data.GeneratorSchedule;
col="Hour"+hour;
if isempty(tbl) || ~ismember(col,tbl.Properties.VariableNames)
    return;
end

names=case1354_generator_names(data.Generator,data.Initial);
scheduleNames=normalize_generator_names(tbl.('GenName'));
marketType=strtrim(string(data.Generator.('MarketType')));
genType=strtrim(string(data.Generator.('GenType')));

outHour=zeros(0,1);
outRow=zeros(0,1);
outName=strings(0,1);
outMarketType=strings(0,1);
outGenType=strings(0,1);
outMarketModel=strings(0,1);
outInput=zeros(0,1);
outApplied=zeros(0,1);
outPhysicalPmin=zeros(0,1);
outPhysicalPmax=zeros(0,1);
outAvailable=zeros(0,1);
outDeviationPenalty=zeros(0,1);
outCurtailmentPenalty=zeros(0,1);
outNote=strings(0,1);
outFixed=false(0,1);
outClipped=false(0,1);

for i=1:numel(names)
    ix=find(scheduleNames==names(i),1);
    if isempty(ix), continue; end

    p=tbl.(col)(ix);
    if ~isnumeric(p), p=str2double(string(p)); end
    p=double(p);
    if ~isfinite(p), continue; end

    originalPmin=mpc.gen(i,10);
    originalPmax=mpc.gen(i,9);
    appliedP=min(max(p,originalPmin),originalPmax);
    clipped=abs(appliedP-p)>1e-8;
    isTypeA=strcmpi(marketType(i),"A");
    isFixed=isTypeA&&scheduleModel=="legacy_fixed";

    if isTypeA&&scheduleModel=="technology_specific"
        model=scheduled_generator_model(genType(i),originalPmin,originalPmax,p,config);
        mpc.gen(i,2)=model.InitialPg;
        mpc.gen(i,9)=model.Pmax;
        mpc.gen(i,10)=model.Pmin;
    else
        model=legacy_model(genType(i),originalPmin,originalPmax,appliedP,isFixed);
        mpc.gen(i,2)=appliedP;
    end
    if isFixed
        % 计划出力超过物理上下限时采用物理边界，并在输出中明确标记 Clipped。
        mpc.gen(i,9)=appliedP;
        mpc.gen(i,10)=appliedP;
    end

    outHour(end+1,1)=hour; %#ok<AGROW>
    outRow(end+1,1)=i; %#ok<AGROW>
    outName(end+1,1)=names(i); %#ok<AGROW>
    outMarketType(end+1,1)=marketType(i); %#ok<AGROW>
    outGenType(end+1,1)=genType(i); %#ok<AGROW>
    outMarketModel(end+1,1)=model.MarketModel; %#ok<AGROW>
    outInput(end+1,1)=p; %#ok<AGROW>
    outApplied(end+1,1)=mpc.gen(i,2); %#ok<AGROW>
    outPhysicalPmin(end+1,1)=originalPmin; %#ok<AGROW>
    outPhysicalPmax(end+1,1)=originalPmax; %#ok<AGROW>
    outAvailable(end+1,1)=model.AvailablePowerMW; %#ok<AGROW>
    outDeviationPenalty(end+1,1)=model.DeviationPenalty; %#ok<AGROW>
    outCurtailmentPenalty(end+1,1)=model.CurtailmentPenalty; %#ok<AGROW>
    outNote(end+1,1)=model.ModelNote; %#ok<AGROW>
    outFixed(end+1,1)=isFixed; %#ok<AGROW>
    outClipped(end+1,1)=clipped; %#ok<AGROW>
end

scheduleInfo=table(outHour,outRow,outName,outMarketType,outGenType,outMarketModel,outInput, ...
    outApplied,outPhysicalPmin,outPhysicalPmax,outAvailable,outDeviationPenalty, ...
    outCurtailmentPenalty,outFixed,outClipped,outNote, ...
    'VariableNames',{'Hour','GeneratorRow','GenName','MarketType','GenType','MarketModel', ...
    'InputScheduledPgMW','AppliedScheduledPgMW','PhysicalPminMW','PhysicalPmaxMW', ...
    'AvailablePowerMW','DeviationPenalty','CurtailmentPenalty','FixedBySchedule', ...
    'ScheduleClipped','ModelNote'});
end

function model=legacy_model(genType,pmin,pmax,pg,isFixed)
if isFixed,name="LegacyFixedSchedule";note="兼容模式：计划出力完全固定";
else,name="CompetitiveBid";note="计划值仅作为普通竞价机组初值";end
model=struct('GenType',string(genType),'MarketModel',name,'Pmin',pmin,'Pmax',pmax, ...
    'InitialPg',pg,'AvailablePowerMW',nan,'DeviationPenalty',nan, ...
    'CurtailmentPenalty',nan,'ModelNote',note);
end

function t=empty_schedule_table()
t=table(zeros(0,1),zeros(0,1),strings(0,1),strings(0,1),strings(0,1),strings(0,1), ...
    zeros(0,1),zeros(0,1),zeros(0,1),zeros(0,1),zeros(0,1),zeros(0,1), ...
    zeros(0,1),false(0,1),false(0,1),strings(0,1), ...
    'VariableNames',{'Hour','GeneratorRow','GenName','MarketType','GenType','MarketModel', ...
    'InputScheduledPgMW','AppliedScheduledPgMW','PhysicalPminMW','PhysicalPmaxMW', ...
    'AvailablePowerMW','DeviationPenalty','CurtailmentPenalty','FixedBySchedule', ...
    'ScheduleClipped','ModelNote'});
end

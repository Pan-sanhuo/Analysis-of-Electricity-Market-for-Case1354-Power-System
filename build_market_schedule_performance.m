function performance = build_market_schedule_performance(opf,meta,hour,resultValid)
%BUILD_MARKET_SCHEDULE_PERFORMANCE 计算计划偏差、新能源弃电及对应惩罚成本。
performance=empty_table();
if ~isfield(meta,'generatorSchedule')||isempty(meta.generatorSchedule)
    return;
end
s=meta.generatorSchedule;
keep=s.MarketModel~="CompetitiveBid";
s=s(keep,:);
if isempty(s),return;end
n=height(s);actual=nan(n,1);deviation=nan(n,1);curtailment=nan(n,1);
penaltyCost=nan(n,1);
if resultValid
    rows=double(s.GeneratorRow);
    valid=rows>=1&rows<=size(opf.gen,1);
    actual(valid)=opf.gen(rows(valid),2);
    deviation=actual-double(s.InputScheduledPgMW);
    renewable=s.MarketModel=="RenewableAvailability";
    curtailment(renewable)=max(0,double(s.AvailablePowerMW(renewable))-actual(renewable));
    penaltyCost(renewable)=curtailment(renewable).*double(s.CurtailmentPenalty(renewable));
    other=~renewable;
    penaltyCost(other)=abs(deviation(other)).*double(s.DeviationPenalty(other));
end
performance=table(repmat(hour,n,1),repmat(logical(resultValid),n,1), ...
    s.GeneratorRow,s.GenName,s.GenType,s.MarketModel,s.InputScheduledPgMW, ...
    s.AvailablePowerMW,actual,deviation,curtailment,penaltyCost,s.ModelNote, ...
    'VariableNames',{'Hour','ResultValid','GeneratorRow','GenName','GenType', ...
    'MarketModel','ScheduledPgMW','AvailablePowerMW','ActualPgMW', ...
    'ScheduleDeviationMW','CurtailmentMW','PenaltyCost','ModelNote'});
end

function t=empty_table()
t=table(zeros(0,1),false(0,1),zeros(0,1),strings(0,1),strings(0,1), ...
    strings(0,1),zeros(0,1),zeros(0,1),zeros(0,1),zeros(0,1),zeros(0,1), ...
    zeros(0,1),strings(0,1),'VariableNames',{'Hour','ResultValid','GeneratorRow', ...
    'GenName','GenType','MarketModel','ScheduledPgMW','AvailablePowerMW', ...
    'ActualPgMW','ScheduleDeviationMW','CurtailmentMW','PenaltyCost','ModelNote'});
end

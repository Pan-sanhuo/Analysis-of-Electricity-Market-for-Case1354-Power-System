function model = scheduled_generator_model(genType,physicalPmin,physicalPmax,schedulePg,config)
%SCHEDULED_GENERATOR_MODEL 按能源类型定义无能量报价计划机组的小时市场模型。
type=lower(strtrim(string(genType)));
physicalPmin=double(physicalPmin);physicalPmax=double(physicalPmax);
schedulePg=min(max(double(schedulePg),physicalPmin),physicalPmax);
model=struct('GenType',string(genType),'MarketModel',"ScheduleDeviation", ...
    'Pmin',physicalPmin,'Pmax',physicalPmax,'InitialPg',schedulePg, ...
    'AvailablePowerMW',nan,'DeviationPenalty',config_value(config, ...
    'scheduleDeviationPenalty',1000),'CurtailmentPenalty',nan, ...
    'CostX',[],'CostY',[],'ModelNote',"计划值作为基准，允许在物理范围内调整");

if any(type==["wind","solar","photovoltaic","pv"])
    available=max(0,min(schedulePg,physicalPmax));
    model.MarketModel="RenewableAvailability";
    model.Pmin=max(0,physicalPmin);
    model.Pmax=max(model.Pmin,available);
    model.InitialPg=model.Pmax;
    model.AvailablePowerMW=model.Pmax;
    model.CurtailmentPenalty=config_value(config,'renewableCurtailmentPenalty',800);
    model.DeviationPenalty=nan;
    model.CostX=[model.Pmin;model.Pmax];
    model.CostY=[model.CurtailmentPenalty*(model.Pmax-model.Pmin);0];
    model.ModelNote="预测计划作为可用功率上限，允许经济弃电";
elseif type=="nuclear"
    model.MarketModel="NuclearScheduleDeviation";
    model.DeviationPenalty=config_value(config,'nuclearScheduleDeviationPenalty',1000);
    model.ModelNote="保留物理上下限，并惩罚偏离核电计划值";
elseif any(type==["hydro","water"])
    model.MarketModel="HydroHourlyProxy";
    model.DeviationPenalty=config_value(config,'hydroScheduleDeviationPenalty',300);
    model.ModelNote="小时计划偏差代理；日水量和库容约束需联合多时段模型";
end

if isempty(model.CostX)
    x=unique([model.Pmin;schedulePg;model.Pmax],'sorted');
    y=model.DeviationPenalty*abs(x-schedulePg);
    if numel(x)==1
        x=[x;x+1e-6];y=[0;model.DeviationPenalty*1e-6];
    end
    model.CostX=x;model.CostY=y;
end
end

function value=config_value(config,name,defaultValue)
if isfield(config,name)&&isscalar(config.(name))&&isfinite(config.(name))&&config.(name)>=0
    value=double(config.(name));
else
    value=defaultValue;
end
end

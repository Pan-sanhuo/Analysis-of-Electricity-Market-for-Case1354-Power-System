function validation = validate_case1354_input(data, config)
%VALIDATE_CASE1354_INPUT 对 Excel 输入做可追溯的数据质量检查。
% Severe/Error 会由主程序阻止 OPF；Warning 只写入 DataValidation 工作表。
if nargin < 2, config = struct(); end
rows = cell(0,5);
try
    settings=market_settings(config);
catch ME
    settings=[];
    add('MarketConfig','config','Error',ME.message,'修正 marketMode、missingBidPolicy、bidMWMode 和价格上下限配置。');
end
ldfTolerance=1e-6;
if isfield(config,'loadLdfTolerance'),ldfTolerance=double(config.loadLdfTolerance);end
    function add(type, object, severity, message, action)
        rows(end+1,:) = {string(type),string(object),string(severity),string(message),string(action)};
    end
bus = data.Bus; branch = data.Branch; gen = data.Generator;
busNo = numcol(bus,'BusNo');
if any(isnan(busNo)) || any(busNo ~= round(busNo))
    add('BusNo','Bus','Error','BusNo 存在空值或非整数。','修正 Bus 工作表的 BusNo。');
end
if numel(unique(busNo)) ~= numel(busNo)
    add('BusNo','Bus','Error','BusNo 存在重复值。','每个母线必须唯一。');
end
bt = numcol(bus,'BusType'); nRef = sum(bt == 3);
if nRef ~= 1
    add('SlackBus','Bus','Error',sprintf('检测到 %d 个平衡母线，必须恰好为 1 个。',nRef),'将唯一参考母线的 BusType 设置为 3。');
end
f = numcol(branch,'FromBus'); t = numcol(branch,'ToBus');
if any(~ismember(f,busNo) | ~ismember(t,busNo))
    add('BranchBus','Branch','Error','支路首端或末端母线不在 Bus 表中。','修正 FromBus/ToBus 或补充对应母线。');
end
gb = numcol(gen,'BusNo');
if any(~ismember(gb,busNo))
    add('GeneratorBus','Generator','Error','存在机组接入的母线不在 Bus 表中。','修正 Generator.BusNo。');
end
pmin=numcol(gen,'Pmin（MW）'); pmax=numcol(gen,'Pmax（MW）'); qmin=numcol(gen,'Qmin（MVAr）'); qmax=numcol(gen,'Qmax（MVAr）');
if any(pmin > pmax), add('GeneratorLimit','Generator','Error','存在 Pmin 大于 Pmax 的机组。','修正有功上下限（MW）。'); end
if any(qmin > qmax), add('GeneratorLimit','Generator','Error','存在 Qmin 大于 Qmax 的机组。','修正无功上下限（MVAr）。'); end
names = case1354_generator_names(gen,data.Initial);
if numel(unique(names)) ~= numel(names)
    add('GeneratorName','Generator','Error','唯一化后的机组名称仍重复。','在 Generator/Initial 中建立一一对应的机组名称。');
end
if height(data.Initial)~=height(gen)
    add('GeneratorMapping','Initial','Error', ...
        sprintf('Initial 有 %d 行、Generator 有 %d 行，无法按 GeneratorRow 建立永久对应。',height(data.Initial),height(gen)), ...
        '使 Initial 与 Generator 行数及行顺序保持一一对应。');
end
check_mapping('GeneratorSchedule',data.GeneratorSchedule,names);
check_mapping('GenBid',data.GenBid,names);
check_mapping('ASBid',data.ASBid,names);
ldf = numcol(data.LoadEntity,'LDF'); le = string(data.LoadEntity.('LoadEntityName'));
if any(~isfinite(ldf))
    add('LDF','LoadEntity','Error','LDF 存在 NaN 或 Inf。','修正所有无效 LDF 后再运行。');
end
if any(ldf<0)
    add('LDF','LoadEntity','Warning',sprintf('检测到 %d 个负 LDF；逐小时负荷分配将保留基准负荷并把模型标记为无效。',sum(ldf<0)), ...
        '核对负 LDF 是否为数据错误；若代表净注入，应改为独立发电/注入模型。');
end
for k=1:numel(unique(le))
    key=unique(le); key=key(k); total=sum(ldf(le==key),'omitnan');
    if abs(total-1)>ldfTolerance
        severity='Warning'; if abs(total-1)>0.01, severity='Error'; end
        add('LDF',key,severity,sprintf('LDF 之和为 %.10g，超出 %.3g 容差。',total,ldfTolerance),'修正 LDF；建模阶段不会静默归一化无效数据。');
    end
end
requiredHours = "Hour" + string(1:24);
if ~all(ismember(requiredHours,string(data.LoadSchedule.Properties.VariableNames)))
    add('LoadSchedule','LoadSchedule','Error','LoadSchedule 缺少 Hour1 至 Hour24 中的列。','补齐 24 个小时列。');
end
x=numcol(branch,'X'); r=numcol(branch,'R'); ra=numcol(branch,'Rate1');
if any(x==0), add('BranchX','Branch','Warning','检测到 X=0 的支路，可能导致数值病态。','检查零电抗是否为数据录入错误。'); end
if any(abs(r./max(abs(x),eps))>10), add('BranchRX','Branch','Warning','检测到异常大的 R/X 比值。','核对支路单位和阻抗数据。'); end
if any(ra<0), add('BranchRate','Branch','Error','检测到负的 Rate1。','线路热稳定限额必须为非负值。'); end
if ~isempty(settings),validate_bids();end
if isempty(rows)
    rows = {'Input','All','Info','未发现阻止运行的输入错误。','可继续执行 OPF。'};
end
validation = cell2table(rows,'VariableNames',{'CheckType','ObjectName','Severity','Message','SuggestedAction'});
    function check_mapping(sheet,tbl,validNames)
        if ~ismember('GenName',tbl.Properties.VariableNames), return; end
        n=normalize_generator_names(tbl.('GenName'));
        bad=unique(n(~ismember(n,validNames)));
        if ~isempty(bad), add('GeneratorMapping',sheet,'Warning',"未匹配机组: "+strjoin(bad,', '),'核对 Generator 与 '+string(sheet)+' 的 GenName。'); end
    end
    function validate_bids()
        b=data.GenBid;
        if isempty(b) || ~ismember('GenName',b.Properties.VariableNames), return; end
        for ii=1:height(b)
            p=[]; q=[];
            for jj=1:12
                pc="SegMW"+jj; qc="SegPrc"+jj;
                if ismember(pc,b.Properties.VariableNames) && ismember(qc,b.Properties.VariableNames)
                    pv=numcol(b,pc); qv=numcol(b,qc);
                    if isfinite(pv(ii))
                        if ~isfinite(qv(ii))
                            add('GenBidPrice',string(b.('GenName')(ii)),'Error', ...
                                sprintf('SegMW%d 已填写但对应 SegPrc%d 为 NaN/Inf。',jj,jj), ...
                                '补齐价格或清空该报价点。');
                        else
                            p(end+1)=pv(ii);q(end+1)=qv(ii); %#ok<AGROW>
                        end
                    end
                end
            end
            if ~isempty(q)
                bad=q<settings.priceFloor|q>settings.priceCap;
                if any(bad)
                    add('GenBidPriceBand',string(b.('GenName')(ii)),'Error', ...
                        sprintf('报价 %.10g 超出价格带 [%.10g, %.10g]，疑似价格单位错误。', ...
                        q(find(bad,1)),settings.priceFloor,settings.priceCap), ...
                        '核对元/MWh单位，或显式调整 marketPriceFloor/marketPriceCap。');
                end
            end
            if settings.bidMWMode=="breakpoint" && numel(p)>1 && any(diff(p)<=0)
                add('GenBidMW',string(b.('GenName')(ii)),'Error', ...
                    'bidMWMode=breakpoint，但 SegMW 未严格递增。', ...
                    '按累计功率点严格递增填写，或显式设置 bidMWMode=segment_capacity。');
            elseif settings.bidMWMode=="segment_capacity" && any(p<=0)
                add('GenBidMW',string(b.('GenName')(ii)),'Error', ...
                    'bidMWMode=segment_capacity，但存在非正分段容量。', ...
                    '每个报价段容量必须为正。');
            end
            if numel(p)>1 && any(diff(q)<0)
                add('GenBid',string(b.('GenName')(ii)),'Warning','报价分段边际价格递减；该机组将在成本构造时按缺失报价策略处理。','按分段 MW 非负、边际价格非递减重新填写报价。');
            end
        end
    end
end

function v = numcol(tbl,name)
if ~ismember(name,tbl.Properties.VariableNames), v=nan(height(tbl),1); return; end
v = tbl.(name); if ~isnumeric(v), v=str2double(string(v)); end; v=double(v);
end

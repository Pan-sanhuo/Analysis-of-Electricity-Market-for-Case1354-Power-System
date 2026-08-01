function [gencost, gen, curves, issues] = build_gencost_matrix(data, gen, names, hour, config)
%BUILD_GENCOST_MATRIX 将 GenBid 分段报价转为 MATPOWER PWL 成本函数。
% 默认情况下，缺失/无效报价不会改变机组原始状态，而是使用可追溯的非零
% 默认边际报价。只有 missingBidPolicy='exclude_generator' 才允许停运机组。

settings=market_settings(config);
policy=settings.missingBidPolicy;

bid=data.GenBid;
bidRawName=string(bid.('GenName'));
bidNormalizedName=normalize_generator_names(bidRawName);
bidHour=num(bid,'Hour',nan);
[fallbackPrice,fallbackSource]=resolve_default_price(bid,hour,config);
marketType=strtrim(string(data.Generator.('MarketType')));
genType=strtrim(string(data.Generator.('GenType')));
physicalPmin=num(data.Generator,'Pmin（MW）',0);
physicalPmax=num(data.Generator,'Pmax（MW）',0);

nG=size(gen,1);
gencost=zeros(nG,4+2*13); % 12 个报价段加 0 MW 起点，最多 13 个 PWL 点。
curves=cell(0,9);

issueHour=zeros(0,1);
issueGenRow=zeros(0,1);
issueGenName=strings(0,1);
issueNormalizedName=strings(0,1);
issueGenType=strings(0,1);
issueMarketModel=strings(0,1);
issueFailureCategory=strings(0,1);
issueMarketMode=strings(0,1);
issueBidMWMode=strings(0,1);
issuePriceFloor=zeros(0,1);
issuePriceCap=zeros(0,1);
issueNameMatchCount=zeros(0,1);
issueHourMatchCount=zeros(0,1);
issueMatchedRows=strings(0,1);
issueMatchedNames=strings(0,1);
issueValidSegmentCount=zeros(0,1);
issueReason=strings(0,1);
issuePolicy=strings(0,1);
issueAction=strings(0,1);
issueOriginalStatus=zeros(0,1);
issueFinalStatus=zeros(0,1);
issueDefaultPrice=zeros(0,1);
issueDefaultPriceSource=strings(0,1);
issueBidSource=strings(0,1);
issueScheduledPg=zeros(0,1);
issueAppliedScheduledPg=zeros(0,1);
issueScheduleClipped=false(0,1);
issueSegMW=zeros(0,12);
issueSegPrc=zeros(0,12);
scheduledSourceCount=0;
defaultPriceCount=0;
excludedCount=0;

for i=1:nG
    nameRows=find(bidNormalizedName==names(i));
    matchedRows=find(bidNormalizedName==names(i) & bidHour==hour);
    rows=bid(matchedRows,:);
    [segMW,segPrc]=read_segment_values(rows);
    tseg=nan;
    if height(rows)==1 && ismember('Tseg',rows.Properties.VariableNames)
        value=num(rows,'Tseg',nan);
        tseg=value(1);
    end
    [scheduledPg,appliedScheduledPg,scheduleClipped]= ...
        get_schedule_trace(data.GeneratorSchedule,names(i),hour,gen(i,2));
    isScheduledSource=strcmpi(marketType(i),"A") && numel(matchedRows)==1 && ...
        tseg==0 && isfinite(scheduledPg);

    if isempty(matchedRows)
        x=[]; y=[]; ok=false;
        if isempty(nameRows)
            msg='标准化名称在 GenBid 中未匹配到任何行';
        else
            msg=sprintf('名称匹配到 %d 行，但 Hour%d 匹配到 0 行',numel(nameRows),hour);
        end
    elseif numel(matchedRows)>1
        x=[]; y=[]; ok=false;
        msg=sprintf('标准化名称和 Hour%d 匹配到 %d 行，无法唯一确定报价',hour,numel(matchedRows));
    else
        [x,y,ok,msg]=points(rows,gen(i,10),gen(i,9),settings);
    end

    originalStatus=gen(i,8);
    if ~ok
        action=""; %#ok<NASGU>
        rowPolicy=policy;
        rowDefaultPrice=fallbackPrice;
        rowDefaultSource=fallbackSource;
        bidSource="DefaultBidPrice";
        if isScheduledSource && policy~="exclude_generator"
            scheduleMode=get_schedule_mode(config);
            model=scheduled_generator_model(genType(i),physicalPmin(i),physicalPmax(i), ...
                scheduledPg,config);
            if scheduleMode=="legacy_fixed"
                x=[0;max(gen(i,9),1e-6)];y=[0;0];
                marketModel="LegacyFixedSchedule";
                rowPolicy="legacy_fixed_schedule";
                rowDefaultPrice=nan;
                rowDefaultSource="兼容模式：计划机组出力固定";
                action="兼容模式：固定为 GeneratorSchedule 计划出力";
            else
                x=model.CostX;y=model.CostY;
                marketModel=model.MarketModel;
                rowPolicy="technology_specific_schedule";
                if model.MarketModel=="RenewableAvailability"
                    rowDefaultPrice=model.CurtailmentPenalty;
                    rowDefaultSource="config.renewableCurtailmentPenalty/默认800";
                    action="可再生能源：计划值作为可用功率上限，允许弃电并计罚";
                else
                    rowDefaultPrice=model.DeviationPenalty;
                    rowDefaultSource="对应技术类型的计划偏差惩罚参数";
                    action="计划机组：保留物理范围，按偏离计划值计罚";
                end
            end
            msg='MarketType=A 且 Tseg=0：使用按 GenType 区分的计划机组市场模型';
            bidSource="GeneratorScheduleTechnologyModel";
            scheduledSourceCount=scheduledSourceCount+1;
        else
            marketModel="CompetitiveBidFallback";
            switch policy
                case "exclude_generator"
                gen(i,8)=0;
                gen(i,2:3)=0;
                x=[0;max(gen(i,9),0)];
                y=[0;0];
                action="显式策略 exclude_generator：机组停运";
                excludedCount=excludedCount+1;
                case "warning_and_default"
                    % 仅用于真正缺失/无效的竞价机组，不用于 MarketType=A 计划机组。
                    x=[0;max(gen(i,9),0)];
                    y=[0;max(gen(i,9),0)*fallbackPrice];
                    action="保留原始状态，使用可追溯默认边际报价";
                    defaultPriceCount=defaultPriceCount+1;
                otherwise
                    error('case1354:MissingBid', ...
                        '机组 %s 在 Hour%d 缺少唯一有效报价: %s。',names(i),hour,msg);
            end
        end

        issueHour(end+1,1)=hour; %#ok<AGROW>
        issueGenRow(end+1,1)=i; %#ok<AGROW>
        issueGenName(end+1,1)=string(data.Generator.('GenName')(i)); %#ok<AGROW>
        issueNormalizedName(end+1,1)=names(i); %#ok<AGROW>
        issueGenType(end+1,1)=genType(i); %#ok<AGROW>
        issueMarketModel(end+1,1)=marketModel; %#ok<AGROW>
        issueFailureCategory(end+1,1)=classify_bid_issue(msg,marketModel); %#ok<AGROW>
        issueMarketMode(end+1,1)=settings.marketMode; %#ok<AGROW>
        issueBidMWMode(end+1,1)=settings.bidMWMode; %#ok<AGROW>
        issuePriceFloor(end+1,1)=settings.priceFloor; %#ok<AGROW>
        issuePriceCap(end+1,1)=settings.priceCap; %#ok<AGROW>
        issueNameMatchCount(end+1,1)=numel(nameRows); %#ok<AGROW>
        issueHourMatchCount(end+1,1)=numel(matchedRows); %#ok<AGROW>
        issueMatchedRows(end+1,1)=join_or_empty(string(matchedRows.')); %#ok<AGROW>
        issueMatchedNames(end+1,1)=join_or_empty(unique(bidRawName(matchedRows),'stable')); %#ok<AGROW>
        issueValidSegmentCount(end+1,1)=sum(isfinite(segMW) & isfinite(segPrc) & segMW>0); %#ok<AGROW>
        issueReason(end+1,1)=string(msg); %#ok<AGROW>
        issuePolicy(end+1,1)=rowPolicy; %#ok<AGROW>
        issueAction(end+1,1)=action; %#ok<AGROW>
        issueOriginalStatus(end+1,1)=originalStatus; %#ok<AGROW>
        issueFinalStatus(end+1,1)=gen(i,8); %#ok<AGROW>
        issueDefaultPrice(end+1,1)=rowDefaultPrice; %#ok<AGROW>
        issueDefaultPriceSource(end+1,1)=rowDefaultSource; %#ok<AGROW>
        issueBidSource(end+1,1)=bidSource; %#ok<AGROW>
        issueScheduledPg(end+1,1)=scheduledPg; %#ok<AGROW>
        issueAppliedScheduledPg(end+1,1)=appliedScheduledPg; %#ok<AGROW>
        issueScheduleClipped(end+1,1)=scheduleClipped; %#ok<AGROW>
        issueSegMW(end+1,:)=segMW; %#ok<AGROW>
        issueSegPrc(end+1,:)=segPrc; %#ok<AGROW>
    end

    np=numel(x);
    gencost(i,1:4)=[1 0 0 np];
    gencost(i,5:4+2*np)=reshape([x(:) y(:)].',1,[]);
    curves(end+1,:)={hour,names(i),mat2str(x.'),mat2str(y.'),ok, ...
        settings.marketMode,settings.bidMWMode,settings.priceFloor,settings.priceCap}; %#ok<AGROW>
end

curves=cell2table(curves,'VariableNames', ...
    {'Hour','GenName','PowerBreakpointsMW','CostBreakpoints','BidValid', ...
    'MarketMode','BidMWMode','PriceFloor','PriceCap'});

issues=table(issueHour,issueGenRow,issueGenName,issueNormalizedName, ...
    issueGenType,issueMarketModel,issueFailureCategory,issueMarketMode, ...
    issueBidMWMode,issuePriceFloor,issuePriceCap, ...
    issueNameMatchCount,issueHourMatchCount,issueMatchedRows,issueMatchedNames, ...
    issueValidSegmentCount,issueReason,issuePolicy,issueAction, ...
    issueOriginalStatus,issueFinalStatus,issueDefaultPrice,issueDefaultPriceSource, ...
    issueBidSource,issueScheduledPg,issueAppliedScheduledPg,issueScheduleClipped, ...
    'VariableNames',{'Hour','GeneratorRow','GeneratorName', ...
    'NormalizedGeneratorName','GenType','MarketModel','FailureCategory', ...
    'MarketMode','BidMWMode','PriceFloor','PriceCap', ...
    'NameMatchedRowCount','HourMatchedRowCount', ...
    'MatchedGenBidRowIndices','MatchedGenBidNames','ValidSegmentCount', ...
    'FailureReason','MissingBidPolicy','Action','OriginalStatus','FinalStatus', ...
    'DefaultMarginalPrice','DefaultPriceSource','BidSource','ScheduledPgMW', ...
    'AppliedScheduledPgMW','ScheduleClipped'});
for k=1:12
    issues.("SegMW"+k)=issueSegMW(:,k);
    issues.("SegPrc"+k)=issueSegPrc(:,k);
end

if scheduledSourceCount>0
    warning('case1354:ScheduledNonBiddingGenerator', ...
        ['Hour%d: 识别到 %d 台 MarketType=A、Tseg=0 的计划机组；' ...
         '已按 GenType 使用计划偏差/新能源弃电模型，不再统一固定出力。'], ...
        hour,scheduledSourceCount);
end

if defaultPriceCount>0
        warning('case1354:MissingBid', ...
            ['Hour%d: %d 台机组缺少唯一有效报价；保留原始状态并使用 %.6g 元/MWh。' ...
             '详细匹配过程见 BidValidation。'], ...
            hour,defaultPriceCount,fallbackPrice);
end
if excludedCount>0
    warning('case1354:ExcludedGenerator', ...
        'Hour%d: 按显式 exclude_generator 策略停运 %d 台机组，详见 BidValidation。', ...
        hour,excludedCount);
end
end

function mode=get_schedule_mode(config)
if isfield(config,'scheduledGeneratorModel')
    mode=lower(string(config.scheduledGeneratorModel));
elseif isfield(config,'fixMarketTypeASchedule')&&logical(config.fixMarketTypeASchedule)
    mode="legacy_fixed";
else
    mode="technology_specific";
end
end

function category=classify_bid_issue(message,marketModel)
message=string(message);
if marketModel~="CompetitiveBidFallback"
    category="ScheduledNoEnergyBid";
elseif contains(message,"价格带")
    category="PriceOutOfRangeOrUnit";
elseif contains(message,"NaN/Inf")
    category="NumericalPriceInvalid";
elseif contains(message,"SegMW")||contains(message,"breakpoint")||contains(message,"segment_capacity")
    category="BidMWDefinitionInvalid";
elseif contains(message,"未匹配")||contains(message,"匹配到")
    category="BidMissingOrAmbiguous";
else
    category="BidCurveInvalid";
end
end

function [x,y,ok,msg]=points(rows,pmin,pmax,settings)
ok=false;
msg='未找到 GenBid 行';
x=[];
y=[];
if isempty(rows), return; end

[segMW,segPrc]=read_segment_values(rows);
present=isfinite(segMW);
if any(present & ~isfinite(segPrc))
    msg='存在已填写 SegMW 但 SegPrc 为 NaN/Inf 的报价点';
    return;
end
active=isfinite(segMW) & isfinite(segPrc);
segMW=segMW(active);
segPrc=segPrc(active);
if isempty(segMW)
    msg='已唯一匹配 GenBid 行，但没有有效的报价功率点';
    return;
end

x=segMW(:);
price=segPrc(:);
if any(price<settings.priceFloor|price>settings.priceCap)
    msg=sprintf('报价超出价格带 [%.10g, %.10g]，可能存在价格单位错误', ...
        settings.priceFloor,settings.priceCap);
    return;
end
if settings.bidMWMode=="breakpoint"
    if any(diff(x)<=0)
        msg='bidMWMode=breakpoint，但 SegMW 未严格递增；不会自动改写为分段容量';
        return;
    end
else
    if any(x<=0)
        msg='bidMWMode=segment_capacity，但存在非正的分段容量';
        return;
    end
    x=cumsum(x);
end
if any(diff(price)<0)
    msg='边际报价递减';
    return;
end

if x(1)>pmin
    x=[pmin;x];
    price=[price(1);price];
end
if x(end)<pmax
    x=[x;pmax];
    price=[price;price(end)];
end
x=max(x,pmin);
x=min(x,pmax);
[x,ia]=unique(x,'stable');
price=price(ia);

if numel(x)<2 || pmax<pmin
    msg='Pmin/Pmax 或报价点无效';
    return;
end

% MATPOWER PWL 的纵坐标是累计成本，不是边际价格。
y=zeros(size(x));
for k=2:numel(x)
    y(k)=y(k-1)+(x(k)-x(k-1))*price(k);
end
ok=true;
msg='';
end

function [segMW,segPrc]=read_segment_values(rows)
segMW=nan(1,12);
segPrc=nan(1,12);
if isempty(rows), return; end
row=rows(1,:);
for k=1:12
    mwCol="SegMW"+k;
    prcCol="SegPrc"+k;
    if ismember(mwCol,row.Properties.VariableNames)
        v=num(row,mwCol,nan);
        segMW(k)=v(1);
    end
    if ismember(prcCol,row.Properties.VariableNames)
        v=num(row,prcCol,nan);
        segPrc(k)=v(1);
    end
end
end

function [price,source]=resolve_default_price(bid,hour,config)
settings=market_settings(config);
if isfield(config,'defaultBidPrice') && isscalar(config.defaultBidPrice) && ...
        isfinite(config.defaultBidPrice) && config.defaultBidPrice>=settings.priceFloor && ...
        config.defaultBidPrice<=settings.priceCap
    price=double(config.defaultBidPrice);
    source="config.defaultBidPrice";
    return;
end

hourRows=bid;
if ismember('Hour',bid.Properties.VariableNames)
    hourRows=bid(num(bid,'Hour',nan)==hour,:);
end
validPrices=zeros(0,1);
for k=1:12
    mwCol="SegMW"+k;
    prcCol="SegPrc"+k;
    if ismember(mwCol,hourRows.Properties.VariableNames) && ...
            ismember(prcCol,hourRows.Properties.VariableNames)
        mw=num(hourRows,mwCol,nan);
        prc=num(hourRows,prcCol,nan);
        use=isfinite(mw) & isfinite(prc) & ...
            prc>=settings.priceFloor & prc<=settings.priceCap;
        validPrices=[validPrices;prc(use)]; %#ok<AGROW>
    end
end
if isempty(validPrices)
    price=min(max(1000,settings.priceFloor),settings.priceCap);
    source="安全回退值：本小时没有位于价格带内的有效报价点";
else
    price=median(validPrices);
    source="本小时价格带内有效报价点的边际价格中位数";
end
end

function [inputPg,appliedPg,clipped]=get_schedule_trace(scheduleTbl,name,hour,currentPg)
inputPg=nan;
appliedPg=currentPg;
clipped=false;
if isempty(scheduleTbl), return; end
hourCol="Hour"+hour;
if ~ismember('GenName',scheduleTbl.Properties.VariableNames) || ...
        ~ismember(hourCol,scheduleTbl.Properties.VariableNames)
    return;
end
scheduleNames=normalize_generator_names(scheduleTbl.('GenName'));
ix=find(scheduleNames==name,1);
if isempty(ix), return; end
values=num(scheduleTbl,hourCol,nan);
inputPg=values(ix);
if isfinite(inputPg)
    clipped=abs(inputPg-appliedPg)>1e-8;
end
end

function value=join_or_empty(values)
values=string(values);
if isempty(values)
    value="";
else
    value=strjoin(values,",");
end
end

function v=num(t,c,d)
if ~ismember(c,t.Properties.VariableNames)
    v=d*ones(height(t),1);
else
    v=t.(c);
    if ~isnumeric(v), v=str2double(string(v)); end
    v=double(v);
end
end

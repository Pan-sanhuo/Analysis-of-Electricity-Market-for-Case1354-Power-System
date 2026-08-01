function settings = market_settings(config)
%MARKET_SETTINGS 统一报价解释、价格带和正式/调试市场策略。
settings.marketMode="production";
if isfield(config,'marketMode'),settings.marketMode=lower(string(config.marketMode));end
if ~any(settings.marketMode==["debug","production"])
    error('case1354:InvalidMarketMode','marketMode 必须为 debug 或 production。');
end
settings.bidMWMode="breakpoint";
if isfield(config,'bidMWMode'),settings.bidMWMode=lower(string(config.bidMWMode));end
if ~any(settings.bidMWMode==["breakpoint","segment_capacity"])
    error('case1354:InvalidBidMWMode', ...
        'bidMWMode 必须为 breakpoint 或 segment_capacity。');
end
settings.priceFloor=config_value(config,'marketPriceFloor',-1000);
settings.priceCap=config_value(config,'marketPriceCap',10000);
if settings.priceFloor>settings.priceCap
    error('case1354:InvalidPriceBand','marketPriceFloor 不能大于 marketPriceCap。');
end
if settings.marketMode=="production"
    settings.missingBidPolicy="error";
    if isfield(config,'missingBidPolicy')&&lower(string(config.missingBidPolicy))~="error"
        error('case1354:ProductionMissingBidPolicy', ...
            'production 模式只允许 missingBidPolicy=''error''；缺失普通竞价报价必须阻止出清。');
    end
else
    settings.missingBidPolicy="warning_and_default";
    if isfield(config,'missingBidPolicy'),settings.missingBidPolicy=lower(string(config.missingBidPolicy));end
end
if ~any(settings.missingBidPolicy==["error","warning_and_default","exclude_generator"])
    error('case1354:InvalidMissingBidPolicy', ...
        'missingBidPolicy 必须为 error、warning_and_default 或 exclude_generator。');
end
end

function value=config_value(config,name,defaultValue)
if isfield(config,name)&&isscalar(config.(name))&&isfinite(config.(name))
    value=double(config.(name));
else
    value=defaultValue;
end
end

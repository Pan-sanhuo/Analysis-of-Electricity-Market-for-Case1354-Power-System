function balance = calculate_power_balance(bus, gen, branch)
%CALCULATE_POWER_BALANCE 按 MATPOWER 支路两端功率口径计算全网功率平衡。
% Pf+Pt 是单条支路的有功损耗，不应除以 2；母线 Gs 还会消耗 Gs*Vm^2。

balance=struct( ...
    'TotalLoadMW',nan,'TotalGenerationMW',nan, ...
    'GenerationLoadDifferenceMW',nan,'BranchLossMW',nan,'BusShuntMW',nan, ...
    'PowerBalanceErrorMW',nan,'PowerBalanceAbsErrorMW',nan, ...
    'TotalLoadMVAr',nan,'TotalGenerationMVAr',nan, ...
    'BranchNetQMVAr',nan,'BusShuntQMVAr',nan,'ReactiveBalanceErrorMVAr',nan);

if isempty(bus) || isempty(gen) || size(bus,2)<8 || size(gen,2)<8
    return;
end

online=gen(:,8)>0;
balance.TotalLoadMW=sum(bus(:,3));
balance.TotalGenerationMW=sum(gen(online,2));
balance.GenerationLoadDifferenceMW=balance.TotalGenerationMW-balance.TotalLoadMW;
balance.BusShuntMW=sum(bus(:,5).*bus(:,8).^2);

balance.TotalLoadMVAr=sum(bus(:,4));
balance.TotalGenerationMVAr=sum(gen(online,3));
% MATPOWER 中母线并联无功消耗为 -Bs*Vm^2。
balance.BusShuntQMVAr=sum(-bus(:,6).*bus(:,8).^2);

if size(branch,2)>=17
    balance.BranchLossMW=sum(branch(:,14)+branch(:,16));
    balance.BranchNetQMVAr=sum(branch(:,15)+branch(:,17));
    balance.PowerBalanceErrorMW=balance.GenerationLoadDifferenceMW ...
        -balance.BranchLossMW-balance.BusShuntMW;
    balance.PowerBalanceAbsErrorMW=abs(balance.PowerBalanceErrorMW);
    balance.ReactiveBalanceErrorMVAr=balance.TotalGenerationMVAr ...
        -balance.TotalLoadMVAr-balance.BranchNetQMVAr-balance.BusShuntQMVAr;
end
end

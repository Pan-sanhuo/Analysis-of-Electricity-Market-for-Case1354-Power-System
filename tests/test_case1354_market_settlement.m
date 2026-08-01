function test_case1354_market_settlement
%TEST_CASE1354_MARKET_SETTLEMENT Focused Stage 10 settlement regression.
setup=case1354_test_setup();
out=fullfile(setup.outDir,'case1354_stage10_settlement.xlsx');
c=struct('targetHours',1,'mode','SCED','useIntertemporalRamp',false, ...
 'useAuxiliaryServices',false,'useDemandBids',false,'useSecurityConstraints',false, ...
 'marketMode','debug','missingBidPolicy','warning_and_default','outFile',out);
r=case1354_multiperiod_market(c);assert(r.success,'Stage 10 settlement case did not solve.');
out=r.outputExcel;n=readtable(out,'Sheet','NodalEnergyPrice','VariableNamingRule','preserve');
g=readtable(out,'Sheet','GeneratorSettlement','VariableNamingRule','preserve');
b=readtable(out,'Sheet','BranchLimitStatus','VariableNamingRule','preserve');
s=readtable(out,'Sheet','MarketSettlementSummary','VariableNamingRule','preserve');
assert(all(n.ResultValid)&all(isfinite(n.LMP)),'Successful hour contains invalid LMP.');
assert(all(g.ResultValid)&all(isfinite(g.EnergyRevenue)),'Generator settlement is invalid.');
assert(abs(sum(g.EnergyRevenue)-s.GeneratorEnergyRevenue)<1e-4,'Generator revenue does not reconcile.');
assert(abs(sum(n.ServedLoadMW.*n.LMP)-s.LoadEnergyPayment)<1e-4,'Load payment does not reconcile.');
assert(abs(s.LoadEnergyPayment-s.GeneratorEnergyRevenue-s.CongestionRent)<1e-4,'Congestion rent identity failed.');
assert(~any(g.AtPmax&g.AbovePmaxViolation),'At-limit and violation states were conflated.');
assert(~any(g.AtPmin&g.BelowPminViolation),'At-limit and violation states were conflated.');
assert(~any(b.AtRateLimit&b.RateLimitViolated),'Branch binding and violation states were conflated.');
assert(~s.ActualProductionCostAvailable&&isnan(s.ActualProductionCost),'Unavailable actual production cost was not explicit.');
disp('MARKET_SETTLEMENT_TEST_PASS');
end

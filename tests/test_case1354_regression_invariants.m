function test_case1354_regression_invariants
%TEST_CASE1354_REGRESSION_INVARIANTS Two-hour combined-market regression.
setup=case1354_test_setup();
out=fullfile(setup.outDir,'case1354_stage11_invariants.xlsx');
c=struct('targetHours',1:2,'mode','SCED','useIntertemporalRamp',true, ...
 'useAuxiliaryServices',true,'useDemandBids',true,'useSecurityConstraints',false, ...
 'marketMode','debug','missingBidPolicy','warning_and_default','outFile',out);
r=case1354_multiperiod_market(c);assert(r.success,'Combined two-hour market regression failed.');
out=r.outputExcel;
d=readtable(out,'Sheet','MultiPeriodDispatch','VariableNamingRule','preserve');
u=readtable(out,'Sheet','UnitCommitmentAudit','VariableNamingRule','preserve');
n=readtable(out,'Sheet','NodalEnergyPrice','VariableNamingRule','preserve');
dr=readtable(out,'Sheet','DemandResponse','VariableNamingRule','preserve');
s=readtable(out,'Sheet','MarketSettlementSummary','VariableNamingRule','preserve');
ng=sum(d.Hour==1);assert(ng>0&&sum(d.Hour==2)==ng,'Generator count changed between hours.');
assert(isequal(d.GeneratorRow(d.Hour==1),d.GeneratorRow(d.Hour==2)),'Generator order changed between hours.');
assert(all(isfinite(n.LMP))&&all(n.ResultValid),'Successful hours contain invalid LMP.');
for h=1:2
 assert(abs(sum(n.ServedLoadMW(n.Hour==h))-sum(dr.ServedLoadMW(dr.Hour==h)))<1e-4,'Demand allocation is not conserved.');
end
p1=d.PgMW(d.Hour==1);p2=d.PgMW(d.Hour==2);ramp=u.RampMWPerHour;
limited=isfinite(ramp)&ramp>0;assert(all(abs(p2(limited)-p1(limited))<=ramp(limited)+1e-5),'Inter-hour ramp limit violated.');
assert(all(isfinite(s.GeneratorEnergyRevenue)&isfinite(s.LoadEnergyPayment)),'Settlement metrics are invalid.');
disp('REGRESSION_INVARIANTS_TEST_PASS');
end

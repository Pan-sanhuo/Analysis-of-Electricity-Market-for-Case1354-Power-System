function ok=test_case1354_demand_response()
%TEST_CASE1354_DEMAND_RESPONSE Two-hour LoadBid social-welfare regression.
setup=case1354_test_setup();
out=fullfile(setup.outDir,'case1354_demand_regression.xlsx');
c=struct('targetHours',1:2,'mode','SCED','useAuxiliaryServices',false,'useDemandBids',true,'outFile',out,'verbose',0);
r=case1354_multiperiod_market(c);assert(r.success,'Demand-side market did not solve.');out=r.outputExcel;
d=readtable(out,'Sheet','DemandResponse','VariableNamingRule','preserve');s=readtable(out,'Sheet','DemandMarketSummary','VariableNamingRule','preserve');
assert(all(d.ServedLoadMW>=d.SelfScheduleMW-1e-5),'Inelastic self-schedule was curtailed.');
assert(all(d.ServedLoadMW<=d.MaximumBidLoadMW+1e-5),'Served load exceeds maximum bid.');
assert(all(abs(d.ServedLoadMW+d.CurtailedMW-d.MaximumBidLoadMW)<1e-5),'Demand quantity identity failed.');
assert(all(isfinite(s.ConsumerBenefit)&isfinite(s.LostUtility)),'Welfare outputs are not finite.');
mat=load(r.outputMat,'mdo','dr');
for t=1:2
 x=mat.mdo.mpc.baseMVA*mat.mdo.om.get_soln('var','DRCurt',{t});
 assert(all(x>=-1e-7&x<=mat.dr.SegmentCapacity(t,:).'+1e-5),'Curtailment segment bound failed.');
end
assert(all(mat.dr.LdfNormalizationError<1e-10),'LDF normalization failed.');ok=true;
end

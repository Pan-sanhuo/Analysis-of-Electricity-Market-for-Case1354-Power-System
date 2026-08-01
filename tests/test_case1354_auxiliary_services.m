function ok=test_case1354_auxiliary_services()
%TEST_CASE1354_AUXILIARY_SERVICES Two-hour joint energy/reserve regression.
setup=case1354_test_setup();
out=fullfile(setup.outDir,'case1354_as_regression.xlsx');
c=struct('targetHours',1:2,'mode','SCED','useAuxiliaryServices',true,'useDemandBids',false,'outFile',out,'verbose',0);
r=case1354_multiperiod_market(c);assert(r.success,'Joint energy/AS model did not solve.');
s=r.auxiliaryServiceSummary;
assert(all(s.ProcuredMW+s.ShortageMW>=s.MinimumMW-1e-5),'Reserve minimum or shortage identity failed.');
finiteMax=isfinite(s.MaximumMW);assert(all(s.ProcuredMW(finiteMax)<=s.MaximumMW(finiteMax)+1e-5),'Reserve maximum exceeded.');
out=r.outputExcel;mat=load(r.outputMat,'mdo','as');mdo=mat.mdo;as=mat.as;base=mdo.mpc.baseMVA;
for t=1:2
 pg=mdo.flow(t,1,1).mpc.gen(:,2);pmax=mdo.flow(t,1,1).mpc.gen(:,9);pmin=mdo.flow(t,1,1).mpc.gen(:,10);
 up=base*mdo.om.get_soln('var','AS_RegUp',{t});dn=base*mdo.om.get_soln('var','AS_RegDn',{t});
 spin=base*mdo.om.get_soln('var','AS_Spin',{t});nonspin=base*mdo.om.get_soln('var','AS_NonSpin',{t});
 assert(all(pg+up+spin+nonspin<=pmax+1e-5),'Energy/up-reserve Pmax coupling failed.');
 assert(all(pg-dn>=pmin-1e-5),'Energy/down-reserve Pmin coupling failed.');
 awards=[up dn spin nonspin];offers=squeeze(as.Quantity(t,:,:));self=squeeze(as.SelfSchedule(t,:,:));
 assert(all(awards(:)<=offers(:)+1e-5),'AS award exceeds qualified offer.');
 assert(all(awards(:)>=self(:)-1e-5),'AS self-schedule not honored.');
end
assert(all(sum(as.ZoneMatrix(2:end,:),2)>0),'One or more AS regions have no mapped generators.');
ok=true;
end

function test_case1354_security_constraints
%TEST_CASE1354_SECURITY_CONSTRAINTS Focused Stage 9 N-1 regression test.
setup=case1354_test_setup();
cfg=struct( ...
    'targetHours',1, ...
    'mode','SCED', ...
    'useIntertemporalRamp',false, ...
    'useAuxiliaryServices',true, ...
    'useDemandBids',false, ...
    'useSecurityConstraints',true, ...
    'securityScreeningMode','screened', ...
    'maxLineContingencies',2, ...
    'maxTransformerContingencies',1, ...
    'maxGeneratorContingencies',1, ...
    'runAcN1PostCheck',true, ...
    'maxAcN1PostChecks',2, ...
    'marketMode','debug', ...
    'missingBidPolicy','warning_and_default', ...
    'outFile',fullfile(setup.outDir,'case1354_stage9_security.xlsx'));
r=case1354_multiperiod_market(cfg);
assert(r.success,'Stage 9 security-constrained MOST model did not solve.');
audit=readtable(r.outputExcel,'Sheet','SecurityContingencyAudit','VariableNamingRule','preserve');
sr=readtable(r.outputExcel,'Sheet','SecurityContingencyResults','VariableNamingRule','preserve');
ac=readtable(r.outputExcel,'Sheet','ACN1PostCheck','VariableNamingRule','preserve');
included=audit(audit.Included,:);
assert(~isempty(included),'No N-1 contingency was included.');
assert(any(included.ElementType=="Line"),'No line outage was included.');
assert(any(included.ElementType=="Transformer"),'No transformer outage was included.');
assert(any(included.ElementType=="Generator"),'No generator outage was included.');
assert(height(sr)==r.mdo.idx.nc(1,1),'Scenario audit/result count mismatch.');
assert(all(sr.DCConstraintSatisfied),'A screened DC N-1 scenario violates a branch limit.');

basePg=r.mdo.flow(1,1,1).mpc.gen(:,2);
regUp=r.mdo.om.get_soln('var','AS_RegUp',{1})*r.mdo.mpc.baseMVA;
spin=r.mdo.om.get_soln('var','AS_Spin',{1})*r.mdo.mpc.baseMVA;
regDn=r.mdo.om.get_soln('var','AS_RegDn',{1})*r.mdo.mpc.baseMVA;
for k=2:r.mdo.idx.nc(1,1)+1
    pg=r.mdo.flow(1,1,k).mpc.gen(:,2);
    assert(all(pg-basePg<=regUp+spin+1e-5),'Contingency upward redispatch exceeds procured reserve.');
    checkRows=true(size(pg));failedGen=outaged_generator_row(r.mdo,k);
    if failedGen>0,checkRows(failedGen)=false;end
    assert(all(basePg(checkRows)-pg(checkRows)<=regDn(checkRows)+1e-5), ...
        'Contingency downward redispatch exceeds procured reserve.');
end
assert(~isempty(ac),'Missing AC N-1 post-check output.');
for k=1:height(ac)
    if ac.ACConverged(k)
        assert(isfinite(ac.MaxVoltageViolation(k))&&isfinite(ac.MaxBranchLoadingPercent(k)), ...
            'Converged AC N-1 check contains invalid metrics.');
    else
        assert(strlength(string(ac.Message(k)))>0,'Failed AC N-1 check has no diagnostic message.');
    end
end
disp('SECURITY_CONSTRAINT_TEST_PASS');
end

function g=outaged_generator_row(mdo,scenario)
g=0;tab=mdo.cont(1,1).contab;
[~,~,~,~,CT_TGEN]=idx_ct;[~,~,~,~,~,~,~,GEN_STATUS]=idx_gen;
labels=sort(unique(tab(:,1)));label=labels(scenario-1);
row=find(tab(:,1)==label&tab(:,3)==CT_TGEN&tab(:,5)==GEN_STATUS&tab(:,7)==0,1);
if ~isempty(row),g=tab(row,4);end
end

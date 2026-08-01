function tables=build_demand_response_results(mdo,dr,hours)
%BUILD_DEMAND_RESPONSE_RESULTS Report served load, curtailment and welfare.
tables=struct('DemandResponse',empty_detail(),'DemandMarketSummary',empty_summary(),'DemandAllocationAudit',empty_audit());
if ~isfield(mdo.results,'success')||~mdo.results.success,return;end
nt=numel(hours);ne=dr.EntityCount;detail=cell(0,11);summary=cell(0,8);
for t=1:nt
 curtSeg=mdo.mpc.baseMVA*mdo.om.get_soln('var','DRCurt',{t});
 curt=accumarray(dr.EntityOfSegment,curtSeg,[ne 1]);lost=accumarray(dr.EntityOfSegment,curtSeg.*dr.SegmentPrice(t,:).',[ne 1]);
 served=dr.MaximumLoadMW(t,:).'-curt;benefit=dr.MaximumUtility(t,:).'-lost;
 for e=1:ne
  detail(end+1,:)={hours(t),dr.Entities(e),dr.SelfScheduleMW(t,e),dr.MaximumLoadMW(t,e),dr.ScheduledLoadMW(t,e),curt(e),served(e),dr.MaximumUtility(t,e),lost(e),benefit(e),served(e)>=dr.SelfScheduleMW(t,e)-1e-6}; %#ok<AGROW>
 end
 objective=mdo.results.f;totalBenefit=sum(benefit);summary(end+1,:)={hours(t),sum(dr.MaximumLoadMW(t,:)),sum(served),sum(curt),totalBenefit,sum(lost),objective,totalBenefit-objective}; %#ok<AGROW>
end
tables.DemandResponse=cell2table(detail,'VariableNames',{'Hour','LoadEntityName','SelfScheduleMW','MaximumBidLoadMW','ReferenceScheduleMW','CurtailedMW','ServedLoadMW','MaximumUtility','LostUtility','ConsumerBenefit','SelfScheduleSatisfied'});
tables.DemandMarketSummary=cell2table(summary,'VariableNames',{'Hour','MaximumBidLoadMW','ServedLoadMW','CurtailedMW','ConsumerBenefit','LostUtility','TotalHorizonObjective','WelfareIndicator'});
tables.DemandAllocationAudit=table(dr.Entities,repmat(dr.NegativeLdfClippedCount,ne,1),dr.LdfNormalizationError, ...
 'VariableNames',{'LoadEntityName','WorkbookNegativeLdfCount','PostNormalizationError'});
end
function t=empty_detail(),t=table(zeros(0,1),strings(0,1),zeros(0,1),zeros(0,1),zeros(0,1),zeros(0,1),zeros(0,1),zeros(0,1),zeros(0,1),zeros(0,1),false(0,1),'VariableNames',{'Hour','LoadEntityName','SelfScheduleMW','MaximumBidLoadMW','ReferenceScheduleMW','CurtailedMW','ServedLoadMW','MaximumUtility','LostUtility','ConsumerBenefit','SelfScheduleSatisfied'});end
function t=empty_summary(),t=table(zeros(0,1),zeros(0,1),zeros(0,1),zeros(0,1),zeros(0,1),zeros(0,1),zeros(0,1),zeros(0,1),'VariableNames',{'Hour','MaximumBidLoadMW','ServedLoadMW','CurtailedMW','ConsumerBenefit','LostUtility','TotalHorizonObjective','WelfareIndicator'});end
function t=empty_audit(),t=table(strings(0,1),zeros(0,1),zeros(0,1),'VariableNames',{'LoadEntityName','WorkbookNegativeLdfCount','PostNormalizationError'});end

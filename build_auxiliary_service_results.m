function tables=build_auxiliary_service_results(mdo,as,hours,config)
%BUILD_AUXILIARY_SERVICE_RESULTS Extract awards, shortages and scarcity prices.
tables=struct('AuxiliaryServiceAwards',empty_awards(),'AuxiliaryServiceSummary',empty_summary(),'AuxiliaryServiceAudit',empty_audit());
if ~isfield(mdo.results,'success')||~mdo.results.success,return;end
nt=numel(hours);ng=numel(as.GeneratorNames);nr=numel(as.Regions); products=as.Products;
awardRows=cell(0,9);summaryRows=cell(0,11);
for t=1:nt
 awards=cell(1,4);
 for p=1:4
  awards{p}=mdo.mpc.baseMVA*mdo.om.get_soln('var',char("AS_"+products(p)),{t});
  for g=1:ng
   awardRows(end+1,:)={hours(t),g,as.GeneratorNames(g),products(p),as.Quantity(t,g,p),as.Price(t,g,p),as.SelfSchedule(t,g,p),awards{p}(g),awards{p}(g)*as.Price(t,g,p)}; %#ok<AGROW>
  end
 end
 labels=["AGCUp","AGCDn","TenMin","ThirtyMin"];
 actual={as.ZoneMatrix*awards{1},as.ZoneMatrix*awards{2},as.ZoneMatrix*(awards{1}+awards{3}),as.ZoneMatrix*(awards{1}+awards{3}+awards{4})};
 mins={as.Requirement.AGCMin(t,:).',as.Requirement.AGCMin(t,:).',as.Requirement.TenMin(t,:).',as.Requirement.ThirtyMin(t,:).'};
 maxs={as.Requirement.AGCMax(t,:).',as.Requirement.AGCMax(t,:).',as.Requirement.TenMax(t,:).',as.Requirement.ThirtyMax(t,:).'};
 for s=1:4
  shortage=mdo.mpc.baseMVA*mdo.om.get_soln('var',char("ASShort_"+labels(s)),{t});
  scarcity=mdo.om.get_soln('lin','mu_l',char("ASReq_"+labels(s)),{t})/mdo.mpc.baseMVA;
  for z=1:nr
   summaryRows(end+1,:)={hours(t),as.Regions(z),labels(s),mins{s}(z),actual{s}(z),maxs{s}(z),shortage(z),scarcity(z),config.reserveShortagePenalty,shortage(z)>1e-6,actual{s}(z)>=mins{s}(z)-1e-6}; %#ok<AGROW>
  end
 end
end
tables.AuxiliaryServiceAwards=cell2table(awardRows,'VariableNames',{'Hour','GeneratorRow','GenName','ASType','OfferedMW','OfferPrice','SelfScheduleMW','AwardMW','AwardCost'});
tables.AuxiliaryServiceSummary=cell2table(summaryRows,'VariableNames',{'Hour','Region','RequirementType','MinimumMW','ProcuredMW','MaximumMW','ShortageMW','ScarcityPrice','ShortagePenalty','HasShortage','RequirementSatisfied'});
auditRows=cell(0,7);
for t=1:nt,for p=1:4
 q=squeeze(as.Quantity(t,:,p));pr=squeeze(as.Price(t,:,p));ss=squeeze(as.SelfSchedule(t,:,p));valid=q>0;
 if any(valid),pmin=min(pr(valid));pmax=max(pr(valid));else,pmin=nan;pmax=nan;end
 auditRows(end+1,:)={hours(t),products(p),sum(q),sum(ss),sum(valid),pmin,pmax}; %#ok<AGROW>
end,end
tables.AuxiliaryServiceAudit=cell2table(auditRows,'VariableNames',{'Hour','ASType','QualifiedOfferMW','SelfScheduledMW','QualifiedGeneratorCount','MinimumOfferPrice','MaximumOfferPrice'});
end
function t=empty_awards(),t=table(zeros(0,1),zeros(0,1),strings(0,1),strings(0,1),zeros(0,1),zeros(0,1),zeros(0,1),zeros(0,1),zeros(0,1),'VariableNames',{'Hour','GeneratorRow','GenName','ASType','OfferedMW','OfferPrice','SelfScheduleMW','AwardMW','AwardCost'});end
function t=empty_summary(),t=table(zeros(0,1),strings(0,1),strings(0,1),zeros(0,1),zeros(0,1),zeros(0,1),zeros(0,1),zeros(0,1),zeros(0,1),false(0,1),false(0,1),'VariableNames',{'Hour','Region','RequirementType','MinimumMW','ProcuredMW','MaximumMW','ShortageMW','ScarcityPrice','ShortagePenalty','HasShortage','RequirementSatisfied'});end
function t=empty_audit(),t=table(zeros(0,1),strings(0,1),zeros(0,1),zeros(0,1),zeros(0,1),zeros(0,1),zeros(0,1),'VariableNames',{'Hour','ASType','QualifiedOfferMW','SelfScheduledMW','QualifiedGeneratorCount','MinimumOfferPrice','MaximumOfferPrice'});end

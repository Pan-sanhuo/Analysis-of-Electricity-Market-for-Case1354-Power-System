function tables=build_market_settlement_results(mdo,meta,hours,config,dr)
%BUILD_MARKET_SETTLEMENT_RESULTS Build valid-price and settlement reports.
% OfferCost is the submitted energy-offer cost. ActualProductionCost is NaN
% because the workbook does not provide an independent audited cost curve.
if nargin<5,dr=struct();end
valid=isfield(mdo.results,'success')&&logical(mdo.results.success);
nt=numel(hours);nb=size(mdo.mpc.bus,1);ng=size(mdo.mpc.gen,1);nl=size(mdo.mpc.branch,1);
busRows=cell(nt*nb,5);genRows=cell(nt*ng,15);branchRows=cell(nt*nl,10);summaryRows=cell(nt,13);
busNo=external_bus_numbers(mdo.mpc);genNames=string(meta.genName(:));tol=config.limitBindingToleranceMW;
for t=1:nt
 r=mdo.flow(t,1,1).mpc;resultValid=valid;
 lmp=nan(nb,1);pg=nan(ng,1);offerCost=nan(ng,1);servedBus=nan(nb,1);
 if resultValid
  lmp=r.bus(:,14);pg=r.gen(:,2);offerCost=totcost(r.gencost(1:ng,:),pg);
  servedBus=served_bus_load(mdo,dr,t,r);
 end
 for b=1:nb
  busRows{(t-1)*nb+b,1}=hours(t);busRows{(t-1)*nb+b,2}=resultValid;
  busRows{(t-1)*nb+b,3}=busNo(b);busRows{(t-1)*nb+b,4}=servedBus(b);busRows{(t-1)*nb+b,5}=lmp(b);
 end
 pmax=r.gen(:,9);pmin=r.gen(:,10);atMax=false(ng,1);atMin=atMax;violMax=atMax;violMin=atMax;
 energyRevenue=nan(ng,1);grossMargin=nan(ng,1);
 if resultValid
  atMax=abs(pg-pmax)<=tol;atMin=abs(pg-pmin)<=tol;
  violMax=pg>pmax+tol;violMin=pg<pmin-tol;
  energyRevenue=pg.*lmp(r.gen(:,1));grossMargin=energyRevenue-offerCost;
 end
 for g=1:ng
  q=(t-1)*ng+g;genRows(q,:)={hours(t),resultValid,g,genNames(g),busNo(r.gen(g,1)),pg(g),pmin(g),pmax(g), ...
   atMin(g),atMax(g),violMin(g),violMax(g),offerCost(g),energyRevenue(g),grossMargin(g)};
 end
 flow=nan(nl,1);loading=nan(nl,1);atLimit=false(nl,1);violated=false(nl,1);rate=r.branch(:,6);
 if resultValid
  flow=r.branch(:,14);limited=rate>0&r.branch(:,11)>0;loading(limited)=100*abs(flow(limited))./rate(limited);
  atLimit(limited)=abs(abs(flow(limited))-rate(limited))<=tol;
  violated(limited)=abs(flow(limited))>rate(limited)+tol;
 end
 for br=1:nl
  q=(t-1)*nl+br;branchRows(q,:)={hours(t),resultValid,br,busNo(r.branch(br,1)),busNo(r.branch(br,2)), ...
   flow(br),rate(br),loading(br),atLimit(br),violated(br)};
 end
 if resultValid
  loadPayment=sum(servedBus.*lmp);genRevenue=sum(energyRevenue);totalOfferCost=sum(offerCost);
  congestionRent=loadPayment-genRevenue;objective=mdo.results.f;
  atGen=sum(atMax|atMin);violGen=sum(violMax|violMin);atBr=sum(atLimit);violBr=sum(violated);
 else
  loadPayment=nan;genRevenue=nan;totalOfferCost=nan;congestionRent=nan;objective=nan;
  atGen=nan;violGen=nan;atBr=nan;violBr=nan;
 end
 summaryRows(t,:)={hours(t),resultValid,objective,totalOfferCost,nan,false,genRevenue,loadPayment,congestionRent,atGen,violGen,atBr,violBr};
end
tables=struct();
tables.NodalEnergyPrice=cell2table(busRows,'VariableNames',{'Hour','ResultValid','BusNo','ServedLoadMW','LMP'});
tables.GeneratorSettlement=cell2table(genRows,'VariableNames',{'Hour','ResultValid','GeneratorRow','GenName','BusNo','PgMW','PminMW','PmaxMW','AtPmin','AtPmax','BelowPminViolation','AbovePmaxViolation','EnergyOfferCost','EnergyRevenue','OfferBasedGrossMargin'});
tables.BranchLimitStatus=cell2table(branchRows,'VariableNames',{'Hour','ResultValid','BranchRow','FromBus','ToBus','PfMW','RateA','DCLoadingPercent','AtRateLimit','RateLimitViolated'});
tables.MarketSettlementSummary=cell2table(summaryRows,'VariableNames',{'Hour','ResultValid','TotalHorizonObjective','EnergyOfferCost','ActualProductionCost','ActualProductionCostAvailable','GeneratorEnergyRevenue','LoadEnergyPayment','CongestionRent','GeneratorAtLimitCount','GeneratorLimitViolationCount','BranchAtLimitCount','BranchLimitViolationCount'});
end

function served=served_bus_load(mdo,dr,t,r)
if isstruct(dr)&&isfield(dr,'MaximumBusLoadMW')&&isfield(dr,'BusSegmentMatrix')
 curt=mdo.mpc.baseMVA*mdo.om.get_soln('var','DRCurt',{t});
 served=dr.MaximumBusLoadMW(t,:).'-dr.BusSegmentMatrix*curt;
else
 served=r.bus(:,3);
end
end
function busNo=external_bus_numbers(mpc)
busNo=mpc.bus(:,1);
if isfield(mpc,'order')&&isfield(mpc.order,'bus')&&isfield(mpc.order.bus,'i2e')
 busNo=mpc.order.bus.i2e(mpc.bus(:,1));
end
end

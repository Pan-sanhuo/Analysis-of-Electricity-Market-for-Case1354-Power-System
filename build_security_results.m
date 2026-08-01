function tables=build_security_results(mdo,audit,hours,config)
%BUILD_SECURITY_RESULTS Summarize DC SCOPF contingencies and optional AC checks.
tables=struct('SecurityContingencyAudit',audit,'SecurityContingencyResults',empty_results(),'ACN1PostCheck',empty_ac());
if ~isfield(mdo.results,'success')||~mdo.results.success,return;end
nt=numel(hours);rows=cell(0,9);acRows=cell(0,9);
for t=1:nt
 labels=scenario_labels(mdo,t);
 for k=1:numel(labels)
  label=labels(k);a=find(audit.Included&audit.ContingencyLabel==label,1);
  if isempty(a),continue;end
  scenario=k+1;r=mdo.flow(t,1,scenario).mpc;rate=r.branch(:,6);loading=nan(size(rate));on=rate>0&r.branch(:,11)>0;
  loading(on)=100*abs(r.branch(on,14))./rate(on);maxLoad=max(loading,[],'omitnan');viol=sum(loading>100+1e-6);
  rows(end+1,:)={hours(t),label,audit.ElementType(a),audit.ElementName(a),maxLoad,viol,sum(r.gen(:,2)),sum(r.bus(:,3)),viol==0}; %#ok<AGROW>
  if config.runAcN1PostCheck&&k<=config.maxAcN1PostChecks
   [ok,maxV,maxBr,vCount,bCount,msg]=ac_check(r);
   acRows(end+1,:)={hours(t),label,audit.ElementType(a),ok,maxV,maxBr,vCount,bCount,string(msg)}; %#ok<AGROW>
  end
 end
end
tables.SecurityContingencyResults=cell2table(rows,'VariableNames',{'Hour','ContingencyLabel','ElementType','ElementName','MaxBranchLoadingPercent','OverloadedBranchCount','TotalGenerationMW','ModelBusLoadMW','DCConstraintSatisfied'});
if ~isempty(acRows),tables.ACN1PostCheck=cell2table(acRows,'VariableNames',{'Hour','ContingencyLabel','ElementType','ACConverged','MaxVoltageViolation','MaxBranchLoadingPercent','VoltageViolationCount','OverloadedBranchCount','Message'});end
end
function labels=scenario_labels(mdo,t)
labels=[];
if ~isfield(mdo,'cont')||isempty(mdo.cont(t,1).contab),return;end
labels=sort(unique(mdo.cont(t,1).contab(:,1))).';
end
function [ok,maxV,maxBr,vCount,bCount,msg]=ac_check(m)
try
 r=runpf(m,mpoption('verbose',0,'out.all',0));
 ok=logical(r.success);msg="";
 if ok
  v=max([r.bus(:,8)-r.bus(:,12),r.bus(:,13)-r.bus(:,8),zeros(size(r.bus,1),1)],[],2);
  maxV=max(v);vCount=sum(v>1e-6);rate=r.branch(:,6);
  s=max(hypot(r.branch(:,14),r.branch(:,15)),hypot(r.branch(:,16),r.branch(:,17)));
  ld=nan(size(rate));ld(rate>0)=100*s(rate>0)./rate(rate>0);
  maxBr=max(ld,[],'omitnan');bCount=sum(ld>100+1e-6);
 else
  maxV=nan;maxBr=nan;vCount=nan;bCount=nan;msg="AC power flow did not converge";
 end
catch ME
 ok=false;maxV=nan;maxBr=nan;vCount=nan;bCount=nan;msg=ME.message;
end
end
function t=empty_results(),t=table(zeros(0,1),zeros(0,1),strings(0,1),strings(0,1),zeros(0,1),zeros(0,1),zeros(0,1),zeros(0,1),false(0,1),'VariableNames',{'Hour','ContingencyLabel','ElementType','ElementName','MaxBranchLoadingPercent','OverloadedBranchCount','TotalGenerationMW','ModelBusLoadMW','DCConstraintSatisfied'});end
function t=empty_ac(),t=table(zeros(0,1),zeros(0,1),strings(0,1),false(0,1),zeros(0,1),zeros(0,1),zeros(0,1),zeros(0,1),strings(0,1),'VariableNames',{'Hour','ContingencyLabel','ElementType','ACConverged','MaxVoltageViolation','MaxBranchLoadingPercent','VoltageViolationCount','OverloadedBranchCount','Message'});end

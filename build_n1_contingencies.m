function [contab,audit]=build_n1_contingencies(mpc,config)
%BUILD_N1_CONTINGENCIES Build screened/exhaustive line, transformer and gen N-1 set.
[~,~,~,~,~,~,~,GEN_STATUS,PMAX]=idx_gen;
[~,~,~,~,~,RATE_A,~,~,TAP,SHIFT,BR_STATUS,PF]=idx_brch;
[~,~,~,~,CT_TGEN,CT_TBRCH,~,~,~,~,~,~,CT_REP]=idx_ct;
nl=size(mpc.branch,1);metric=zeros(nl,1);
try
 r=runopf(mpc,mpoption('verbose',0,'out.all',0,'model','DC'));
 if r.success
  rate=mpc.branch(:,RATE_A);
  metric=abs(r.branch(:,PF))./max(rate,1);
 else
  metric=1./max(mpc.branch(:,RATE_A),1);
 end
catch,metric=1./max(mpc.branch(:,RATE_A),1);end
isTransformer=mpc.branch(:,TAP)~=0|abs(mpc.branch(:,SHIFT))>1e-9;
lineRows=find(mpc.branch(:,BR_STATUS)>0&~isTransformer);transformerRows=find(mpc.branch(:,BR_STATUS)>0&isTransformer);
genRows=find(mpc.gen(:,GEN_STATUS)>0&mpc.gen(:,PMAX)>0);
mode=lower(string(config.securityScreeningMode));
if mode=="screened"
 lineRows=top_rows(lineRows,metric,numel(lineRows));
 transformerRows=top_rows(transformerRows,metric,numel(transformerRows));
 [~,o]=sort(mpc.gen(genRows,PMAX),'descend');genRows=genRows(o(1:min(numel(o),config.maxGeneratorContingencies)));
elseif mode~="exhaustive",error('case1354:InvalidSecurityMode','securityScreeningMode must be screened or exhaustive.');end
rows=cell(0,8);contab=zeros(0,7);label=0;
if mode=="screened"
 process_branch_candidates(lineRows,"Line",config.maxLineContingencies);
 process_branch_candidates(transformerRows,"Transformer",config.maxTransformerContingencies);
else
 for i=1:numel(lineRows),add_branch(lineRows(i),"Line");end
 for i=1:numel(transformerRows),add_branch(transformerRows(i),"Transformer");end
end
for i=1:numel(genRows)
 label=label+1;g=genRows(i);contab(end+1,:)=[label 0 CT_TGEN g GEN_STATUS CT_REP 0]; %#ok<AGROW>
 rows(end+1,:)={label,"Generator",g,"GenRow"+g,mpc.gen(g,PMAX),true,"Included","Generator trip"}; %#ok<AGROW>
end
audit=cell2table(rows,'VariableNames',{'ContingencyLabel','ElementType','ElementRow','ElementName','RiskMetric','Included','ScreeningDecision','Description'});

 function process_branch_candidates(candidates,typ,target)
  accepted=0;
  for q=1:numel(candidates)
   wasIncluded=add_branch(candidates(q),typ);
   accepted=accepted+double(wasIncluded);
   if accepted>=target,break;end
  end
 end

 function included=add_branch(br,typ)
  if creates_island(mpc,br)
   rows(end+1,:)={nan,typ,br,"BranchRow"+br,metric(br),false,"ExcludedIslanding","Outage creates an electrical island"};included=false;return;
  end
  label=label+1;contab(end+1,:)=[label 0 CT_TBRCH br BR_STATUS CT_REP 0]; %#ok<AGROW>
  rows(end+1,:)={label,typ,br,"BranchRow"+br,metric(br),true,"Included","Branch/transformer outage"}; %#ok<AGROW>
  included=true;
 end
end
function rows=top_rows(rows,metric,n),[~,o]=sort(metric(rows),'descend');rows=rows(o(1:min(numel(o),n)));end
function tf=creates_island(mpc,br)
m=mpc;m.branch(br,11)=0;
try
 [groups,isolated]=find_islands(m);
 tf=numel(groups)>1||~isempty(isolated);
catch
 tf=false;
end
end

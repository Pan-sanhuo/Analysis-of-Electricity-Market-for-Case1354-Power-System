function [mdo,dr]=add_demand_response_to_most(mdo,data,hours,config)
%ADD_DEMAND_RESPONSE_TO_MOST Add LoadBid welfare variables to nodal balance.
% Gross demand is the maximum accepted bid quantity. DRCurt variables remove
% optional bid segments at their lost-utility price. Minimizing production
% cost + lost utility is equivalent to maximizing social welfare.
dr=build_input(mdo,data,hours,config);om=mdo.om;nt=numel(hours);base=mdo.mpc.baseMVA;
om.init_indexed_name('var','DRCurt',{nt});om.init_indexed_name('qdc','Cost_DRCurt',{nt});
for t=1:nt
    cap=dr.SegmentCapacity(t,:).'/base;om.add_var('DRCurt',{t},dr.SegmentCount,[],zeros(dr.SegmentCount,1),cap);
    cost=dr.SegmentPrice(t,:).'*base;vsCost=struct('name',{'DRCurt'},'idx',{{t}});
    om.add_quad_cost('Cost_DRCurt',{t},sparse(dr.SegmentCount,dr.SegmentCount),cost,0,vsCost);
    for k=1:mdo.idx.nc(t,1)+1
        [A,l,u,vs]=om.lin.params(om.var,'Pmis',{t,1,k});
        A=[A -dr.BusSegmentMatrix]; %#ok<AGROW>
        currentPd=mdo.flow(t,1,k).mpc.bus(:,3);
        shift=(dr.MaximumBusLoadMW(t,:).'-currentPd)/base;
        l=l-shift;u=u-shift;
        vs=[vs struct('name',{'DRCurt'},'idx',{{t}})];
        om.set_params('lin','Pmis',{t,1,k},{'A','l','u','vs'},{A,l,u,vs});
    end
end
mdo.om=om;
end

function dr=build_input(mdo,data,hours,config)
entities=unique(string(data.LoadBid.('LoadEntityName')),'stable');ne=numel(entities);nt=numel(hours);maxFlex=5;ns=ne*maxFlex;
cap=zeros(nt,ns);price=zeros(nt,ns);selfMW=zeros(nt,ne);maxMW=zeros(nt,ne);fullUtility=zeros(nt,ne);schedule=zeros(nt,ne);
b=data.LoadBid;bh=num(b,'Hour',nan);bn=string(b.('LoadEntityName'));ls=data.LoadSchedule;
entityOfSegment=repelem((1:ne).',maxFlex);slotOfSegment=repmat((1:maxFlex).',ne,1);
for t=1:nt,for e=1:ne
 row=find(bh==hours(t)&strcmpi(bn,entities(e)),1);
 if isempty(row),error('case1354:MissingLoadBid','Missing LoadBid for Hour%d %s.',hours(t),entities(e));end
 selfMW(t,e)=value(b,row,'SelfSchedule',0);[x,p]=bid_points(b,row);
 if isempty(x),maxMW(t,e)=selfMW(t,e);continue;end
 maxMW(t,e)=x(end);fullUtility(t,e)=selfMW(t,e)*p(1);
 prev=selfMW(t,e);
 for k=2:numel(x)
  j=(e-1)*maxFlex+k-1;cap(t,j)=max(0,x(k)-max(prev,x(k-1)));price(t,j)=p(k);fullUtility(t,e)=fullUtility(t,e)+cap(t,j)*p(k);prev=x(k);
 end
 schedule(t,e)=schedule_value(ls,entities(e),hours(t),maxMW(t,e));
end,end
[entityBus,negCount,ldfError]=entity_bus_matrix(mdo,data,entities,config);
segmentEntity=sparse(entityOfSegment,1:ns,1,ne,ns);
dr=struct('Entities',entities,'EntityCount',ne,'SegmentCount',ns,'EntityOfSegment',entityOfSegment, ...
 'SlotOfSegment',slotOfSegment,'SegmentCapacity',cap,'SegmentPrice',price,'SelfScheduleMW',selfMW, ...
 'MaximumLoadMW',maxMW,'ScheduledLoadMW',schedule,'MaximumUtility',fullUtility, ...
 'EntityBusMatrix',entityBus,'BusSegmentMatrix',entityBus*segmentEntity, ...
 'MaximumBusLoadMW',maxMW*entityBus.','NegativeLdfClippedCount',negCount,'LdfNormalizationError',ldfError);
end

function [M,negativeCount,normalizationError]=entity_bus_matrix(mdo,data,entities,config)
nb=size(mdo.mpc.bus,1);ne=numel(entities);M=sparse(nb,ne);le=data.LoadEntity;
names=string(le.('LoadEntityName'));bus=num(le,'BusNo',nan);ldf=num(le,'LDF',nan);negativeCount=0;normalizationError=zeros(ne,1);
e2i=mdo.mpc.order.bus.e2i;
for e=1:ne
 rows=find(strcmpi(names,entities(e)));w=ldf(rows);negativeCount=negativeCount+sum(w<0);
 if any(w<0)
  if lower(string(config.negativeLdfPolicy))=="error",error('case1354:NegativeLDF','%s contains negative LDF.',entities(e));end
  w(w<0)=0;
 end
 if sum(w)<=0,error('case1354:InvalidLDF','%s has no positive LDF.',entities(e));end
 w=w/sum(w);normalizationError(e)=abs(sum(w)-1);
 for k=1:numel(rows)
  ext=round(bus(rows(k)));if ext>=1&&ext<=numel(e2i),ib=e2i(ext);else,ib=0;end
  if ib>0,M(ib,e)=M(ib,e)+w(k);end
 end
 if abs(sum(M(:,e))-1)>1e-8,error('case1354:UnmappedLoadEntity','%s LDF buses do not map to active buses.',entities(e));end
end
end

function [x,p]=bid_points(b,row)
x=[];p=[];
for k=1:6
 mw=value(b,row,'SegMW'+string(k),nan);pr=value(b,row,'SegPrc'+string(k),nan);
 if isfinite(mw)&&isfinite(pr),x(end+1,1)=mw;p(end+1,1)=pr;end %#ok<AGROW>
end
if any(diff(x)<-1e-9),error('case1354:InvalidLoadBid','LoadBid breakpoints must be nondecreasing.');end
end
function v=schedule_value(t,entity,hour,fallback),r=find(strcmpi(string(t.('LoadEntityName')),entity),1);c='Hour'+string(hour);if isempty(r)||~ismember(c,t.Properties.VariableNames),v=fallback;else,v=value(t,r,c,fallback);end,end
function v=value(t,row,c,d),if~ismember(c,t.Properties.VariableNames),v=d;else,x=t.(c);v=x(row);if~isnumeric(v),v=str2double(string(v));end;v=double(v);if~isfinite(v),v=d;end,end,end
function v=num(t,c,d),if~ismember(c,t.Properties.VariableNames),v=d*ones(height(t),1);else,v=t.(c);if~isnumeric(v),v=str2double(string(v));end;v=double(v);v(~isfinite(v))=d;end,end

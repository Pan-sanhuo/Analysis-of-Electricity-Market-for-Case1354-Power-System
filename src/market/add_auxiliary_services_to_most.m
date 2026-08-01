function [mdo, as] = add_auxiliary_services_to_most(mdo,data,hours,activeGen,config)
%ADD_AUXILIARY_SERVICES_TO_MOST Add RegUp/RegDn/Spin/NonSpin co-optimization.
% Requirements are nested: AGC=Reg, 10m=RegUp+Spin,
% 30m=RegUp+Spin+NonSpin. Regional procurement provides the first level of
% deliverability; contingency/network deliverability is handled by SCOPF.
baseMVA=mdo.mpc.baseMVA; nt=numel(hours); ng=numel(activeGen);
as=build_input(data,hours,activeGen,config);
om=mdo.om; products=as.Products;
for p=1:numel(products)
    name=char("AS_"+products(p)); om.init_indexed_name('var',name,{nt});
    costName=char("Cost_"+string(name)); om.init_indexed_name('qdc',costName,{nt});
end
shortNames=["AGCUp","AGCDn","TenMin","ThirtyMin"];
for s=1:numel(shortNames)
    name=char("ASShort_"+shortNames(s));om.init_indexed_name('var',name,{nt});
    costName=char("Cost_"+string(name));om.init_indexed_name('qdc',costName,{nt});
    om.init_indexed_name('lin',char("ASReq_"+shortNames(s)),{nt});
    om.init_indexed_name('lin',char("ASMax_"+shortNames(s)),{nt});
end
om.init_indexed_name('lin','ASEnergyUp',{nt});
om.init_indexed_name('lin','ASEnergyDown',{nt});
maxNc=max(mdo.idx.nc(:));
if maxNc>0
    om.init_indexed_name('lin','ASContingencyUp',{nt,maxNc});
    om.init_indexed_name('lin','ASContingencyDown',{nt,maxNc});
end
nr=numel(as.Regions); I=speye(ng);
for t=1:nt
    for p=1:numel(products)
        name=char("AS_"+products(p)); lb=as.SelfSchedule(t,:,p).'/baseMVA; ub=as.Quantity(t,:,p).'/baseMVA;
        om.add_var(name,{t},ng,[],lb,ub);
        c=as.Price(t,:,p).'*baseMVA;
        costVars=struct('name',{name},'idx',{{t}});
        om.add_quad_cost(char("Cost_"+string(name)),{t},sparse(ng,ng),c,0,costVars);
    end
    for s=1:numel(shortNames)
        name=char("ASShort_"+shortNames(s));om.add_var(name,{t},nr,[],zeros(nr,1),[]);
        costVars=struct('name',{name},'idx',{{t}});
        om.add_quad_cost(char("Cost_"+string(name)),{t},sparse(nr,nr),config.reserveShortagePenalty*baseMVA*ones(nr,1),0,costVars);
    end
    % Pg + RegUp + Spin + NonSpin <= Pmax [* u in SCUC].
    if config.mode=="SCUC"
        A=[I I I I sparse(ng,ng) -spdiags(mdo.flow(t,1,1).mpc.gen(:,9)/baseMVA,0,ng,ng)];
        vs=struct('name',{'Pg','AS_RegUp','AS_Spin','AS_NonSpin','AS_RegDn','u'}, ...
            'idx',{{t,1,1},{t},{t},{t},{t},{t}}); upper=zeros(ng,1);
    else
        A=[I I I I sparse(ng,ng)];
        vs=struct('name',{'Pg','AS_RegUp','AS_Spin','AS_NonSpin','AS_RegDn'}, ...
            'idx',{{t,1,1},{t},{t},{t},{t}}); upper=mdo.flow(t,1,1).mpc.gen(:,9)/baseMVA;
    end
    om.add_lin_constraint('ASEnergyUp',{t},A,[],upper,vs);
    % Pg - RegDn >= Pmin [* u in SCUC].
    if config.mode=="SCUC"
        A=[I -I -spdiags(mdo.flow(t,1,1).mpc.gen(:,10)/baseMVA,0,ng,ng)];
        vs=struct('name',{'Pg','AS_RegDn','u'},'idx',{{t,1,1},{t},{t}}); lower=zeros(ng,1);
    else
        A=[I -I];vs=struct('name',{'Pg','AS_RegDn'},'idx',{{t,1,1},{t}});lower=mdo.flow(t,1,1).mpc.gen(:,10)/baseMVA;
    end
    om.add_lin_constraint('ASEnergyDown',{t},A,lower,[],vs);
    % N-1 redispatch must be physically backed by procured reserve. A
    % contingency may increase output only through RegUp+Spin and may
    % decrease output only through RegDn. This adds network deliverability
    % to the regional reserve procurement constraints above.
    for k=2:mdo.idx.nc(t,1)+1
        vsUp=struct('name',{'Pg','Pg','AS_RegUp','AS_Spin'}, ...
            'idx',{{t,1,k},{t,1,1},{t},{t}});
        om.add_lin_constraint('ASContingencyUp',{t,k-1}, ...
            [I -I -I -I],[],zeros(ng,1),vsUp);
        downMask=I;
        failedGen=outaged_generator_row(mdo,t,k);
        if failedGen>0,downMask(failedGen,failedGen)=0;end
        vsDn=struct('name',{'Pg','Pg','AS_RegDn'}, ...
            'idx',{{t,1,1},{t,1,k},{t}});
        om.add_lin_constraint('ASContingencyDown',{t,k-1}, ...
            [downMask -downMask -I],[],zeros(ng,1),vsDn);
    end
    add_requirement("AGCUp",{'AS_RegUp'},as.Requirement.AGCMin(t,:),as.Requirement.AGCMax(t,:));
    add_requirement("AGCDn",{'AS_RegDn'},as.Requirement.AGCMin(t,:),as.Requirement.AGCMax(t,:));
    add_requirement("TenMin",{'AS_RegUp','AS_Spin'},as.Requirement.TenMin(t,:),as.Requirement.TenMax(t,:));
    add_requirement("ThirtyMin",{'AS_RegUp','AS_Spin','AS_NonSpin'},as.Requirement.ThirtyMin(t,:),as.Requirement.ThirtyMax(t,:));
end
mdo.om=om;

    function add_requirement(label,varNames,minMW,maxMW)
        nv=numel(varNames); Z=repmat({as.ZoneMatrix},1,nv); A=[Z{:} speye(nr)];
        names=[varNames {char("ASShort_"+label)}]; idx=repmat({{t}},1,numel(names));
        vs=struct('name',names,'idx',idx);
        om.add_lin_constraint(char("ASReq_"+label),{t},A,minMW(:)/baseMVA,[],vs);
        Amax=[Z{:}]; vsmax=struct('name',varNames,'idx',repmat({{t}},1,nv));
        om.add_lin_constraint(char("ASMax_"+label),{t},Amax,[],maxMW(:)/baseMVA,vsmax);
    end
end

function g=outaged_generator_row(mdo,t,scenario)
g=0;tab=mdo.cont(t,1).contab;
if isempty(tab),return;end
[~,~,~,~,CT_TGEN]=idx_ct;[~,~,~,~,~,~,~,GEN_STATUS]=idx_gen;
labels=sort(unique(tab(:,1)));label=labels(scenario-1);
row=find(tab(:,1)==label&tab(:,3)==CT_TGEN&tab(:,5)==GEN_STATUS&tab(:,7)==0,1);
if ~isempty(row),g=tab(row,4);end
end

function as=build_input(data,hours,activeGen,config)
products=["RegUp","RegDn","Spin","NonSpin"]; nt=numel(hours);ng=numel(activeGen);
qty=zeros(nt,ng,4);price=zeros(nt,ng,4);self=zeros(nt,ng,4);
names=normalize_generator_names(string(data.Generator.('GenName'))); activeNames=names(activeGen);
b=data.ASBid; bNames=normalize_generator_names(string(b.('GenName'))); bHours=num(b,'Hour',nan);bType=string(b.('ASType'));
physical=physical_caps(data.Generator(activeGen,:),config);
for t=1:nt
 for g=1:ng
  for p=1:4
   rows=find(bNames==activeNames(g)&bHours==hours(t)&strcmpi(bType,products(p)));
   if numel(rows)>1,error('case1354:DuplicateASBid','Hour%d %s %s has %d ASBid rows.',hours(t),activeNames(g),products(p),numel(rows));end
   if isempty(rows),continue;end
   q=num(b(rows,:),'ASMW',0);pr=num(b(rows,:),'ASPRC',0);ss=num(b(rows,:),'SelfSchedule',0);
   qty(t,g,p)=min(max(q(1),0),physical(g,p)); price(t,g,p)=pr(1);
   self(t,g,p)=min(max(ss(1),0),qty(t,g,p));
  end
 end
end
[regions,requirements]=requirements_table(data.ASRequirement,hours);
Z=region_matrix(data,activeGen,regions);
as=struct('Products',products,'Regions',regions,'Quantity',qty,'Price',price, ...
 'SelfSchedule',self,'Requirement',requirements,'ZoneMatrix',Z,'GeneratorNames',activeNames);
end

function caps=physical_caps(g,c)
ng=height(g);caps=inf(ng,4);
agc=num(g,'Ramp_AGC (MW/分钟)',nan)*c.regulationResponseMinutes;
r10=num(g,'Ramp_10M (MW/分钟)',nan)*c.spinResponseMinutes;
r30=num(g,'Ramp_30M(MW/分钟)',nan)*c.nonSpinResponseMinutes;
for k=1:ng
 if isfinite(agc(k))&&agc(k)>0,caps(k,1:2)=agc(k);end
 if isfinite(r10(k))&&r10(k)>0,caps(k,3)=r10(k);end
 if isfinite(r30(k))&&r30(k)>0,caps(k,4)=r30(k);end
end
end

function [regions,r]=requirements_table(q,hours)
regions=unique(string(q.('Region')),'stable');nt=numel(hours);nr=numel(regions);
fields={'AGCMin(MW)','AGCMax(MW)','10mMin(MW)','10mMax(MW)','30mMin(MW)','30mMax(MW)'};
vals=cell(1,6);for f=1:6,vals{f}=nan(nt,nr);end
qh=num(q,'Hour',nan);
for t=1:nt,for z=1:nr
 row=find(qh==hours(t)&strcmpi(string(q.('Region')),regions(z)),1);
 if isempty(row),error('case1354:MissingASRequirement','Missing ASRequirement for Hour%d Region %s.',hours(t),regions(z));end
 for f=1:6,v=num(q(row,:),fields{f},nan);vals{f}(t,z)=v(1);end
end,end
r=struct('AGCMin',vals{1},'AGCMax',vals{2},'TenMin',vals{3},'TenMax',vals{4},'ThirtyMin',vals{5},'ThirtyMax',vals{6});
end

function Z=region_matrix(data,activeGen,regions)
busNo=num(data.Generator,'BusNo',nan); busNo=busNo(activeGen);bus=data.Bus;zone=data.Zone;
busIds=num(bus,'BusNo',nan);busZone=num(bus,'Zone',nan);zoneNo=num(zone,'Zone',nan);zoneName=string(zone.('ZoneName'));
genZone=strings(numel(activeGen),1);
for g=1:numel(activeGen),i=find(busIds==busNo(g),1);if~isempty(i),j=find(zoneNo==busZone(i),1);if~isempty(j),genZone(g)=zoneName(j);end,end,end
ar=data.ASRegion; Z=false(numel(regions),numel(activeGen));
for z=1:numel(regions)
 regionNames=string(ar.('RegionName'));zoneNames=string(ar.('ZoneName'));
 rows=strcmpi(regionNames,regions(z));allowed=normalize_id(zoneNames(rows));
 if strcmpi(regions(z),'All'),Z(z,:)=true;else,Z(z,:)=ismember(normalize_id(genZone),allowed);end
end
end
function s=normalize_id(s),s=lower(regexprep(strtrim(string(s)),'[^a-zA-Z0-9]',''));end
function v=num(t,c,d),if~ismember(c,t.Properties.VariableNames),v=d*ones(height(t),1);else,v=t.(c);if~isnumeric(v),v=str2double(string(v));end;v=double(v);v(~isfinite(v))=d;end,end

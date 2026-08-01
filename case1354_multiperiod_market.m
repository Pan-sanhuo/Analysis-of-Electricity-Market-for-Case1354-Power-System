function results = case1354_multiperiod_market(config)
%CASE1354_MULTIPERIOD_MARKET Joint 24-hour DC-SCED or SCUC using MATPOWER MOST.
% Unlike case1354cljs, this routine solves every period in ONE optimization.
% mode='SCED' fixes commitment and co-optimizes Pg with inter-temporal ramps.
% mode='SCUC' also optimizes eligible thermal unit status, startup/shutdown,
% and minimum up/down time. It is a day-ahead DC market layer; afterwards run
% case1354cljs for AC feasibility and reactive-power validation.
if nargin < 1, config = struct(); end
c = defaults(config);
[c,runInfo]=initialize_run(c);
runTimer=tic;
require_most(c);
data = read_case1354_excel(c.dataFile);
hours = c.targetHours(:).'; nt = numel(hours);

% Build one physical base case. MOST profiles replace hourly demand and Pmax.
baseConfig = struct('useLoadSchedule',false,'useGeneratorSchedule',true, ...
    'branchLimitType','MVA','marketMode',c.marketMode, ...
    'missingBidPolicy',c.missingBidPolicy,'bidMWMode',c.bidMWMode, ...
    'marketPriceFloor',c.marketPriceFloor,'marketPriceCap',c.marketPriceCap);
dataBase = data; dataBase.TransmissionConstr = dataBase.TransmissionConstr([],:);
[mpc, meta] = build_matpower_case(dataBase, hours(1), baseConfig);
sourceInitialStatus = mpc.gen(:,8)>0;
if c.mode == "SCUC"
    % Keep initially-off but physically available units in the model. Their
    % actual initial commitment is carried by xgd.InitialState below.
    mpc.gen(mpc.gen(:,9)>0,8)=1;
end
mpc = ext2int(mpc);
activeGen = mpc.order.gen.status.on;
meta.genName = meta.genName(activeGen);
meta.generatorRow = meta.generatorRow(activeGen);
meta.generatorKey = meta.generatorKey(activeGen);
define_constants;
[loadMW, pmax, hourlyCost, scheduleAudit] = hourly_profiles(data, dataBase, hours, baseConfig, mpc, activeGen);
profiles = make_profiles(loadMW, pmax, hourlyCost);
[mpc, xgd, unitAudit] = make_xgd_and_costs(data, mpc, c, activeGen, sourceInitialStatus(activeGen));
[contab,securityAudit]=deal([],table());
if c.useSecurityConstraints,[contab,securityAudit]=build_n1_contingencies(mpc,c);end

if c.mode == "SCED"
    % No binary variables: preserve current online/offline commitment.
    xgd = rmfield(xgd, intersect(fieldnames(xgd), {'CommitKey','InitialState','MinUp','MinDown'}));
else
    if ~have_feature('intlinprog') && ~have_feature('cplex') && ~have_feature('gurobi') && ~have_feature('glpk') && ~have_feature('mosek')
        error('case1354:NoMilpSolver', 'SCUC requires intlinprog, CPLEX, Gurobi, GLPK, or MOSEK.');
    end
end

mpopt = mpoption('verbose', c.verbose, 'out.all', 0, 'model', 'DC', ...
    'most.dc_model', 1, 'most.solver', 'DEFAULT','most.security_constraints',double(c.useSecurityConstraints));
mdi = loadmd(mpc, nt, xgd, [], contab, profiles);
as=struct();dr=struct();
if c.useAuxiliaryServices||c.useDemandBids
    buildOpt=mpoption(mpopt,'most.build_model',1,'most.solve_model',0);
    mdo=most(mdi,buildOpt);
    if c.useAuxiliaryServices,[mdo,as]=add_auxiliary_services_to_most(mdo,data,hours,activeGen,c);end
    if c.useDemandBids,[mdo,dr]=add_demand_response_to_most(mdo,data,hours,c);end
    solveOpt=mpoption(mpopt,'most.build_model',0,'most.solve_model',1,'most.resolve_new_cost',1);
    mdo=most(mdo,solveOpt);
else
    mdo=most(mdi,mpopt);
end
tables = result_tables(mdo, meta, hours, scheduleAudit, unitAudit, c);
if c.useAuxiliaryServices
    asTables=build_auxiliary_service_results(mdo,as,hours,c);
    tables.AuxiliaryServiceAwards=asTables.AuxiliaryServiceAwards;
    tables.AuxiliaryServiceSummary=asTables.AuxiliaryServiceSummary;
    tables.AuxiliaryServiceAudit=asTables.AuxiliaryServiceAudit;
end
if c.useDemandBids
    drTables=build_demand_response_results(mdo,dr,hours);
    tables.DemandResponse=drTables.DemandResponse;
    tables.DemandMarketSummary=drTables.DemandMarketSummary;
    tables.DemandAllocationAudit=drTables.DemandAllocationAudit;
end
if c.useSecurityConstraints
    secTables=build_security_results(mdo,securityAudit,hours,c);
    tables.SecurityContingencyAudit=secTables.SecurityContingencyAudit;
    tables.SecurityContingencyResults=secTables.SecurityContingencyResults;
    tables.ACN1PostCheck=secTables.ACN1PostCheck;
end
settlementTables=build_market_settlement_results(mdo,meta,hours,c,dr);
tables.NodalEnergyPrice=settlementTables.NodalEnergyPrice;
tables.GeneratorSettlement=settlementTables.GeneratorSettlement;
tables.BranchLimitStatus=settlementTables.BranchLimitStatus;
tables.MarketSettlementSummary=settlementTables.MarketSettlementSummary;
if ~results_success(mdo)
    tables.MultiPeriodPrecheck = dc_precheck(data, dataBase, hours, baseConfig);
else
    tables.MultiPeriodPrecheck = table(hours(:),repmat(true,nt,1),repmat("Joint model solved",nt,1), ...
        'VariableNames',{'Hour','DCSinglePeriodFeasible','Message'});
end
artifactTables=build_run_artifacts(c,tables,runInfo,toc(runTimer));
tables.RunConfiguration=artifactTables.RunConfiguration;
tables.RunManifest=artifactTables.RunManifest;
tables.RunLog=artifactTables.RunLog;
if ~exist(c.outDir, 'dir'), mkdir(c.outDir); end
write_output_excel(c.outFile, tables);
save(replace(c.outFile, '.xlsx', '.mat'), 'mdo', 'mdi', 'data', 'c', 'tables', 'as', 'dr');
sidecars=write_run_sidecars(c,tables.RunManifest,tables.RunLog);
results = struct('success', results_success(mdo), 'mode', c.mode, ...
    'outputExcel', c.outFile, 'outputMat', replace(c.outFile,'.xlsx','.mat'), ...
    'summary', tables.MultiPeriodSummary, ...
    'auxiliaryServiceSummary',table_field(tables,'AuxiliaryServiceSummary'), ...
    'runId',c.runId,'runManifest',tables.RunManifest,'sidecars',sidecars,'mdo',mdo);
end
function value=table_field(s,name),if isfield(s,name),value=s.(name);else,value=table();end,end

function ok = results_success(mdo)
ok = isfield(mdo.results,'success') && logical(mdo.results.success);
end

function precheck = dc_precheck(data, dataBase, hours, baseConfig)
nt=numel(hours); feasible=false(nt,1); inputLoad=nan(nt,1); onlinePmax=nan(nt,1); message=strings(nt,1);
baseLoad=nan;
for k=1:nt
    [m,~]=build_matpower_case(dataBase,hours(k),baseConfig);
    if isnan(baseLoad),baseLoad=sum(m.bus(:,3));end
    target=scheduled_total_load(data.LoadSchedule,hours(k),baseLoad);
    m.bus(:,3:4)=m.bus(:,3:4)*(target/baseLoad); inputLoad(k)=target;
    onlinePmax(k)=sum(m.gen(m.gen(:,8)>0,9));
    r=runopf(m,mpoption('verbose',0,'out.all',0,'model','DC'));
    feasible(k)=logical(r.success);
    if feasible(k),message(k)="DC OPF feasible with original physical branch limits.";
    elseif onlinePmax(k)>inputLoad(k),message(k)="DC OPF infeasible despite sufficient total Pmax: network/line constraint bottleneck.";
    else,message(k)="DC OPF infeasible: online Pmax below scheduled load.";end
end
precheck=table(hours(:),inputLoad,onlinePmax,onlinePmax-inputLoad,feasible,message, ...
 'VariableNames',{'Hour','ScheduledLoadMW','OnlinePmaxMW','CapacityMarginMW','DCSinglePeriodFeasible','Message'});
end

function c = defaults(user)
c = struct('dataFile','D:\桌面\潮流\资料\case1354cdf-V2.9和说明2.xlsx', ...
 'outDir','D:\桌面\潮流\结果\case1354\New', 'outFile','', 'matpowerPath','D:\Program Files\MATLAB\matpower8.1', ...
 'targetHours',1:24,'mode','SCED','verbose',0,'useIntertemporalRamp',true, ...
 'useAuxiliaryServices',true,'reserveShortagePenalty',15000, ...
 'useDemandBids',true,'negativeLdfPolicy','clip_and_renormalize', ...
 'useSecurityConstraints',false,'securityScreeningMode','screened', ...
 'maxLineContingencies',10,'maxTransformerContingencies',5,'maxGeneratorContingencies',5, ...
 'runAcN1PostCheck',true,'maxAcN1PostChecks',5, ...
 'limitBindingToleranceMW',1e-4, ...
 'runId','', 'preserveExistingResults',false, 'writeRunSidecars',true, ...
 'regulationResponseMinutes',5,'spinResponseMinutes',10,'nonSpinResponseMinutes',30,'marketMode','production', ...
 'missingBidPolicy','error','bidMWMode','breakpoint','marketPriceFloor',-1000,'marketPriceCap',10000);
f = fieldnames(user); for k=1:numel(f), c.(f{k})=user.(f{k}); end
c.mode = upper(string(c.mode));
if ~any(c.mode == ["SCED","SCUC"]), error('case1354:InvalidMode','mode must be SCED or SCUC.'); end
end

function [c,info]=initialize_run(c)
if strlength(string(c.runId))==0
 c.runId=string(datetime('now','Format','yyyyMMdd_HHmmss_SSS'));
else
 c.runId=string(c.runId);
end
if isempty(c.outFile)
 c.outFile=fullfile(c.outDir,'case1354_multiperiod_sced.xlsx');
end
[folder,~,~]=fileparts(c.outFile);if ~isempty(folder),c.outDir=folder;end
info=struct('StartTime',datetime('now','TimeZone','local'),'RunId',c.runId);
end

function require_most(c)
if exist(c.matpowerPath,'dir'), addpath(genpath(c.matpowerPath)); end
if exist('most','file') ~= 2 || exist('loadmd','file') ~= 2
    error('case1354:MOSTNotFound','MATPOWER MOST was not found under %s.', c.matpowerPath);
end
end

function [loadMW, pmax, hourlyCost, audit] = hourly_profiles(data, dataBase, hours, baseConfig, mpc, activeGen)
nt=numel(hours); ng=size(mpc.gen,1); loadMW=zeros(nt,1); pmax=zeros(nt,ng);
hourlyCost=zeros(nt,ng,size(mpc.gencost,2));
baseLoad=sum(mpc.bus(:,3));
for k=1:nt
    hour=hours(k);
    loadMW(k)=scheduled_total_load(data.LoadSchedule,hour,baseLoad);
    [mk,~]=build_matpower_case(dataBase,hour,baseConfig);
    pmax(k,:)=mk.gen(activeGen,9).';
    hourlyCost(k,:,:)=mk.gencost(activeGen,:);
end
audit=table(hours(:),loadMW,repmat(baseLoad,nt,1),loadMW-baseLoad, ...
    'VariableNames',{'Hour','ScheduledTotalLoadMW','BaseCaseLoadMW','LoadDifferenceMW'});
end

function total = scheduled_total_load(t,hour,fallback)
col="Hour"+hour;
if ~ismember(col,t.Properties.VariableNames), total=fallback; return; end
v=t.(col); if ~isnumeric(v),v=str2double(string(v));end; v=double(v);v=v(isfinite(v));
if isempty(v)||sum(v)<=0,total=fallback;else,total=sum(v);end
end

function profiles = make_profiles(loadMW,pmax,hourlyCost)
[~,~,~,~,~,~,~,~,~,~,~,~,CT_REP,~,~,~,CT_TLOAD,~,CT_LOAD_ALL_PQ] = idx_ct;
profiles(1)=struct('type','mpcData','table',CT_TLOAD,'rows',0,'col',CT_LOAD_ALL_PQ, ...
    'chgtype',CT_REP,'values',reshape(loadMW,[],1,1));
% Generator availability is replaced at each hour; each row maps to its source unit.
[~,~,~,CT_TGEN] = idx_ct;
[~,~,~,~,~,~,~,~,PMAX] = idx_gen;
profiles(2)=struct('type','mpcData','table',CT_TGEN,'rows',(1:size(pmax,2)).', ...
    'col',PMAX,'chgtype',CT_REP,'values',reshape(pmax,size(pmax,1),1,size(pmax,2)));
% Preserve each hour's GenBid PWL curve. Columns 4:end include NCOST and
% all breakpoint/cost values; startup/shutdown columns are set separately.
[~,~,~,~,~,~,~,~,CT_TGENCOST] = idx_ct;
nt=size(hourlyCost,1); ng=size(hourlyCost,2); nc=size(hourlyCost,3);
for col = 4:nc
    profiles(end+1)=struct('type','mpcData','table',CT_TGENCOST,'rows',(1:ng).', ...
        'col',col,'chgtype',CT_REP,'values',reshape(hourlyCost(:,:,col),nt,1,ng)); %#ok<AGROW>
end
end

function [mpc,xgd,audit] = make_xgd_and_costs(data,mpc,c,activeGen,sourceInitialStatus)
ng=size(mpc.gen,1); g=data.Generator(activeGen,:); init=data.Initial(activeGen,:);
status=logical(sourceInitialStatus(:)); initialPg=mpc.gen(:,2);
duration=col(init,'Duration（分钟）',nan); if numel(duration)~=ng,duration=nan(ng,1);end
minUp=ceil(col(g,'MinOnTime (分钟)',60)/60); minDown=ceil(col(g,'MinOFFTime (分钟)',60)/60);
minUp(~isfinite(minUp)|minUp<1)=1; minDown(~isfinite(minDown)|minDown<1)=1;
ramp=col(g,'Ramp_AGC (MW/分钟)',nan)*60; missing=~isfinite(ramp)|ramp<=0; ramp(missing)=inf;
if ~c.useIntertemporalRamp, ramp(:)=inf; end
% MOST bounds load-following transitions by these quantities. RAMP_30 is
% stored as a 30-minute rate, so half of the hourly MW ramp is supplied.
mpc.gen(:,19)=ramp/2; %#ok<NASGU>
commit=double(is_conventional(string(g.('GenType'))) & mpc.gen(:,9)>0);
elapsed=max(1,ceil(duration/60)); elapsed(~isfinite(elapsed))=1;
initialState=elapsed; initialState(~status)=-elapsed(~status);
xgdTable.colnames={'CommitKey','InitialPg','InitialState','MinUp','MinDown', ...
    'PositiveLoadFollowReserveQuantity','NegativeLoadFollowReserveQuantity'};
xgdTable.data=[commit initialPg initialState minUp minDown ramp ramp];
xgd=loadxgendata(xgdTable,mpc);
startup=col(g,'StartUpCost (万元）',0)*10000; shutdown=col(g,'ShutDownCost (万元）',0)*10000;
mpc.gencost(:,2)=startup; mpc.gencost(:,3)=shutdown;
audit=table((1:ng).',string(g.('GenName')),commit,minUp,minDown,ramp,missing,startup,shutdown, ...
 'VariableNames',{'GeneratorRow','GenName','CommitEligible','MinUpHour','MinDownHour','RampMWPerHour','MissingRampSkipped','StartupCostYuan','ShutdownCostYuan'});
end

function tf=is_conventional(types)
types=lower(strtrim(types)); tf=~contains(types,["wind","solar","pv","photovoltaic","battery","pump"]);
end
function v=col(t,name,d),if~ismember(name,t.Properties.VariableNames),v=d*ones(height(t),1);else,v=t.(name);if~isnumeric(v),v=str2double(string(v));end;v=double(v);v(~isfinite(v))=d;end,end

function tables = result_tables(mdo,meta,hours,loadAudit,unitAudit,c)
nt=numel(hours); ng=numel(meta.genName); pg=nan(nt,ng); status=nan(nt,ng); energyCost=nan(nt,1); load=nan(nt,1); gen=nan(nt,1);
success=isfield(mdo.results,'success') && logical(mdo.results.success);
objective=nan; if isfield(mdo.results,'f'),objective=mdo.results.f;end
if ~success
    tables.MultiPeriodDispatch=table(zeros(0,1),zeros(0,1),strings(0,1),zeros(0,1),false(0,1),false(0,1),false(0,1), ...
        'VariableNames',{'Hour','GeneratorRow','GenName','PgMW','Committed','Startup','Shutdown'});
    tables.MultiPeriodSummary=table(hours(:),loadAudit.ScheduledTotalLoadMW,nan(nt,1),nan(nt,1),nan(nt,1),nan(nt,1),repmat(string(c.mode),nt,1),repmat(false,nt,1), ...
        'VariableNames',{'Hour','TotalLoadMW','TotalGenerationMW','GenerationMinusLoadMW','EnergyOfferCost','TotalHorizonObjective','Mode','Success'});
    tables.LoadProfileAudit=loadAudit; tables.UnitCommitmentAudit=unitAudit;
    tables.ModelScope=table(string(c.mode),"Joint 24-hour DC MOST", "MOST returned infeasible/no solution; inspect MultiPeriodSummary and relax only a diagnosed constraint.", ...
        'VariableNames',{'Mode','OptimizationModel','Limitation'});
    return;
end
for t=1:nt
    r=mdo.flow(t,1,1).mpc; pg(t,:)=r.gen(:,2).'; status(t,:)=r.gen(:,8).';
    load(t)=sum(r.bus(:,3)); gen(t)=sum(r.gen(:,2)); energyCost(t)=sum(totcost(r.gencost,r.gen(:,2)));
end
hourCol=reshape(repmat(hours(:).',ng,1),[],1);
genRow=repmat((1:ng).',nt,1);pgCol=reshape(pg.',[],1);statusCol=reshape(status.',[],1)>0;
if c.mode=="SCUC"
    initialCommitted=mdo.InitialState(:).'>0;
    previousCommitted=[initialCommitted;status(1:end-1,:)>0];
    startup=status>0&~previousCommitted;
    shutdown=status<=0&previousCommitted;
else
    startup=false(nt,ng);shutdown=false(nt,ng);
end
nameCol=repmat(string(meta.genName(:)),nt,1);
startupCol=reshape(startup.',[],1);shutdownCol=reshape(shutdown.',[],1);
columnHeights=[size(hourCol,1),size(genRow,1),size(nameCol,1),size(pgCol,1), ...
    size(statusCol,1),size(startupCol,1),size(shutdownCol,1)];
if any(columnHeights~=columnHeights(1))
    error('case1354:DispatchTableSizeMismatch', ...
        'Dispatch column heights are [%s].',strjoin(string(columnHeights),','));
end
tables.MultiPeriodDispatch=table(hourCol,genRow,nameCol,pgCol,statusCol,startupCol,shutdownCol, ...
 'VariableNames',{'Hour','GeneratorRow','GenName','PgMW','Committed','Startup','Shutdown'});
tables.MultiPeriodSummary=table(hours(:),load,gen,gen-load,energyCost,repmat(objective,nt,1),repmat(string(c.mode),nt,1),repmat(true,nt,1), ...
 'VariableNames',{'Hour','TotalLoadMW','TotalGenerationMW','GenerationMinusLoadMW','EnergyOfferCost','TotalHorizonObjective','Mode','Success'});
tables.LoadProfileAudit=loadAudit; tables.UnitCommitmentAudit=unitAudit;
tables.ModelScope=table(string(c.mode),"Joint 24-hour DC MOST", ...
 "Network: DC; AC OPF remains required for voltage/reactive validation", ...
 'VariableNames',{'Mode','OptimizationModel','Limitation'});
end

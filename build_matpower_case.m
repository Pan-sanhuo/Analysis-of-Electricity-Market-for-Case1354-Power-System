function [mpc, meta] = build_matpower_case(data, hour, config)
%BUILD_MATPOWER_CASE 将 Excel 的基础数据转换为 MATPOWER mpc 结构。
busT=data.Bus; brT=data.Branch; genT=data.Generator;
meta=struct('targetHour',hour,'genName',case1354_generator_names(genT,data.Initial));
mpc=struct('version','2','baseMVA',100);
bn=n(busT,'BusNo',0); bt=n(busT,'BusType',1); bt(bt==0)=1;
mpc.bus=[bn bt n(busT,'Pd',0) n(busT,'Qd',0) n(busT,'Gs',0) n(busT,'Bs',0) ...
    n(busT,'Area',1) n(busT,'Vm',1) n(busT,'Va',0) n(busT,'baseKV',0) ...
    n(busT,'Zone',1) n(busT,'Vmax',1.1) n(busT,'Vmin',0.9)];
mpc.branch=[n(brT,'FromBus',0) n(brT,'ToBus',0) n(brT,'R',0) n(brT,'X',0) n(brT,'B',0) ...
    n(brT,'Rate1',0) n(brT,'Rate2',0) n(brT,'Rate3',0) n(brT,'Ratio',0) n(brT,'Angle',0) ...
    n(brT,'status',1) -360*ones(height(brT),1) 360*ones(height(brT),1)];
ng=height(genT); names=meta.genName; init=data.Initial;
pg=zeros(ng,1); qg=zeros(ng,1); vg=ones(ng,1); status=ones(ng,1);
for i=1:ng
    % Initial 与 Generator 在该工作簿中按 GeneratorRow 一一对应。
    % Initial.GenName 使用 GenGen... 包装，不能再依赖名称相似匹配。
    ix=[]; if i<=height(init), ix=i; end
    if ~isempty(ix)
        pg(i)=at(init,ix,'Pg（MW）',0); qg(i)=at(init,ix,'Qg（MW）',0); vg(i)=at(init,ix,'Vg',1); status(i)=at(init,ix,'Status',1);
    else
        pminValues=n(genT,'Pmin（MW）',0);
        pg(i)=max(0,pminValues(i));
    end
end
meta.generatorRow=(1:ng).';
meta.generatorKey="G"+string(meta.generatorRow)+"_B"+string(n(genT,'BusNo',0))+"_"+names;
mpc.gen=[n(genT,'BusNo',0) pg qg n(genT,'Qmax（MVAr）',0) n(genT,'Qmin（MVAr）',0) vg mpc.baseMVA*ones(ng,1) status ...
    n(genT,'Pmax（MW）',0) n(genT,'Pmin（MW）',0) zeros(ng,6) ...
    n(genT,'Ramp_AGC (MW/分钟)',0) n(genT,'Ramp_10M (MW/分钟)',0) n(genT,'Ramp_30M(MW/分钟)',0) n(genT,'APF',0)];
[mpc,meta.loadAllocation,meta.loadAllocationSummary]=apply_load_schedule(mpc,data,hour,config);
meta.modelValid=all(meta.loadAllocationSummary.AllocationSuccess);
if meta.modelValid, meta.modelError=""; else, meta.modelError=meta.loadAllocationSummary.Message; end
[mpc,meta.generatorSchedule]=apply_generator_schedule(mpc,data,hour,config);
[mpc.gencost,mpc.gen,meta.costCurve,meta.bidIssues]=build_gencost_matrix(data,mpc.gen,names,hour,config);
[mpc,meta.appliedTransmissionConstraints]=apply_transmission_constraints(mpc,data,hour,config);
meta.originalPmin=mpc.gen(:,10); meta.originalPmax=mpc.gen(:,9);
meta.feasibilityCheck=check_case_feasibility(mpc,hour);
meta.scalingDiagnostics=build_scaling_diagnostics(mpc,hour);
end

function v=n(t,c,d), if ~ismember(c,t.Properties.VariableNames), v=d*ones(height(t),1); else, v=t.(c); if ~isnumeric(v), v=str2double(string(v)); end; v=double(v); v(isnan(v))=d; end, end
function v=at(t,i,c,d), x=n(t,c,d); v=x(i); end

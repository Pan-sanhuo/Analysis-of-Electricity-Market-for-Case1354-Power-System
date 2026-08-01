function [mpc, check] = apply_ramp_constraints(mpc, previousOpf, data, hour)
%APPLY_RAMP_CONSTRAINTS 将相邻小时爬坡能力转成当前 OPF 的 Pmin/Pmax。
% 仅表示相邻小时可行性，不是跨 24 小时联合优化，也不包含启停和最小开停机约束。
origMin=mpc.gen(:,10); origMax=mpc.gen(:,9); ramp=data.Generator.('Ramp_AGC (MW/分钟)');
if ~isnumeric(ramp),ramp=str2double(string(ramp));end; ramp=double(ramp); ramp(isnan(ramp))=0;
prev=previousOpf.gen(:,2); up=ramp*60; down=ramp*60;
currentOnline=mpc.gen(:,8)>0;
previousOnline=previousOpf.gen(:,8)>0;
rampApplied=currentOnline & previousOnline & ramp>0;
missingRamp=currentOnline & previousOnline & ramp<=0;

% 只对相邻两小时都在线的机组施加爬坡约束。无有效报价而退出市场的机组
% GEN_STATUS=0、Pg=0，若仍用原始 Pmin 计算，会错误地产生 Pmin>Pmax。
% 爬坡值为 0/缺失表示本算例没有可用爬坡参数，不解释为“机组必须固定出力”。
mpc.gen(rampApplied,9)=min(origMax(rampApplied),prev(rampApplied)+up(rampApplied));
mpc.gen(rampApplied,10)=max(origMin(rampApplied),prev(rampApplied)-down(rampApplied));
mpc.gen(~currentOnline,2:3)=0;

conflict=rampApplied & mpc.gen(:,10)>mpc.gen(:,9);
skipReason=strings(size(ramp));
skipReason(~currentOnline)="当前小时离线";
skipReason(currentOnline & ~previousOnline)="上一小时离线，未建模启动爬坡";
skipReason(missingRamp)="爬坡值为0/缺失，跳过约束";
skipReason(rampApplied)="";
names=case1354_generator_names(data.Generator,data.Initial);
check=table(repmat(hour,numel(names),1),names,origMin,origMax,prev,up,down, ...
    mpc.gen(:,10),mpc.gen(:,9),missingRamp,rampApplied,skipReason,conflict, ...
    'VariableNames',{'Hour','GenName','OriginalPminMW','OriginalPmaxMW', ...
    'PreviousPgMW','RampUpMW','RampDownMW','AppliedPminMW','AppliedPmaxMW', ...
    'MissingOrZeroRamp','RampConstraintApplied','SkipReason','ConstraintConflict'});
if any(missingRamp)
    warning('case1354:MissingRamp', ...
        'Hour%d: 有 %d 台在线机组爬坡数据为 0/缺失，已跳过约束并保留当前小时边界。', ...
        hour,sum(missingRamp));
end
if any(conflict), error('case1354:RampConflict','Hour%d: 爬坡约束造成 Pmin > Pmax。',hour); end
end

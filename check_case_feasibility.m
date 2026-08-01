function check = check_case_feasibility(mpc,hour)
%CHECK_CASE_FEASIBILITY 在调用求解器前检查容量、边界和网络结构。
online=mpc.gen(:,8)>0;loadP=sum(mpc.bus(:,3));loadQ=sum(mpc.bus(:,4));
pmin=sum(mpc.gen(online,10));pmax=sum(mpc.gen(online,9));
qmin=sum(mpc.gen(online,5));qmax=sum(mpc.gen(online,4));
pConflict=sum(online&mpc.gen(:,10)>mpc.gen(:,9));
qConflict=sum(online&mpc.gen(:,5)>mpc.gen(:,4));
pminLoadConflict=loadP<pmin;
qCapabilityConflict=loadQ<qmin||loadQ>qmax;
islands=estimate_islands(mpc);refCount=sum(mpc.bus(:,2)==3);
active=mpc.branch(:,11)>0;zeroX=sum(active & mpc.branch(:,4)==0);
tinyX=sum(active & abs(mpc.branch(:,4))>0 & abs(mpc.branch(:,4))<1e-6);
tap=mpc.branch(:,9);abnormalTap=sum(active & tap~=0 & (tap<0.5|tap>2));
hardFailure=loadP>pmax || pConflict>0 || qConflict>0 || islands~=1 || refCount~=1 || zeroX>0;
message="检查通过";
if hardFailure
    parts=strings(0,1);
    if loadP>pmax,parts(end+1)="有功负荷超过在线Pmax";end
    if pConflict>0,parts(end+1)="Pmin>Pmax";end
    if qConflict>0,parts(end+1)="Qmin>Qmax";end
    if islands~=1,parts(end+1)="网络不是单岛";end
    if refCount~=1,parts(end+1)="参考节点数量不为1";end
    if zeroX>0,parts(end+1)="在线支路X=0";end
    message=strjoin(parts,"；");
elseif pminLoadConflict||qCapabilityConflict
    parts=strings(0,1);
    if pminLoadConflict,parts(end+1)="总负荷低于在线Pmin；需结合网损判断";end
    if qCapabilityConflict,parts(end+1)="无功需求在总Q能力范围外；需结合并联元件判断";end
    message="近似容量风险："+strjoin(parts,"；");
end
check=table(hour,loadP,loadQ,pmin,pmax,qmin,qmax,pminLoadConflict,qCapabilityConflict, ...
    pConflict,qConflict,islands, ...
    refCount,zeroX,tinyX,abnormalTap,hardFailure,message, ...
    'VariableNames',{'Hour','TotalLoadMW','TotalLoadMVAr','OnlinePminMW', ...
    'OnlinePmaxMW','OnlineQminMVAr','OnlineQmaxMVAr','PminLoadConflict', ...
    'QCapabilityConflict','PminPmaxConflictCount', ...
    'QminQmaxConflictCount','IslandCount','ReferenceBusCount','ZeroXBranchCount', ...
    'TinyXBranchCount','AbnormalTapCount','HardFailure','Message'});
end

function n=estimate_islands(mpc)
b=mpc.bus(:,1);if isempty(b),n=0;return;end
on=mpc.branch(:,11)>0;
[fi,f]=ismember(mpc.branch(on,1),b);[ti,t]=ismember(mpc.branch(on,2),b);
valid=fi&ti;network=graph(f(valid),t(valid),[],numel(b));n=max(conncomp(network));
end

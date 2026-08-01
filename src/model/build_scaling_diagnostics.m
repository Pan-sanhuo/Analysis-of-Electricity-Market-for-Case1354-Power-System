function diagnostics = build_scaling_diagnostics(mpc,hour)
%BUILD_SCALING_DIAGNOSTICS 汇总可能造成病态矩阵的参数尺度和退化约束。
rows=cell(0,7);
    function add(type,values,count,issue)
        values=abs(double(values(:)));values=values(isfinite(values));
        nz=values(values>0);
        if isempty(values),minimum=nan;maximum=nan;ratio=nan;
        else
            minimum=min(values);maximum=max(values);
            if isempty(nz),ratio=nan;else,ratio=max(nz)/min(nz);end
        end
        rows(end+1,:)={hour,string(type),minimum,maximum,ratio,double(count),string(issue)};
    end

active=mpc.branch(:,11)>0;x=mpc.branch(active,4);r=mpc.branch(active,3);
b=mpc.branch(active,5);rate=mpc.branch(active,6);tap=mpc.branch(active,9);
add('BranchX',x,sum(x==0|abs(x)<1e-6),'X=0/极小会导致网络雅可比病态');
rx=abs(r)./max(abs(x),eps);add('BranchRtoX',rx,sum(rx>10),'极大R/X可能表示单位或录入错误');
add('BranchChargingB',b,sum(abs(b)>10),'极大线路充电电纳');
add('BranchRateA',rate(rate>0),sum(rate>0&rate<1),'极小线路容量造成强退化约束');
add('TransformerTap',tap(tap~=0),sum(tap~=0&(tap<0.5|tap>2)),'异常变压器变比');

ends=sort(mpc.branch(active,1:2),2);duplicateBranches=size(ends,1)-size(unique(ends,'rows'),1);
add('ParallelBranchPairs',duplicateBranches,duplicateBranches,'重复端点支路需核对回路编号与参数');

online=mpc.gen(:,8)>0;fixedP=online&abs(mpc.gen(:,9)-mpc.gen(:,10))<=1e-9;
fixedQ=online&abs(mpc.gen(:,4)-mpc.gen(:,5))<=1e-9;
add('GeneratorPmax',mpc.gen(online,9),sum(online&mpc.gen(:,9)<=0),'在线机组Pmax为0');
add('FixedActivePower',mpc.gen(fixedP,9),sum(fixedP),'大量Pmin=Pmax增加等式退化风险');
add('FixedReactivePower',mpc.gen(fixedQ,4),sum(fixedQ),'大量Qmin=Qmax增加等式退化风险');
fixedMismatch=fixedP&abs(mpc.gen(:,2)-mpc.gen(:,9))>1e-8;
add('FixedPgInitialMismatch',abs(mpc.gen(fixedMismatch,2)-mpc.gen(fixedMismatch,9)),sum(fixedMismatch),'固定机组Pg初值不在固定值');
unitSignature=mpc.gen(online,[1 4 5 9 10]);
duplicateUnits=size(unitSignature,1)-size(unique(unitSignature,'rows'),1);
add('DuplicateGeneratorSignature',duplicateUnits,duplicateUnits,'同母线完全相同机组可能造成对称退化');

[slopes,duplicateBreaks,zeroCost]=cost_metrics(mpc.gencost);
add('MarginalBidSlope',slopes,sum(slopes==0),'报价尺度过大或零斜率过多');
add('DuplicateCostBreakpoints',duplicateBreaks,duplicateBreaks,'成本曲线存在重复功率断点');
add('ZeroCostCurves',zeroCost,zeroCost,'零成本曲线过多会造成经济排序退化');
diagnostics=cell2table(rows,'VariableNames',{'Hour','ParameterType','MinimumValue', ...
    'MaximumValue','Ratio','PotentialIssueCount','PotentialIssue'});
end

function [slopes,duplicateBreaks,zeroCost]=cost_metrics(gencost)
slopes=zeros(0,1);duplicateBreaks=0;zeroCost=0;
for i=1:size(gencost,1)
    if gencost(i,1)==1
        n=gencost(i,4);xy=gencost(i,5:4+2*n);x=xy(1:2:end);y=xy(2:2:end);
        dx=diff(x);dy=diff(y);duplicateBreaks=duplicateBreaks+sum(dx<=0);
        valid=dx>0;slopes=[slopes;(dy(valid)./dx(valid)).']; %#ok<AGROW>
        if all(abs(y)<eps),zeroCost=zeroCost+1;end
    elseif gencost(i,1)==2
        n=gencost(i,4);coeff=gencost(i,5:4+n);
        if all(abs(coeff)<eps),zeroCost=zeroCost+1;end
    end
end
end

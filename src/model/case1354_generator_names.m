function names = case1354_generator_names(genTbl, initTbl)
%CASE1354_GENERATOR_NAMES 生成可用于跨表匹配的唯一机组名称。
% Generator 表存在同名机组时，优先按 Initial 表的顺序恢复名称；其余重复项加后缀。
raw = normalize_generator_names(genTbl.('GenName'));
names = raw;
if nargin >= 2 && ~isempty(initTbl) && ismember('GenName', initTbl.Properties.VariableNames)
    init = normalize_generator_names(initTbl.('GenName'));
    for i = 1:height(genTbl)
        if sum(raw == raw(i)) > 1 && i <= numel(init) && strlength(init(i)) > 0
            % Initial 使用 GenGen124A 形式引用 Generator.Gen124A。
            % 第一次统一标准化后为 Gen124A，此处只解析 Initial 的引用包装层。
            candidate=init(i);
            if startsWith(candidate,"Gen",'IgnoreCase',true)
                candidate=extractAfter(candidate,3);
            end
            names(i)=candidate;
        end
    end
end
for i = 1:numel(names)
    if any(names(1:i-1) == names(i))
        names(i) = names(i) + "_" + string(i);
    end
end
end

function names = normalize_generator_names(names)
%NORMALIZE_GENERATOR_NAMES 统一机组名称，只移除字符串开头的 Gen 前缀。
names=strtrim(string(names));
names=regexprep(names,'^(?i:Gen)','');
names=strtrim(names);
end

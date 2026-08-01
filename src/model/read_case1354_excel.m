function data = read_case1354_excel(dataFile)
%READ_CASE1354_EXCEL 读取 case1354 工作簿，并保留原始列名。
sheetNames = {'Bus','Branch','Zone','Interchange','TieLine','ASRegion', ...
    'Generator','LoadEntity','BranchGroup','Nomogram','UCOptions', ...
    'UCParameters','Initial','LoadForecast','GenBid','LoadBid', ...
    'TransmissionConstr','GeneratorSchedule','LoadSchedule','ShiftFactor', ...
    'TransmissionSchedule','ASRequirement','ASBid'};
if exist(dataFile, 'file') ~= 2
    error('case1354:InputFileNotFound', '找不到 Excel 数据文件: %s', dataFile);
end
persistent cachedPath cachedStamp cachedData
info=dir(dataFile);stamp=string(info.bytes)+"_"+string(info.datenum);
if ~isempty(cachedData)&&strcmpi(string(cachedPath),string(dataFile))&&cachedStamp==stamp
    data=cachedData;
    return;
end
data = struct('sourceFile', dataFile);
for i = 1:numel(sheetNames)
    name = sheetNames{i};
    try
        tbl = readtable(dataFile, 'Sheet', name, 'VariableNamingRule', 'preserve');
    catch ME
        error('case1354:MissingSheet', '无法读取工作表 %s: %s', name, ME.message);
    end
    data.(name) = remove_empty_rows(tbl);
end
cachedPath=dataFile;cachedStamp=stamp;cachedData=data;
end

function tbl = remove_empty_rows(tbl)
if isempty(tbl) || height(tbl) == 0, return; end
keep = false(height(tbl), 1);
for i = 1:width(tbl)
    v = tbl{:,i};
    if isnumeric(v) || islogical(v)
        keep = keep | ~isnan(double(v));
    else
        s = string(v);
        keep = keep | (~ismissing(s) & strlength(strtrim(s)) > 0);
    end
end
tbl = tbl(keep,:);
end

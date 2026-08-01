function write_output_excel(outFile, tables)
%WRITE_OUTPUT_EXCEL 将所有非空结果表写入同一个 Excel 工作簿。
[outDir,~,~]=fileparts(outFile); if exist(outDir,'dir')~=7,mkdir(outDir);end
if exist(outFile,'file')==2, delete(outFile); end
names=fieldnames(tables);
for i=1:numel(names)
    tbl=tables.(names{i}); if istable(tbl), writetable(tbl,outFile,'Sheet',names{i}); end
end
end

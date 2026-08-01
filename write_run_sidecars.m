function paths=write_run_sidecars(config,manifest,runLog)
%WRITE_RUN_SIDECARS Write JSON configuration/manifest and CSV hourly log.
paths=struct('configJson',"",'manifestJson',"",'logCsv',"");
if ~config.writeRunSidecars,return;end
[folder,name,~]=fileparts(config.outFile);
paths.configJson=fullfile(folder,name+"_config.json");
paths.manifestJson=fullfile(folder,name+"_manifest.json");
paths.logCsv=fullfile(folder,name+"_runlog.csv");
write_text(paths.configJson,jsonencode(config,'PrettyPrint',true));
write_text(paths.manifestJson,jsonencode(table2struct(manifest),'PrettyPrint',true));
writetable(runLog,paths.logCsv);
end
function write_text(path,value)
fid=fopen(path,'w','n','UTF-8');if fid<0,error('case1354:SidecarWriteFailed','Cannot write %s.',path);end
cleaner=onCleanup(@() fclose(fid));fprintf(fid,'%s',value); %#ok<NASGU>
end

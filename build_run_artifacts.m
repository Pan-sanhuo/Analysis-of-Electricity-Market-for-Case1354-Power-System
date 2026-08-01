function artifacts=build_run_artifacts(config,tables,runInfo,elapsedSeconds)
%BUILD_RUN_ARTIFACTS Build reproducibility manifest, config and hourly log.
artifacts=struct();artifacts.RunConfiguration=config_table(config);
inputInfo=dir(config.dataFile);codeFile=which('case1354_multiperiod_market');
try,mpVersion=string(mpver);catch,mpVersion="Unknown";end
manifest=table(string(config.runId),string(runInfo.StartTime),string(datetime('now','TimeZone','local')),elapsedSeconds, ...
 string(config.dataFile),file_sha256(config.dataFile),inputInfo.bytes,string(inputInfo.date), ...
 string(codeFile),file_sha256(codeFile),string(version),mpVersion,string(config.outFile), ...
 'VariableNames',{'RunId','StartTime','EndTime','ElapsedSeconds','InputFile','InputSHA256','InputBytes','InputModified','EntryPoint','CodeSHA256','MATLABVersion','MATPOWERVersion','OutputExcel'});
artifacts.RunManifest=manifest;artifacts.RunLog=run_log(tables,elapsedSeconds);
end

function t=config_table(c)
names=fieldnames(c);values=strings(numel(names),1);
for k=1:numel(names)
 try,values(k)=string(jsonencode(c.(names{k})));catch,values(k)=string(c.(names{k}));end
end
t=table(string(names),values,'VariableNames',{'Setting','Value'});
end
function t=run_log(tables,elapsed)
s=tables.MultiPeriodSummary;n=height(s);securityCount=zeros(n,1);message=repmat("Solved",n,1);
if isfield(tables,'SecurityContingencyResults')
 q=tables.SecurityContingencyResults;
 for k=1:n,securityCount(k)=sum(q.Hour==s.Hour(k));end
end
message(~s.Success)="Joint optimization failed; inspect MultiPeriodPrecheck.";
t=table(s.Hour,s.Success,s.TotalLoadMW,s.TotalGenerationMW,s.TotalHorizonObjective,securityCount,repmat(elapsed,n,1),message, ...
 'VariableNames',{'Hour','Success','TotalLoadMW','TotalGenerationMW','Objective','SecurityScenarioCount','RunElapsedSeconds','Message'});
end
function hash=file_sha256(path)
fid=fopen(path,'rb');if fid<0,hash="";return;end
cleaner=onCleanup(@() fclose(fid));bytes=fread(fid,Inf,'*uint8'); %#ok<NASGU>
md=java.security.MessageDigest.getInstance('SHA-256');md.update(bytes);raw=typecast(md.digest(),'uint8');
hash=lower(string(reshape(dec2hex(raw,2).',1,[])));
end

function stageDir = prepareStageDirectory(outputRoot, stageName, overwrite)
%PREPARESTAGEDIRECTORY Create one clean, protected derived-output directory.

stageDir = string(fullfile(outputRoot, stageName));
completionPath = fullfile(stageDir, "stage_complete.txt");

% An incomplete stage is disposable: remove it and restart from a clean
% directory. A completed stage is protected unless replacement is explicit.
if isfolder(stageDir)
    if isfile(completionPath) && ~overwrite
        error("stpt:ExistingStage", ...
            "%s is complete. Set cfg.execution.overwrite=true to replace " + ...
            "it: %s", stageName, stageDir);
    end
    if isfile(completionPath)
        fprintf("Replacing completed stage: %s\n", stageDir);
    else
        fprintf("Discarding incomplete stage: %s\n", stageDir);
    end
    rmdir(stageDir, "s");
end
mkdir(stageDir);
end

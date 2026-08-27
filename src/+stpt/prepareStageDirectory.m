function stageDir = prepareStageDirectory(outputRoot, stageName, overwrite)
%PREPARESTAGEDIRECTORY Create one clean, protected derived-output directory.

stageDir = string(fullfile(outputRoot, stageName));
completionPath = fullfile(stageDir, "stage_complete.txt");

% Existing output is never modified implicitly. Explicit overwrite removes the
% complete derived stage directory so stale plots and markers cannot survive.
if isfolder(stageDir)
    if ~overwrite
        if isfile(completionPath)
            state = "complete";
        else
            state = "incomplete";
        end
        error("stpt:ExistingStage", ...
            "%s output is already %s. Set cfg.execution.overwrite=true " + ...
            "to replace it: %s", stageName, state, stageDir);
    end
    rmdir(stageDir, "s");
end
mkdir(stageDir);
end

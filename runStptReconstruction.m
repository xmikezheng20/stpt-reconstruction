function result = runStptReconstruction(cfg)
%RUNSTPTRECONSTRUCTION Run the configured STPT reconstruction stages.
%
% RESULT = RUNSTPTRECONSTRUCTION(CFG) is the single pipeline entry point.
% During initial development CFG.execution.stopAfter is "index", so only the
% read-only indexing and geometry-QC stage runs.

arguments
    cfg (1,1) struct
end

repoRoot = fileparts(mfilename("fullpath"));
addpath(fullfile(repoRoot, "src"));

cfg = stpt.validateConfig(cfg);
stageDir = fullfile(cfg.paths.outputRoot, "01_index");
completionPath = fullfile(stageDir, "stage_complete.txt");

% A stage directory represents one coherent run. Refuse both completed and
% partial directories by default. An explicit overwrite starts from an empty
% derived-output directory, preventing stale artifacts or completion markers.
if isfolder(stageDir)
    if ~cfg.execution.overwrite
        if isfile(completionPath)
            state = "complete";
        else
            state = "incomplete";
        end
        error("stpt:ExistingStage", ...
            "Stage 1 output is already %s. Set cfg.execution.overwrite=true " + ...
            "to replace it: %s", state, stageDir);
    end
    rmdir(stageDir, "s");
end
mkdir(stageDir);

logPath = fullfile(stageDir, "stage.log");
diary(logPath);
diaryCleanup = onCleanup(@() diary("off"));

% Capture the exact code state before producing any scientific artifacts.
provenance = stpt.captureProvenance(repoRoot, cfg);

fprintf("\nSTPT reconstruction\n");
fprintf("Experiment: %s\n", cfg.experiment.id);
fprintf("Started:    %s\n", string(datetime("now")));
fprintf("MATLAB:     %s\n", version);
fprintf("Raw root:   %s\n", cfg.paths.rawRoot);
fprintf("Output:     %s\n\n", cfg.paths.outputRoot);
fprintf("Code commit:     %s%s\n", provenance.repository.commit, ...
    dirtySuffix(provenance.repository.isDirty));
fprintf("StitchIt commit: %s%s\n\n", provenance.stitchIt.commit, ...
    dirtySuffix(provenance.stitchIt.isDirty));

save(fullfile(stageDir, "resolved_config.mat"), "cfg", "provenance");
stpt.writeProvenance(provenance, fullfile(stageDir, "provenance.txt"));

fprintf("Stage 1/4: build and validate native-data index\n");
datasetIndex = stpt.buildIndex(cfg);
datasetIndex.provenance = provenance;
stpt.writeIndexQC(datasetIndex, cfg, stageDir);
save(fullfile(stageDir, "datasetIndex.mat"), "datasetIndex", "-v7.3");
writelines("Stage 1 completed " + string(datetime("now")), completionPath);

fprintf("Stage 1 complete: %s\n", string(datetime("now")));
fprintf("Indexed %d sections, %d layers, %d tiles/layer, and %d channels.\n", ...
    numel(datasetIndex.sections), datasetIndex.geometry.layersPerSection, ...
    datasetIndex.geometry.tilesPerLayer, numel(datasetIndex.channels));
fprintf("QC outputs: %s\n\n", stageDir);

result = struct("config", cfg, "index", datasetIndex, ...
    "stageDirectory", string(stageDir));

if strcmpi(cfg.execution.stopAfter, "index")
    fprintf("Stopped after the configured Stage 1 checkpoint.\n");
    return
end

error("stpt:NotImplemented", ...
    "Stages after indexing have not been implemented yet.");
end

function suffix = dirtySuffix(isDirty)
% Make a dirty worktree impossible to overlook in the console and stage log.
if isDirty
    suffix = " (dirty worktree)";
else
    suffix = "";
end
end

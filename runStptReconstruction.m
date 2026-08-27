function result = runStptReconstruction(cfg)
%RUNSTPTRECONSTRUCTION Run configured STPT reconstruction stages in order.
%
% Completed prerequisite stages are loaded rather than regenerated. The scalar
% CFG.execution.overwrite applies only to the requested terminal stage.

arguments
    cfg (1,1) struct
end

repoRoot = fileparts(mfilename("fullpath"));
addpath(fullfile(repoRoot, "src"));
cfg = stpt.validateConfig(cfg);
targetStage = lower(string(cfg.execution.stopAfter));

% Stage 1 is either the requested target or a prerequisite for Stage 2.
indexDir = string(fullfile(cfg.paths.outputRoot, "01_index"));
indexComplete = isfile(fullfile(indexDir, "stage_complete.txt"));
if targetStage == "index" || ~indexComplete
    datasetIndex = runIndexStage(cfg, repoRoot, ...
        targetStage == "index" && cfg.execution.overwrite);
else
    fprintf("Loading completed Stage 1 index: %s\n", indexDir);
    saved = load(fullfile(indexDir, "datasetIndex.mat"), "datasetIndex");
    datasetIndex = saved.datasetIndex;
end

result = struct("config", cfg, "index", datasetIndex, ...
    "indexDirectory", indexDir);
if targetStage == "index"
    return
end

% Stage 2 fits one configured method through the shared illumination interface.
[illuminationModel, illuminationAudit, illuminationDir] = ...
    runIlluminationStage( ...
    datasetIndex, cfg, repoRoot, cfg.execution.overwrite);
result.illuminationModel = illuminationModel;
result.illuminationAudit = illuminationAudit;
result.illuminationDirectory = illuminationDir;
end

function datasetIndex = runIndexStage(cfg, repoRoot, overwrite)
% Build Stage 1 in a fresh directory and mark it complete only at the end.
stageDir = stpt.prepareStageDirectory(cfg.paths.outputRoot, "01_index", overwrite);
diary(fullfile(stageDir, "stage.log"));
diaryCleanup = onCleanup(@() diary("off"));
provenance = stpt.captureProvenance(repoRoot);
logRunHeader(cfg, provenance, "Stage 1/2: native-data index", stageDir);

save(fullfile(stageDir, "resolved_config.mat"), "cfg", "provenance");
stpt.writeProvenance(provenance, fullfile(stageDir, "provenance.txt"));

datasetIndex = stpt.index.build(cfg);
datasetIndex.provenance = provenance;
stpt.index.writeQC(datasetIndex, cfg, stageDir);
save(fullfile(stageDir, "datasetIndex.mat"), "datasetIndex", "-v7.3");
writelines("Stage 1 completed " + string(datetime("now")), ...
    fullfile(stageDir, "stage_complete.txt"));

fprintf("Stage 1 complete: indexed %d sections, %d layers, " + ...
    "%d tiles/layer, and %d channels.\n", numel(datasetIndex.sections), ...
    datasetIndex.geometry.layersPerSection, ...
    datasetIndex.geometry.tilesPerLayer, numel(datasetIndex.channels));
fprintf("Outputs: %s\n\n", stageDir);
end

function [model, audit, stageDir] = runIlluminationStage( ...
        datasetIndex, cfg, repoRoot, overwrite)
% Fit the configured illumination method and save its common outputs.
stageDir = stpt.prepareStageDirectory(cfg.paths.outputRoot, ...
    "02_illumination_pilot", overwrite);
diary(fullfile(stageDir, "stage.log"));
diaryCleanup = onCleanup(@() diary("off"));
provenance = stpt.captureProvenance(repoRoot);
logRunHeader(cfg, provenance, ...
    "Stage 2/2: illumination-model fit", stageDir);

save(fullfile(stageDir, "resolved_config.mat"), "cfg", "provenance");
stpt.writeProvenance(provenance, fullfile(stageDir, "provenance.txt"));

[model, audit] = stpt.illumination.fitModel(datasetIndex, cfg, stageDir);
model.provenance = provenance;
audit.provenance = provenance;
save(fullfile(stageDir, "illuminationModel.mat"), "model", "-v7.3");
save(fullfile(stageDir, "illuminationAudit.mat"), "audit", "-v7.3");
writelines("Stage 2 completed " + string(datetime("now")), ...
    fullfile(stageDir, "stage_complete.txt"));

fprintf("Stage 2 complete: %s fitted from %d training sections.\n", ...
    cfg.illumination.method, numel(cfg.illumination.trainingSections));
fprintf("Outputs: %s\n\n", stageDir);
end

function logRunHeader(cfg, provenance, stageLabel, stageDir)
% Print the same compact provenance header for every independently logged stage.
fprintf("\nSTPT reconstruction\n");
fprintf("Experiment:  %s\n", cfg.experiment.id);
fprintf("Stage:       %s\n", stageLabel);
fprintf("Started:     %s\n", string(datetime("now")));
fprintf("MATLAB:      %s\n", version);
fprintf("Raw root:    %s\n", cfg.paths.rawRoot);
fprintf("Stage output:%s\n", stageDir);
fprintf("Code commit: %s%s\n\n", provenance.repository.commit, ...
    dirtySuffix(provenance.repository.isDirty));
end

function suffix = dirtySuffix(isDirty)
% Make a dirty worktree impossible to overlook in the console and stage log.
if isDirty
    suffix = " (dirty worktree)";
else
    suffix = "";
end
end

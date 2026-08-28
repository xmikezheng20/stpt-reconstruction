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

% Stage 1 is either the requested target or a prerequisite for later stages.
indexDir = string(fullfile(cfg.paths.outputRoot, "01_index"));
indexComplete = isfile(fullfile(indexDir, "stage_complete.txt"));
if targetStage == "index" || ~indexComplete
    datasetIndex = runIndexStage(cfg, repoRoot, ...
        targetStage == "index" && cfg.execution.overwrite);
else
    fprintf("Loading completed Stage 1 index: %s\n", indexDir);
    datasetIndex = loadCompletedIndex(indexDir, cfg);
end
stpt.index.validateAgainstConfig(datasetIndex, cfg);

result = struct("config", cfg, "index", datasetIndex, ...
    "indexDirectory", indexDir);
if targetStage == "index"
    return
end

% Tissue selection is an independently auditable part of Stage 2.
if targetStage == "illuminationselection"
    [tissueSelection, selectionDir] = runIlluminationSelectionStage( ...
        datasetIndex, cfg, repoRoot, cfg.execution.overwrite);
    result.tissueSelection = tissueSelection;
    result.illuminationSelectionDirectory = selectionDir;
    return
end

% A tissue-aware model depends on the separately auditable selection. Create
% it when absent; otherwise validate and reuse the exact completed checkpoint.
if strcmpi(cfg.illumination.method, "tissueOtsu")
    selectionDir = string(fullfile(cfg.paths.outputRoot, "02_illumination", ...
        "tissue_otsu", "01_selection"));
    selectionPath = fullfile(selectionDir, "tissueSelection.mat");
    selectionComplete = isfile(selectionPath) && ...
        isfile(fullfile(selectionDir, "stage_complete.txt"));
    if selectionComplete
        stpt.illumination.tissueOtsu.loadSelection( ...
            selectionPath, datasetIndex, cfg);
        fprintf("Loading completed tissue selection: %s\n", selectionDir);
    else
        fprintf("Tissue selection is absent; running that Stage 2 substep first.\n");
        [~, selectionDir] = runIlluminationSelectionStage( ...
            datasetIndex, cfg, repoRoot, false);
    end
    result.illuminationSelectionDirectory = selectionDir;
end

% Stage 2 is regenerated only when it is the requested terminal stage or is
% absent. Stage 3 otherwise loads and validates the completed model.
illuminationDir = string(fullfile(cfg.paths.outputRoot, ...
    illuminationStageName(cfg)));
illuminationComplete = isfile(fullfile(illuminationDir, "stage_complete.txt"));
if targetStage == "illuminationmodel" || ~illuminationComplete
    [illuminationModel, illuminationAudit, illuminationDir] = ...
        runIlluminationStage(datasetIndex, cfg, repoRoot, ...
        targetStage == "illuminationmodel" && cfg.execution.overwrite);
else
    fprintf("Loading completed Stage 2 model: %s\n", illuminationDir);
    [illuminationModel, illuminationAudit] = ...
        stpt.illumination.loadCompletedModel( ...
        illuminationDir, datasetIndex, cfg);
end
result.illuminationModel = illuminationModel;
result.illuminationAudit = illuminationAudit;
result.illuminationDirectory = illuminationDir;

if targetStage == "illuminationmodel"
    return
end

% Stage 3 runs the shared reconstruction core on one derived center section.
% The pilot is an independent, disposable validation product; production will
% use a separate output tree.
[reconstructionManifest, reconstructionDir, comparisonManifest] = ...
    runReconstructionPilotStage( ...
        datasetIndex, illuminationModel, cfg, repoRoot, ...
        cfg.execution.overwrite);
result.reconstructionManifest = reconstructionManifest;
result.reconstructionDirectory = reconstructionDir;
if ~isempty(comparisonManifest)
    result.reconstructionStepComparisonManifest = comparisonManifest;
end
end

function [selection, stageDir] = runIlluminationSelectionStage( ...
        datasetIndex, cfg, repoRoot, overwrite)
% Run the tissue-Otsu selector as an independently auditable checkpoint.
stageName = fullfile("02_illumination", "tissue_otsu", "01_selection");
stageDir = stpt.prepareStageDirectory(cfg.paths.outputRoot, stageName, overwrite);
diary(fullfile(stageDir, "stage.log"));
diaryCleanup = onCleanup(@() diary("off"));
provenance = stpt.captureProvenance(repoRoot);
logRunHeader(cfg, provenance, ...
    "Stage 2: tissue selection", stageDir);

save(fullfile(stageDir, "resolved_config.mat"), "cfg", "provenance");
stpt.writeProvenance(provenance, fullfile(stageDir, "provenance.txt"));

selection = stpt.illumination.tissueOtsu.classifyTiles(datasetIndex, cfg);
selection.provenance = provenance;
save(fullfile(stageDir, "tissueSelection.mat"), "selection", "-v7.3");
stpt.illumination.tissueOtsu.writeQC(selection, stageDir);
writelines("Illumination selection completed " + string(datetime("now")), ...
    fullfile(stageDir, "stage_complete.txt"));

fprintf("Selection complete: retained %d/%d green tiles (%.2f%%).\n", ...
    nnz(selection.tiles.selectedForIllumination), height(selection.tiles), ...
    100 * mean(selection.tiles.selectedForIllumination));
fprintf("Outputs: %s\n\n", stageDir);
end

function datasetIndex = loadCompletedIndex(indexDir, cfg)
% Load Stage 1 only when its geometry and representative QC still match.
indexPath = fullfile(indexDir, "datasetIndex.mat");
configPath = fullfile(indexDir, "resolved_config.mat");
if ~isfile(indexPath) || ~isfile(configPath)
    error("stpt:IncompleteIndex", ...
        "Completed Stage 1 files are missing from %s.", indexDir);
end

saved = load(indexPath, "datasetIndex");
datasetIndex = saved.datasetIndex;

saved = load(configPath, "cfg");
indexConfig = saved.cfg;
if ~isfield(indexConfig, "sampling") || ...
        ~isfield(indexConfig.sampling, "qcSections")
    error("stpt:StaleIndex", ...
        "The completed index does not record its representative QC sections.");
end
indexedQcSections = indexConfig.sampling.qcSections;
if ~isequal(indexedQcSections(:)', cfg.sampling.qcSections(:)')
    error("stpt:StaleIndex", ...
        "Stage 1 QC was generated for different representative sections. " + ...
        "Rerun the index stage with cfg.execution.overwrite=true.");
end
end

function datasetIndex = runIndexStage(cfg, repoRoot, overwrite)
% Build Stage 1 in a fresh directory and mark it complete only at the end.
stageDir = stpt.prepareStageDirectory(cfg.paths.outputRoot, "01_index", overwrite);
diary(fullfile(stageDir, "stage.log"));
diaryCleanup = onCleanup(@() diary("off"));
provenance = stpt.captureProvenance(repoRoot);
logRunHeader(cfg, provenance, "Stage 1: native-data index", stageDir);

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
stageName = illuminationStageName(cfg);
stageDir = stpt.prepareStageDirectory(cfg.paths.outputRoot, stageName, overwrite);
diary(fullfile(stageDir, "stage.log"));
diaryCleanup = onCleanup(@() diary("off"));
provenance = stpt.captureProvenance(repoRoot);
logRunHeader(cfg, provenance, ...
    "Stage 2: illumination model", stageDir);

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

function stageName = illuminationStageName(cfg)
% Keep the Stage 2 output path identical for fitting and prerequisite loading.
switch lower(string(cfg.illumination.method))
    case "tissueotsu"
        stageName = fullfile("02_illumination", "tissue_otsu", "02_model");
    case "stitchitreference"
        stageName = fullfile("02_illumination", ...
            "stitchit_reference", "02_model");
    otherwise
        error("stpt:IlluminationMethod", ...
            "Unknown illumination method: %s", cfg.illumination.method);
end
end

function [manifest, stageDir, comparisonManifest] = ...
        runReconstructionPilotStage( ...
        datasetIndex, model, cfg, repoRoot, overwrite)
% Reconstruct the derived center section in a clean, independent pilot tree.
stageName = fullfile("03_reconstruction", "pilot");
stageDir = stpt.prepareStageDirectory( ...
    cfg.paths.outputRoot, stageName, overwrite);

diary(fullfile(stageDir, "stage.log"));
diaryCleanup = onCleanup(@() diary("off"));
provenance = stpt.captureProvenance(repoRoot);
logRunHeader(cfg, provenance, "Stage 3: reconstruction pilot", stageDir);

save(fullfile(stageDir, "resolved_config.mat"), "cfg", "provenance");
stpt.writeProvenance(provenance, fullfile(stageDir, "provenance.txt"));

sectionNumber = cfg.sampling.reconstructionPilotSection;
signature = stpt.reconstruction.buildSignature( ...
    datasetIndex, model, cfg, sectionNumber);
save(fullfile(stageDir, "reconstruction_signature.mat"), "signature");
geometry = stpt.fusion.computeGeometry(datasetIndex, sectionNumber);
writetable(geometry.placements, fullfile(stageDir, "tile_placement.csv"));
canonicalRoot = string(fullfile(stageDir, "stitched"));
manifest = stpt.fusion.processPlanes( ...
    datasetIndex, model, cfg, sectionNumber, canonicalRoot);
stpt.writeTableAtomic(manifest, fullfile(stageDir, "manifest.csv"));
stpt.fusion.writePilotQC( ...
    datasetIndex, model, cfg, sectionNumber, manifest, stageDir);

% Optional comparisons are independent products. They use the same fusion
% interface but never source planes from the canonical stitched tree.
comparisonManifest = table();
if cfg.qc.comparisons.reconstructionSteps
    comparisonManifest = stpt.fusion.writeReconstructionStepComparison( ...
        datasetIndex, model, cfg, sectionNumber, stageDir);
end

writelines("Reconstruction pilot completed " + string(datetime("now")), ...
    fullfile(stageDir, "stage_complete.txt"));
fprintf("Stage 3 pilot complete: section %d, %d reconstructed planes.\n", ...
    sectionNumber, height(manifest));
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

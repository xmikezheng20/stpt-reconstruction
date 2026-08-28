function [model, audit] = loadCompletedModel(stageDir, datasetIndex, cfg)
%LOADCOMPLETEDMODEL Load a completed model matching this reconstruction.

stageDir = string(stageDir);
modelPath = fullfile(stageDir, "illuminationModel.mat");
auditPath = fullfile(stageDir, "illuminationAudit.mat");
completionPath = fullfile(stageDir, "stage_complete.txt");
if ~isfile(modelPath) || ~isfile(auditPath) || ~isfile(completionPath)
    error("stpt:IncompleteIlluminationModel", ...
        "Completed Stage 2 output is required: %s", stageDir);
end

saved = load(modelPath, "model");
model = saved.model;
saved = load(auditPath, "audit");
audit = saved.audit;

% Validate both the common numerical contract and configuration fields that
% determine which fitted model is scientifically appropriate for this run.
stpt.illumination.validateModel(model, datasetIndex);
if ~strcmpi(model.method, cfg.illumination.method) || ...
        ~strcmpi(model.rowMode, cfg.illumination.rowMode) || ...
        ~isequal(model.trainingSections, ...
        cfg.illumination.trainingSections(:)') || ...
        model.tissueReferenceChannel ~= ...
        cfg.illumination.tissueReferenceChannel || ...
        ~isequal(model.cropPixels, cfg.preprocessing.cropPixels)
    error("stpt:StaleIlluminationModel", ...
        "Completed Stage 2 output does not match the current configuration.");
end
end

function [model, audit] = fitModel(datasetIndex, cfg, stageDir)
%FITMODEL Fit the configured illumination algorithm through one interface.
%
% Algorithm-specific code may estimate its model however it chooses, but every
% method must return the standard offset-and-gain model validated below.

validateFitConfig(datasetIndex, cfg);
method = lower(string(cfg.illumination.method));
switch method
    case "stitchitreference"
        [model, audit] = ...
            stpt.illumination.stitchitReference.fit( ...
            datasetIndex, cfg, stageDir);
    otherwise
        error("stpt:IlluminationMethod", ...
            "Unknown illumination method: %s", cfg.illumination.method);
end

stpt.illumination.validateModel(model, datasetIndex);
end

function validateFitConfig(datasetIndex, cfg)
% Keep method configuration checks at the module that consumes them.
required = ["method", "rowMode", "trainingSections", ...
    "tissueReferenceChannel"];
for field = required
    if ~isfield(cfg.illumination, field)
        error("stpt:IlluminationConfig", ...
            "Missing cfg.illumination.%s.", field);
    end
end
if ~strcmpi(cfg.illumination.method, "stitchitReference") || ...
        ~strcmpi(cfg.illumination.rowMode, "split")
    error("stpt:IlluminationConfig", ...
        "The current implementation supports split stitchitReference fitting.");
end
if any(~ismember(cfg.illumination.trainingSections, ...
        [datasetIndex.sections.number]))
    error("stpt:IlluminationConfig", ...
        "Training sections must be present in the dataset index.");
end
if ~ismember(cfg.illumination.tissueReferenceChannel, ...
        [datasetIndex.channels.id])
    error("stpt:IlluminationConfig", ...
        "The tissue-reference channel must be present in the dataset index.");
end

referenceFields = ["bottomFraction", "bottomStdLimit", ...
    "prefixStdLimit", "thresholdScale", "maxRejectedFraction", ...
    "minimumTilesPerParity", "acrossSectionTrimPercent"];
if ~isfield(cfg.illumination, "stitchitReference")
    error("stpt:IlluminationConfig", ...
        "Missing cfg.illumination.stitchitReference.");
end
for field = referenceFields
    if ~isfield(cfg.illumination.stitchitReference, field)
        error("stpt:IlluminationConfig", ...
            "Missing cfg.illumination.stitchitReference.%s.", field);
    end
end
end

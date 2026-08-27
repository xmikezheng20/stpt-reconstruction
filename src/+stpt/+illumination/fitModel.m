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
    case "tissueotsu"
        [model, audit] = stpt.illumination.tissueOtsu.fit( ...
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
    "qcSections", "tissueReferenceChannel"];
for field = required
    if ~isfield(cfg.illumination, field)
        error("stpt:IlluminationConfig", ...
            "Missing cfg.illumination.%s.", field);
    end
end
if ~strcmpi(cfg.illumination.rowMode, "split")
    error("stpt:IlluminationConfig", ...
        "The current implementation supports split odd/even fitting.");
end
if any(~ismember(cfg.illumination.trainingSections, ...
        [datasetIndex.sections.number]))
    error("stpt:IlluminationConfig", ...
        "Training sections must be present in the dataset index.");
end
if any(~ismember(cfg.illumination.qcSections, ...
        cfg.illumination.trainingSections))
    error("stpt:IlluminationConfig", ...
        "Illumination QC sections must be part of the training sample.");
end
if ~ismember(cfg.illumination.tissueReferenceChannel, ...
        [datasetIndex.channels.id])
    error("stpt:IlluminationConfig", ...
        "The tissue-reference channel must be present in the dataset index.");
end

method = lower(string(cfg.illumination.method));
switch method
    case "stitchitreference"
        referenceFields = ["bottomFraction", "bottomStdLimit", ...
            "prefixStdLimit", "thresholdScale", "maxRejectedFraction", ...
            "minimumTilesPerParity", "acrossSectionTrimPercent"];
        requireMethodFields(cfg.illumination, "stitchitReference", ...
            referenceFields);
    case "tissueotsu"
        requireMethodFields(cfg.illumination, "tissueOtsu", ...
            "templateTrimPercent");
        trimPercent = cfg.illumination.tissueOtsu.templateTrimPercent;
        if ~isscalar(trimPercent) || trimPercent < 0 || trimPercent >= 100
            error("stpt:IlluminationConfig", ...
                "Template trim percent must be in [0, 100).");
        end
    otherwise
        error("stpt:IlluminationConfig", ...
            "Unknown illumination method: %s", cfg.illumination.method);
end
end

function requireMethodFields(illuminationConfig, methodName, fields)
% Require only the parameter block consumed by the selected algorithm.
if ~isfield(illuminationConfig, methodName)
    error("stpt:IlluminationConfig", ...
        "Missing cfg.illumination.%s.", methodName);
end
for field = fields
    if ~isfield(illuminationConfig.(methodName), field)
        error("stpt:IlluminationConfig", ...
            "Missing cfg.illumination.%s.%s.", methodName, field);
    end
end
end

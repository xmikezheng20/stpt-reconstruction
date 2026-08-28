function [corrected, audit, diagnostics] = apply(planes, cfg)
%APPLY Apply the configured within-section correction to optical layers.
%
% PLANES is one cell per optical layer for a single physical section and
% channel. A one-layer acquisition is always an identity operation.

nLayers = numel(planes);
if nLayers < 1
    error("stpt:ZIlluminationInput", ...
        "At least one optical layer is required.");
end
validatePlanes(planes);

configuredMethod = string(cfg.zIllumination.method);
method = lower(configuredMethod);
if nLayers == 1 || method == "none"
    corrected = planes;
    audit = identityAudit(planes, cfg.zIllumination, configuredMethod);
    diagnostics = identityDiagnostics( ...
        nLayers, cfg.zIllumination, configuredMethod);
    return
end

switch method
    case "stitchitsmoothratio"
        [corrected, audit, diagnostics] = ...
            stpt.zillumination.stitchitSmoothRatio( ...
            planes, cfg.zIllumination);
    otherwise
        error("stpt:ZIlluminationMethod", ...
            "Unknown z-illumination method: %s", ...
            cfg.zIllumination.method);
end
end

function validatePlanes(planes)
% All layers must be matching 2-D uint16 fused mosaics.
referenceSize = size(planes{1});
for layer = 1:numel(planes)
    if ~isa(planes{layer}, "uint16") || ...
            ~ismatrix(planes{layer}) || ...
            ~isequal(size(planes{layer}), referenceSize)
        error("stpt:ZIlluminationInput", ...
            "Optical layers must be matching 2-D uint16 images.");
    end
end
end

function audit = identityAudit(planes, parameters, method)
nLayers = numel(planes);
audit = repmat(emptyAudit(), nLayers, 1);
for layer = 1:nLayers
    planeMean = mean(planes{layer}, "all");
    audit(layer).method = method;
    audit(layer).applied = false;
    audit(layer).referenceLayer = parameters.referenceLayer;
    audit(layer).preMean = planeMean;
    audit(layer).postMean = planeMean;
    audit(layer).gainP01 = 1;
    audit(layer).gainMedian = 1;
    audit(layer).gainP99 = 1;
end
end

function diagnostics = identityDiagnostics(nLayers, parameters, method)
diagnostics = struct();
diagnostics.method = method;
diagnostics.referenceLayer = parameters.referenceLayer;
diagnostics.estimationSizePixels = [];
diagnostics.gaussianSigmaPixels = nan;
diagnostics.gainFields = cell(1, nLayers);
end

function value = emptyAudit()
value = struct("method", "", "applied", false, ...
    "referenceLayer", nan, "preMean", nan, "postMean", nan, ...
    "gainP01", nan, "gainMedian", nan, "gainP99", nan, ...
    "estimationHeightPixels", nan, "estimationWidthPixels", nan, ...
    "gaussianSigmaPixels", nan, ...
    "clippedLowPixels", 0, "clippedHighPixels", 0, ...
    "correctionSeconds", 0);
end

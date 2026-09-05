function [corrected, audit, diagnostics] = apply(planes, cfg, supportMasks)
%APPLY Apply the configured within-section correction to optical layers.
%
% PLANES is one cell per optical layer for a single physical section and
% channel. SUPPORTMASKS distinguishes acquired coverage from real zero-valued
% pixels. A one-layer acquisition is always an identity operation.

nLayers = numel(planes);
if nLayers < 1
    error("stpt:ZIlluminationInput", ...
        "At least one optical layer is required.");
end
validatePlanes(planes);
if nargin < 3
    supportMasks = repmat({true}, size(planes));
end
validateSupportMasks(supportMasks, planes);

configuredMethod = string(cfg.zIllumination.method);
method = lower(configuredMethod);
if nLayers == 1
    corrected = planes;
    audit = identityAudit( ...
        planes, cfg.zIllumination, configuredMethod, "singleLayer");
    diagnostics = identityDiagnostics( ...
        nLayers, cfg.zIllumination, configuredMethod, "singleLayer");
    return
elseif method == "none"
    corrected = planes;
    audit = identityAudit( ...
        planes, cfg.zIllumination, configuredMethod, "disabled");
    diagnostics = identityDiagnostics( ...
        nLayers, cfg.zIllumination, configuredMethod, "disabled");
    return
end

switch method
    case "stitchitsmoothratio"
        [corrected, audit, diagnostics] = ...
            stpt.zillumination.stitchitSmoothRatio( ...
            planes, cfg.zIllumination, supportMasks);
    otherwise
        error("stpt:ZIlluminationMethod", ...
            "Unknown z-illumination method: %s", ...
            cfg.zIllumination.method);
end
end

function validateSupportMasks(supportMasks, planes)
if ~iscell(supportMasks) || numel(supportMasks) ~= numel(planes)
    error("stpt:ZIlluminationInput", ...
        "One support mask is required for every optical layer.");
end
for layer = 1:numel(planes)
    mask = supportMasks{layer};
    isComplete = islogical(mask) && isscalar(mask) && mask;
    isSparse = islogical(mask) && ...
        isequal(size(mask), size(planes{layer})) && any(mask(:));
    if ~isComplete && ~isSparse
        error("stpt:ZIlluminationInput", ...
            "Support must be scalar true or a nonempty logical plane mask.");
    end
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

function audit = identityAudit(planes, parameters, method, reason)
nLayers = numel(planes);
audit = repmat(emptyAudit(), nLayers, 1);
for layer = 1:nLayers
    planeMean = mean(planes{layer}, "all");
    audit(layer).method = method;
    audit(layer).applied = false;
    audit(layer).reason = string(reason);
    audit(layer).referenceLayer = parameters.referenceLayer;
    audit(layer).preMean = planeMean;
    audit(layer).postMean = planeMean;
    audit(layer).gainP01 = 1;
    audit(layer).gainMedian = 1;
    audit(layer).gainP99 = 1;
end
end

function diagnostics = identityDiagnostics( ...
        nLayers, parameters, method, reason)
diagnostics = struct();
diagnostics.method = method;
diagnostics.referenceLayer = parameters.referenceLayer;
diagnostics.estimationSizePixels = [];
diagnostics.gaussianSigmaPixels = nan;
diagnostics.gainFields = cell(1, nLayers);
diagnostics.correctionApplied = false(1, nLayers);
diagnostics.correctionReason = repmat(string(reason), 1, nLayers);
end

function value = emptyAudit()
value = struct("method", "", "applied", false, ...
    "reason", "", ...
    "referenceLayer", nan, "preMean", nan, "postMean", nan, ...
    "gainP01", nan, "gainMedian", nan, "gainP99", nan, ...
    "estimationHeightPixels", nan, "estimationWidthPixels", nan, ...
    "gaussianSigmaPixels", nan, ...
    "clippedHighPixels", 0, ...
    "correctionSeconds", 0);
end

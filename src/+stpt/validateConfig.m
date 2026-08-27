function cfg = validateConfig(cfg)
%VALIDATECONFIG Check the small set of assumptions used by the core pipeline.

% Require the groups used before a stage-specific algorithm is dispatched.
% Method-specific illumination fields are checked at that module's interface.
requiredTopLevel = ["experiment", "paths", "channels", "acquisition", ...
    "stitching", "preprocessing", "processing", "sampling", "execution"];
for field = requiredTopLevel
    if ~isfield(cfg, field)
        error("stpt:MissingConfig", "Missing cfg.%s.", field);
    end
end

% Raw roots must already exist; the master runner creates derived output roots.
if ~isfolder(cfg.paths.rawRoot)
    error("stpt:MissingRawRoot", "Raw root does not exist: %s", ...
        cfg.paths.rawRoot);
end

if numel(cfg.channels) < 1
    error("stpt:NoChannels", "At least one channel must be configured.");
end

% Validate the explicit channel-to-directory mapping before any indexing work.
for channel = cfg.channels
    channelRoot = fullfile(cfg.paths.rawRoot, channel.directory);
    if ~isfolder(channelRoot)
        error("stpt:MissingChannelRoot", ...
            "Channel directory does not exist: %s", channelRoot);
    end
end

% Check the geometry vectors whose element order affects later arithmetic.
if ~isequal(size(cfg.acquisition.pixelSizeUm), [1, 2]) || ...
        any(cfg.acquisition.pixelSizeUm <= 0)
    error("stpt:PixelSize", ...
        "cfg.acquisition.pixelSizeUm must be positive [x, y].");
end

if ~isequal(size(cfg.preprocessing.cropPixels), [1, 4]) || ...
        any(~isfinite(cfg.preprocessing.cropPixels)) || ...
        any(cfg.preprocessing.cropPixels < 0) || ...
        any(mod(cfg.preprocessing.cropPixels, 1) ~= 0)
    error("stpt:Crop", ...
        "cfg.preprocessing.cropPixels must contain nonnegative integer " + ...
        "[left right top bottom] values.");
end
if numel(unique(cfg.preprocessing.cropPixels)) ~= 1
    error("stpt:Crop", ...
        "This pipeline currently requires the same crop on all four sides.");
end

% Cropping may shrink support, but it must leave positive XY overlap at the
% configured target step so later fusion has no gaps between nominal tiles.
retainedSize = cfg.acquisition.tileSizePixels - [ ...
    cfg.preprocessing.cropPixels(1) + cfg.preprocessing.cropPixels(2), ...
    cfg.preprocessing.cropPixels(3) + cfg.preprocessing.cropPixels(4)];
targetStepPixels = cfg.stitching.targetStepUm ./ ...
    cfg.acquisition.pixelSizeUm;
if any(retainedSize <= 0)
    error("stpt:Crop", "Cropping removes the complete tile support.");
end
if any(retainedSize <= targetStepPixels)
    error("stpt:CropOverlap", ...
        "Cropping must leave positive overlap at the configured target step.");
end

% Resolve the exact reconstruction range. The acquisition count remains the
% planned metadata value even when only a complete prefix or subset is used.
if ~isPositiveInteger(cfg.acquisition.sectionCount)
    error("stpt:SectionCount", ...
        "cfg.acquisition.sectionCount must be a positive integer.");
end
sectionStart = cfg.processing.sectionStart;
sectionStop = cfg.processing.sectionStop;
if ~isPositiveInteger(sectionStart) || ~isPositiveInteger(sectionStop) || ...
        sectionStart > sectionStop || ...
        sectionStop > cfg.acquisition.sectionCount
    error("stpt:ProcessingSections", ...
        "Processing sections require integer 1 <= sectionStart <= " + ...
        "sectionStop <= acquisition.sectionCount.");
end
cfg.processing.sections = sectionStart:sectionStop;

% Illumination computation and visual QC deliberately use different regular
% samples, both anchored at the requested processing start.
illuminationStride = cfg.sampling.illuminationEveryNSections;
qcStride = cfg.sampling.qcEveryNSections;
if ~isPositiveInteger(illuminationStride) || ~isPositiveInteger(qcStride)
    error("stpt:SectionSampling", ...
        "Illumination and QC section intervals must be positive integers.");
end
if mod(qcStride, illuminationStride) ~= 0
    error("stpt:SectionSampling", ...
        "qcEveryNSections must be a multiple of " + ...
        "illuminationEveryNSections.");
end
cfg.sampling.illuminationSections = ...
    sectionStart:illuminationStride:sectionStop;
cfg.sampling.qcSections = sectionStart:qcStride:sectionStop;
cfg.qc.representativeSections = cfg.sampling.qcSections;

% Keep the initial implementation deliberately narrow and auditable.
if ~strcmpi(cfg.stitching.positionSource, "target")
    error("stpt:PositionSource", ...
        "The initial implementation supports target positions only.");
end

validStops = ["index", "illuminationSelection", "illuminationModel"];
if ~any(strcmpi(cfg.execution.stopAfter, validStops))
    error("stpt:StopAfter", "cfg.execution.stopAfter must be %s.", ...
        strjoin(validStops, " or "));
end
if ~strcmpi(cfg.execution.stopAfter, "index") && ...
        ~isfield(cfg, "illumination")
    error("stpt:MissingConfig", ...
        "Stage 2 requires cfg.illumination.");
end
if isfield(cfg, "illumination")
    cfg.illumination.trainingSections = ...
        cfg.sampling.illuminationSections;
    cfg.illumination.qcSections = cfg.sampling.qcSections;
end

% Normalize filesystem values once so downstream code uses one path type.
cfg.paths.rawRoot = string(cfg.paths.rawRoot);
cfg.paths.outputRoot = string(cfg.paths.outputRoot);
end

function tf = isPositiveInteger(value)
tf = isscalar(value) && isfinite(value) && value >= 1 && ...
    mod(value, 1) == 0;
end

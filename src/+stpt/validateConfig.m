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
if ~isfield(cfg.acquisition, "planeSpacingUm") || ...
        ~isscalar(cfg.acquisition.planeSpacingUm) || ...
        ~isfinite(cfg.acquisition.planeSpacingUm) || ...
        cfg.acquisition.planeSpacingUm <= 0
    error("stpt:PlaneSpacing", ...
        "cfg.acquisition.planeSpacingUm must be a positive scalar.");
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
if ~isfield(cfg.preprocessing, "tileOrientation") || ...
        ~any(strcmpi(cfg.preprocessing.tileOrientation, ["none", "rot90cw"]))
    error("stpt:TileOrientation", ...
        "cfg.preprocessing.tileOrientation must be none or rot90cw.");
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
if strcmpi(cfg.preprocessing.tileOrientation, "rot90cw") && ...
        retainedSize(1) ~= retainedSize(2)
    error("stpt:TileOrientation", ...
        "The current rot90cw implementation requires square retained tiles.");
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
cfg.sampling.reconstructionPilotSection = ...
    round((sectionStart + sectionStop) / 2);

% Target-position placement is the deliberate scope of this reconstruction.
if ~strcmpi(cfg.stitching.positionSource, "target")
    error("stpt:PositionSource", ...
        "This pipeline supports target positions only.");
end

validStops = ["index", "illuminationSelection", "illuminationModel", ...
    "reconstructionPilot", "reconstructionProduction", "downsampling"];
if ~any(strcmpi(cfg.execution.stopAfter, validStops))
    error("stpt:StopAfter", "cfg.execution.stopAfter must be %s.", ...
        strjoin(validStops, " or "));
end
if ~strcmpi(cfg.execution.stopAfter, "index") && ...
        ~isfield(cfg, "illumination")
    error("stpt:MissingConfig", ...
        "Stage 2 requires cfg.illumination.");
end
if strcmpi(cfg.execution.stopAfter, "illuminationSelection") && ...
        ~strcmpi(cfg.illumination.method, "tissueOtsu")
    error("stpt:IlluminationConfig", ...
        "The illuminationSelection checkpoint belongs to tissueOtsu.");
end
if isfield(cfg, "illumination")
    cfg.illumination.trainingSections = ...
        cfg.sampling.illuminationSections;
    cfg.illumination.qcSections = cfg.sampling.qcSections;
end

% Reconstruction policy is shared by the independent pilot and production
% stage targets and remains independent of target-grid placement.
isPilot = strcmpi(cfg.execution.stopAfter, "reconstructionPilot");
isProduction = strcmpi(cfg.execution.stopAfter, "reconstructionProduction");
isDownsampling = strcmpi(cfg.execution.stopAfter, "downsampling");
if isPilot || isProduction || isDownsampling
    if ~isfield(cfg, "fusion") || ~isfield(cfg, "zIllumination")
        error("stpt:MissingConfig", ...
            "Stage 3 requires cfg.fusion and cfg.zIllumination.");
    end
    if ~isfield(cfg.execution, "reconstructionWorkers") || ...
            ~isPositiveInteger(cfg.execution.reconstructionWorkers)
        error("stpt:ParallelReconstruction", ...
            "cfg.execution.reconstructionWorkers must be a positive integer.");
    end
    requiredFusionFields = ["mode", "compression", "qcPreviewScale"];
    for field = requiredFusionFields
        if ~isfield(cfg.fusion, field)
            error("stpt:FusionConfig", "Missing cfg.fusion.%s.", field);
        end
    end
    validFusionModes = ["overwrite", "fijiBlend"];
    if ~any(strcmpi(cfg.fusion.mode, validFusionModes))
        error("stpt:FusionConfig", ...
            "cfg.fusion.mode must be overwrite or fijiBlend.");
    end
    if ~strcmpi(cfg.fusion.compression, "lzw")
        error("stpt:FusionConfig", ...
            "Fusion TIFF compression must currently be lossless LZW.");
    end
    if ~isscalar(cfg.fusion.qcPreviewScale) || ...
            cfg.fusion.qcPreviewScale <= 0 || cfg.fusion.qcPreviewScale > 1
        error("stpt:FusionConfig", ...
            "cfg.fusion.qcPreviewScale must be in (0, 1].");
    end
    if isPilot
        if ~isfield(cfg, "qc") || ~isfield(cfg.qc, "comparisons") || ...
                ~isfield(cfg.qc.comparisons, "reconstructionSteps") || ...
                ~islogical(cfg.qc.comparisons.reconstructionSteps) || ...
                ~isscalar(cfg.qc.comparisons.reconstructionSteps)
            error("stpt:FusionConfig", ...
                "cfg.qc.comparisons.reconstructionSteps must be true or false.");
        end
        comparisonsEnabled = cfg.qc.comparisons.reconstructionSteps;
    else
        comparisonsEnabled = false;
    end
    needsBlending = strcmpi(cfg.fusion.mode, "fijiBlend") || ...
        comparisonsEnabled;
    if needsBlending && (~isfield(cfg.fusion, "blending") || ...
            ~isfield(cfg.fusion.blending, "method") || ...
            ~strcmpi(cfg.fusion.blending.method, "fijiDistance") || ...
            ~isfield(cfg.fusion.blending, "alpha") || ...
            ~isscalar(cfg.fusion.blending.alpha) || ...
            ~isfinite(cfg.fusion.blending.alpha) || ...
            cfg.fusion.blending.alpha <= 0)
        error("stpt:FusionConfig", ...
            "Fiji blending requires method=fijiDistance and alpha > 0.");
    end

    % Z illumination is a fused-section operation. The StitchIt method is
    % configurable, while a one-layer acquisition passes through unchanged.
    requiredZFields = ["method", "referenceLayer", ...
        "maxEstimationPixels", "filterAreaFraction"];
    for field = requiredZFields
        if ~isfield(cfg.zIllumination, field)
            error("stpt:ZIlluminationConfig", ...
                "Missing cfg.zIllumination.%s.", field);
        end
    end
    validZMethods = ["none", "stitchitSmoothRatio"];
    if ~any(strcmpi(cfg.zIllumination.method, validZMethods))
        error("stpt:ZIlluminationConfig", ...
            "cfg.zIllumination.method must be none or stitchitSmoothRatio.");
    end
    if ~isPositiveInteger(cfg.zIllumination.referenceLayer) || ...
            cfg.zIllumination.referenceLayer > ...
            cfg.acquisition.layersPerSection
        error("stpt:ZIlluminationConfig", ...
            "The z-illumination reference layer is outside the acquisition.");
    end
    if ~isscalar(cfg.zIllumination.maxEstimationPixels) || ...
            ~isfinite(cfg.zIllumination.maxEstimationPixels) || ...
            cfg.zIllumination.maxEstimationPixels <= 0 || ...
            ~isscalar(cfg.zIllumination.filterAreaFraction) || ...
            ~isfinite(cfg.zIllumination.filterAreaFraction) || ...
            cfg.zIllumination.filterAreaFraction <= 0 || ...
            cfg.zIllumination.filterAreaFraction > 1
        error("stpt:ZIlluminationConfig", ...
            "Z-illumination estimation pixels must be positive and " + ...
            "filterAreaFraction must be in (0, 1].");
    end
end

% Stage 4 consumes the ordered final-plane series. The generic resampler uses
% [z, y, x] voxel order, while acquisition XY metadata is stored as [x, y].
if isDownsampling
    if ~isfield(cfg, "downsampling") || ...
            ~isfield(cfg.downsampling, "outputVoxelSizeUm") || ...
            ~isfield(cfg.downsampling, "compression")
        error("stpt:DownsamplingConfig", ...
            "Stage 4 requires outputVoxelSizeUm and compression.");
    end
    inputVoxelSizeUm = [cfg.acquisition.planeSpacingUm, ...
        cfg.acquisition.pixelSizeUm(2), cfg.acquisition.pixelSizeUm(1)];
    outputVoxelSizeUm = cfg.downsampling.outputVoxelSizeUm;
    if ~isequal(size(outputVoxelSizeUm), [1, 3]) || ...
            any(~isfinite(outputVoxelSizeUm)) || ...
            any(outputVoxelSizeUm <= 0)
        error("stpt:DownsamplingConfig", ...
            "outputVoxelSizeUm must be positive [z, y, x].");
    end
    if any(outputVoxelSizeUm < inputVoxelSizeUm)
        error("stpt:DownsamplingConfig", ...
            "Stage 4 supports identity sampling or downsampling, not upsampling.");
    end
    if ~strcmpi(cfg.downsampling.compression, "lzw")
        error("stpt:DownsamplingConfig", ...
            "Downsampled TIFF compression must currently be lossless LZW.");
    end
    cfg.downsampling.inputVoxelSizeUm = inputVoxelSizeUm;
end

% Normalize filesystem values once so downstream code uses one path type.
cfg.paths.rawRoot = string(cfg.paths.rawRoot);
cfg.paths.outputRoot = string(cfg.paths.outputRoot);
end

function tf = isPositiveInteger(value)
tf = isscalar(value) && isfinite(value) && value >= 1 && ...
    mod(value, 1) == 0;
end

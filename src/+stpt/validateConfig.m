function cfg = validateConfig(cfg)
%VALIDATECONFIG Check the small set of assumptions used by the core pipeline.

% First require the major config groups shared by all planned pipeline stages.
requiredTopLevel = ["experiment", "paths", "channels", "acquisition", ...
    "stitching", "preprocessing", "illumination", "fusion", "qc", ...
    "execution", "references"];
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
        any(cfg.preprocessing.cropPixels < 0)
    error("stpt:Crop", ...
        "cfg.preprocessing.cropPixels must be [left right top bottom].");
end

% Keep the initial implementation deliberately narrow and auditable.
if ~strcmpi(cfg.stitching.positionSource, "target")
    error("stpt:PositionSource", ...
        "The initial implementation supports target positions only.");
end

% Normalize filesystem values once so downstream code uses one path type.
cfg.paths.rawRoot = string(cfg.paths.rawRoot);
cfg.paths.outputRoot = string(cfg.paths.outputRoot);
end

function validateAgainstConfig(datasetIndex, cfg)
%VALIDATEAGAINSTCONFIG Reject a completed index built for another geometry.

if string(datasetIndex.rawRoot) ~= string(cfg.paths.rawRoot)
    error("stpt:StaleIndex", ...
        "The completed index belongs to a different raw-data root.");
end
if ~isfield(datasetIndex, "masterMosaic") || ...
        datasetIndex.masterMosaic.parameters.sections ~= ...
        cfg.acquisition.sectionCount
    error("stpt:StaleIndex", ...
        "The completed index has a different planned acquisition count.");
end

% These values determine file addressing, parity, tile support, or placement.
geometryChecks = {
    "gridSize",               cfg.acquisition.gridSize
    "layersPerSection",       cfg.acquisition.layersPerSection
    "tileSizePixels",         cfg.acquisition.tileSizePixels
    "pixelSizeUm",            cfg.acquisition.pixelSizeUm
    "targetStepUm",           cfg.stitching.targetStepUm
    "cropPixels",             cfg.preprocessing.cropPixels
    };
for i = 1:size(geometryChecks, 1)
    field = geometryChecks{i, 1};
    expected = geometryChecks{i, 2};
    if ~isfield(datasetIndex.geometry, field) || ...
            ~isequal(datasetIndex.geometry.(field), expected)
        error("stpt:StaleIndex", ...
            "The completed index does not match geometry field '%s'.", field);
    end
end

expectedSections = cfg.processing.sections(:)';
if numel(datasetIndex.sections) ~= numel(expectedSections) || ...
        ~isequal([datasetIndex.sections.number], expectedSections)
    error("stpt:StaleIndex", ...
        "The completed index does not match the configured section sequence.");
end
if ~isfield(datasetIndex, "processingSections") || ...
        ~isequal(datasetIndex.processingSections, expectedSections)
    error("stpt:StaleIndex", ...
        "The completed index records a different processing range.");
end

% Compare the complete explicit channel map, including native filename codes.
if numel(datasetIndex.channels) ~= numel(cfg.channels)
    error("stpt:StaleIndex", ...
        "The completed index has a different number of channels.");
end
for c = 1:numel(cfg.channels)
    indexed = datasetIndex.channels(c);
    configured = cfg.channels(c);
    expectedRoot = string(fullfile(cfg.paths.rawRoot, configured.directory));
    if indexed.id ~= configured.id || ...
            string(indexed.name) ~= string(configured.name) || ...
            string(indexed.directory) ~= string(configured.directory) || ...
            string(indexed.root) ~= expectedRoot || ...
            string(indexed.fileCode) ~= string(configured.fileCode)
        error("stpt:StaleIndex", ...
            "The completed index does not match configured channel %d.", ...
            configured.id);
    end
end
end

function validateAgainstConfig(datasetIndex, cfg)
%VALIDATEAGAINSTCONFIG Reject a completed index built for another geometry.

if ~isfield(datasetIndex, "missingTiles") || ...
        string(datasetIndex.rawRoot) ~= string(cfg.paths.rawRoot)
    error("stpt:StaleIndex", ...
        "The completed index is missing the sparse-file inventory or " + ...
        "belongs to a different raw-data root.");
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

% Every channel retains one fixed slot per expected native index. Empty slots
% must agree exactly with the explicit missing-tile inventory.
expectedSlots = prod(cfg.acquisition.gridSize) * ...
    cfg.acquisition.layersPerSection;
indexedMissing = 0;
for s = 1:numel(datasetIndex.sections)
    section = datasetIndex.sections(s);
    for c = 1:numel(datasetIndex.channels)
        files = section.channelFiles{c};
        if numel(files) ~= expectedSlots
            error("stpt:StaleIndex", ...
                "Section %d, channel %d does not have %d fixed file slots.", ...
                section.number, datasetIndex.channels(c).id, expectedSlots);
        end
        indexedMissing = indexedMissing + nnz(strlength(files) == 0);
    end
end
if indexedMissing ~= height(datasetIndex.missingTiles)
    error("stpt:StaleIndex", ...
        "The fixed file slots disagree with the missing-tile inventory.");
end
end

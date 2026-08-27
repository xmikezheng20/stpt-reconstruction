function datasetIndex = build(cfg)
%BUILD Build a read-only map from acquisition coordinates to raw TIFFs.
%
% No image is copied, renamed, or modified. The resulting index records native
% filenames and reconstructs the regular target grid from the movement records
% in each section's Mosaic file.

% Derive the expected number of files in one section from acquisition geometry.
nChannels = numel(cfg.channels);
nTiles = prod(cfg.acquisition.gridSize);
nLayers = cfg.acquisition.layersPerSection;
expectedFileCount = nTiles * nLayers;

% Resolve each configured channel to its native root and discover only numbered
% section directories. Unrelated directories such as ch1/trigger are ignored.
channels = repmat(struct("id", [], "name", "", "directory", "", ...
    "root", "", "fileCode", ""), nChannels, 1);
sectionMaps = cell(nChannels, 1);

for c = 1:nChannels
    channels(c).id = cfg.channels(c).id;
    channels(c).name = string(cfg.channels(c).name);
    channels(c).directory = string(cfg.channels(c).directory);
    channels(c).root = string(fullfile(cfg.paths.rawRoot, ...
        cfg.channels(c).directory));
    channels(c).fileCode = string(cfg.channels(c).fileCode);
    sectionMaps{c} = discoverSections(channels(c).root);
end

% Require identical, complete section coverage before combining channel data.
expectedSections = (1:cfg.acquisition.sectionCount)';
for c = 1:nChannels
    if ~isequal(sectionMaps{c}.sectionNumber, expectedSections)
        error("stpt:SectionSequence", ...
            "Channel %d does not contain exactly sections 1:%d.", ...
            channels(c).id, cfg.acquisition.sectionCount);
    end
end

% Read geometry from the designated metadata channel. In this dataset the
% master and per-section Mosaic files live under ch1.
metadataChannelPosition = find([channels.id] == ...
    cfg.acquisition.metadataChannel, 1);
if isempty(metadataChannelPosition)
    error("stpt:MetadataChannel", ...
        "Configured metadata channel %d is not present.", ...
        cfg.acquisition.metadataChannel);
end

masterPath = findSingleMosaic(channels(metadataChannelPosition).root);
masterMosaic = stpt.io.readMosaicFile(masterPath);
validateMasterMetadata(masterMosaic.parameters, cfg);

% Preallocate the complete index and the compact per-section QC measurements.
emptySection = struct("number", [], "mosaicPath", "", ...
    "channelDirectories", strings(1, nChannels), ...
    "channelFiles", {cell(1, nChannels)}, "positions", table(), ...
    "nativeStartIndex", [], "nativeEndIndex", []);
sections = repmat(emptySection, cfg.acquisition.sectionCount, 1);
fileCounts = zeros(cfg.acquisition.sectionCount, nChannels);
positionCounts = zeros(cfg.acquisition.sectionCount, 1);
metadataStartNumbers = zeros(cfg.acquisition.sectionCount, 1);
residualRmsXUm = zeros(cfg.acquisition.sectionCount, 1);
residualRmsYUm = zeros(cfg.acquisition.sectionCount, 1);
residualMaxUm = zeros(cfg.acquisition.sectionCount, 1);

fprintf("  Master Mosaic: %s\n", masterPath);
fprintf("  Discovering %d sections across %d channels...\n", ...
    cfg.acquisition.sectionCount, nChannels);

% Index one physical section at a time. The Mosaic startnum supplies the native
% global TIFF span; filenames within every channel must agree with that span.
for s = 1:cfg.acquisition.sectionCount
    sectionNumber = expectedSections(s);
    channelDirectories = strings(1, nChannels);
    channelFiles = cell(1, nChannels);

    for c = 1:nChannels
        channelDirectories(c) = sectionMaps{c}.directoryName(s);
    end

    % Parse target/actual positions before TIFFs because startnum defines the
    % expected global file indices for this section.
    metadataSectionPath = fullfile( ...
        channels(metadataChannelPosition).root, ...
        channelDirectories(metadataChannelPosition));
    sectionMosaicPath = findSingleMosaic(metadataSectionPath);
    sectionMosaic = stpt.io.readMosaicFile(sectionMosaicPath);
    positions = buildTargetGrid(sectionMosaic.positions, cfg);
    nativeStartIndex = sectionMosaic.parameters.startnum;

    % Inventory filenames only. No TIFF pixels are loaded in this loop.
    for c = 1:nChannels
        sectionPath = fullfile(channels(c).root, channelDirectories(c));
        [channelFiles{c}, fileCounts(s, c)] = inventoryTiffs( ...
            sectionPath, channels(c).fileCode, expectedFileCount, ...
            nativeStartIndex);
    end

    % Each position corresponds to one XY tile and is reused by both layers.
    if height(positions) ~= nTiles
        error("stpt:TilePositionCount", ...
            "Section %d has %d positions; expected %d.", ...
            sectionNumber, height(positions), nTiles);
    end

    % Store the auditable mapping and summarize target-versus-stage residuals.
    sections(s).number = sectionNumber;
    sections(s).mosaicPath = string(sectionMosaicPath);
    sections(s).channelDirectories = channelDirectories;
    sections(s).channelFiles = channelFiles;
    sections(s).positions = positions;
    sections(s).nativeStartIndex = nativeStartIndex;
    sections(s).nativeEndIndex = nativeStartIndex + expectedFileCount - 1;
    positionCounts(s) = height(positions);
    metadataStartNumbers(s) = nativeStartIndex;
    residualRmsXUm(s) = sqrt(mean(positions.targetResidualXUm.^2));
    residualRmsYUm(s) = sqrt(mean(positions.targetResidualYUm.^2));
    residualMaxUm(s) = max(hypot(positions.targetResidualXUm, ...
        positions.targetResidualYUm));

    if mod(s, 25) == 0 || s == 1
        fprintf("    indexed section %d/%d\n", s, cfg.acquisition.sectionCount);
    end
end

% Confirm that consecutive sections form one continuous native TIFF sequence.
expectedStartNumbers = (0:expectedFileCount: ...
    expectedFileCount * (cfg.acquisition.sectionCount - 1))';
if ~isequal(metadataStartNumbers, expectedStartNumbers)
    error("stpt:SectionStartSequence", ...
        "Section startnum values are not the expected contiguous native sequence.");
end

% The inventory is intentionally compact so dataset-wide integrity can be
% inspected without loading the much larger per-tile index MAT file.
sectionInventory = table(expectedSections, positionCounts, ...
    metadataStartNumbers, residualRmsXUm, residualRmsYUm, residualMaxUm, ...
    'VariableNames', {'sectionNumber', 'positionCount', ...
    'metadataStartNumber', 'targetResidualRmsXUm', ...
    'targetResidualRmsYUm', 'targetResidualMaxUm'});
for c = 1:nChannels
    variableName = sprintf("ch%dFileCount", channels(c).id);
    sectionInventory.(variableName) = fileCounts(:, c);
end

% Read one TIFF header as a lightweight check of configured pixel dimensions.
firstFilePath = fullfile(channels(1).root, ...
    sections(1).channelDirectories(1), sections(1).channelFiles{1}(1));
sampleInfo = imfinfo(firstFilePath);
if sampleInfo.Width ~= cfg.acquisition.tileSizePixels(1) || ...
        sampleInfo.Height ~= cfg.acquisition.tileSizePixels(2)
    error("stpt:TileDimensions", ...
        "Sample TIFF is %d-by-%d pixels; configured size is %d-by-%d.", ...
        sampleInfo.Width, sampleInfo.Height, ...
        cfg.acquisition.tileSizePixels(1), ...
        cfg.acquisition.tileSizePixels(2));
end

% Make overlap arithmetic explicit. Cropping changes retained support and
% overlap, while the 700-pixel target step remains the placement rule.
crop = cfg.preprocessing.cropPixels;
retainedSize = cfg.acquisition.tileSizePixels - ...
    [crop(1) + crop(2), crop(3) + crop(4)];
targetStepPixels = cfg.stitching.targetStepUm ./ ...
    cfg.acquisition.pixelSizeUm;
rawOverlapPixels = cfg.acquisition.tileSizePixels - targetStepPixels;
postCropOverlapPixels = retainedSize - targetStepPixels;

% Package all derived geometry in one place for later preprocessing/stitching.
geometry = struct();
geometry.gridSize = cfg.acquisition.gridSize;
geometry.tilesPerLayer = nTiles;
geometry.layersPerSection = nLayers;
geometry.tileSizePixels = cfg.acquisition.tileSizePixels;
geometry.pixelSizeUm = cfg.acquisition.pixelSizeUm;
geometry.targetStepUm = cfg.stitching.targetStepUm;
geometry.targetStepPixels = targetStepPixels;
geometry.cropPixels = crop;
geometry.retainedTileSizePixels = retainedSize;
geometry.rawOverlapPixels = rawOverlapPixels;
geometry.postCropOverlapPixels = postCropOverlapPixels;
geometry.nominalCanvasSizePixels = retainedSize + ...
    (cfg.acquisition.gridSize - 1) .* targetStepPixels;

% Assemble a self-contained index that references, but never contains or alters,
% the raw image pixels.
datasetIndex = struct();
datasetIndex.schemaVersion = 1;
datasetIndex.created = string(datetime("now"));
datasetIndex.rawRoot = cfg.paths.rawRoot;
datasetIndex.channels = channels;
datasetIndex.masterMosaic = masterMosaic;
datasetIndex.geometry = geometry;
datasetIndex.sampleTiff = struct("path", string(firstFilePath), ...
    "width", sampleInfo.Width, "height", sampleInfo.Height, ...
    "bitDepth", sampleInfo.BitDepth);
datasetIndex.sectionInventory = sectionInventory;
datasetIndex.sections = sections;
end

function sectionMap = discoverSections(channelRoot)
% Recognize the native UUID-NNNN section suffix and ignore other directories.
listing = dir(channelRoot);
listing = listing([listing.isdir]);

sectionNumbers = [];
directoryNames = strings(0, 1);
for i = 1:numel(listing)
    token = regexp(listing(i).name, "-(\d{4})$", "tokens", "once");
    if isempty(token)
        continue
    end
    sectionNumbers(end+1, 1) = str2double(token{1}); %#ok<AGROW>
    directoryNames(end+1, 1) = string(listing(i).name); %#ok<AGROW>
end

[sectionNumbers, order] = sort(sectionNumbers);
directoryNames = directoryNames(order);
sectionMap = table(sectionNumbers, directoryNames, 'VariableNames', ...
    {'sectionNumber', 'directoryName'});
end

function mosaicPath = findSingleMosaic(directoryPath)
% Ambiguous metadata is an error because silently choosing a file is unsafe.
listing = dir(fullfile(directoryPath, "Mosaic_*.txt"));
if numel(listing) ~= 1
    error("stpt:MosaicCount", ...
        "Expected one Mosaic_*.txt in %s; found %d.", ...
        directoryPath, numel(listing));
end
mosaicPath = string(fullfile(listing(1).folder, listing(1).name));
end

function [fileNames, fileCount] = inventoryTiffs(sectionPath, fileCode, ...
        expectedCount, expectedStartIndex)
% Count files first, then parse native global index and channel code from names.
listing = dir(fullfile(sectionPath, "*.tif"));
fileCount = numel(listing);
if fileCount ~= expectedCount
    error("stpt:TiffCount", ...
        "%s has %d TIFFs; expected %d.", ...
        sectionPath, fileCount, expectedCount);
end

rawIndices = nan(fileCount, 1);
fileNames = strings(fileCount, 1);
for i = 1:fileCount
    token = regexp(listing(i).name, "-(\d+)_([0-9]+)\.tif$", ...
        "tokens", "once");
    if isempty(token)
        error("stpt:TiffName", "Unrecognized TIFF name: %s", ...
            fullfile(sectionPath, listing(i).name));
    end
    if string(token{2}) ~= string(fileCode)
        error("stpt:TiffChannel", ...
            "Unexpected channel code in %s.", listing(i).name);
    end
    rawIndices(i) = str2double(token{1});
    fileNames(i) = string(listing(i).name);
end

% Sorting by parsed numeric index avoids lexicographic ordering (1, 10, 100...).
[rawIndices, order] = sort(rawIndices);
fileNames = fileNames(order);
expectedIndices = (expectedStartIndex:expectedStartIndex+expectedCount-1)';
if ~isequal(rawIndices, expectedIndices)
    error("stpt:TiffSequence", ...
        "%s does not contain the native TIFF span %d:%d recorded by startnum.", ...
        sectionPath, expectedIndices(1), expectedIndices(end));
end
end

function positions = buildTargetGrid(positionRecords, cfg)
% Integrate signed movement commands to recover the serpentine integer grid.
% Only movement direction changes grid coordinates; magnitude is checked below.
nPositions = height(positionRecords);
gridX = ones(nPositions, 1);
gridY = ones(nPositions, 1);

for i = 2:nPositions
    gridX(i) = gridX(i-1) + sign(positionRecords.commandedDXUm(i));
    gridY(i) = gridY(i-1) + sign(positionRecords.commandedDYUm(i));
end

gridX = gridX - min(gridX) + 1;
gridY = gridY - min(gridY) + 1;

% The traversal must visit every configured grid location exactly once.
if max(gridX) ~= cfg.acquisition.gridSize(1) || ...
        max(gridY) ~= cfg.acquisition.gridSize(2) || ...
        size(unique([gridX, gridY], "rows"), 1) ~= nPositions
    error("stpt:TargetGrid", ...
        "Movement records do not form the configured %d-by-%d grid.", ...
        cfg.acquisition.gridSize(1), cfg.acquisition.gridSize(2));
end

% Verify that every non-zero acquisition movement matches the configured step.
movement = [abs(positionRecords.commandedDXUm); ...
            abs(positionRecords.commandedDYUm)];
movement = unique(movement(movement > 0));
expectedMovement = unique(cfg.stitching.targetStepUm);
if ~isequal(movement, expectedMovement(:))
    error("stpt:TargetStep", ...
        "Mosaic movement magnitudes do not match the configured target step.");
end

% Convert integer grid coordinates to physical target positions.
targetXUm = (gridX - 1) * cfg.stitching.targetStepUm(1);
targetYUm = (gridY - 1) * cfg.stitching.targetStepUm(2);
% The target grid has an arbitrary zero origin. Remove only the best-fit
% translation from the absolute stage readings; retain all scale and local
% positioning errors for QC.
actualXOffsetUm = median(positionRecords.actualXUm - targetXUm);
actualYOffsetUm = median(positionRecords.actualYUm - targetYUm);
actualXAlignedUm = positionRecords.actualXUm - actualXOffsetUm;
actualYAlignedUm = positionRecords.actualYUm - actualYOffsetUm;
targetResidualXUm = actualXAlignedUm - targetXUm;
targetResidualYUm = actualYAlignedUm - targetYUm;

% Retain raw commands, absolute readings, aligned readings, and residuals in one
% table so the placement decision can be audited later.
positions = positionRecords;
positions.rawTileIndex = positions.acquisitionIndex - 1;
positions.gridX = gridX;
positions.gridY = gridY;
positions.targetXUm = targetXUm;
positions.targetYUm = targetYUm;
positions.actualXAlignedUm = actualXAlignedUm;
positions.actualYAlignedUm = actualYAlignedUm;
positions.targetResidualXUm = targetResidualXUm;
positions.targetResidualYUm = targetResidualYUm;
end

function validateMasterMetadata(metadata, cfg)
% Compare only fields that define file counts or nominal stitching geometry.
% xres/yres are deliberately not included: the config's 1 um/pixel is the
% documented authority for this dataset.
checks = {
    "rows",     metadata.rows,     cfg.acquisition.tileSizePixels(2)
    "columns",  metadata.columns,  cfg.acquisition.tileSizePixels(1)
    "layers",   metadata.layers,   cfg.acquisition.layersPerSection
    "mrows",    metadata.mrows,    cfg.acquisition.gridSize(1)
    "mcolumns", metadata.mcolumns, cfg.acquisition.gridSize(2)
    "sections", metadata.sections, cfg.acquisition.sectionCount
    "mrowres",  metadata.mrowres,  cfg.stitching.targetStepUm(1)
    "mcolumnres", metadata.mcolumnres, cfg.stitching.targetStepUm(2)
    };

for i = 1:size(checks, 1)
    if checks{i, 2} ~= checks{i, 3}
        error("stpt:MetadataMismatch", ...
            "Mosaic %s=%g, but config expects %g.", ...
            checks{i, 1}, checks{i, 2}, checks{i, 3});
    end
end
end

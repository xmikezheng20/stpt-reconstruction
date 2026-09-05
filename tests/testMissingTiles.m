function testMissingTiles()
%TESTMISSINGTILES Exercise sparse lookup, loading, fusion, and support masks.

addpath(fullfile(fileparts(fileparts(mfilename("fullpath"))), "src"));
testRoot = string(tempname);
mkdir(testRoot);
cleanup = onCleanup(@() rmdir(testRoot, "s"));
sectionDir = fullfile(testRoot, "section_001");
mkdir(sectionDir);

% Construct a 3-by-3 plane with the center acquisition slot absent. Fixed file
% slots preserve every later tile's identity.
nTiles = 9;
fileNames = strings(nTiles, 1);
for acquisitionIndex = [1:4, 6:9]
    fileNames(acquisitionIndex) = sprintf("tile_%02d.tif", acquisitionIndex);
    imwrite(repmat(uint16(100), 6, 6), ...
        fullfile(sectionDir, fileNames(acquisitionIndex)));
end

[gridX, gridY] = meshgrid(1:3, 1:3);
targetXUm = (gridX(:) - 1) * 4;
targetYUm = (gridY(:) - 1) * 4;
positions = table((1:nTiles)', gridX(:), gridY(:), targetXUm, targetYUm, ...
    'VariableNames', {'acquisitionIndex', 'gridX', 'gridY', ...
    'targetXUm', 'targetYUm'});
section = struct("number", 1, "channelDirectories", "section_001", ...
    "channelFiles", {{fileNames}}, "positions", positions, ...
    "nativeStartIndex", 0);

datasetIndex.rawRoot = testRoot;
datasetIndex.channels = struct("id", 1, "name", "test", ...
    "root", testRoot, "directory", "", "fileCode", "01");
datasetIndex.sections = section;
datasetIndex.geometry.tilesPerLayer = nTiles;
datasetIndex.geometry.layersPerSection = 1;
datasetIndex.geometry.tileSizePixels = [6, 6];
datasetIndex.geometry.retainedTileSizePixels = [6, 6];
datasetIndex.geometry.targetStepPixels = [4, 4];
datasetIndex.geometry.nominalCanvasSizePixels = [14, 14];
datasetIndex.geometry.gridSize = [3, 3];

% Lookup exposes the missing slot without shifting the following file.
[missingPath, isPresent] = stpt.io.resolveTileFile( ...
    datasetIndex, 1, 1, 5, 1);
assert(~isPresent && missingPath == "");
[sixthPath, isPresent] = stpt.io.resolveTileFile( ...
    datasetIndex, 1, 1, 6, 1);
assert(isPresent && endsWith(sixthPath, "tile_06.tif"));

% Illumination loaders return only actual observations and retain coordinates.
[stack, statistics] = stpt.io.loadTileStack(datasetIndex, 1, 1, 1);
assert(size(stack, 3) == 8);
assert(~ismember(5, statistics.acquisitionIndex));
assert(ismember(6, statistics.acquisitionIndex));

model = identityModel(datasetIndex);
cfg.preprocessing.tileOrientation = "none";
cfg.fusion.blending.alpha = 1.5;
geometry = stpt.fusion.computeGeometry(datasetIndex, 1);

% A missing tile contributes neither signal nor weight. Neighbor coverage stays
% exactly 100 and only the 2-by-2 unsupported center remains zero.
[blended, blendAudit, blendSupport] = ...
    stpt.fusion.fuseFijiBlendPlane( ...
    datasetIndex, model, cfg, 1, 1, 1, geometry);
assert(all(blended(blendSupport) == 100));
assert(all(blended(~blendSupport) == 0));
assert(nnz(~blendSupport) == 4);
assert(blendAudit.expectedTileCount == 9);
assert(blendAudit.presentTileCount == 8);
assert(blendAudit.missingTileCount == 1);
assert(blendAudit.uncoveredPixelCount == 4);

[overwritten, overwriteAudit, overwriteSupport] = ...
    stpt.fusion.fuseOverwritePlane( ...
    datasetIndex, model, cfg, 1, 1, 1, geometry);
assert(isequal(overwriteSupport, blendSupport));
assert(all(overwritten(overwriteSupport) == 100));
assert(all(overwritten(~overwriteSupport) == 0));
assert(overwriteAudit.missingTileCount == 1);
assert(overwriteAudit.uncoveredPixelCount == 4);

% The section worker publishes an ordinary full-size TIFF and carries compact
% sparse-data counts into its standard manifest.
cfg.fusion.mode = "fijiBlend";
cfg.fusion.compression = "lzw";
cfg.zIllumination.method = "none";
cfg.zIllumination.referenceLayer = 1;
cfg.execution.reconstructionWorkers = 1;
manifest = stpt.reconstruction.processSections(datasetIndex, model, cfg, ...
    1, fullfile(testRoot, "reconstruction"));
assert(height(manifest) == 1);
assert(manifest.expectedTileCount == 9);
assert(manifest.presentTileCount == 8);
assert(manifest.missingTileCount == 1);
assert(manifest.uncoveredPixelCount == 4);
assert(isequal(size(imread(manifest.filePath)), [14, 14]));

% On a complete plane, the new sparse-aware fusion path remains pixel-identical
% to the original all-tile normalized calculation.
for acquisitionIndex = 1:nTiles
    fileNames(acquisitionIndex) = sprintf("tile_%02d.tif", acquisitionIndex);
    imwrite(repmat(uint16(100 * acquisitionIndex), 6, 6), ...
        fullfile(sectionDir, fileNames(acquisitionIndex)));
end
datasetIndex.sections.channelFiles{1} = fileNames;
[completeBlend, completeAudit, completeSupport] = ...
    stpt.fusion.fuseFijiBlendPlane( ...
    datasetIndex, model, cfg, 1, 1, 1, geometry);
legacyBlend = originalCompleteBlend( ...
    datasetIndex, model, cfg, geometry);
assert(isequal(completeBlend, legacyBlend));
assert(all(completeSupport(:)));
assert(completeAudit.missingTileCount == 0);
assert(completeAudit.uncoveredPixelCount == 0);

fprintf("testMissingTiles: PASS\n");
end

function stitched = originalCompleteBlend(datasetIndex, model, cfg, geometry)
% Reproduce the pre-sparse normalized loop for complete-data regression.
canvasSize = geometry.canvasSizePixels;
weightedSum = zeros(canvasSize(2), canvasSize(1), "single");
weightSum = zeros(canvasSize(2), canvasSize(1), "single");
weight = stpt.fusion.fijiWeight( ...
    geometry.tileSizePixels, cfg.fusion.blending.alpha);

for row = geometry.reverseAcquisitionOrder(:)'
    placement = geometry.placements(row, :);
    tile = stpt.fusion.prepareTile(datasetIndex, model, cfg, ...
        1, 1, 1, placement.acquisitionIndex, placement.gridY);
    y = placement.yStart:placement.yEnd;
    x = placement.xStart:placement.xEnd;
    weightedSum(y, x) = weightedSum(y, x) + tile .* weight;
    weightSum(y, x) = weightSum(y, x) + weight;
end

stitched = uint16(round(min(max(weightedSum ./ weightSum, 0), 65535)));
end

function model = identityModel(datasetIndex)
model.inputTileSizePixels = [6, 6];
model.cropPixels = [0, 0, 0, 0];
layer.offset.oddRows = single(0);
layer.offset.evenRows = single(0);
layer.gain.oddRows = ones(6, 6, "single");
layer.gain.evenRows = ones(6, 6, "single");
channel.id = datasetIndex.channels.id;
channel.layers = layer;
model.channels = channel;
end

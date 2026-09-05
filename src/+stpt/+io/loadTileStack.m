function [imageStack, tileStatistics] = loadTileStack( ...
        datasetIndex, sectionNumber, layer, channelId)
%LOADTILESTACK Load one native section/channel/layer without preprocessing.
%
% This is an independent native-TissueCyte implementation. It replaces, rather
% than calls or ports, StitchIt's BakingTray-specific stitching/tileLoad.m.
% Only acquired TIFFs are returned; tileStatistics preserves their original
% acquisition indices and target-grid coordinates.

sectionPosition = find([datasetIndex.sections.number] == sectionNumber, 1);
if isempty(sectionPosition)
    error("stpt:UnknownSection", "Section %d is not indexed.", sectionNumber);
end

nTiles = datasetIndex.geometry.tilesPerLayer;
tileSize = datasetIndex.geometry.tileSizePixels; % [width, height]

% Missing acquisition slots are absent observations, not zero-valued images.
% Build a compact stack of only the TIFFs that physically exist while retaining
% their original acquisition and target-grid coordinates in tileStatistics.
present = false(nTiles, 1);
for tile = 1:nTiles
    [~, present(tile)] = stpt.io.resolveTileFile( ...
        datasetIndex, sectionNumber, layer, tile, channelId);
end
acquisitionIndices = find(present);
nPresent = numel(acquisitionIndices);
if nPresent == 0
    error("stpt:MissingPlane", ...
        "No TIFFs were acquired for section %d, layer %d, ch%d.", ...
        sectionNumber, layer, channelId);
end

[firstImage, firstPath] = stpt.io.loadTile(datasetIndex, sectionNumber, ...
    layer, acquisitionIndices(1), channelId);
imageStack = zeros(tileSize(2), tileSize(1), nPresent, "like", firstImage);

filePaths = strings(nPresent, 1);
tileMeans = zeros(nPresent, 1);
tileStdDevs = zeros(nPresent, 1);

for stackIndex = 1:nPresent
    acquisitionIndex = acquisitionIndices(stackIndex);
    if stackIndex == 1
        image = firstImage;
        filePath = firstPath;
    else
        [image, filePath] = stpt.io.loadTile(datasetIndex, sectionNumber, ...
            layer, acquisitionIndex, channelId);
    end

    imageStack(:, :, stackIndex) = image;
    pixels = double(image(:));
    tileMeans(stackIndex) = mean(pixels);
    tileStdDevs(stackIndex) = std(pixels);
    filePaths(stackIndex) = filePath;
end

% Combine native file coordinates, target-grid coordinates, and compact image
% statistics in a table that can be written directly to CSV.
section = datasetIndex.sections(sectionPosition);
positions = section.positions(acquisitionIndices, :);
nativeIndex = section.nativeStartIndex + (layer - 1) * nTiles + ...
    positions.acquisitionIndex - 1;
tileStatistics = table( ...
    repmat(sectionNumber, nPresent, 1), ...
    repmat(channelId, nPresent, 1), ...
    repmat(layer, nPresent, 1), ...
    positions.acquisitionIndex, nativeIndex, positions.gridX, positions.gridY, ...
    positions.targetXUm, positions.targetYUm, tileMeans, tileStdDevs, filePaths, ...
    'VariableNames', {'sectionNumber', 'channelId', 'layer', ...
    'acquisitionIndex', 'nativeIndex', 'gridX', 'gridY', 'targetXUm', ...
    'targetYUm', 'tileMean', 'tileStdDev', 'filePath'});
end

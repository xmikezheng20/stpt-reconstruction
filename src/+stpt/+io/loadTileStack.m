function [imageStack, tileStatistics] = loadTileStack( ...
        datasetIndex, sectionNumber, layer, channelId)
%LOADTILESTACK Load one native section/channel/layer without preprocessing.
%
% This is an independent native-TissueCyte implementation. It replaces, rather
% than calls or ports, StitchIt's BakingTray-specific stitching/tileLoad.m.

sectionPosition = find([datasetIndex.sections.number] == sectionNumber, 1);
if isempty(sectionPosition)
    error("stpt:UnknownSection", "Section %d is not indexed.", sectionNumber);
end

section = datasetIndex.sections(sectionPosition);
nTiles = datasetIndex.geometry.tilesPerLayer;
tileSize = datasetIndex.geometry.tileSizePixels; % [width, height]

% Load the first tile to establish the native MATLAB class, then preallocate one
% contiguous stack. Only one channel/layer stack is resident at a time.
[firstImage, firstPath] = stpt.io.loadTile( ...
    datasetIndex, sectionNumber, layer, 1, channelId);
imageStack = zeros(tileSize(2), tileSize(1), nTiles, "like", firstImage);

filePaths = strings(nTiles, 1);
tileMeans = zeros(nTiles, 1);
tileStdDevs = zeros(nTiles, 1);

for tile = 1:nTiles
    if tile == 1
        image = firstImage;
        filePath = firstPath;
    else
        [image, filePath] = stpt.io.loadTile(datasetIndex, sectionNumber, ...
            layer, tile, channelId);
    end

    imageStack(:, :, tile) = image;
    pixels = double(image(:));
    tileMeans(tile) = mean(pixels);
    tileStdDevs(tile) = std(pixels);
    filePaths(tile) = filePath;
end

% Combine native file coordinates, target-grid coordinates, and compact image
% statistics in a table that can be written directly to CSV.
positions = section.positions;
nativeIndex = section.nativeStartIndex + (layer - 1) * nTiles + ...
    positions.acquisitionIndex - 1;
tileStatistics = table( ...
    repmat(sectionNumber, nTiles, 1), ...
    repmat(channelId, nTiles, 1), ...
    repmat(layer, nTiles, 1), ...
    positions.acquisitionIndex, nativeIndex, positions.gridX, positions.gridY, ...
    positions.targetXUm, positions.targetYUm, tileMeans, tileStdDevs, filePaths, ...
    'VariableNames', {'sectionNumber', 'channelId', 'layer', ...
    'acquisitionIndex', 'nativeIndex', 'gridX', 'gridY', 'targetXUm', ...
    'targetYUm', 'tileMean', 'tileStdDev', 'filePath'});
end

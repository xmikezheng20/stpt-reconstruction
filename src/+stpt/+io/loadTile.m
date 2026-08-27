function [image, filePath] = loadTile(datasetIndex, sectionNumber, layer, ...
        acquisitionIndex, channelId)
%LOADTILE Read one indexed native TIFF and verify its basic image format.

filePath = stpt.io.resolveTileFile(datasetIndex, sectionNumber, layer, ...
    acquisitionIndex, channelId);
image = imread(filePath);

expectedSize = datasetIndex.geometry.tileSizePixels; % [width, height]
if ~ismatrix(image) || size(image, 2) ~= expectedSize(1) || ...
        size(image, 1) ~= expectedSize(2)
    error("stpt:TileDimensions", ...
        "Tile %s does not match configured size %d-by-%d.", ...
        filePath, expectedSize(1), expectedSize(2));
end
if ~isa(image, "uint16")
    error("stpt:TileClass", "Expected uint16 TIFF data, found %s in %s.", ...
        class(image), filePath);
end
end

function tissue = tissueMasks(planes, supportMasks, parameters, pixelSizeUm)
%TISSUEMASKS Tissue on the estimation grid for each optical layer.
%
% Called with the fused layers of the tissue channel. Each layer is reduced to
% block means of estimationGridUm, smoothed by one grid pixel, and split into
% empty canvas and tissue by Otsu on log(1 + intensity). Pieces smaller than
% one gain window (2*pi*sigma^2) are dropped, and only fully acquired blocks
% count. localTissueRatio uses these masks for every channel of the section.

% pixelSizeUm is [x, y]; planes and grids are [rows, columns].
block = max(1, round(parameters.estimationGridUm ./ pixelSizeUm([2, 1])));
gridUm = block .* pixelSizeUm([2, 1]);
minimumPiecePixels = ceil(2 * pi * prod(parameters.windowSigmaUm ./ gridUm));

layers = cell(1, numel(planes));
for layer = 1:numel(planes)
    reduced = stpt.zillumination.blockMean(planes{layer}, block);
    smoothed = imgaussfilt(reduced, 1, "Padding", "symmetric");
    mask = bwareaopen(logOtsuMask(smoothed), minimumPiecePixels, 8);
    layers{layer} = mask & stpt.zillumination.coveredBlocks( ...
        supportMasks{layer}, block, size(reduced));
end

tissue = struct("block", block, "gridUm", gridUm, ...
    "gridSize", size(reduced), "layers", {layers});
end

function mask = logOtsuMask(image)
% Empty canvas against tissue: Otsu on log(1 + intensity) over all pixels.
logIntensity = log1p(image);
if max(logIntensity, [], "all") <= min(logIntensity, [], "all")
    mask = false(size(image));
    return
end
mask = logIntensity > multithresh(logIntensity, 1);
end

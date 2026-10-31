function tissue = tissueMasks(planes, tileThresholdLog, parameters, ...
        pixelSizeUm)
%TISSUEMASKS Tissue on the estimation grid for each optical layer.
%
% Called with the fused layers of the tissue channel. Each layer is reduced to
% block means of estimationGridUm and smoothed by one grid pixel. A block holds
% tissue when its log(1 + intensity) exceeds half of tileThresholdLog, stage
% 2's log-Otsu split of the same channel's tile means: midway in log between
% the empty canvas (about 0) and that split. One threshold serves the whole
% brain, so dim tissue in a deep layer still counts. Pieces smaller than one
% gain window (2*pi*sigma^2) are dropped. localTissueRatio uses these masks for
% every channel of the section, restricted to that channel's acquired blocks.

% pixelSizeUm is [x, y]; planes and grids are [rows, columns].
block = max(1, round(parameters.estimationGridUm ./ pixelSizeUm([2, 1])));
gridUm = block .* pixelSizeUm([2, 1]);
minimumPiecePixels = ceil(2 * pi * prod(parameters.windowSigmaUm ./ gridUm));

layers = cell(1, numel(planes));
for layer = 1:numel(planes)
    reduced = stpt.zillumination.blockMean(planes{layer}, block);
    smoothed = imgaussfilt(reduced, 1, "Padding", "symmetric");
    layers{layer} = bwareaopen(log1p(smoothed) > tileThresholdLog / 2, ...
        minimumPiecePixels, 8);
end

tissue = struct("block", block, "gridUm", gridUm, ...
    "gridSize", size(reduced), "layers", {layers});
end

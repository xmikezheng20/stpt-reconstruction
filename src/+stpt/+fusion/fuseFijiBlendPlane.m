function [stitched, audit, supportMask] = fuseFijiBlendPlane( ...
        datasetIndex, model, cfg, sectionNumber, layer, channelId, geometry)
%FUSEFIJIBLENDPLANE Fuse corrected tiles by normalized Fiji-style weights.
%
% This implements OpenSTP's fusionMethod=3 calculation using our indexed target
% placement. Every contributing tile is accumulated in single precision; the
% normalized mosaic is clipped and converted to uint16 only after blending.

canvasSize = geometry.canvasSizePixels; % [width, height]
weightedSum = zeros(canvasSize(2), canvasSize(1), "single");
weightSum = zeros(canvasSize(2), canvasSize(1), "single");
weight = stpt.fusion.fijiWeight( ...
    geometry.tileSizePixels, cfg.fusion.blending.alpha);

correctedMinimum = inf;
correctedMaximum = -inf;
clippedLowPixels = 0;
clippedHighPixels = 0;
presentTileCount = 0;
started = tic;

% The normalized sum is order-independent. We retain the same traversal as
% overwrite fusion so both alternatives read tiles in the same sequence.
for row = geometry.reverseAcquisitionOrder(:)'
    placement = geometry.placements(row, :);
    [~, isPresent] = stpt.io.resolveTileFile(datasetIndex, sectionNumber, ...
        layer, placement.acquisitionIndex, channelId);
    if ~isPresent
        continue
    end

    tile = stpt.fusion.prepareTile( ...
        datasetIndex, model, cfg, sectionNumber, layer, channelId, ...
        placement.acquisitionIndex, placement.gridY);
    correctedMinimum = min(correctedMinimum, double(min(tile(:))));
    correctedMaximum = max(correctedMaximum, double(max(tile(:))));
    clippedLowPixels = clippedLowPixels + nnz(tile < 0);
    clippedHighPixels = clippedHighPixels + nnz(tile > 65535);
    presentTileCount = presentTileCount + 1;

    y = placement.yStart:placement.yEnd;
    x = placement.xStart:placement.xEnd;
    weightedSum(y, x) = weightedSum(y, x) + tile .* weight;
    weightSum(y, x) = weightSum(y, x) + weight;
end

if presentTileCount == 0
    error("stpt:MissingPlane", ...
        "No tiles are available for section %d, layer %d, ch%d.", ...
        sectionNumber, layer, channelId);
end

% A scalar true denotes complete canvas support without retaining a full-size
% logical array for every normal plane. Sparse planes carry the explicit mask.
if presentTileCount == height(geometry.placements)
    supportMask = true;
    uncoveredPixelCount = 0;
else
    supportMask = weightSum > 0;
    uncoveredPixelCount = nnz(~supportMask);
end

% Normalize only where an acquired tile contributes. Unsupported pixels remain
% zero; a missing tile never contributes synthetic zero intensity or weight.
stitched = zeros(canvasSize(2), canvasSize(1), "uint16");
blockHeight = 512;
for firstRow = 1:blockHeight:size(stitched, 1)
    rows = firstRow:min(firstRow + blockHeight - 1, size(stitched, 1));
    blockWeightedSum = weightedSum(rows, :);
    blockWeightSum = weightSum(rows, :);
    if isscalar(supportMask)
        blended = blockWeightedSum ./ blockWeightSum;
    else
        blockSupport = supportMask(rows, :);
        blended = zeros(numel(rows), size(stitched, 2), "single");
        blended(blockSupport) = ...
            blockWeightedSum(blockSupport) ./ blockWeightSum(blockSupport);
    end
    stitched(rows, :) = uint16(round(min(max(blended, 0), 65535)));
end

audit = struct();
audit.sectionNumber = sectionNumber;
audit.layer = layer;
audit.channelId = channelId;
audit.expectedTileCount = height(geometry.placements);
audit.presentTileCount = presentTileCount;
audit.missingTileCount = audit.expectedTileCount - presentTileCount;
audit.uncoveredPixelCount = uncoveredPixelCount;
audit.correctedMinimum = correctedMinimum;
audit.correctedMaximum = correctedMaximum;
audit.clippedLowPixels = clippedLowPixels;
audit.clippedHighPixels = clippedHighPixels;
audit.fusionSeconds = toc(started);
end

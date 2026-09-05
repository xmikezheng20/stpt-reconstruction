function [stitched, audit, supportMask] = fuseOverwritePlane( ...
        datasetIndex, model, cfg, sectionNumber, layer, channelId, geometry)
%FUSEOVERWRITEPLANE Fuse by reverse-order overwrite, matching StitchIt default.

canvasSize = geometry.canvasSizePixels; % [width, height]
stitched = zeros(canvasSize(2), canvasSize(1), "uint16");
[correctedMinimum, correctedMaximum, clippedLowPixels, ...
    clippedHighPixels] = initialIntensityAudit();
available = false(height(geometry.placements), 1);
for row = 1:height(geometry.placements)
    placement = geometry.placements(row, :);
    [~, available(row)] = stpt.io.resolveTileFile( ...
        datasetIndex, sectionNumber, layer, ...
        placement.acquisitionIndex, channelId);
end
presentTileCount = nnz(available);
if presentTileCount == 0
    error("stpt:MissingPlane", ...
        "No tiles are available for section %d, layer %d, ch%d.", ...
        sectionNumber, layer, channelId);
elseif presentTileCount == height(geometry.placements)
    supportMask = true;
else
    supportMask = false(canvasSize(2), canvasSize(1));
end
started = tic;

% Reverse traversal makes the earliest-acquired tile the final contributor in
% every overlap, matching StitchIt's default fusionWeight=0 behavior.
for row = geometry.reverseAcquisitionOrder(:)'
    placement = geometry.placements(row, :);
    if ~available(row)
        continue
    end

    tile = stpt.fusion.prepareTile( ...
        datasetIndex, model, cfg, sectionNumber, layer, channelId, ...
        placement.acquisitionIndex, placement.gridY);
    [correctedMinimum, correctedMaximum, clippedLowPixels, ...
        clippedHighPixels] = updateIntensityAudit(tile, ...
        correctedMinimum, correctedMaximum, clippedLowPixels, ...
        clippedHighPixels);

    % Overwrite output is cast tile-by-tile; only the selected contributor is
    % retained in each overlap.
    tile = uint16(round(min(max(tile, 0), 65535)));
    y = placement.yStart:placement.yEnd;
    x = placement.xStart:placement.xEnd;
    stitched(y, x) = tile;
    if ~isscalar(supportMask)
        supportMask(y, x) = true;
    end
end

if isscalar(supportMask)
    uncoveredPixelCount = 0;
else
    uncoveredPixelCount = nnz(~supportMask);
end

audit = buildAudit(sectionNumber, layer, channelId, geometry, ...
    correctedMinimum, correctedMaximum, clippedLowPixels, ...
    clippedHighPixels, presentTileCount, uncoveredPixelCount, toc(started));
end

function [minimum, maximum, lowPixels, highPixels] = initialIntensityAudit()
minimum = inf;
maximum = -inf;
lowPixels = 0;
highPixels = 0;
end

function [minimum, maximum, lowPixels, highPixels] = updateIntensityAudit( ...
        tile, minimum, maximum, lowPixels, highPixels)
minimum = min(minimum, double(min(tile(:))));
maximum = max(maximum, double(max(tile(:))));
lowPixels = lowPixels + nnz(tile < 0);
highPixels = highPixels + nnz(tile > 65535);
end

function audit = buildAudit(sectionNumber, layer, channelId, geometry, ...
        minimum, maximum, lowPixels, highPixels, presentTileCount, ...
        uncoveredPixelCount, fusionSeconds)
audit = struct();
audit.sectionNumber = sectionNumber;
audit.layer = layer;
audit.channelId = channelId;
audit.expectedTileCount = height(geometry.placements);
audit.presentTileCount = presentTileCount;
audit.missingTileCount = audit.expectedTileCount - presentTileCount;
audit.uncoveredPixelCount = uncoveredPixelCount;
audit.correctedMinimum = minimum;
audit.correctedMaximum = maximum;
audit.clippedLowPixels = lowPixels;
audit.clippedHighPixels = highPixels;
audit.fusionSeconds = fusionSeconds;
end

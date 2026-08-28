function [stitched, audit] = fuseOverwritePlane( ...
        datasetIndex, model, cfg, sectionNumber, layer, channelId, geometry)
%FUSEOVERWRITEPLANE Fuse by reverse-order overwrite, matching StitchIt default.

canvasSize = geometry.canvasSizePixels; % [width, height]
stitched = zeros(canvasSize(2), canvasSize(1), "uint16");
[correctedMinimum, correctedMaximum, clippedLowPixels, ...
    clippedHighPixels] = initialIntensityAudit();
started = tic;

% Reverse traversal makes the earliest-acquired tile the final contributor in
% every overlap, matching StitchIt's default fusionWeight=0 behavior.
for row = geometry.reverseAcquisitionOrder(:)'
    placement = geometry.placements(row, :);
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
    stitched(placement.yStart:placement.yEnd, ...
        placement.xStart:placement.xEnd) = tile;
end

audit = buildAudit(sectionNumber, layer, channelId, geometry, ...
    correctedMinimum, correctedMaximum, clippedLowPixels, ...
    clippedHighPixels, toc(started));
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
        minimum, maximum, lowPixels, highPixels, fusionSeconds)
audit = struct();
audit.sectionNumber = sectionNumber;
audit.layer = layer;
audit.channelId = channelId;
audit.tileCount = height(geometry.placements);
audit.correctedMinimum = minimum;
audit.correctedMaximum = maximum;
audit.clippedLowPixels = lowPixels;
audit.clippedHighPixels = highPixels;
audit.fusionSeconds = fusionSeconds;
end

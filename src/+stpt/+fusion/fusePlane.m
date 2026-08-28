function [stitched, audit, geometry] = fusePlane( ...
        datasetIndex, model, cfg, sectionNumber, layer, channelId)
%FUSEPLANE Correct and overwrite-fuse one full-resolution image plane.
%
% Only one raw tile and its corrected single-precision result are resident in
% addition to the uint16 stitched canvas. No corrected tile TIFFs are written.

geometry = stpt.fusion.computeGeometry(datasetIndex, sectionNumber);
canvasSize = geometry.canvasSizePixels; % [width, height]
stitched = zeros(canvasSize(2), canvasSize(1), "uint16");

correctedMinimum = inf;
correctedMaximum = -inf;
clippedLowPixels = 0;
clippedHighPixels = 0;
started = tic;

% Reverse traversal makes the earliest-acquired tile the final contributor in
% every overlap, matching StitchIt's default fusionWeight=0 behavior.
for row = geometry.reverseAcquisitionOrder(:)'
    placement = geometry.placements(row, :);
    acquisitionIndex = placement.acquisitionIndex;
    rawTile = stpt.io.loadTile(datasetIndex, sectionNumber, layer, ...
        acquisitionIndex, channelId);
    corrected = stpt.illumination.applyModel(rawTile, model, ...
        channelId, layer, placement.gridY);
    corrected = stpt.preprocessing.applyTileOrientation( ...
        corrected, cfg.preprocessing.tileOrientation);

    if any(~isfinite(corrected(:)))
        error("stpt:FusionIntensity", ...
            "Non-finite corrected pixels in section %d, layer %d, ch%d.", ...
            sectionNumber, layer, channelId);
    end
    correctedMinimum = min(correctedMinimum, double(min(corrected(:))));
    correctedMaximum = max(correctedMaximum, double(max(corrected(:))));
    clippedLowPixels = clippedLowPixels + nnz(corrected < 0);
    clippedHighPixels = clippedHighPixels + nnz(corrected > 65535);

    % Make the output conversion explicit. MATLAB's integer cast is not left as
    % an implicit side effect of assigning singles into the stitched canvas.
    corrected = uint16(round(min(max(corrected, 0), 65535)));
    stitched(placement.yStart:placement.yEnd, ...
        placement.xStart:placement.xEnd) = corrected;
end

audit = struct();
audit.sectionNumber = sectionNumber;
audit.layer = layer;
audit.channelId = channelId;
audit.tileCount = height(geometry.placements);
audit.correctedMinimum = correctedMinimum;
audit.correctedMaximum = correctedMaximum;
audit.clippedLowPixels = clippedLowPixels;
audit.clippedHighPixels = clippedHighPixels;
audit.fusionSeconds = toc(started);
end

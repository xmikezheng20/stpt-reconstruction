function writePilotQC( ...
        datasetIndex, model, cfg, sectionNumber, manifest, stageDir)
%WRITEPILOTQC Write compact, center-section fusion diagnostics.
%
% QC reads canonical fused TIFFs and, for one checkerboard, the same native
% tiles through the public correction interface. It never changes fused data.

qcDir = string(fullfile(stageDir, "qc"));
if ~isfolder(qcDir)
    mkdir(qcDir);
end

nChannels = numel(datasetIndex.channels);
nLayers = datasetIndex.geometry.layersPerSection;
previews = cell(nChannels, nLayers);
displayLimits = zeros(nChannels, 2);

% Load only 10% previews into memory. Both layers of a channel share one display
% range so optical-layer attenuation remains visible rather than normalized out.
for c = 1:nChannels
    channelId = datasetIndex.channels(c).id;
    for layer = 1:nLayers
        row = manifest.sectionNumber == sectionNumber & ...
            manifest.channelId == channelId & manifest.layer == layer;
        if nnz(row) ~= 1
            error("stpt:FusionQC", ...
                "Expected one fused plane for section %d, layer %d, ch%d.", ...
                sectionNumber, layer, channelId);
        end
        image = imread(manifest.filePath(row));
        previews{c, layer} = imresize( ...
            image, cfg.fusion.qcPreviewScale, "bilinear");
    end
    values = double([previews{c, :}]);
    values = values(values > 0);
    if isempty(values)
        displayLimits(c, :) = [0, 1];
    else
        displayLimits(c, :) = prctile(values, [0.5, 99.8]);
        if displayLimits(c, 1) == displayLimits(c, 2)
            displayLimits(c, 2) = displayLimits(c, 1) + 1;
        end
    end
end

plotChannelLayers(datasetIndex, cfg, sectionNumber, previews, displayLimits, ...
    fullfile(qcDir, "center_section_channels_layers.png"));
plotChannelOverlay(datasetIndex, cfg, sectionNumber, previews, displayLimits, ...
    fullfile(qcDir, "center_section_red_green_overlay.png"));
plotChessboard(datasetIndex, model, cfg, sectionNumber, displayLimits, ...
    fullfile(qcDir, "center_section_green_chessboard.png"));
writeSummary(datasetIndex, cfg, sectionNumber, manifest, ...
    fullfile(stageDir, "fusion_summary.txt"));
end

function plotChannelLayers(datasetIndex, cfg, sectionNumber, previews, ...
        displayLimits, outputPath)
% Show all canonical center-section planes without independently rescaling layers.
nChannels = numel(datasetIndex.channels);
nLayers = datasetIndex.geometry.layersPerSection;
fig = figure("Visible", "off", "Color", "w", ...
    "Position", [100, 100, 700 * nLayers, 650 * nChannels]);
tiledlayout(nChannels, nLayers, ...
    "Padding", "compact", "TileSpacing", "compact");

for c = 1:nChannels
    for layer = 1:nLayers
        nexttile
        imagesc(previews{c, layer});
        axis image off
        clim(displayLimits(c, :));
        colormap(gca, gray(256));
        title(sprintf("ch%d %s, layer %d", ...
            datasetIndex.channels(c).id, ...
            datasetIndex.channels(c).name, layer));
    end
end
sgtitle(sprintf("Section %d: illumination-corrected %s fusion", ...
    sectionNumber, fusionModeLabel(cfg)));
exportgraphics(fig, outputPath, "Resolution", 160);
close(fig);
end

function plotChannelOverlay(datasetIndex, cfg, sectionNumber, previews, ...
        displayLimits, outputPath)
% Confirm that red and green channels occupy the same stitched coordinates.
names = lower(string({datasetIndex.channels.name}));
redPosition = find(names == "red", 1);
greenPosition = find(names == "green", 1);
if isempty(redPosition) || isempty(greenPosition)
    error("stpt:FusionQC", ...
        "The pilot overlay requires configured red and green channels.");
end

red = normalizeForDisplay(previews{redPosition, 1}, ...
    displayLimits(redPosition, :));
green = normalizeForDisplay(previews{greenPosition, 1}, ...
    displayLimits(greenPosition, :));
overlay = cat(3, red, green, zeros(size(red), "single"));

fig = figure("Visible", "off", "Color", "w", ...
    "Position", [100, 100, 900, 1000]);
imshow(overlay);
title(sprintf("Section %d, layer 1: red ch1 / green ch2 (%s fusion)", ...
    sectionNumber, fusionModeLabel(cfg)));
exportgraphics(fig, outputPath, "Resolution", 160);
close(fig);
end

function plotChessboard(datasetIndex, model, cfg, sectionNumber, ...
        displayLimits, outputPath)
% Render alternating grid tiles in red/green to expose overlap alignment.
referenceChannel = cfg.illumination.tissueReferenceChannel;
channelPosition = find([datasetIndex.channels.id] == referenceChannel, 1);
if isempty(channelPosition)
    error("stpt:FusionQC", "The tissue-reference channel is not indexed.");
end
limits = displayLimits(channelPosition, :);
layer = 1;
geometry = stpt.fusion.computeGeometry(datasetIndex, sectionNumber);
scale = cfg.fusion.qcPreviewScale;

previewHeight = round(geometry.canvasSizePixels(2) * scale);
previewWidth = round(geometry.canvasSizePixels(1) * scale);
preview = zeros(previewHeight, previewWidth, 3, "uint8");

% The inset straddles the central four-tile junction at native resolution.
insetSize = 1200;
junctionX = 1 + floor(datasetIndex.geometry.gridSize(1) / 2) * ...
    geometry.targetStepPixels(1);
junctionY = 1 + floor(datasetIndex.geometry.gridSize(2) / 2) * ...
    geometry.targetStepPixels(2);
insetXStart = max(1, junctionX - insetSize / 2);
insetYStart = max(1, junctionY - insetSize / 2);
insetXEnd = min(geometry.canvasSizePixels(1), ...
    insetXStart + insetSize - 1);
insetYEnd = min(geometry.canvasSizePixels(2), ...
    insetYStart + insetSize - 1);
inset = zeros(insetYEnd - insetYStart + 1, ...
    insetXEnd - insetXStart + 1, 3, "uint8");

for row = 1:height(geometry.placements)
    placement = geometry.placements(row, :);
    corrected = stpt.fusion.prepareTile( ...
        datasetIndex, model, cfg, sectionNumber, layer, referenceChannel, ...
        placement.acquisitionIndex, placement.gridY);
    displayTile = uint8(round(255 * normalizeForDisplay(corrected, limits)));

    % True grid parity yields a stable checkerboard independent of acquisition
    % direction. Overlap between neighboring tiles appears in both color planes.
    if mod(placement.gridX + placement.gridY, 2) == 0
        colorPlane = 1;
    else
        colorPlane = 2;
    end

    reducedTile = imresize(displayTile, scale, "bilinear");
    previewX = round((placement.xStart - 1) * scale) + 1;
    previewY = round((placement.yStart - 1) * scale) + 1;
    preview(:, :, colorPlane) = placeMaximum( ...
        preview(:, :, colorPlane), reducedTile, previewX, previewY);

    % Place only the intersection with the native-resolution inset.
    overlapXStart = max(placement.xStart, insetXStart);
    overlapXEnd = min(placement.xEnd, insetXEnd);
    overlapYStart = max(placement.yStart, insetYStart);
    overlapYEnd = min(placement.yEnd, insetYEnd);
    if overlapXStart <= overlapXEnd && overlapYStart <= overlapYEnd
        sourceX = (overlapXStart:overlapXEnd) - placement.xStart + 1;
        sourceY = (overlapYStart:overlapYEnd) - placement.yStart + 1;
        targetX = (overlapXStart:overlapXEnd) - insetXStart + 1;
        targetY = (overlapYStart:overlapYEnd) - insetYStart + 1;
        current = inset(targetY, targetX, colorPlane);
        inset(targetY, targetX, colorPlane) = ...
            max(current, displayTile(sourceY, sourceX));
    end
end

fig = figure("Visible", "off", "Color", "w", ...
    "Position", [100, 100, 1500, 850]);
tiledlayout(1, 2, "Padding", "compact", "TileSpacing", "compact");
nexttile
imshow(preview);
title(sprintf("Section %d, green layer 1: tile checkerboard", sectionNumber));
nexttile
imshow(inset);
title("Native-resolution central junction");
sgtitle("Tile-placement QC (not fused); yellow regions are nominal overlap");
exportgraphics(fig, outputPath, "Resolution", 160);
close(fig);
end

function canvas = placeMaximum(canvas, tile, xStart, yStart)
% Place a downsampled tile while tolerating only final-pixel rounding at edges.
xEnd = min(size(canvas, 2), xStart + size(tile, 2) - 1);
yEnd = min(size(canvas, 1), yStart + size(tile, 1) - 1);
tile = tile(1:yEnd-yStart+1, 1:xEnd-xStart+1);
canvas(yStart:yEnd, xStart:xEnd) = ...
    max(canvas(yStart:yEnd, xStart:xEnd), tile);
end

function image = normalizeForDisplay(image, limits)
% Convert one intensity range to [0,1] for display only.
image = (single(image) - single(limits(1))) / ...
    single(limits(2) - limits(1));
image = min(max(image, 0), 1);
end

function writeSummary(datasetIndex, cfg, sectionNumber, manifest, outputPath)
% Record geometry, output policy, clipping, compression, and timing in plain text.
geometry = datasetIndex.geometry;
uncompressedBytes = prod(geometry.nominalCanvasSizePixels) * 2 * ...
    height(manifest);
compressedBytes = sum(manifest.outputBytes, "omitnan");

fid = fopen(outputPath, "w");
if fid < 0
    error("stpt:WriteOutput", "Could not write %s.", outputPath);
end
fprintf(fid, "STPT center-section fusion pilot completed\n");
fprintf(fid, "Pilot section: %d (derived from processing range %d:%d)\n", ...
    sectionNumber, cfg.processing.sectionStart, cfg.processing.sectionStop);
fprintf(fid, "Channels: %s\n", mat2str([datasetIndex.channels.id]));
fprintf(fid, "Layers: %d\n", geometry.layersPerSection);
fprintf(fid, "Raw tile: %d x %d pixels\n", geometry.tileSizePixels);
fprintf(fid, "Crop [left right top bottom]: %s pixels\n", ...
    mat2str(geometry.cropPixels));
fprintf(fid, "Retained tile: %d x %d pixels\n", ...
    geometry.retainedTileSizePixels);
fprintf(fid, "Target step: %d x %d pixels\n", geometry.targetStepPixels);
fprintf(fid, "Derived overlap: %d x %d pixels\n", ...
    geometry.postCropOverlapPixels);
fprintf(fid, "Stitched canvas: %d x %d pixels\n", ...
    geometry.nominalCanvasSizePixels);
if strcmpi(cfg.fusion.mode, "overwrite")
    fprintf(fid, ...
        "Fusion: reverse-acquisition overwrite; earlier tiles win\n");
else
    fprintf(fid, ...
        "Fusion: Fiji-style normalized weighted blending; alpha %.6g\n", ...
        cfg.fusion.blending.alpha);
end
fprintf(fid, "Per-tile orientation: %s after illumination correction\n", ...
    string(cfg.preprocessing.tileOrientation));
fprintf(fid, "Final mosaic orientation transform: none\n");
fprintf(fid, "Output: uint16 TIFF, lossless %s compression\n", ...
    upper(string(cfg.fusion.compression)));
fprintf(fid, "Planes: %d\n", height(manifest));
fprintf(fid, "Compressed size: %.3f GiB\n", compressedBytes / 1024^3);
fprintf(fid, "Compressed/uncompressed ratio: %.4f\n", ...
    compressedBytes / uncompressedBytes);
fprintf(fid, "Corrected pixels below zero before casting: %.0f\n", ...
    sum(manifest.clippedLowPixels, "omitnan"));
fprintf(fid, "Corrected pixels above uint16 before casting: %.0f\n", ...
    sum(manifest.clippedHighPixels, "omitnan"));
fprintf(fid, "Fusion computation time: %.1f seconds\n", ...
    sum(manifest.fusionSeconds, "omitnan"));
fprintf(fid, "LZW writing time: %.1f seconds\n", ...
    sum(manifest.writeSeconds, "omitnan"));
fprintf(fid, "Raw TIFFs modified: no\n");
fprintf(fid, "Corrected tile TIFFs written: no\n");
fprintf(fid, "Completed: %s\n", string(datetime("now")));
fclose(fid);
end

function label = fusionModeLabel(cfg)
switch lower(string(cfg.fusion.mode))
    case "overwrite"
        label = "overwrite";
    case "fijiblend"
        label = "Fiji-blended";
    otherwise
        label = string(cfg.fusion.mode);
end
end

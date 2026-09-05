function writeProductionQC( ...
        datasetIndex, cfg, manifest, stageDir, reconstructionWallSeconds)
%WRITEPRODUCTIONQC Write compact checks of the published production volume.
%
% Representative images are read back from final TIFFs. Z-illumination trends
% use the compact gain percentiles already recorded for every output plane.

qcDir = string(fullfile(stageDir, "qc"));
mkdir(qcDir);
qcSections = cfg.sampling.qcSections(:)';

[previews, displayLimits] = loadRepresentativePreviews( ...
    datasetIndex, cfg, manifest, qcSections);
plotRepresentativeSections( ...
    datasetIndex, qcSections, previews, displayLimits, ...
    fullfile(qcDir, "representative_sections.png"));

if any(manifest.zIlluminationApplied)
    plotZIlluminationTrends(datasetIndex, manifest, ...
        fullfile(qcDir, "z_illumination_trends.png"));
end

writeSummary(datasetIndex, cfg, manifest, qcSections, ...
    reconstructionWallSeconds, ...
    fullfile(stageDir, "reconstruction_summary.txt"));
end

function [previews, displayLimits] = loadRepresentativePreviews( ...
        datasetIndex, cfg, manifest, sections)
% Load only reduced final images and derive one common range per channel.
nSections = numel(sections);
nChannels = numel(datasetIndex.channels);
nLayers = datasetIndex.geometry.layersPerSection;
previews = cell(nSections, nChannels, nLayers);
displayLimits = zeros(nChannels, 2);

for s = 1:nSections
    for c = 1:nChannels
        channelId = datasetIndex.channels(c).id;
        for layer = 1:nLayers
            path = findPlane(manifest, sections(s), channelId, layer);
            previews{s, c, layer} = imresize( ...
                imread(path), cfg.fusion.qcPreviewScale, "bilinear");
        end
    end
end

% A shared range preserves real intensity differences between sections and
% optical layers. Empty early or late sections therefore remain visibly dim.
for c = 1:nChannels
    channelPreviews = reshape(previews(:, c, :), [], 1);
    displayLimits(c, :) = commonDisplayLimits(channelPreviews);
end
end

function plotRepresentativeSections( ...
        datasetIndex, sections, previews, displayLimits, outputPath)
% Arrange one row per sampled section and one column per channel/layer.
nSections = numel(sections);
nChannels = numel(datasetIndex.channels);
nLayers = datasetIndex.geometry.layersPerSection;
nColumns = nChannels * nLayers;

fig = figure("Visible", "off", "Color", "w", ...
    "Position", [100, 100, 520 * nColumns, 380 * nSections]);
tiledlayout(nSections, nColumns, ...
    "Padding", "compact", "TileSpacing", "compact");

for s = 1:nSections
    for c = 1:nChannels
        channel = datasetIndex.channels(c);
        for layer = 1:nLayers
            nexttile
            imagesc(previews{s, c, layer});
            axis image off
            clim(displayLimits(c, :));
            colormap(gca, gray(256));
            title(sprintf("section %03d | ch%d %s | layer %d", ...
                sections(s), channel.id, channel.name, layer));
        end
    end
end

sgtitle("Production reconstruction: representative final sections");
exportgraphics(fig, outputPath, "Resolution", 160);
close(fig);
end

function plotZIlluminationTrends(datasetIndex, manifest, outputPath)
% Show the spatial gain distribution for every corrected section and channel.
nChannels = numel(datasetIndex.channels);
fig = figure("Visible", "off", "Color", "w", ...
    "Position", [100, 100, 1200, 420 * nChannels]);
tiledlayout(nChannels, 1, ...
    "Padding", "compact", "TileSpacing", "compact");

for c = 1:nChannels
    channel = datasetIndex.channels(c);
    rows = manifest.channelId == channel.id & ...
        manifest.zIlluminationApplied;
    values = sortrows(manifest(rows, :), "sectionNumber");
    if isempty(values)
        error("stpt:ReconstructionQC", ...
            "No z-corrected rows were found for channel %d.", channel.id);
    end

    nexttile
    plot(values.sectionNumber, values.zGainP01, ":", ...
        "Color", [0.45, 0.55, 0.75], "LineWidth", 1, ...
        "DisplayName", "1st percentile");
    hold on
    plot(values.sectionNumber, values.zGainMedian, "-", ...
        "Color", [0.10, 0.30, 0.70], "LineWidth", 1.5, ...
        "DisplayName", "median");
    plot(values.sectionNumber, values.zGainP99, ":", ...
        "Color", [0.45, 0.55, 0.75], "LineWidth", 1, ...
        "DisplayName", "99th percentile");
    yline(1, "k--", "DisplayName", "identity");
    xlabel("Physical section");
    ylabel("Reference/target gain");
    title(sprintf("ch%d %s: gain applied to non-reference layer", ...
        channel.id, channel.name));
    grid on
    legend("Location", "best");
end

sgtitle("Production z-illumination gain percentiles");
exportgraphics(fig, outputPath, "Resolution", 160);
close(fig);
end

function path = findPlane(manifest, sectionNumber, channelId, layer)
row = manifest.sectionNumber == sectionNumber & ...
    manifest.channelId == channelId & manifest.layer == layer;
if nnz(row) ~= 1
    error("stpt:ReconstructionQC", ...
        "Expected one final plane for section %d, layer %d, ch%d.", ...
        sectionNumber, layer, channelId);
end
path = manifest.filePath(row);
end

function limits = commonDisplayLimits(images)
values = cellfun(@(image) double(image(:)), images, ...
    "UniformOutput", false);
values = vertcat(values{:});
values = values(values > 0);
if isempty(values)
    limits = [0, 1];
else
    limits = prctile(values, [0.5, 99.8]);
    if limits(1) == limits(2)
        limits(2) = limits(1) + 1;
    end
end
end

function writeSummary( ...
        datasetIndex, cfg, manifest, qcSections, ...
        reconstructionWallSeconds, outputPath)
% Record production scope, output policy, storage, clipping, and timing.
geometry = datasetIndex.geometry;
sections = unique(manifest.sectionNumber, "stable");
compressedBytes = sum(manifest.outputBytes, "omitnan");
uncompressedBytes = sum( ...
    manifest.widthPixels .* manifest.heightPixels * 2, "omitnan");

fid = fopen(outputPath, "w");
if fid < 0
    error("stpt:WriteOutput", "Could not write %s.", outputPath);
end
fprintf(fid, "STPT production reconstruction completed\n");
fprintf(fid, "Sections: %d:%d (%d total)\n", ...
    sections(1), sections(end), numel(sections));
fprintf(fid, "Channels: %s\n", mat2str([datasetIndex.channels.id]));
fprintf(fid, "Layers/section: %d\n", geometry.layersPerSection);
fprintf(fid, "Final planes: %d\n", height(manifest));
fprintf(fid, "Missing raw TIFFs represented in index: %d\n", ...
    height(datasetIndex.missingTiles));
fprintf(fid, "Reconstructed planes with missing tiles: %d\n", ...
    nnz(manifest.missingTileCount > 0));
fprintf(fid, "Missing tile observations across output planes: %.0f\n", ...
    sum(manifest.missingTileCount, "omitnan"));
fprintf(fid, "Unsupported output pixels across output planes: %.0f\n", ...
    sum(manifest.uncoveredPixelCount, "omitnan"));
fprintf(fid, "Reconstruction workers: %d\n", ...
    min(cfg.execution.reconstructionWorkers, numel(sections)));
fprintf(fid, "Reconstruction wall time: %.1f seconds\n", ...
    reconstructionWallSeconds);
fprintf(fid, "Representative QC sections: %s\n", mat2str(qcSections));
fprintf(fid, "Crop [left right top bottom]: %s pixels\n", ...
    mat2str(geometry.cropPixels));
fprintf(fid, "Retained tile: %d x %d pixels\n", ...
    geometry.retainedTileSizePixels);
fprintf(fid, "Target step: %d x %d pixels\n", geometry.targetStepPixels);
fprintf(fid, "Stitched canvas: %d x %d pixels\n", ...
    geometry.nominalCanvasSizePixels);
if strcmpi(cfg.fusion.mode, "fijiBlend")
    fprintf(fid, "Fusion: Fiji-style normalized weighted blending; " + ...
        "alpha %.6g\n", cfg.fusion.blending.alpha);
else
    fprintf(fid, "Fusion: %s\n", string(cfg.fusion.mode));
end
fprintf(fid, "Z illumination: %s; reference layer %d; " + ...
    "filter-area fraction %.6g\n", string(cfg.zIllumination.method), ...
    cfg.zIllumination.referenceLayer, ...
    cfg.zIllumination.filterAreaFraction);
fprintf(fid, "Output: uint16 TIFF, lossless %s compression\n", ...
    upper(string(cfg.fusion.compression)));
fprintf(fid, "Compressed size: %.3f GiB\n", compressedBytes / 1024^3);
fprintf(fid, "Compressed/uncompressed ratio: %.4f\n", ...
    compressedBytes / uncompressedBytes);
fprintf(fid, "XY-corrected tile pixels below zero before fusion: %.0f\n", ...
    sum(manifest.clippedLowPixels, "omitnan"));
fprintf(fid, "XY-corrected tile pixels above uint16 before fusion: %.0f\n", ...
    sum(manifest.clippedHighPixels, "omitnan"));
fprintf(fid, "Planes changed by z illumination: %d\n", ...
    nnz(manifest.zIlluminationApplied));
% CSV round-tripping may represent this Boolean column as numeric 0/1.
correctedRows = manifest.zIlluminationApplied ~= 0;
if any(correctedRows)
    fprintf(fid, "Z gain median range: %.6g to %.6g\n", ...
        min(manifest.zGainMedian(correctedRows)), ...
        max(manifest.zGainMedian(correctedRows)));
    fprintf(fid, "Z gain 1st-99th percentile envelope: %.6g to %.6g\n", ...
        min(manifest.zGainP01(correctedRows)), ...
        max(manifest.zGainP99(correctedRows)));
end
fprintf(fid, "Z-corrected pixels above uint16 before casting: %.0f\n", ...
    sum(manifest.zClippedHighPixels, "omitnan"));
fprintf(fid, "Cumulative fusion task time: %.1f seconds\n", ...
    sum(manifest.fusionSeconds, "omitnan"));
fprintf(fid, "Cumulative z-illumination task time: %.1f seconds\n", ...
    sum(manifest.zCorrectionSeconds, "omitnan"));
fprintf(fid, "Cumulative LZW writing task time: %.1f seconds\n", ...
    sum(manifest.writeSeconds, "omitnan"));
fprintf(fid, "Raw TIFFs modified: no\n");
fprintf(fid, "Intermediate full-resolution TIFFs written: no\n");
fprintf(fid, "Downsampled reconstruction written: no\n");
fprintf(fid, "Completed: %s\n", string(datetime("now")));
fclose(fid);
end

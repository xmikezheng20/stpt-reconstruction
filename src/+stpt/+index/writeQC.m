function writeQC(datasetIndex, cfg, stageDir)
%WRITEQC Write human-readable Stage 1 tables, summaries, and plots.

% Write dataset-wide summaries first; these remain useful even without MATLAB.
stageDir = string(stageDir);
writetable(datasetIndex.sectionInventory, ...
    fullfile(stageDir, "section_inventory.csv"));
writetable(datasetIndex.missingTiles, ...
    fullfile(stageDir, "missing_tiles.csv"));
writeMetadataSummary(datasetIndex, cfg, ...
    fullfile(stageDir, "metadata_summary.txt"));

% Missing acquisition slots are always visualized, independent of the regular
% representative-section QC sample.
writeMissingTileQC(datasetIndex, fullfile(stageDir, "qc", "missing_tiles"));

% Emit a complete tile audit and two geometry checks for selected sections.
for sectionNumber = cfg.sampling.qcSections
    sectionPosition = find([datasetIndex.sections.number] == sectionNumber, 1);
    if isempty(sectionPosition)
        error("stpt:QCSection", ...
            "QC section %d is not present in the index.", sectionNumber);
    end

    section = datasetIndex.sections(sectionPosition);
    auditTable = makeAuditTable(datasetIndex, section);
    stem = sprintf("section_%03d", sectionNumber);
    writetable(auditTable, fullfile(stageDir, stem + "_tiles.csv"));

    plotTargetGrid(section.positions, sectionNumber, ...
        fullfile(stageDir, stem + "_target_grid.png"));
    plotTargetVsActual(section.positions, sectionNumber, ...
        fullfile(stageDir, stem + "_target_vs_actual.png"));
end

% Write this last so its presence means every requested QC artifact succeeded.
writeStageSummary(datasetIndex, cfg, ...
    fullfile(stageDir, "stage_summary.txt"));
end

function auditTable = makeAuditTable(datasetIndex, section)
% Start with the acquisition/position table, then add native file coordinates.
auditTable = section.positions;
nTiles = datasetIndex.geometry.tilesPerLayer;
nLayers = datasetIndex.geometry.layersPerSection;

for layer = 1:nLayers
    auditTable.(sprintf("layer%dNativeIndex", layer)) = ...
        section.nativeStartIndex + (layer - 1) * nTiles + ...
        auditTable.acquisitionIndex - 1;
end

% Record absolute source paths for every channel/layer combination. This CSV is
% the easiest line-by-line proof that logical coordinates resolve correctly.
for c = 1:numel(datasetIndex.channels)
    channelId = datasetIndex.channels(c).id;
    for layer = 1:nLayers
        paths = strings(height(auditTable), 1);
        for tile = 1:height(auditTable)
            paths(tile) = stpt.io.resolveTileFile(datasetIndex, section.number, ...
                layer, tile, channelId);
        end
        auditTable.(sprintf("ch%dLayer%dFile", channelId, layer)) = paths;
    end
end
end

function writeMetadataSummary(datasetIndex, cfg, outputPath)
% Summarize configured policy beside the raw Mosaic values and derived geometry.
metadata = datasetIndex.masterMosaic.parameters;
geometry = datasetIndex.geometry;
fid = fopen(outputPath, "w");
if fid < 0
    error("stpt:WriteOutput", "Could not write %s.", outputPath);
end

fprintf(fid, "STPT Stage 1 metadata summary\n");
fprintf(fid, "Experiment: %s\n", cfg.experiment.id);
fprintf(fid, "Raw root: %s\n\n", cfg.paths.rawRoot);

fprintf(fid, "Configured channels\n");
for channel = datasetIndex.channels'
    fprintf(fid, "  ch%d: %s -> %s\n", ...
        channel.id, channel.name, channel.root);
end
fprintf(fid, "  Mosaic channels field: %g (ch3 was not retained)\n\n", ...
    metadata.channels);

fprintf(fid, "Acquisition geometry\n");
fprintf(fid, "  Planned sections in metadata: %d\n", metadata.sections);
fprintf(fid, "  Processing sections: %d:%d (%d total)\n", ...
    cfg.processing.sections(1), cfg.processing.sections(end), ...
    numel(cfg.processing.sections));
fprintf(fid, "  Layers/section: %d\n", geometry.layersPerSection);
fprintf(fid, "  Grid: %d x %d tiles\n", geometry.gridSize);
fprintf(fid, "  Raw tile: %d x %d pixels\n", geometry.tileSizePixels);
fprintf(fid, "  Configured pixel size: %.6g x %.6g um/pixel\n", ...
    geometry.pixelSizeUm);
fprintf(fid, "  Mosaic xres/yres: %.6g x %.6g\n", ...
    metadata.xres, metadata.yres);
fprintf(fid, "%s\n", ...
    "  Resolution policy: configured 1 um/pixel is authoritative; " + ...
    "the legacy 0.875 values are retained as a documented discrepancy.");
fprintf(fid, "  Target step: %.6g x %.6g um = %.6g x %.6g pixels\n", ...
    geometry.targetStepUm, geometry.targetStepPixels);
fprintf(fid, "  Raw overlap: %.6g x %.6g pixels\n", ...
    geometry.rawOverlapPixels);
fprintf(fid, "  Crop [left right top bottom]: [%g %g %g %g] pixels\n", ...
    geometry.cropPixels);
fprintf(fid, "  Retained tile: %.6g x %.6g pixels\n", ...
    geometry.retainedTileSizePixels);
fprintf(fid, "  Post-crop overlap: %.6g x %.6g pixels\n", ...
    geometry.postCropOverlapPixels);
fprintf(fid, "  Nominal stitched canvas: %.6g x %.6g pixels\n\n", ...
    geometry.nominalCanvasSizePixels);

fprintf(fid, "Acquisition completeness\n");
fprintf(fid, "  Missing expected TIFFs: %d\n", ...
    height(datasetIndex.missingTiles));
fprintf(fid, "  Missing-tile table: missing_tiles.csv\n");
fprintf(fid, "  Missing-plane maps: qc/missing_tiles\n\n");

fclose(fid);
end

function writeStageSummary(datasetIndex, cfg, outputPath)
% Distill the pass criteria and dataset-wide positioning statistics.
inventory = datasetIndex.sectionInventory;
fid = fopen(outputPath, "w");
if fid < 0
    error("stpt:WriteOutput", "Could not write %s.", outputPath);
end

if isempty(datasetIndex.missingTiles)
    fprintf(fid, "Stage 1 completed: no expected TIFFs are missing\n");
else
    fprintf(fid, "Stage 1 completed with %d missing expected TIFF(s)\n", ...
        height(datasetIndex.missingTiles));
end
fprintf(fid, "Sections indexed: %d\n", height(inventory));
fprintf(fid, "Processing range: %d:%d\n", ...
    cfg.processing.sections(1), cfg.processing.sections(end));
fprintf(fid, "Positions per section: %d\n", unique(inventory.positionCount));
for channel = datasetIndex.channels'
    countField = sprintf("ch%dFileCount", channel.id);
    missingField = sprintf("ch%dMissingCount", channel.id);
    counts = inventory.(countField);
    fprintf(fid, "ch%d available TIFFs/section: %d to %d\n", ...
        channel.id, min(counts), max(counts));
    fprintf(fid, "ch%d missing expected TIFFs: %d\n", ...
        channel.id, sum(inventory.(missingField)));
end
fprintf(fid, "Representative QC sections: %s\n", ...
    mat2str(cfg.sampling.qcSections));
fprintf(fid, "Target/actual residual RMS x range: %.3f to %.3f um\n", ...
    min(inventory.targetResidualRmsXUm), ...
    max(inventory.targetResidualRmsXUm));
fprintf(fid, "Target/actual residual RMS y range: %.3f to %.3f um\n", ...
    min(inventory.targetResidualRmsYUm), ...
    max(inventory.targetResidualRmsYUm));
fprintf(fid, "Maximum target/actual residual: %.3f um\n", ...
    max(inventory.targetResidualMaxUm));
fprintf(fid, "Raw TIFFs modified: no\n");
fprintf(fid, "Completed: %s\n", string(datetime("now")));
fclose(fid);
end

function writeMissingTileQC(datasetIndex, outputDir)
% Draw one compact grid map for every channel/section/layer with missing data.
outputDir = string(outputDir);
if ~isfolder(outputDir)
    mkdir(outputDir);
end
missing = datasetIndex.missingTiles;
if isempty(missing)
    return
end

planes = unique(missing(:, ...
    ["sectionNumber", "channelId", "channelName", "layer"]), "rows");
for i = 1:height(planes)
    plane = planes(i, :);
    rows = missing.sectionNumber == plane.sectionNumber & ...
        missing.channelId == plane.channelId & missing.layer == plane.layer;
    planeMissing = missing(rows, :);
    outputPath = fullfile(outputDir, sprintf( ...
        "section_%03d_ch%02d_%s_layer_%02d.png", ...
        plane.sectionNumber, plane.channelId, plane.channelName, plane.layer));
    plotMissingTileMap(planeMissing, datasetIndex.geometry.gridSize, ...
        outputPath);
end
end

function plotMissingTileMap(missing, gridSize, outputPath)
% Show acquired grid slots in gray and missing slots in red with exact indices.
occupancy = ones(gridSize(2), gridSize(1));
linear = sub2ind(size(occupancy), missing.gridY, missing.gridX);
occupancy(linear) = 0;

fig = figure("Visible", "off", "Color", "w", ...
    "Position", [100, 100, 900, 700]);
imagesc(occupancy, [0, 1]);
axis image
set(gca, "YDir", "reverse", "XTick", 1:gridSize(1), ...
    "YTick", 1:gridSize(2));
xlabel("Grid x");
ylabel("Grid y");
colormap(gca, [0.90, 0.20, 0.15; 0.88, 0.88, 0.88]);
hold on
for i = 1:height(missing)
    text(missing.gridX(i), missing.gridY(i), sprintf( ...
        "a%d\nn%d", missing.acquisitionIndex(i), missing.nativeIndex(i)), ...
        "HorizontalAlignment", "center", "VerticalAlignment", "middle", ...
        "Color", "w", "FontWeight", "bold", "FontSize", 8);
end
title(sprintf("Section %03d | ch%d %s | layer %d | %d missing tile(s)", ...
    missing.sectionNumber(1), missing.channelId(1), ...
    missing.channelName(1), missing.layer(1), height(missing)));
subtitle("Red labels: acquisition index (a), native index (n)");
grid on
exportgraphics(fig, outputPath, "Resolution", 160);
close(fig);
end

function plotTargetGrid(positions, sectionNumber, outputPath)
% Confirm all target locations exist and are assigned a unique acquisition order.
fig = figure("Visible", "off", "Color", "w", ...
    "Position", [100, 100, 800, 650]);
scatter(positions.targetXUm, positions.targetYUm, 24, ...
    positions.acquisitionIndex, "filled");
axis equal tight
set(gca, "YDir", "reverse");
xlabel("Target x (um)");
ylabel("Target y (um)");
title(sprintf("Section %d: reconstructed target grid", sectionNumber));
colorScale = colorbar;
colorScale.Label.String = "Acquisition index";
grid on
exportgraphics(fig, outputPath, "Resolution", 150);
close(fig);
end

function plotTargetVsActual(positions, sectionNumber, outputPath)
% Compare the placement grid with measured stage positions after translation-only
% alignment, then show where residual positioning error is concentrated.
fig = figure("Visible", "off", "Color", "w", ...
    "Position", [100, 100, 1200, 520]);
tiledlayout(1, 2, "Padding", "compact", "TileSpacing", "compact");

nexttile
plot(positions.targetXUm, positions.targetYUm, ".", ...
    "MarkerSize", 12, "DisplayName", "target");
hold on
plot(positions.actualXAlignedUm, positions.actualYAlignedUm, ".", ...
    "MarkerSize", 9, "DisplayName", "actual, translation-aligned");
axis equal tight
set(gca, "YDir", "reverse");
xlabel("x (um)");
ylabel("y (um)");
title("Target and actual positions");
legend("Location", "best");
grid on

nexttile
residualMagnitude = hypot(positions.targetResidualXUm, ...
    positions.targetResidualYUm);
scatter(positions.targetXUm, positions.targetYUm, 28, ...
    residualMagnitude, "filled");
axis equal tight
set(gca, "YDir", "reverse");
xlabel("Target x (um)");
ylabel("Target y (um)");
title(sprintf("Residual magnitude: RMS %.2f um", ...
    sqrt(mean(residualMagnitude.^2))));
colorScale = colorbar;
colorScale.Label.String = "Residual magnitude (um)";
grid on

sgtitle(sprintf("Section %d: target-position QC", sectionNumber));
exportgraphics(fig, outputPath, "Resolution", 150);
close(fig);
end

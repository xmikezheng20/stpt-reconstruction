function writeQC(selection, stageDir)
%WRITEQC Write the compact tissue-Otsu selection checkpoint.

stageDir = string(stageDir);
qcDir = fullfile(stageDir, "qc");
mkdir(qcDir);

% Tables retain every tile decision and the compact section/parity counts.
writetable(selection.tiles, fullfile(stageDir, "tile_selection.csv"));
writetable(selection.summary, fullfile(stageDir, "selection_summary.csv"));

plotHistogram(selection, fullfile(qcDir, "log_mean_histogram.png"));
plotSelectionMaps(selection, fullfile(qcDir, "selection_maps.png"));
writeSummary(selection, fullfile(stageDir, "stage_summary.txt"));
end

function plotHistogram(selection, outputPath)
% Show the single fitted threshold on the complete training distribution.
fig = figure("Visible", "off", "Color", "w", ...
    "Position", [100, 100, 900, 600]);
histogram(selection.tiles.logCroppedMean, 100, ...
    "FaceColor", [0.25, 0.45, 0.70], "EdgeColor", "none");
hold on
xline(selection.thresholdLog, "--", ...
    sprintf("Otsu = %.3f (raw mean %.2f)", ...
    selection.thresholdLog, selection.thresholdRawEquivalent), ...
    "LineWidth", 1.5, "LabelVerticalAlignment", "middle");
xlabel("log(1 + cropped green tile mean)");
ylabel("Tile count");
title("Global green-tile tissue selection");
grid on
exportgraphics(fig, outputPath, "Resolution", 160);
close(fig);
end

function plotSelectionMaps(selection, outputPath)
% Confirm that selected tiles follow tissue rather than the acquisition floor.
sections = selection.qcSections;
nLayers = max(selection.tiles.layer);
fig = figure("Visible", "off", "Color", "w", ...
    "Position", [100, 100, 1000, 300 * numel(sections)]);
tiledlayout(numel(sections), nLayers, ...
    "Padding", "compact", "TileSpacing", "compact");

for sectionNumber = sections
    for layer = 1:nLayers
        nexttile
        rows = selection.tiles.sectionNumber == sectionNumber & ...
            selection.tiles.layer == layer;
        q = selection.tiles(rows, :);
        rejected = ~q.selectedForIllumination;
        scatter(q.gridX(rejected), q.gridY(rejected), 38, ...
            [0.75, 0.78, 0.82], "s", "filled");
        hold on
        scatter(q.gridX(~rejected), q.gridY(~rejected), 38, ...
            [0.20, 0.48, 0.72], "s", "filled");
        axis equal
        xlim([0.5, max(q.gridX) + 0.5]);
        ylim([0.5, max(q.gridY) + 0.5]);
        set(gca, "YDir", "reverse");
        xlabel("Grid x");
        ylabel("Grid y");
        title(sprintf("Section %d, layer %d: %d/%d selected", ...
            sectionNumber, layer, nnz(~rejected), height(q)));
        grid on
    end
end
sgtitle("Log-Otsu selection: rejected (gray), selected (blue)");
exportgraphics(fig, outputPath, "Resolution", 160);
close(fig);
end

function writeSummary(selection, outputPath)
% Record the checkpoint decision in a format readable without MATLAB.
selected = selection.tiles.selectedForIllumination;
fid = fopen(outputPath, "w");
if fid < 0
    error("stpt:WriteOutput", "Could not write %s.", outputPath);
end

fprintf(fid, "Tissue-Otsu selection checkpoint completed\n");
fprintf(fid, "Reference channel: ch%d\n", selection.referenceChannel);
fprintf(fid, "Training sections: %s\n", mat2str(selection.trainingSections));
fprintf(fid, "QC sections: %s\n", mat2str(selection.qcSections));
fprintf(fid, "Crop [left right top bottom]: %s pixels\n", ...
    mat2str(selection.cropPixels));
fprintf(fid, "Threshold on log(1 + cropped mean): %.9g\n", ...
    selection.thresholdLog);
fprintf(fid, "Equivalent cropped raw mean: %.9g\n", ...
    selection.thresholdRawEquivalent);
fprintf(fid, "Selected tiles: %d/%d (%.2f%%)\n", ...
    nnz(selected), numel(selected), 100 * mean(selected));
fprintf(fid, "Illumination template fitted: no\n");
fprintf(fid, "Raw TIFFs modified: no\n");
fprintf(fid, "Completed: %s\n", string(datetime("now")));
fclose(fid);
end

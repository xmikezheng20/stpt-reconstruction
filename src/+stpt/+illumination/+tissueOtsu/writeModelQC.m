function writeModelQC(audit, model, stageDir)
%WRITEMODELQC Write compact direct-pooling model diagnostics.

stageDir = string(stageDir);
qcDir = fullfile(stageDir, "qc");
mkdir(qcDir);

plotGainFields(model, fullfile(qcDir, "gain_fields.png"));
writeSummary(audit, model, fullfile(stageDir, "stage_summary.txt"));
end

function plotGainFields(model, outputPath)
% Display each distinct fitted field on one common scale.
nChannels = numel(model.channels);
nLayers = numel(model.channels(1).layers);
isPooled = strcmpi(model.rowMode, "pool");
allGains = [];
for c = 1:nChannels
    for layer = 1:nLayers
        allGains = [allGains; ...
            model.channels(c).layers(layer).gain.oddRows(:)]; %#ok<AGROW>
        if ~isPooled
            allGains = [allGains; ...
                model.channels(c).layers(layer).gain.evenRows(:)]; %#ok<AGROW>
        end
    end
end
colorLimits = double(prctile(allGains, [1, 99]));

fig = figure("Visible", "off", "Color", "w", ...
    "Position", [100, 100, 1600, 750]);
fieldsPerLayer = 2 - isPooled;
tiledlayout(nChannels, nLayers * fieldsPerLayer, ...
    "Padding", "compact", "TileSpacing", "compact");

for c = 1:nChannels
    for layer = 1:nLayers
        layerModel = model.channels(c).layers(layer);
        if isPooled
            rowFields = "pool";
        else
            rowFields = ["odd", "even"];
        end
        for rowField = rowFields
            nexttile
            if rowField == "even"
                gain = layerModel.gain.evenRows;
            else
                gain = layerModel.gain.oddRows;
            end
            imagesc(gain, colorLimits);
            axis image off
            colorbar
            title(sprintf("ch%d layer %d %s", ...
                model.channels(c).id, layer, rowField));
        end
    end
end
sgtitle(sprintf("Illumination gains: %s rows (common 1st-99th percentile scale)", ...
    model.rowMode));
exportgraphics(fig, outputPath, "Resolution", 160);
close(fig);
end

function writeSummary(audit, model, outputPath)
% Record the mathematical choices and pass quantities without requiring MATLAB.
fid = fopen(outputPath, "w");
if fid < 0
    error("stpt:WriteOutput", "Could not write %s.", outputPath);
end

fprintf(fid, "Tissue-Otsu illumination model completed\n");
fprintf(fid, "Training sections: %s\n", mat2str(model.trainingSections));
fprintf(fid, "QC sections: %s\n", mat2str(audit.qcSections));
fprintf(fid, "Selection source: %s\n", audit.selectionPath);
fprintf(fid, "Selection threshold log: %.9g\n", ...
    audit.selectionThresholdLog);
fprintf(fid, "Selection threshold raw equivalent: %.9g\n", ...
    audit.selectionThresholdRawEquivalent);
fprintf(fid, "Template trim: %.3g%%\n", ...
    model.methodDetails.templateTrimPercent);
fprintf(fid, "Row mode: %s\n", model.rowMode);
fprintf(fid, "Templates: direct pooling across sections; no section averages\n");
fprintf(fid, "Additive offset: zero\n");
fprintf(fid, "Model support: cropped %d-by-%d pixels\n", ...
    model.outputTileSizePixels(1), model.outputTileSizePixels(2));
fprintf(fid, "Maximum fitted gain: %.6g\n", max([ ...
    audit.templateSummary.oddGainMax; ...
    audit.templateSummary.evenGainMax]));
fprintf(fid, "Corrected TIFFs written: no\n");
fprintf(fid, "Raw TIFFs modified: no\n");
fprintf(fid, "Completed: %s\n", string(datetime("now")));
fclose(fid);
end

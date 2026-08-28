function [model, audit] = fit(datasetIndex, cfg, stageDir)
%FIT Fit and audit the standalone StitchIt-reference illumination model.
%
% This method preserves StitchIt's detector-floor rejection, row-parity split,
% and two-level trimmed means. It reads native TIFFs through the shared loader
% and returns the same standard offset-and-gain model as other algorithms.

stageDir = string(stageDir);
averageDir = fullfile(stageDir, "section_averages");
templateDir = fullfile(stageDir, "templates");
mkdir(averageDir);
mkdir(templateDir);

sections = cfg.illumination.trainingSections(:)';
referenceConfig = cfg.illumination.stitchitReference;
nSections = numel(sections);
nChannels = numel(datasetIndex.channels);
nLayers = datasetIndex.geometry.layersPerSection;
nCombinations = nSections * nChannels * nLayers;

statisticsParts = cell(nCombinations, 1);
summaryParts = cell(nCombinations, 1);
sectionAveragePaths = strings(nChannels, nLayers, nSections);
templates = cell(nChannels, nLayers);
templatePaths = strings(nChannels, nLayers);
record = 0;

fprintf("Method: %s\n", cfg.illumination.method);
fprintf("Processing %d training sections x %d channels x %d layers.\n", ...
    nSections, nChannels, nLayers);
fprintf("No corrected TIFFs are written.\n\n");

% Load one channel/layer stack at a time. All numerical estimation below is
% confined to this algorithm package; native file access remains shared.
for c = 1:nChannels
    channelId = datasetIndex.channels(c).id;
    for layer = 1:nLayers
        averagesForTemplate = cell(nSections, 1);

        for s = 1:nSections
            sectionNumber = sections(s);
            record = record + 1;
            fprintf("  section %03d, ch%d, layer %d (%d/%d)\n", ...
                sectionNumber, channelId, layer, record, nCombinations);

            [imageStack, tileStatistics] = stpt.io.loadTileStack( ...
                datasetIndex, sectionNumber, layer, channelId);
            [avData, tileStatistics, summary] = ...
                stpt.illumination.stitchitReference.estimateSectionAverage( ...
                imageStack, tileStatistics, referenceConfig);
            clear imageStack

            averagesForTemplate{s} = avData;
            statisticsParts{record} = tileStatistics;
            summaryParts{record} = summary;

            sectionDir = fullfile(averageDir, ...
                sprintf("section_%03d", sectionNumber));
            if ~isfolder(sectionDir)
                mkdir(sectionDir);
            end
            averagePath = fullfile(sectionDir, ...
                sprintf("ch%d_layer%d.mat", channelId, layer));
            save(averagePath, "avData");
            sectionAveragePaths(c, layer, s) = averagePath;
        end

        template = ...
            stpt.illumination.stitchitReference.collateSectionAverages( ...
            averagesForTemplate, referenceConfig);
        templates{c, layer} = template;
        templatePath = fullfile(templateDir, ...
            sprintf("ch%d_layer%d.mat", channelId, layer));
        save(templatePath, "template");
        templatePaths(c, layer) = templatePath;
    end
end

tileStatistics = vertcat(statisticsParts{:});
selectionSummary = struct2table(vertcat(summaryParts{:}));
model = stpt.illumination.buildModelFromTemplates(templates, datasetIndex, cfg);
templateSummary = stpt.illumination.summarizeModel(model);

writetable(tileStatistics, fullfile(stageDir, "tile_statistics.csv"));
writetable(selectionSummary, fullfile(stageDir, "selection_summary.csv"));
writetable(templateSummary, fullfile(stageDir, "template_summary.csv"));

audit = struct();
audit.created = string(datetime("now"));
audit.method = string(cfg.illumination.method);
audit.trainingSections = sections;
audit.qcSections = cfg.illumination.qcSections(:)';
audit.tileStatistics = tileStatistics;
audit.selectionSummary = selectionSummary;
audit.templateSummary = templateSummary;
audit.sectionAveragePaths = sectionAveragePaths;
audit.templates = templates;
audit.templatePaths = templatePaths;
audit.algorithmReference = struct( ...
    "project", "StitchIt", ...
    "commit", "383b9fbd5f0664bf232c897a87759d8da43b725c", ...
    "relationship", "source-level reference only; no runtime dependency");

stpt.illumination.stitchitReference.writeQC( ...
    audit, datasetIndex, cfg, stageDir);
writeStageSummary(audit, model, fullfile(stageDir, "stage_summary.txt"));
end

function writeStageSummary(audit, model, outputPath)
% Distill the reference checkpoint without requiring MATLAB to inspect it.
selection = audit.selectionSummary;
fid = fopen(outputPath, "w");
if fid < 0
    error("stpt:WriteOutput", "Could not write %s.", outputPath);
end

fprintf(fid, "Stage 2 illumination reference completed; inspect QC before acceptance\n");
fprintf(fid, "Method: %s\n", model.method);
fprintf(fid, "Training sections: %s\n", mat2str(model.trainingSections));
fprintf(fid, "QC sections: %s\n", mat2str(audit.qcSections));
fprintf(fid, "Configured tissue-reference channel: ch%d (unused by this method)\n", ...
    model.tissueReferenceChannel);
fprintf(fid, "Tile records: %d\n", height(audit.tileStatistics));
fprintf(fid, "Section/channel/layer combinations: %d\n", height(selection));
fprintf(fid, "Detector-floor threshold fallbacks: %d/%d\n", ...
    nnz(selection.thresholdFallback), height(selection));
fprintf(fid, "Tiles rejected at detector floor: %d/%d (%.2f%%)\n", ...
    sum(selection.floorRejectedCount), height(audit.tileStatistics), ...
    100 * sum(selection.floorRejectedCount) / height(audit.tileStatistics));
fprintf(fid, "Floor-retained is not a tissue classification\n");
fprintf(fid, "Model support: cropped %d-by-%d pixels\n", ...
    model.outputTileSizePixels(1), model.outputTileSizePixels(2));
fprintf(fid, "Corrected TIFFs written: no\n");
fprintf(fid, "StitchIt functions called directly: none\n");
fprintf(fid, "StitchIt source reference: %s\n", ...
    audit.algorithmReference.commit);
fprintf(fid, "Completed: %s\n", string(datetime("now")));
fclose(fid);
end

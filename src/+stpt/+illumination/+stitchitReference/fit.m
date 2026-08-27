function [model, audit] = fit(datasetIndex, cfg, stageDir)
%FIT Fit and audit the standalone StitchIt-reference illumination model.
%
% This method preserves StitchIt's detector-floor rejection, row-parity split,
% and two-level trimmed means. It reads native TIFFs through the shared loader
% and returns the same standard offset-and-gain model as future algorithms.

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
model = buildModel(templates, datasetIndex, cfg);
templateSummary = makeTemplateSummary(model);

writetable(tileStatistics, fullfile(stageDir, "tile_statistics.csv"));
writetable(selectionSummary, fullfile(stageDir, "selection_summary.csv"));
writetable(templateSummary, fullfile(stageDir, "template_summary.csv"));

audit = struct();
audit.schemaVersion = 1;
audit.created = string(datetime("now"));
audit.method = string(cfg.illumination.method);
audit.trainingSections = sections;
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

function model = buildModel(templates, datasetIndex, cfg)
% Convert raw reference templates into the shared cropped correction model.
model = struct();
model.schemaVersion = 1;
model.created = string(datetime("now"));
model.method = string(cfg.illumination.method);
model.rowMode = string(cfg.illumination.rowMode);
model.trainingSections = cfg.illumination.trainingSections(:)';
model.tissueReferenceChannel = cfg.illumination.tissueReferenceChannel;
model.cropPixels = cfg.preprocessing.cropPixels;
model.inputTileSizePixels = datasetIndex.geometry.tileSizePixels;
model.outputTileSizePixels = datasetIndex.geometry.retainedTileSizePixels;

nChannels = numel(datasetIndex.channels);
nLayers = datasetIndex.geometry.layersPerSection;
channels = repmat(struct("id", [], "name", "", "layers", struct([])), ...
    nChannels, 1);
for c = 1:nChannels
    channels(c).id = datasetIndex.channels(c).id;
    channels(c).name = datasetIndex.channels(c).name;
    layers = repmat(emptyLayerModel(), nLayers, 1);
    for layer = 1:nLayers
        template = templates{c, layer};
        [layers(layer).gain.oddRows, ...
            layers(layer).normalization.oddRows] = templateGain( ...
            template.oddRows, model.cropPixels);
        [layers(layer).gain.evenRows, ...
            layers(layer).normalization.evenRows] = templateGain( ...
            template.evenRows, model.cropPixels);
    end
    channels(c).layers = layers;
end
model.channels = channels;
end

function layer = emptyLayerModel()
% Reference correction has no additive offset; future methods may provide one.
layer = struct();
layer.offset = struct("oddRows", single(0), "evenRows", single(0));
layer.gain = struct("oddRows", single([]), "evenRows", single([]));
layer.normalization = struct("oddRows", single(nan), ...
    "evenRows", single(nan));
end

function [gain, normalization] = templateGain(template, cropPixels)
% Preserve StitchIt's gain on retained pixels without defining discarded edges.
template = single(template);
normalization = median(template(:));
cropped = template( ...
    cropPixels(3)+1:end-cropPixels(4), ...
    cropPixels(1)+1:end-cropPixels(2));
if ~isfinite(normalization) || normalization <= 0 || ...
        any(~isfinite(cropped(:))) || any(cropped(:) <= 0)
    error("stpt:IlluminationTemplate", ...
        "The reference template is invalid within cropped support.");
end
gain = normalization ./ cropped;
end

function summaryTable = makeTemplateSummary(model)
% Record the small set of values needed to audit correction magnitude.
nChannels = numel(model.channels);
nLayers = numel(model.channels(1).layers);
rows = cell(nChannels * nLayers, 1);
record = 0;

for c = 1:nChannels
    for layer = 1:nLayers
        record = record + 1;
        layerModel = model.channels(c).layers(layer);
        oddGain = layerModel.gain.oddRows;
        evenGain = layerModel.gain.evenRows;
        row = struct();
        row.channelId = model.channels(c).id;
        row.layer = layer;
        row.oddNormalization = layerModel.normalization.oddRows;
        row.evenNormalization = layerModel.normalization.evenRows;
        row.oddGainP01 = prctile(oddGain(:), 1);
        row.oddGainMedian = median(oddGain(:));
        row.oddGainP99 = prctile(oddGain(:), 99);
        row.evenGainP01 = prctile(evenGain(:), 1);
        row.evenGainMedian = median(evenGain(:));
        row.evenGainP99 = prctile(evenGain(:), 99);
        rows{record} = row;
    end
end
summaryTable = struct2table(vertcat(rows{:}));
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

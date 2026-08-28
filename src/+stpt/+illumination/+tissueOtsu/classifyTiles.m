function selection = classifyTiles(datasetIndex, cfg)
%CLASSIFYTILES Select tissue-bearing tiles with global green log-Otsu.
%
% One threshold is fitted from cropped tile means pooled across all configured
% training sections and both imaging layers. The resulting physical tile mask
% will be shared across channels when illumination templates are fitted.

validateInputs(datasetIndex, cfg);

sections = cfg.illumination.trainingSections(:)';
channelId = cfg.illumination.tissueReferenceChannel;
nLayers = datasetIndex.geometry.layersPerSection;
parts = cell(numel(sections) * nLayers, 1);
part = 0;

crop = cfg.preprocessing.cropPixels;
rowRange = crop(3)+1 : datasetIndex.geometry.tileSizePixels(2)-crop(4);
columnRange = crop(1)+1 : datasetIndex.geometry.tileSizePixels(1)-crop(2);

fprintf("Method: tissueOtsu\n");
fprintf("Measuring cropped tile means from ch%d across %d sections.\n", ...
    channelId, numel(sections));

% Load one section/layer at a time, calculate the statistic used by Otsu, and
% immediately release the image stack. Raw images are only read.
for sectionNumber = sections
    for layer = 1:nLayers
        part = part + 1;
        fprintf("  section %03d, layer %d (%d/%d)\n", ...
            sectionNumber, layer, part, numel(parts));

        [imageStack, tileStatistics] = stpt.io.loadTileStack( ...
            datasetIndex, sectionNumber, layer, channelId);
        croppedMean = squeeze(mean( ...
            imageStack(rowRange, columnRange, :), [1, 2], "double"));
        clear imageStack

        tileStatistics.croppedMean = croppedMean;
        tileStatistics.logCroppedMean = log1p(croppedMean);
        tileStatistics.gridParity = repmat("odd", height(tileStatistics), 1);
        tileStatistics.gridParity(mod(tileStatistics.gridY, 2) == 0) = "even";
        parts{part} = tileStatistics;
    end
end

% Binary Otsu is fitted once so early/late sections are interpreted using the
% complete training distribution rather than thresholded independently.
tiles = vertcat(parts{:});
thresholdLog = multithresh(tiles.logCroppedMean, 1);
thresholdRawEquivalent = expm1(thresholdLog);
tiles.selectedForIllumination = tiles.logCroppedMean > thresholdLog;

selection = struct();
selection.created = string(datetime("now"));
selection.method = "tissueOtsu";
selection.referenceChannel = channelId;
selection.trainingSections = sections;
selection.qcSections = cfg.illumination.qcSections(:)';
selection.cropPixels = crop;
selection.thresholdLog = thresholdLog;
selection.thresholdRawEquivalent = thresholdRawEquivalent;
selection.tiles = tiles;
selection.summary = summarizeSelection(tiles, sections, nLayers);
end

function summary = summarizeSelection(tiles, sections, nLayers)
% Count selected tiles for every section/layer/parity checkpoint cell.
parities = ["odd", "even"];
rows = cell(numel(sections) * nLayers * numel(parities), 1);
record = 0;

for sectionNumber = sections
    for layer = 1:nLayers
        for parity = parities
            record = record + 1;
            mask = tiles.sectionNumber == sectionNumber & ...
                tiles.layer == layer & tiles.gridParity == parity;
            row = struct();
            row.sectionNumber = sectionNumber;
            row.layer = layer;
            row.gridParity = parity;
            row.tileCount = nnz(mask);
            row.selectedCount = nnz(tiles.selectedForIllumination(mask));
            row.selectedFraction = row.selectedCount / row.tileCount;
            rows{record} = row;
        end
    end
end
summary = struct2table(vertcat(rows{:}));
end

function validateInputs(datasetIndex, cfg)
% Validate only the assumptions consumed by this selection method.
required = ["method", "tissueReferenceChannel", "trainingSections", ...
    "qcSections"];
for field = required
    if ~isfield(cfg.illumination, field)
        error("stpt:TissueOtsuConfig", ...
            "Missing cfg.illumination.%s.", field);
    end
end
if ~strcmpi(cfg.illumination.method, "tissueOtsu")
    error("stpt:TissueOtsuConfig", ...
        "Tissue selection requires cfg.illumination.method='tissueOtsu'.");
end
if ~ismember(cfg.illumination.tissueReferenceChannel, ...
        [datasetIndex.channels.id])
    error("stpt:TissueOtsuConfig", ...
        "The tissue-reference channel is absent from the dataset index.");
end
if any(~ismember(cfg.illumination.trainingSections, ...
        [datasetIndex.sections.number]))
    error("stpt:TissueOtsuConfig", ...
        "Training sections must be present in the dataset index.");
end
if any(~ismember(cfg.illumination.qcSections, ...
        cfg.illumination.trainingSections))
    error("stpt:TissueOtsuConfig", ...
        "QC sections must be part of the illumination training sample.");
end
if ~isequal(cfg.preprocessing.cropPixels, datasetIndex.geometry.cropPixels)
    error("stpt:TissueOtsuConfig", ...
        "Configured crop does not match the completed dataset index.");
end
end

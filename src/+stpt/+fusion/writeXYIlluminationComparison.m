function comparisonManifest = writeXYIlluminationComparison( ...
        datasetIndex, model, cfg, sectionNumber, stageDir)
%WRITEXYILLUMINATIONCOMPARISON Reconstruct matched correction-on/off planes.
%
% Both variants are independently fused through processPlanes. Canonical TIFFs
% are neither copied nor reused, so the comparison directory is self-contained
% and both alternatives have exactly the same computational interface.

comparisonDir = string(fullfile(stageDir, "qc", "comparisons", ...
    "xy_illumination"));
completionPath = fullfile(comparisonDir, "comparison_complete.txt");
combinedManifestPath = fullfile(comparisonDir, "comparison_manifest.csv");

if isfile(completionPath) && isfile(combinedManifestPath)
    comparisonManifest = readtable( ...
        combinedManifestPath, "TextType", "string");
    fprintf("XY illumination comparison already complete: %s\n", ...
        comparisonDir);
    return
end
if ~isfolder(comparisonDir)
    mkdir(comparisonDir);
end

fprintf("\nXY illumination comparison: section %d, all channels/layers.\n", ...
    sectionNumber);

% Reconstruct both alternatives rather than sourcing the corrected variant
% from canonical output. The only difference is the model supplied here.
onDir = string(fullfile(comparisonDir, "illumination_on"));
onManifest = stpt.fusion.processPlanes( ...
    datasetIndex, model, cfg, sectionNumber, onDir, ...
    fullfile(onDir, "fusion_manifest.csv"));

identity = stpt.illumination.identityModel(model);
stpt.illumination.validateModel(identity, datasetIndex);
offDir = string(fullfile(comparisonDir, "illumination_off"));
offManifest = stpt.fusion.processPlanes( ...
    datasetIndex, identity, cfg, sectionNumber, offDir, ...
    fullfile(offDir, "fusion_manifest.csv"));

onManifest.variant = repmat("illumination_on", height(onManifest), 1);
offManifest.variant = repmat("illumination_off", height(offManifest), 1);
comparisonManifest = [onManifest; offManifest];
writetable(comparisonManifest, combinedManifestPath);

plotComparison(datasetIndex, cfg, sectionNumber, comparisonManifest, ...
    fullfile(comparisonDir, "xy_illumination_all_planes.png"));
writeSummary(datasetIndex, model, cfg, sectionNumber, comparisonManifest, ...
    fullfile(comparisonDir, "comparison_summary.txt"));
writelines("XY illumination comparison completed " + ...
    string(datetime("now")), completionPath);

fprintf("XY illumination comparison complete: %d full-resolution planes.\n", ...
    height(comparisonManifest));
fprintf("Outputs: %s\n\n", comparisonDir);
end

function plotComparison( ...
        datasetIndex, cfg, sectionNumber, manifest, outputPath)
% Show matched off/on previews and their signed difference for every plane.
nChannels = numel(datasetIndex.channels);
nLayers = datasetIndex.geometry.layersPerSection;
nRows = nChannels * nLayers;
fig = figure("Visible", "off", "Color", "w", ...
    "Position", [100, 100, 1650, 420 * nRows]);
tiledlayout(nRows, 3, "Padding", "compact", "TileSpacing", "compact");

for c = 1:nChannels
    channel = datasetIndex.channels(c);
    for layer = 1:nLayers
        offPath = findPlane(manifest, "illumination_off", ...
            sectionNumber, channel.id, layer);
        onPath = findPlane(manifest, "illumination_on", ...
            sectionNumber, channel.id, layer);
        off = loadPreview(offPath, cfg.fusion.qcPreviewScale);
        on = loadPreview(onPath, cfg.fusion.qcPreviewScale);
        limits = commonDisplayLimits(off, on);
        difference = single(on) - single(off);
        differenceLimit = robustDifferenceLimit(difference, off, on);
        label = string(sprintf("ch%d %s, layer %d", ...
            channel.id, channel.name, layer));

        nexttile
        imagesc(off);
        axis image off
        clim(limits);
        colormap(gca, gray(256));
        title(label + ": illumination off");

        nexttile
        imagesc(on);
        axis image off
        clim(limits);
        colormap(gca, gray(256));
        title(label + ": illumination on");

        nexttile
        imagesc(difference);
        axis image off
        clim([-differenceLimit, differenceLimit]);
        colormap(gca, blueWhiteRed());
        colorbar
        title(label + ": on minus off");
    end
end

sgtitle(sprintf("Section %d: matched XY illumination comparison", ...
    sectionNumber));
exportgraphics(fig, outputPath, "Resolution", 160);
close(fig);
end

function path = findPlane(manifest, variant, sectionNumber, channelId, layer)
row = manifest.variant == variant & ...
    manifest.sectionNumber == sectionNumber & ...
    manifest.channelId == channelId & manifest.layer == layer;
if nnz(row) ~= 1
    error("stpt:FusionQC", ...
        "Expected one %s plane for section %d, layer %d, ch%d.", ...
        variant, sectionNumber, layer, channelId);
end
path = manifest.filePath(row);
end

function preview = loadPreview(path, scale)
image = imread(path);
preview = imresize(image, scale, "bilinear");
end

function limits = commonDisplayLimits(off, on)
values = double([off(:); on(:)]);
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

function limit = robustDifferenceLimit(difference, off, on)
foreground = off > 0 | on > 0;
values = abs(double(difference(foreground)));
if isempty(values)
    limit = 1;
else
    limit = prctile(values, 99.5);
    if limit == 0
        limit = 1;
    end
end
end

function map = blueWhiteRed()
% Compact diverging map for signed differences.
n = 128;
ramp = linspace(0, 1, n)';
map = [ramp, ramp, ones(n, 1); ...
       ones(n, 1), flipud(ramp), flipud(ramp)];
end

function writeSummary( ...
        datasetIndex, model, cfg, sectionNumber, manifest, outputPath)
fid = fopen(outputPath, "w");
if fid < 0
    error("stpt:WriteOutput", "Could not write %s.", outputPath);
end
fprintf(fid, "XY illumination correction comparison completed\n");
fprintf(fid, "Section: %d\n", sectionNumber);
fprintf(fid, "Channels: %s\n", mat2str([datasetIndex.channels.id]));
fprintf(fid, "Layers: %d\n", datasetIndex.geometry.layersPerSection);
fprintf(fid, "Illumination on model: %s\n", string(model.method));
fprintf(fid, "Illumination off model: identity (D=0, G=1)\n");
fprintf(fid, "Both variants independently reconstructed: yes\n");
fprintf(fid, "Canonical fusion TIFFs copied or reused: no\n");
fprintf(fid, "Crop [left right top bottom]: %s pixels\n", ...
    mat2str(cfg.preprocessing.cropPixels));
fprintf(fid, "Fusion: reverse-acquisition overwrite; earlier tiles win\n");
fprintf(fid, "Output: uint16 TIFF, lossless %s compression\n", ...
    upper(string(cfg.fusion.compression)));
fprintf(fid, "Full-resolution comparison planes: %d\n", height(manifest));
fprintf(fid, "Total comparison size: %.3f GiB\n", ...
    sum(manifest.outputBytes, "omitnan") / 1024^3);
fprintf(fid, "Completed: %s\n", string(datetime("now")));
fclose(fid);
end

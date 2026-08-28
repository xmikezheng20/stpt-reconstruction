function comparisonManifest = writeReconstructionStepComparison( ...
        datasetIndex, model, cfg, sectionNumber, stageDir)
%WRITERECONSTRUCTIONSTEPCOMPARISON Reconstruct three matched pilot variants.
%
% The ordered comparison isolates the effect of XY illumination correction and
% then Fiji-style blending. Every variant is independently reconstructed through
% processPlanes; canonical TIFFs are neither copied nor reused.

comparisonDir = string(fullfile(stageDir, "qc", "comparisons", ...
    "reconstruction_steps"));
combinedManifestPath = fullfile(comparisonDir, "comparison_manifest.csv");
mkdir(comparisonDir);

fprintf("\nReconstruction-step comparison: section %d, all channels/layers.\n", ...
    sectionNumber);

identity = stpt.illumination.identityModel(model);
stpt.illumination.validateModel(identity, datasetIndex);

steps = comparisonSteps(model, identity, cfg);
manifests = cell(numel(steps), 1);
for stepNumber = 1:numel(steps)
    step = steps(stepNumber);
    stepDir = string(fullfile(comparisonDir, step.name));
    manifest = stpt.fusion.processPlanes( ...
        datasetIndex, step.model, step.cfg, sectionNumber, stepDir);
    manifest.stepNumber = repmat(stepNumber, height(manifest), 1);
    manifest.variant = repmat(step.name, height(manifest), 1);
    manifest.illumination = repmat(step.illumination, height(manifest), 1);
    manifest.fusionMode = repmat(step.cfg.fusion.mode, height(manifest), 1);
    manifests{stepNumber} = manifest;
end

comparisonManifest = vertcat(manifests{:});
stpt.writeTableAtomic(comparisonManifest, combinedManifestPath);

plotOverview(datasetIndex, cfg, sectionNumber, comparisonManifest, steps, ...
    fullfile(comparisonDir, "reconstruction_steps_all_planes.png"));
plotCentralJunctions( ...
    datasetIndex, sectionNumber, comparisonManifest, steps, ...
    fullfile(comparisonDir, "reconstruction_steps_central_junctions.png"));
writeSummary(datasetIndex, model, cfg, sectionNumber, comparisonManifest, ...
    fullfile(comparisonDir, "comparison_summary.txt"));

fprintf("Reconstruction-step comparison complete: %d full-resolution planes.\n", ...
    height(comparisonManifest));
fprintf("Outputs: %s\n\n", comparisonDir);
end

function steps = comparisonSteps(model, identity, cfg)
% Define the three scientific conditions without changing shared interfaces.
overwriteCfg = cfg;
overwriteCfg.fusion.mode = "overwrite";
blendCfg = cfg;
blendCfg.fusion.mode = "fijiBlend";

steps = struct( ...
    "name", { ...
        "01_no_correction_no_blend", ...
        "02_xy_correction_no_blend", ...
        "03_xy_correction_fiji_blend"}, ...
    "label", { ...
        "1. no correction / no blend", ...
        "2. XY correction / no blend", ...
        "3. XY correction / Fiji blend"}, ...
    "illumination", {"identity", string(model.method), string(model.method)}, ...
    "model", {identity, model, model}, ...
    "cfg", {overwriteCfg, overwriteCfg, blendCfg});
end

function plotOverview( ...
        datasetIndex, cfg, sectionNumber, manifest, steps, outputPath)
% Show the complete reconstructed field for every channel/layer and step.
nChannels = numel(datasetIndex.channels);
nLayers = datasetIndex.geometry.layersPerSection;
nRows = nChannels * nLayers;
fig = figure("Visible", "off", "Color", "w", ...
    "Position", [100, 100, 1650, 420 * nRows]);
tiledlayout(nRows, numel(steps), ...
    "Padding", "compact", "TileSpacing", "compact");

for c = 1:nChannels
    channel = datasetIndex.channels(c);
    for layer = 1:nLayers
        previews = cell(numel(steps), 1);
        for stepNumber = 1:numel(steps)
            path = findPlane(manifest, steps(stepNumber).name, ...
                sectionNumber, channel.id, layer);
            previews{stepNumber} = loadPreview( ...
                path, cfg.fusion.qcPreviewScale);
        end
        limits = commonDisplayLimits(previews);
        planeLabel = string(sprintf("ch%d %s, layer %d", ...
            channel.id, channel.name, layer));

        for stepNumber = 1:numel(steps)
            nexttile
            imagesc(previews{stepNumber});
            axis image off
            clim(limits);
            colormap(gca, gray(256));
            title(planeLabel + newline + steps(stepNumber).label);
        end
    end
end

sgtitle(sprintf("Section %d: ordered reconstruction comparison", ...
    sectionNumber));
exportgraphics(fig, outputPath, "Resolution", 160);
close(fig);
end

function plotCentralJunctions( ...
        datasetIndex, sectionNumber, manifest, steps, outputPath)
% Show one native-resolution four-tile junction where blending is visible.
geometry = stpt.fusion.computeGeometry(datasetIndex, sectionNumber);
insetSize = 1200;
junctionX = 1 + floor(datasetIndex.geometry.gridSize(1) / 2) * ...
    geometry.targetStepPixels(1);
junctionY = 1 + floor(datasetIndex.geometry.gridSize(2) / 2) * ...
    geometry.targetStepPixels(2);
xStart = max(1, junctionX - insetSize / 2);
yStart = max(1, junctionY - insetSize / 2);
xEnd = min(geometry.canvasSizePixels(1), xStart + insetSize - 1);
yEnd = min(geometry.canvasSizePixels(2), yStart + insetSize - 1);

nChannels = numel(datasetIndex.channels);
nLayers = datasetIndex.geometry.layersPerSection;
nRows = nChannels * nLayers;
fig = figure("Visible", "off", "Color", "w", ...
    "Position", [100, 100, 1650, 420 * nRows]);
tiledlayout(nRows, numel(steps), ...
    "Padding", "compact", "TileSpacing", "compact");

for c = 1:nChannels
    channel = datasetIndex.channels(c);
    for layer = 1:nLayers
        insets = cell(numel(steps), 1);
        for stepNumber = 1:numel(steps)
            path = findPlane(manifest, steps(stepNumber).name, ...
                sectionNumber, channel.id, layer);
            insets{stepNumber} = imread(path, "PixelRegion", ...
                {[yStart, yEnd], [xStart, xEnd]});
        end
        limits = commonDisplayLimits(insets);
        planeLabel = string(sprintf("ch%d %s, layer %d", ...
            channel.id, channel.name, layer));

        for stepNumber = 1:numel(steps)
            nexttile
            imagesc(insets{stepNumber});
            axis image off
            clim(limits);
            colormap(gca, gray(256));
            title(planeLabel + newline + steps(stepNumber).label);
        end
    end
end

sgtitle(sprintf("Section %d: native-resolution central tile junction", ...
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
        datasetIndex, model, cfg, sectionNumber, manifest, outputPath)
fid = fopen(outputPath, "w");
if fid < 0
    error("stpt:WriteOutput", "Could not write %s.", outputPath);
end
fprintf(fid, "Ordered reconstruction-step comparison completed\n");
fprintf(fid, "Section: %d\n", sectionNumber);
fprintf(fid, "Channels: %s\n", mat2str([datasetIndex.channels.id]));
fprintf(fid, "Layers: %d\n", datasetIndex.geometry.layersPerSection);
fprintf(fid, "Step 1: identity illumination; overwrite fusion\n");
fprintf(fid, "Step 2: %s illumination; overwrite fusion\n", ...
    string(model.method));
fprintf(fid, "Step 3: %s illumination; Fiji-style weighted fusion\n", ...
    string(model.method));
fprintf(fid, "Fiji weight: ((dx+1)*(dy+1)+1)^alpha\n");
fprintf(fid, "Fiji alpha: %.6g\n", cfg.fusion.blending.alpha);
fprintf(fid, "Placement: recorded target step; normalized weighted sum\n");
fprintf(fid, "All variants independently reconstructed: yes\n");
fprintf(fid, "Canonical fusion TIFFs copied or reused: no\n");
fprintf(fid, "Crop [left right top bottom]: %s pixels\n", ...
    mat2str(cfg.preprocessing.cropPixels));
fprintf(fid, "Output: uint16 TIFF, lossless %s compression\n", ...
    upper(string(cfg.fusion.compression)));
fprintf(fid, "Full-resolution comparison planes: %d\n", height(manifest));
fprintf(fid, "Total comparison size: %.3f GiB\n", ...
    sum(manifest.outputBytes, "omitnan") / 1024^3);
fprintf(fid, "Completed: %s\n", string(datetime("now")));
fclose(fid);
end

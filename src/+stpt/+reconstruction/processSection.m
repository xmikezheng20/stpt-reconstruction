function [manifest, diagnostics] = processSection( ...
        datasetIndex, model, cfg, sectionNumber, channelDirectories, ...
        collectDiagnostics)
%PROCESSSECTION Reconstruct every channel and optical layer in one section.
%
% Fusion first produces one uint16 mosaic per layer. Z illumination then acts
% on the complete layer group before final TIFFs are published. This function
% carries fusion support masks into z correction, owns no stage lifecycle or
% parallel policy, and is safe to run as one task.

nLayers = datasetIndex.geometry.layersPerSection;
nChannels = numel(datasetIndex.channels);
nPlanes = nLayers * nChannels;
rows = repmat(emptyManifestRow(), nPlanes, 1);
if collectDiagnostics
    diagnostics = repmat(emptyDiagnostic(), nChannels, 1);
else
    diagnostics = struct([]);
end

sectionStarted = tic;
fprintf("  section %03d: starting\n", sectionNumber);

% Placement geometry is shared by every channel and layer in this section.
geometry = stpt.fusion.computeGeometry(datasetIndex, sectionNumber);
rowNumber = 0;
for c = 1:nChannels
    channel = datasetIndex.channels(c);
    planes = cell(1, nLayers);
    supportMasks = cell(1, nLayers);
    fusionAudit = cell(1, nLayers);

    % No uncorrected TIFF intermediate is written. Both layers remain in
    % memory until their section/channel-level z correction is complete.
    for layer = 1:nLayers
        fprintf("    section %03d, ch%d (%s), layer %d: fusing\n", ...
            sectionNumber, channel.id, channel.name, layer);
        [planes{layer}, fusionAudit{layer}, supportMasks{layer}] = ...
            stpt.fusion.fusePlane(datasetIndex, model, cfg, ...
            sectionNumber, layer, channel.id, geometry);
    end

    if collectDiagnostics
        [planes, zAudit, zDiagnostics] = ...
            stpt.zillumination.apply(planes, cfg, supportMasks);
        diagnostics(c).sectionNumber = sectionNumber;
        diagnostics(c).channelId = channel.id;
        diagnostics(c).channelName = string(channel.name);
        diagnostics(c).zIllumination = zDiagnostics;
    else
        [planes, zAudit] = ...
            stpt.zillumination.apply(planes, cfg, supportMasks);
    end

    % Numerical Z failures are explicit identity decisions, not stage errors.
    % Report them with section/channel context while retaining details in the
    % manifest for dataset-wide review.
    for layer = 1:nLayers
        if ~zAudit(layer).applied && isZFallback(zAudit(layer).reason)
            fprintf("    section %03d, ch%d (%s), layer %d: " + ...
                "z identity fallback (%s)\n", sectionNumber, ...
                channel.id, channel.name, layer, zAudit(layer).reason);
        end
    end

    % Publish only final planes. Each path belongs to this section alone.
    for layer = 1:nLayers
        rowNumber = rowNumber + 1;
        outputPath = fullfile(channelDirectories(c), ...
            sprintf("section_%03d_%02d.tif", sectionNumber, layer));
        writeStarted = tic;
        stpt.reconstruction.writePlane( ...
            planes{layer}, outputPath, cfg.fusion.compression);
        writeSeconds = toc(writeStarted);

        fileInfo = dir(outputPath);
        rows(rowNumber) = buildManifestRow( ...
            fusionAudit{layer}, zAudit(layer), channel, ...
            model.channels(c).layers(layer), model.method, outputPath, ...
            fileInfo.bytes, cfg, writeSeconds);
        fprintf("      wrote layer %d: %.1f MiB LZW TIFF in %.1f s\n", ...
            layer, fileInfo.bytes / 1024^2, writeSeconds);
    end
end

manifest = struct2table(rows);
fprintf("  section %03d: complete in %.1f s\n", ...
    sectionNumber, toc(sectionStarted));
end

function row = emptyManifestRow()
row = struct("sectionNumber", nan, "layer", nan, "channelId", nan, ...
    "channelName", "", "filePath", "", ...
    "widthPixels", nan, "heightPixels", nan, "compression", "lzw", ...
    "outputBytes", nan, "fusionSeconds", nan, "writeSeconds", nan, ...
    "totalSeconds", nan, ...
    "expectedTileCount", nan, "presentTileCount", nan, ...
    "missingTileCount", nan, "uncoveredPixelCount", nan, ...
    "xyIlluminationMethod", "", "xyIlluminationApplied", false, ...
    "xyIlluminationReason", "", ...
    "correctedMinimum", nan, "correctedMaximum", nan, ...
    "clippedLowPixels", nan, "clippedHighPixels", nan, ...
    "zIlluminationMethod", "", "zIlluminationApplied", false, ...
    "zIlluminationReason", "", ...
    "zReferenceLayer", nan, "preZMean", nan, "postZMean", nan, ...
    "zGainP01", nan, "zGainMedian", nan, "zGainP99", nan, ...
    "zEstimationHeightPixels", nan, "zEstimationWidthPixels", nan, ...
    "zGaussianSigmaPixels", nan, "zClippedHighPixels", nan, ...
    "zCorrectionSeconds", nan);
end

function row = buildManifestRow( ...
        fusionAudit, zAudit, channel, illuminationLayer, ...
        illuminationMethod, path, outputBytes, cfg, writeSeconds)
% Combine the independent fusion and z-correction audits for one final plane.
row = emptyManifestRow();
row.sectionNumber = fusionAudit.sectionNumber;
row.layer = fusionAudit.layer;
row.channelId = fusionAudit.channelId;
row.channelName = string(channel.name);
row.filePath = string(path);
info = imfinfo(path);
row.widthPixels = info.Width;
row.heightPixels = info.Height;
row.compression = lower(string(cfg.fusion.compression));
row.outputBytes = outputBytes;
row.fusionSeconds = fusionAudit.fusionSeconds;
row.writeSeconds = writeSeconds;
row.totalSeconds = fusionAudit.fusionSeconds + ...
    zAudit.correctionSeconds + writeSeconds;
row.expectedTileCount = fusionAudit.expectedTileCount;
row.presentTileCount = fusionAudit.presentTileCount;
row.missingTileCount = fusionAudit.missingTileCount;
row.uncoveredPixelCount = fusionAudit.uncoveredPixelCount;
row.xyIlluminationMethod = string(illuminationMethod);
row.xyIlluminationApplied = illuminationLayer.correctionApplied;
row.xyIlluminationReason = string(illuminationLayer.correctionReason);
row.correctedMinimum = fusionAudit.correctedMinimum;
row.correctedMaximum = fusionAudit.correctedMaximum;
row.clippedLowPixels = fusionAudit.clippedLowPixels;
row.clippedHighPixels = fusionAudit.clippedHighPixels;
row.zIlluminationMethod = string(zAudit.method);
row.zIlluminationApplied = zAudit.applied;
row.zIlluminationReason = string(zAudit.reason);
row.zReferenceLayer = zAudit.referenceLayer;
row.preZMean = zAudit.preMean;
row.postZMean = zAudit.postMean;
row.zGainP01 = zAudit.gainP01;
row.zGainMedian = zAudit.gainMedian;
row.zGainP99 = zAudit.gainP99;
row.zEstimationHeightPixels = zAudit.estimationHeightPixels;
row.zEstimationWidthPixels = zAudit.estimationWidthPixels;
row.zGaussianSigmaPixels = zAudit.gaussianSigmaPixels;
row.zClippedHighPixels = zAudit.clippedHighPixels;
row.zCorrectionSeconds = zAudit.correctionSeconds;
end

function tf = isZFallback(reason)
% Reference, disabled, and one-layer identities are expected pipeline modes.
tf = ~ismember(string(reason), ...
    ["", "referenceLayer", "disabled", "singleLayer"]);
end

function value = emptyDiagnostic()
value = struct("sectionNumber", nan, "channelId", nan, ...
    "channelName", "", "zIllumination", struct());
end

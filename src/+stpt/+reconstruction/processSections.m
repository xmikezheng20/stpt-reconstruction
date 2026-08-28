function [manifest, diagnostics] = processSections( ...
        datasetIndex, model, cfg, sections, outputRoot)
%PROCESSSECTIONS Reconstruct complete section/channel optical-layer groups.
%
% Fusion produces one uint16 mosaic per layer. Z illumination is then corrected
% across the layers of that physical section and channel before any final TIFF
% is published. Pilot, comparison, and future production runs share this worker.

if isfolder(outputRoot)
    error("stpt:ReconstructionOutput", ...
        "Reconstruction output already exists; start the stage clean: %s", ...
        outputRoot);
end
mkdir(outputRoot);

sections = sections(:)';
nLayers = datasetIndex.geometry.layersPerSection;
nChannels = numel(datasetIndex.channels);
nPlanes = numel(sections) * nLayers * nChannels;
nSectionChannels = numel(sections) * nChannels;
rows = repmat(emptyManifestRow(), nPlanes, 1);
collectDiagnostics = nargout > 1;
if collectDiagnostics
    diagnostics = repmat(emptyDiagnostic(), nSectionChannels, 1);
else
    diagnostics = struct([]);
end
rowNumber = 0;
diagnosticNumber = 0;

channelDirectories = strings(nChannels, 1);
for c = 1:nChannels
    channel = datasetIndex.channels(c);
    channelDirectories(c) = string(fullfile(outputRoot, ...
        sprintf("ch%02d_%s", channel.id, channel.name)));
    mkdir(channelDirectories(c));
end

fprintf("Reconstruction: %d sections x %d layers x %d channels = %d planes.\n", ...
    numel(sections), nLayers, nChannels, nPlanes);
fprintf("Fusion: %s; z illumination: %s.\n", ...
    cfg.fusion.mode, cfg.zIllumination.method);
fprintf("Output: %s\n", outputRoot);

for sectionNumber = sections
    for c = 1:nChannels
        channel = datasetIndex.channels(c);
        planes = cell(1, nLayers);
        fusionAudit = cell(1, nLayers);

        % Fuse every optical layer before applying the section/channel-level
        % z correction. No uncorrected TIFF intermediate is written.
        for layer = 1:nLayers
            fprintf("  section %03d, ch%d (%s), layer %d: fusing\n", ...
                sectionNumber, channel.id, channel.name, layer);
            [planes{layer}, fusionAudit{layer}] = stpt.fusion.fusePlane( ...
                datasetIndex, model, cfg, sectionNumber, layer, channel.id);
        end

        [planes, zAudit, zDiagnostics] = ...
            stpt.zillumination.apply(planes, cfg);
        if collectDiagnostics
            diagnosticNumber = diagnosticNumber + 1;
            diagnostics(diagnosticNumber).sectionNumber = sectionNumber;
            diagnostics(diagnosticNumber).channelId = channel.id;
            diagnostics(diagnosticNumber).channelName = string(channel.name);
            diagnostics(diagnosticNumber).zIllumination = zDiagnostics;
        end

        % Publish only the final planes and record one complete manifest row for
        % every section/layer/channel coordinate.
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
                fusionAudit{layer}, zAudit(layer), channel, outputPath, ...
                fileInfo.bytes, cfg, writeSeconds);
            fprintf("    [%d/%d] wrote layer %d: %.1f MiB LZW TIFF %.1f s\n", ...
                rowNumber, nPlanes, layer, ...
                fileInfo.bytes / 1024^2, writeSeconds);
        end
    end
end

manifest = struct2table(rows);
validateManifest(manifest, nPlanes);
end

function row = emptyManifestRow()
row = struct("sectionNumber", nan, "layer", nan, "channelId", nan, ...
    "channelName", "", "filePath", "", ...
    "widthPixels", nan, "heightPixels", nan, "compression", "lzw", ...
    "outputBytes", nan, "fusionSeconds", nan, "writeSeconds", nan, ...
    "totalSeconds", nan, ...
    "correctedMinimum", nan, "correctedMaximum", nan, ...
    "clippedLowPixels", nan, "clippedHighPixels", nan, ...
    "zIlluminationMethod", "", "zIlluminationApplied", false, ...
    "zReferenceLayer", nan, "preZMean", nan, "postZMean", nan, ...
    "zGainP01", nan, "zGainMedian", nan, "zGainP99", nan, ...
    "zEstimationHeightPixels", nan, "zEstimationWidthPixels", nan, ...
    "zGaussianSigmaPixels", nan, ...
    "zClippedLowPixels", nan, "zClippedHighPixels", nan, ...
    "zCorrectionSeconds", nan);
end

function row = buildManifestRow( ...
        fusionAudit, zAudit, channel, path, outputBytes, cfg, writeSeconds)
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
row.correctedMinimum = fusionAudit.correctedMinimum;
row.correctedMaximum = fusionAudit.correctedMaximum;
row.clippedLowPixels = fusionAudit.clippedLowPixels;
row.clippedHighPixels = fusionAudit.clippedHighPixels;
row.zIlluminationMethod = string(zAudit.method);
row.zIlluminationApplied = zAudit.applied;
row.zReferenceLayer = zAudit.referenceLayer;
row.preZMean = zAudit.preMean;
row.postZMean = zAudit.postMean;
row.zGainP01 = zAudit.gainP01;
row.zGainMedian = zAudit.gainMedian;
row.zGainP99 = zAudit.gainP99;
row.zEstimationHeightPixels = zAudit.estimationHeightPixels;
row.zEstimationWidthPixels = zAudit.estimationWidthPixels;
row.zGaussianSigmaPixels = zAudit.gaussianSigmaPixels;
row.zClippedLowPixels = zAudit.clippedLowPixels;
row.zClippedHighPixels = zAudit.clippedHighPixels;
row.zCorrectionSeconds = zAudit.correctionSeconds;
end

function validateManifest(manifest, expectedPlanes)
% A successful call publishes exactly one existing file per requested plane.
keyNames = ["sectionNumber", "layer", "channelId"];
keys = unique(manifest(:, keyNames), "rows");
if height(manifest) ~= expectedPlanes || height(keys) ~= expectedPlanes || ...
        ~all(isfile(manifest.filePath))
    error("stpt:ReconstructionOutput", ...
        "Reconstruction did not produce one file for every requested plane.");
end
end

function value = emptyDiagnostic()
value = struct("sectionNumber", nan, "channelId", nan, ...
    "channelName", "", "zIllumination", struct());
end

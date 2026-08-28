function manifest = processPlanes( ...
        datasetIndex, model, cfg, sections, planeRoot)
%PROCESSPLANES Reconstruct every requested plane into a new output tree.
%
% Pilot, production, and QC alternatives call this same fresh-run interface.
% Stage lifecycle is owned by the master runner; this function never resumes or
% reuses an existing plane.

if isfolder(planeRoot)
    error("stpt:FusionOutput", ...
        "Plane output root already exists; start the stage clean: %s", ...
        planeRoot);
end
mkdir(planeRoot);

sections = sections(:)';
nLayers = datasetIndex.geometry.layersPerSection;
nChannels = numel(datasetIndex.channels);
nPlanes = numel(sections) * nLayers * nChannels;
rows = repmat(emptyManifestRow(), nPlanes, 1);
rowNumber = 0;

fprintf("Fusion (%s): %d sections x %d layers x %d channels = %d planes.\n", ...
    cfg.fusion.mode, numel(sections), nLayers, nChannels, nPlanes);
fprintf("Fusion output: %s\n", planeRoot);

for sectionNumber = sections
    for c = 1:nChannels
        channel = datasetIndex.channels(c);
        channelDir = fullfile(planeRoot, ...
            sprintf("ch%02d_%s", channel.id, channel.name));
        mkdir(channelDir);

        for layer = 1:nLayers
            rowNumber = rowNumber + 1;
            outputPath = fullfile(channelDir, ...
                sprintf("section_%03d_%02d.tif", sectionNumber, layer));
            fprintf("  [%d/%d] section %03d, layer %d, ch%d (%s)\n", ...
                rowNumber, nPlanes, sectionNumber, layer, ...
                channel.id, channel.name);

            planeStarted = tic;
            [stitched, audit] = stpt.fusion.fusePlane( ...
                datasetIndex, model, cfg, sectionNumber, layer, channel.id);
            writeStarted = tic;
            stpt.fusion.writePlane( ...
                stitched, outputPath, cfg.fusion.compression);
            writeSeconds = toc(writeStarted);
            totalSeconds = toc(planeStarted);

            fileInfo = dir(outputPath);
            rows(rowNumber) = buildManifestRow( ...
                audit, channel, outputPath, fileInfo.bytes, cfg, ...
                writeSeconds, totalSeconds);
            fprintf("    fused %.1f s; wrote %.1f MiB LZW TIFF %.1f s.\n", ...
                audit.fusionSeconds, fileInfo.bytes / 1024^2, writeSeconds);
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
    "clippedLowPixels", nan, "clippedHighPixels", nan);
end

function row = buildManifestRow( ...
        audit, channel, path, outputBytes, cfg, writeSeconds, totalSeconds)
% Record the image contract and scientific audit immediately after writing.
row = emptyManifestRow();
row.sectionNumber = audit.sectionNumber;
row.layer = audit.layer;
row.channelId = audit.channelId;
row.channelName = string(channel.name);
row.filePath = string(path);
info = imfinfo(path);
row.widthPixels = info.Width;
row.heightPixels = info.Height;
row.compression = lower(string(cfg.fusion.compression));
row.outputBytes = outputBytes;
row.fusionSeconds = audit.fusionSeconds;
row.writeSeconds = writeSeconds;
row.totalSeconds = totalSeconds;
row.correctedMinimum = audit.correctedMinimum;
row.correctedMaximum = audit.correctedMaximum;
row.clippedLowPixels = audit.clippedLowPixels;
row.clippedHighPixels = audit.clippedHighPixels;
end

function validateManifest(manifest, expectedPlanes)
% A successful call must publish exactly one existing file per requested plane.
keyNames = ["sectionNumber", "layer", "channelId"];
keys = unique(manifest(:, keyNames), "rows");
if height(manifest) ~= expectedPlanes || height(keys) ~= expectedPlanes || ...
        ~all(isfile(manifest.filePath))
    error("stpt:FusionOutput", ...
        "Reconstruction did not produce one file for every requested plane.");
end
end

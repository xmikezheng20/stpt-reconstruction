function manifest = processPlanes( ...
        datasetIndex, model, cfg, sections, planeRoot, manifestPath)
%PROCESSPLANES Reconstruct fused planes for any section list and output root.
%
% Canonical production and QC alternatives call this same interface. Their
% models and output roots differ; tile processing, fusion, and writing do not.

sections = sections(:)';
nLayers = datasetIndex.geometry.layersPerSection;
nChannels = numel(datasetIndex.channels);
nPlanes = numel(sections) * nLayers * nChannels;
rows = repmat(emptyManifestRow(), nPlanes, 1);
rowNumber = 0;
if isfile(manifestPath)
    previousManifest = readtable(manifestPath, "TextType", "string");
else
    previousManifest = table();
end

fprintf("Fusion (%s): %d sections x %d layers x %d channels = %d planes.\n", ...
    cfg.fusion.mode, numel(sections), nLayers, nChannels, nPlanes);
fprintf("Fusion output: %s\n", planeRoot);

for sectionNumber = sections
    for c = 1:nChannels
        channel = datasetIndex.channels(c);
        channelDir = fullfile(planeRoot, ...
            sprintf("ch%02d_%s", channel.id, channel.name));
        if ~isfolder(channelDir)
            mkdir(channelDir);
        end

        for layer = 1:nLayers
            rowNumber = rowNumber + 1;
            outputPath = fullfile(channelDir, ...
                sprintf("section_%03d_%02d.tif", sectionNumber, layer));
            fprintf("  [%d/%d] section %03d, layer %d, ch%d (%s)\n", ...
                rowNumber, nPlanes, sectionNumber, layer, ...
                channel.id, channel.name);

            if isfile(outputPath)
                validateExistingPlane(outputPath, datasetIndex.geometry);
                rows(rowNumber) = manifestRowForExisting( ...
                    sectionNumber, layer, channel, outputPath, ...
                    previousManifest);
                fprintf("    valid output exists; reusing it.\n");
                continue
            end

            planeStarted = tic;
            [stitched, audit] = stpt.fusion.fusePlane( ...
                datasetIndex, model, cfg, sectionNumber, layer, channel.id);
            writeStarted = tic;
            stpt.fusion.writePlane( ...
                stitched, outputPath, cfg.fusion.compression);
            writeSeconds = toc(writeStarted);
            totalSeconds = toc(planeStarted);
            fileInfo = dir(outputPath);
            rows(rowNumber) = manifestRowForNew( ...
                audit, channel, outputPath, fileInfo.bytes, cfg, ...
                writeSeconds, totalSeconds);
            fprintf("    fused %.1f s; wrote %.1f MiB LZW TIFF %.1f s.\n", ...
                audit.fusionSeconds, fileInfo.bytes / 1024^2, writeSeconds);
        end
    end
end

manifest = struct2table(rows);
writetable(manifest, manifestPath);
end

function validateExistingPlane(path, geometry)
% Existing filenames are trusted only after their basic image contract passes.
info = imfinfo(path);
expected = geometry.nominalCanvasSizePixels;
if numel(info) ~= 1 || info.Width ~= expected(1) || ...
        info.Height ~= expected(2) || info.BitDepth ~= 16
    error("stpt:FusionOutput", ...
        "Existing fused plane has the wrong image format: %s", path);
end
end

function row = emptyManifestRow()
row = struct("sectionNumber", nan, "layer", nan, "channelId", nan, ...
    "channelName", "", "filePath", "", "status", "", ...
    "widthPixels", nan, "heightPixels", nan, "compression", "lzw", ...
    "outputBytes", nan, "fusionSeconds", nan, "writeSeconds", nan, ...
    "totalSeconds", nan, ...
    "correctedMinimum", nan, "correctedMaximum", nan, ...
    "clippedLowPixels", nan, "clippedHighPixels", nan);
end

function row = manifestRowForNew( ...
        audit, channel, path, outputBytes, cfg, writeSeconds, totalSeconds)
row = emptyManifestRow();
row.sectionNumber = audit.sectionNumber;
row.layer = audit.layer;
row.channelId = audit.channelId;
row.channelName = string(channel.name);
row.filePath = string(path);
row.status = "written";
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

function row = manifestRowForExisting( ...
        sectionNumber, layer, channel, path, previousManifest)
% Preserve the original scientific audit when a completed plane is reused.
row = emptyManifestRow();
fields = string(fieldnames(row));
if ~isempty(previousManifest) && all(ismember( ...
        fields, string(previousManifest.Properties.VariableNames)))
    previous = previousManifest.sectionNumber == sectionNumber & ...
        previousManifest.layer == layer & ...
        previousManifest.channelId == channel.id;
    if nnz(previous) == 1
        savedRow = table2struct(previousManifest(previous, :));
        for field = fields'
            row.(field) = savedRow.(field);
        end
    end
end
row.sectionNumber = sectionNumber;
row.layer = layer;
row.channelId = channel.id;
row.channelName = string(channel.name);
row.filePath = string(path);
row.status = "reused";
info = imfinfo(path);
fileInfo = dir(path);
row.widthPixels = info.Width;
row.heightPixels = info.Height;
row.outputBytes = fileInfo.bytes;
end

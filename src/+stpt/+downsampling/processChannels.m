function manifest = processChannels( ...
        reconstructionManifest, datasetIndex, cfg, stageDir)
%PROCESSCHANNELS Downsample each reconstructed channel as one ordered volume.

volumeDir = string(fullfile(stageDir, "volumes"));
qcDir = string(fullfile(stageDir, "qc"));
mkdir(volumeDir);
mkdir(qcDir);

nChannels = numel(datasetIndex.channels);
rows = repmat(emptyManifestRow(), nChannels, 1);
sections = cfg.processing.sections;
nLayers = datasetIndex.geometry.layersPerSection;

for c = 1:nChannels
    channel = datasetIndex.channels(c);
    [inputFiles, orderedRows] = stpt.downsampling.buildPlaneList( ...
        reconstructionManifest, channel.id, sections, nLayers);

    fprintf("\nChannel %d (%s): %d ordered final planes.\n", ...
        channel.id, channel.name, numel(inputFiles));
    [volume, resamplingAudit] = stpt.resampling.resampleVolume( ...
        inputFiles, cfg.downsampling.inputVoxelSizeUm, ...
        cfg.downsampling.outputVoxelSizeUm);

    outputName = sprintf("%s_ch%02d_%s_%s.tif", ...
        cfg.experiment.dataPrefix, channel.id, channel.name, ...
        voxelToken(cfg.downsampling.outputVoxelSizeUm));
    outputPath = string(fullfile(volumeDir, outputName));
    writeAudit = stpt.downsampling.writeVolume( ...
        volume, outputPath, cfg.downsampling.compression);

    qcPath = fullfile(qcDir, ...
        sprintf("ch%02d_%s_orthogonal_sections.png", ...
        channel.id, channel.name));
    stpt.downsampling.writeQC(volume, channel, ...
        resamplingAudit.realizedVoxelSizeUm, qcPath);

    rows(c) = buildManifestRow(channel, orderedRows, outputPath, ...
        resamplingAudit, writeAudit, cfg.downsampling.compression);
    fprintf("Channel %d complete: [%d %d %d] [z y x], %.1f MiB, %.1f s.\n", ...
        channel.id, resamplingAudit.outputSizePixels, ...
        writeAudit.outputBytes / 1024^2, rows(c).totalSeconds);
    clear volume
end

manifest = struct2table(rows);
if ~all(isfile(manifest.outputPath))
    error("stpt:DownsamplingOutput", ...
        "The Stage 4 manifest contains a missing output volume.");
end
end

function row = emptyManifestRow()
row = struct( ...
    "channelId", nan, "channelName", "", ...
    "firstSection", nan, "lastSection", nan, ...
    "layersPerSection", nan, "inputPlaneCount", nan, ...
    "inputZPixels", nan, "inputYPixels", nan, "inputXPixels", nan, ...
    "outputZPixels", nan, "outputYPixels", nan, "outputXPixels", nan, ...
    "inputVoxelZUm", nan, "inputVoxelYUm", nan, "inputVoxelXUm", nan, ...
    "requestedVoxelZUm", nan, "requestedVoxelYUm", nan, ...
    "requestedVoxelXUm", nan, ...
    "realizedVoxelZUm", nan, "realizedVoxelYUm", nan, ...
    "realizedVoxelXUm", nan, ...
    "interpolation", "bicubic", "antialiasing", true, ...
    "outputClass", "uint16", "compression", "lzw", ...
    "outputPath", "", "outputBytes", nan, ...
    "resampledMinimum", nan, "resampledMaximum", nan, ...
    "clippedLowPixels", nan, "clippedHighPixels", nan, ...
    "xySeconds", nan, "zSeconds", nan, "writeSeconds", nan, ...
    "totalSeconds", nan);
end

function row = buildManifestRow( ...
        channel, orderedRows, outputPath, resampling, writing, compression)
row = emptyManifestRow();
row.channelId = channel.id;
row.channelName = string(channel.name);
row.firstSection = orderedRows.sectionNumber(1);
row.lastSection = orderedRows.sectionNumber(end);
row.layersPerSection = numel(unique(orderedRows.layer));
row.inputPlaneCount = height(orderedRows);
row.inputZPixels = resampling.inputSizePixels(1);
row.inputYPixels = resampling.inputSizePixels(2);
row.inputXPixels = resampling.inputSizePixels(3);
row.outputZPixels = resampling.outputSizePixels(1);
row.outputYPixels = resampling.outputSizePixels(2);
row.outputXPixels = resampling.outputSizePixels(3);
row.inputVoxelZUm = resampling.inputVoxelSizeUm(1);
row.inputVoxelYUm = resampling.inputVoxelSizeUm(2);
row.inputVoxelXUm = resampling.inputVoxelSizeUm(3);
row.requestedVoxelZUm = resampling.requestedVoxelSizeUm(1);
row.requestedVoxelYUm = resampling.requestedVoxelSizeUm(2);
row.requestedVoxelXUm = resampling.requestedVoxelSizeUm(3);
row.realizedVoxelZUm = resampling.realizedVoxelSizeUm(1);
row.realizedVoxelYUm = resampling.realizedVoxelSizeUm(2);
row.realizedVoxelXUm = resampling.realizedVoxelSizeUm(3);
row.interpolation = resampling.interpolation;
row.antialiasing = resampling.antialiasing;
row.compression = lower(string(compression));
row.outputPath = outputPath;
row.outputBytes = writing.outputBytes;
row.resampledMinimum = writing.resampledMinimum;
row.resampledMaximum = writing.resampledMaximum;
row.clippedLowPixels = writing.clippedLowPixels;
row.clippedHighPixels = writing.clippedHighPixels;
row.xySeconds = resampling.xySeconds;
row.zSeconds = resampling.zSeconds;
row.writeSeconds = writing.writeSeconds;
row.totalSeconds = resampling.xySeconds + ...
    resampling.zSeconds + writing.writeSeconds;
end

function token = voxelToken(voxelSizeUm)
% Keep isotropic names compact while preserving non-isotropic configurations.
if all(abs(voxelSizeUm - voxelSizeUm(1)) < 1e-12)
    token = numberToken(voxelSizeUm(1)) + "um";
else
    token = "z" + numberToken(voxelSizeUm(1)) + ...
        "_y" + numberToken(voxelSizeUm(2)) + ...
        "_x" + numberToken(voxelSizeUm(3)) + "um";
end
end

function token = numberToken(value)
token = replace(string(sprintf("%.6g", value)), ".", "p");
end

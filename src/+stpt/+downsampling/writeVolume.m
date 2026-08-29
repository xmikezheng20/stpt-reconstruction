function audit = writeVolume(volume, outputPath, compression)
%WRITEVOLUME Atomically write one uint16 multipage TIFF volume.
%
% The single-precision resampled volume is rounded and saturated only here.
% An incomplete partial TIFF remains inside the disposable Stage 4 directory;
% the final path appears only after every page and header has been validated.

outputPath = string(outputPath);
compression = lower(string(compression));
nPlanes = size(volume, 3);
if numel(volume) * 2 >= 2^32
    error("stpt:DownsamplingOutput", ...
        "The requested uint16 volume exceeds the classic TIFF size limit.");
end

[folder, stem, extension] = fileparts(outputPath);
partialPath = fullfile(folder, stem + ".partial" + extension);
writeStarted = tic;
clippedLowPixels = 0;
clippedHighPixels = 0;
resampledMinimum = inf;
resampledMaximum = -inf;

for z = 1:nPlanes
    plane = volume(:, :, z);
    clippedLowPixels = clippedLowPixels + nnz(plane < 0);
    clippedHighPixels = clippedHighPixels + nnz(plane > 65535);
    resampledMinimum = min(resampledMinimum, min(plane, [], "all"));
    resampledMaximum = max(resampledMaximum, max(plane, [], "all"));
    plane = uint16(min(max(round(plane), 0), 65535));

    if z == 1
        imwrite(plane, partialPath, "tif", "Compression", compression);
    else
        imwrite(plane, partialPath, "tif", "WriteMode", "append", ...
            "Compression", compression);
    end
end

% Validate the complete page contract before publishing the final path.
info = imfinfo(partialPath);
height = size(volume, 1);
width = size(volume, 2);
if numel(info) ~= nPlanes || ...
        any([info.Height] ~= height) || any([info.Width] ~= width) || ...
        any([info.BitDepth] ~= 16) || ...
        ~all(strcmpi(string({info.Compression}), compression))
    error("stpt:DownsamplingOutput", ...
        "The completed multipage TIFF does not match the output contract.");
end
movefile(partialPath, outputPath);

fileInfo = dir(outputPath);
audit = struct();
audit.outputBytes = fileInfo.bytes;
audit.writeSeconds = toc(writeStarted);
audit.resampledMinimum = double(resampledMinimum);
audit.resampledMaximum = double(resampledMaximum);
audit.clippedLowPixels = clippedLowPixels;
audit.clippedHighPixels = clippedHighPixels;
end

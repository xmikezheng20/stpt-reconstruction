function [volume, audit] = resampleVolume( ...
        inputFiles, inputVoxelSizeUm, outputVoxelSizeUm)
%RESAMPLEVOLUME Resample an ordered TIFF series in XY first and z second.
%
% INPUTFILES must already be in increasing physical z order. Voxel vectors and
% audit sizes use [z, y, x] order; the returned MATLAB array uses [y, x, z].
% Both passes use bicubic interpolation with antialiasing. The intermediate
% volume is single precision so interpolation is not quantized to uint16.

inputFiles = string(inputFiles(:));
inputVoxelSizeUm = double(inputVoxelSizeUm(:)');
outputVoxelSizeUm = double(outputVoxelSizeUm(:)');
validateInputs(inputFiles, inputVoxelSizeUm, outputVoxelSizeUm);

% The N*spacing convention matches StitchIt's z-size calculation. Rounding
% gives the nearest integer lattice, so the realized spacing may differ very
% slightly from the requested value and is recorded explicitly in the audit.
firstImage = imread(inputFiles(1));
if ~ismatrix(firstImage)
    error("stpt:ResamplingInput", "Input TIFFs must be grayscale images.");
end
inputSizePixels = [numel(inputFiles), size(firstImage, 1), size(firstImage, 2)];
outputSizePixels = max(1, round( ...
    inputSizePixels .* inputVoxelSizeUm ./ outputVoxelSizeUm));
realizedVoxelSizeUm = ...
    inputSizePixels .* inputVoxelSizeUm ./ outputSizePixels;

fprintf("Resampling %d planes: [%d %d %d] -> [%d %d %d] pixels [z y x].\n", ...
    inputSizePixels(1), inputSizePixels, outputSizePixels);
fprintf("Voxel size: requested [%g %g %g], realized [%.6g %.6g %.6g] um.\n", ...
    outputVoxelSizeUm, realizedVoxelSizeUm);

% Downsample each native XY plane and retain the full z series in RAM. Only
% one large reconstructed TIFF is decoded at a time.
xyStarted = tic;
volume = zeros(outputSizePixels(2), outputSizePixels(3), ...
    inputSizePixels(1), "single");
xyUnchanged = isequal(outputSizePixels(2:3), inputSizePixels(2:3));
for z = 1:inputSizePixels(1)
    if z == 1
        image = single(firstImage);
        clear firstImage
    else
        image = single(imread(inputFiles(z)));
    end
    if ~isequal(size(image), inputSizePixels(2:3))
        error("stpt:ResamplingInput", ...
            "Input TIFF dimensions differ at plane %d: %s", z, inputFiles(z));
    end
    if xyUnchanged
        volume(:, :, z) = image;
    else
        volume(:, :, z) = imresize(image, outputSizePixels(2:3), ...
            "bicubic", "Antialiasing", true);
    end
    logProgress("XY", z, inputSizePixels(1));
end
clear image
xySeconds = toc(xyStarted);

% Resample z through YZ slices, preserving the already reduced y dimension.
% This is the same separable XY-then-z organization used by StitchIt.
zStarted = tic;
if outputSizePixels(1) ~= inputSizePixels(1)
    zVolume = zeros(outputSizePixels(2), outputSizePixels(3), ...
        outputSizePixels(1), "single");
    for x = 1:outputSizePixels(3)
        yzSlice = squeeze(volume(:, x, :));
        zVolume(:, x, :) = imresize(yzSlice, ...
            [outputSizePixels(2), outputSizePixels(1)], ...
            "bicubic", "Antialiasing", true);
        logProgress("z", x, outputSizePixels(3));
    end
    volume = zVolume;
else
    fprintf("z: input and output spacing resolve to the same plane count; " + ...
        "no z interpolation needed.\n");
end
zSeconds = toc(zStarted);

audit = struct();
audit.inputSizePixels = inputSizePixels;
audit.outputSizePixels = outputSizePixels;
audit.inputVoxelSizeUm = inputVoxelSizeUm;
audit.requestedVoxelSizeUm = outputVoxelSizeUm;
audit.realizedVoxelSizeUm = realizedVoxelSizeUm;
audit.interpolation = "bicubic";
audit.antialiasing = true;
audit.xySeconds = xySeconds;
audit.zSeconds = zSeconds;
end

function validateInputs(inputFiles, inputVoxelSizeUm, outputVoxelSizeUm)
if isempty(inputFiles) || ~all(isfile(inputFiles))
    error("stpt:ResamplingInput", ...
        "inputFiles must be a nonempty list of existing TIFFs.");
end
if numel(inputVoxelSizeUm) ~= 3 || numel(outputVoxelSizeUm) ~= 3 || ...
        any(~isfinite(inputVoxelSizeUm)) || ...
        any(~isfinite(outputVoxelSizeUm)) || ...
        any(inputVoxelSizeUm <= 0) || any(outputVoxelSizeUm <= 0)
    error("stpt:ResamplingVoxelSize", ...
        "Voxel sizes must be positive [z, y, x] vectors.");
end
if any(outputVoxelSizeUm < inputVoxelSizeUm)
    error("stpt:ResamplingVoxelSize", ...
        "This resampler supports identity sampling or downsampling only.");
end
end

function logProgress(label, completed, total)
interval = max(1, ceil(total / 10));
if completed == 1 || completed == total || mod(completed, interval) == 0
    fprintf("  %s: %d/%d\n", label, completed, total);
end
end

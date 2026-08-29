function testDownsampling()
%TESTDOWNSAMPLING Exercise ordering, size, interpolation, and TIFF contracts.

addpath(fullfile(fileparts(fileparts(mfilename("fullpath"))), "src"));
testRoot = string(tempname);
mkdir(testRoot);
cleanup = onCleanup(@() rmdir(testRoot, "s"));

% Identity sampling preserves values and the explicit [y, x, z] array order.
identityFiles = strings(3, 1);
expected = zeros(7, 9, 3, "uint16");
for z = 1:3
    expected(:, :, z) = uint16(reshape(1:63, 7, 9) + 100 * z);
    identityFiles(z) = fullfile(testRoot, sprintf("identity_%02d.tif", z));
    imwrite(expected(:, :, z), identityFiles(z));
end
[identityVolume, identityAudit] = stpt.resampling.resampleVolume( ...
    identityFiles, [2, 1, 1], [2, 1, 1]);
assert(isequal(identityVolume, single(expected)));
assert(isequal(identityAudit.outputSizePixels, [3, 7, 9]));

% A uniform field remains uniform through non-integer XY and z reductions.
constantFiles = strings(5, 1);
for z = 1:5
    constantFiles(z) = fullfile(testRoot, sprintf("constant_%02d.tif", z));
    imwrite(repmat(uint16(1234), 11, 13), constantFiles(z));
end
[constantVolume, constantAudit] = stpt.resampling.resampleVolume( ...
    constantFiles, [3, 1, 1], [4, 2.5, 2]);
assert(isequal(constantAudit.outputSizePixels, [4, 4, 7]));
assert(max(abs(constantVolume(:) - 1234)) < 1e-3);
assert(isequal(constantAudit.realizedVoxelSizeUm, [3.75, 2.75, 13/7]));

% A z gradient remains ordered after the non-integer z interpolation.
gradientFiles = strings(5, 1);
for z = 1:5
    gradientFiles(z) = fullfile(testRoot, sprintf("gradient_%02d.tif", z));
    imwrite(repmat(uint16(100 * z), 11, 13), gradientFiles(z));
end
gradientVolume = stpt.resampling.resampleVolume( ...
    gradientFiles, [3, 1, 1], [4, 2.5, 2]);
zMeans = squeeze(mean(gradientVolume, [1, 2]));
assert(all(diff(zMeans) > 0));

% The STPT adapter sorts section first and optical layer second.
adapterManifest = table([2; 1; 2; 1], [2; 1; 1; 2], ones(4, 1), ...
    identityFiles([1; 2; 3; 1]), ...
    'VariableNames', {'sectionNumber', 'layer', 'channelId', 'filePath'});
[~, ordered] = stpt.downsampling.buildPlaneList( ...
    adapterManifest, 1, 1:2, 2);
assert(isequal(ordered.sectionNumber, [1; 1; 2; 2]));
assert(isequal(ordered.layer, [1; 2; 1; 2]));

% Final quantization occurs once, with explicit rounding and saturation.
writeInput = single(cat(3, [-2.2, 1.6; 65534.6, 65540], ...
    [0, 10; 20, 30]));
outputPath = fullfile(testRoot, "written.tif");
writeAudit = stpt.downsampling.writeVolume(writeInput, outputPath, "lzw");
assert(writeAudit.clippedLowPixels == 1);
assert(writeAudit.clippedHighPixels == 1);
assert(isequal(imread(outputPath, 1), ...
    uint16([0, 2; 65535, 65535])));
assert(isequal(imread(outputPath, 2), uint16([0, 10; 20, 30])));
info = imfinfo(outputPath);
assert(numel(info) == 2 && all(strcmpi({info.Compression}, "LZW")));

% The channel worker assembles the final manifest, volume, summary, and QC.
stageDir = fullfile(testRoot, "stage");
mkdir(stageDir);
datasetIndex.channels = struct("id", 1, "name", "test");
datasetIndex.geometry.layersPerSection = 2;
cfg.experiment.dataPrefix = "synthetic";
cfg.processing.sections = 1:2;
cfg.downsampling.inputVoxelSizeUm = [2, 1, 1];
cfg.downsampling.outputVoxelSizeUm = [2, 2, 2];
cfg.downsampling.compression = "lzw";
channelManifest = stpt.downsampling.processChannels( ...
    adapterManifest, datasetIndex, cfg, stageDir);
assert(height(channelManifest) == 1);
assert(isequal([channelManifest.outputZPixels, ...
    channelManifest.outputYPixels, channelManifest.outputXPixels], [4, 4, 5]));
assert(isfile(channelManifest.outputPath));
assert(numel(imfinfo(channelManifest.outputPath)) == 4);
assert(isfile(fullfile(stageDir, "qc", ...
    "ch01_test_orthogonal_sections.png")));
summaryPath = fullfile(stageDir, "summary.txt");
stpt.downsampling.writeSummary(channelManifest, summaryPath);
assert(isfile(summaryPath));

fprintf("testDownsampling: PASS\n");
end

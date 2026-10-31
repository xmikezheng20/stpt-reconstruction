function testLocalTissueRatio()
%TESTLOCALTISSUERATIO Exercise the contracts of the local tissue ratio.

addpath(fullfile(fileparts(fileparts(mfilename("fullpath"))), "src"));
cfg = testConfig(20);       % 20 um window = 2 grid pixels, for small images
pixelSizeUm = [1, 1];
centre = [200, 190];
tileThresholdLog = log1p(15);   % stage 2 splits tiles at 15: tissue above 3

% Block means are exact, including zero-padded edge blocks.
values = reshape(single(0:574), 25, 23);
reduced = stpt.zillumination.blockMean(values, [10, 10]);
assert(isequal(size(reduced), [3, 3]));
for i = 1:3
    for j = 1:3
        rows = 10 * (i - 1) + 1 : min(10 * i, 25);
        columns = 10 * (j - 1) + 1 : min(10 * j, 23);
        expected = sum(values(rows, columns), "all") / 100;
        assert(abs(reduced(i, j) - expected) < 1e-3);
    end
end

% The tissue mask is the disc; specks smaller than one window are dropped.
% The real 50 um window is used: neighbouring specks can merge into pieces
% larger than a 2-pixel window.
rng(0);
planes = {disc(centre, 120, 300), disc(centre, 120, 250)};
for k = 1:2
    for speck = 1:20
        position = specklePosition(centre, 180);
        planes{k}(position(1) + (-1:1), position(2) + (-1:1)) = 5000;
    end
end
tissue = stpt.zillumination.tissueMasks(toUint16(planes), {true, true}, ...
    tileThresholdLog, testConfig(50).zIllumination, pixelSizeUm);
inside = blockCentresWithin(centre, 110, tissue.gridSize);
outside = ~blockCentresWithin(centre, 150, tissue.gridSize);
for k = 1:2
    assert(all(tissue.layers{k}(inside)) && ~any(tissue.layers{k}(outside)));
end

% Missing tiles are neither tissue nor estimate; their pixels stay zero.
support = true(400, 380);
support(181:240, 171:230) = false;
planes = toUint16({disc(centre, 120, 300) .* support, ...
    disc(centre, 120, 150) .* support});
tissue = stpt.zillumination.tissueMasks(planes, {support, support}, ...
    tileThresholdLog, cfg.zIllumination, pixelSizeUm);
assert(~any(tissue.layers{1}(19:24, 18:23), "all"));
[corrected, audit] = stpt.zillumination.apply( ...
    planes, cfg, {support, support}, tissue);
assert(audit(2).applied && all(corrected{2}(~support) == 0));

% A uniform two-fold attenuation is exact on shared tissue; zeros stay zero.
planes = toUint16({disc(centre, 120, 1000), disc(centre, 120, 500)});
tissue = stpt.zillumination.tissueMasks(planes, {true, true}, ...
    tileThresholdLog, cfg.zIllumination, pixelSizeUm);
[corrected, audit, diagnostics] = stpt.zillumination.apply( ...
    planes, cfg, {true, true}, tissue);
shared = tissue.layers{1} & tissue.layers{2};
assert(all(diagnostics.gainFields{2}(shared) == 2));
assert(all(diagnostics.gainFields{2}(~shared) == 1));
inDisc = disc(centre, 120, 1) > 0;
assert(max(abs(double(corrected{2}(inDisc)) - double(planes{1}(inDisc)))) <= 1);
assert(all(corrected{2}(~inDisc) == 0));
assert(isequal(corrected{1}, planes{1}) && audit(2).gainMedian == 2);

% Two attenuation regions are each recovered beyond the window.
reference = disc(centre, 150, 1000);
attenuation = repmat([0.5 * ones(1, 200), 0.8 * ones(1, 180)], 400, 1);
planes = toUint16({reference, round(reference .* attenuation)});
tissue = stpt.zillumination.tissueMasks(planes, {true, true}, ...
    tileThresholdLog, cfg.zIllumination, pixelSizeUm);
[~, ~, diagnostics] = stpt.zillumination.apply( ...
    planes, cfg, {true, true}, tissue);
gain = diagnostics.gainFields{2};
shared = tissue.layers{1} & tissue.layers{2};
columnCentres = 10 * (1:tissue.gridSize(2)) - 4.5;
left = shared & columnCentres < 200 - 3 * 20 - 5;
right = shared & columnCentres > 200 + 3 * 20 + 5;
assert(all(abs(gain(left) / 2 - 1) < 1e-3));
assert(all(abs(gain(right) / 1.25 - 1) < 1e-3));

% Dim tissue counts in both layers: a tract at 35 counts in the reference and
% 7 in the target is above the presence threshold of 3, so it is corrected by
% its own ratio of 5 next to the bright tissue's ratio of 2.
inDisc = disc(centre, 150, 1);
tract = [zeros(400, 220), ones(400, 160)];
planes = toUint16({inDisc .* (330 * (1 - tract) + 35 * tract), ...
    inDisc .* (165 * (1 - tract) + 7 * tract)});
tissue = stpt.zillumination.tissueMasks(planes, {true, true}, ...
    tileThresholdLog, cfg.zIllumination, pixelSizeUm);
[~, ~, diagnostics] = stpt.zillumination.apply( ...
    planes, cfg, {true, true}, tissue);
gain = diagnostics.gainFields{2};
shared = tissue.layers{1} & tissue.layers{2};
assert(all(shared(blockCentresWithin(centre, 140, tissue.gridSize))));
columnCentres = 10 * (1:tissue.gridSize(2)) - 4.5;
bright = shared & columnCentres < 220 - 3 * 20 - 5;
dim = shared & columnCentres > 220 + 3 * 20 + 5;
assert(all(abs(gain(bright) / 2 - 1) < 1e-3));
assert(all(abs(gain(dim) / 5 - 1) < 1e-3));

% A constant gain on the target cancels: the field scales and the output holds.
planes = toUint16({disc(centre, 120, 1000), disc(centre, 120, 450)});
tripled = {planes{1}, planes{2} * 3};
tissue = stpt.zillumination.tissueMasks(planes, {true, true}, ...
    tileThresholdLog, cfg.zIllumination, pixelSizeUm);
[correctedA, ~, diagnosticsA] = stpt.zillumination.apply( ...
    planes, cfg, {true, true}, tissue);
[correctedB, ~, diagnosticsB] = stpt.zillumination.apply( ...
    tripled, cfg, {true, true}, tissue);
shared = tissue.layers{1} & tissue.layers{2};
assert(all(abs(diagnosticsB.gainFields{2}(shared) * 3 ./ ...
    diagnosticsA.gainFields{2}(shared) - 1) < 1e-5));
assert(max(abs(double(correctedA{2}) - double(correctedB{2})), [], "all") <= 1);

% Tissue seen by only one layer is left exactly as fused.
sharedDisc = disc([200, 120], 90, 800);
onlyInReference = disc([200, 120], 110, 800) - sharedDisc;
onlyInTarget = disc([80, 320], 40, 400);
planes = toUint16({sharedDisc + onlyInReference, ...
    0.5 * sharedDisc + onlyInTarget});
tissue = stpt.zillumination.tissueMasks(planes, {true, true}, ...
    tileThresholdLog, cfg.zIllumination, pixelSizeUm);
corrected = stpt.zillumination.apply(planes, cfg, {true, true}, tissue);
assert(isequal(corrected{2}(onlyInTarget > 0), planes{2}(onlyInTarget > 0)));
assert(all(corrected{2}(onlyInReference > 0) == 0));

% Each channel uses the tissue channel's mask: a bright tracer blob does not
% define tissue, and the dim rest of the disc is corrected.
green = toUint16({disc(centre, 120, 300), disc(centre, 120, 150)});
redReference = disc(centre, 120, 50) + disc(centre, 15, 5000);
red = toUint16({redReference, 0.5 * redReference});
tissue = stpt.zillumination.tissueMasks(green, {true, true}, ...
    tileThresholdLog, cfg.zIllumination, pixelSizeUm);
[~, ~, diagnostics] = stpt.zillumination.apply(red, cfg, {true, true}, tissue);
dimDisc = blockCentresWithin(centre, 100, tissue.gridSize) & ...
    ~blockCentresWithin(centre, 40, tissue.gridSize);
assert(all(abs(diagnostics.gainFields{2}(dimDisc) / 2 - 1) < 1e-5));

% Without tissue in the tissue channel every channel is left unchanged.
empty = toUint16({zeros(400, 380), zeros(400, 380)});
tissue = stpt.zillumination.tissueMasks(empty, {true, true}, ...
    tileThresholdLog, cfg.zIllumination, pixelSizeUm);
[corrected, audit] = stpt.zillumination.apply(red, cfg, {true, true}, tissue);
assert(isequal(corrected, red) && audit(2).reason == "noCommonTissue");

% Planes of any size keep their size; grid value i sits at native 10*i - 4.5.
plane = toUint16({disc([100, 95], 60, 300, [205, 193])});
tissue = stpt.zillumination.tissueMasks([plane, plane], {true, true}, ...
    tileThresholdLog, cfg.zIllumination, pixelSizeUm);
corrected = stpt.zillumination.apply([plane, plane], cfg, {true, true}, tissue);
assert(isequal(size(corrected{2}), [205, 193]));
assert(isequal(tissue.gridSize, [21, 20]));
ramp = imresize(single(1:21)', [210, 1], "bilinear");
assert(all(abs(ramp([5, 6, 15, 16]) - [1; 1.05; 1.95; 2.05]) < 1e-5));

% The grid and window are physical: 2 um pixels give 5-pixel blocks and the
% same window in grid pixels.
planes = toUint16({disc([100, 95], 70, 1000, [200, 190]), ...
    disc([100, 95], 70, 500, [200, 190])});
tissue = stpt.zillumination.tissueMasks(planes, {true, true}, ...
    tileThresholdLog, testConfig(50).zIllumination, [2, 2]);
assert(isequal(tissue.block, [5, 5]) && isequal(tissue.gridUm, [10, 10]));
[~, audit] = stpt.zillumination.apply(planes, testConfig(50), ...
    {true, true}, tissue);
assert(audit(2).gaussianSigmaPixels == 5);

% The z correction requires the section's tissue masks.
try
    stpt.zillumination.apply(planes, cfg);
    error("testLocalTissueRatio:NoError", ...
        "Missing tissue masks were accepted.");
catch exception
    assert(exception.identifier == "stpt:ZIlluminationInput");
end

fprintf("testLocalTissueRatio: PASS\n");
end

function cfg = testConfig(windowSigmaUm)
cfg.zIllumination.method = "localTissueRatio";
cfg.zIllumination.referenceLayer = 1;
cfg.zIllumination.estimationGridUm = 10;
cfg.zIllumination.windowSigmaUm = windowSigmaUm;
end

function image = disc(centre, radius, value, imageSize)
if nargin < 4
    imageSize = [400, 380];
end
[columns, rows] = meshgrid(1:imageSize(2), 1:imageSize(1));
image = single(value) * single((rows - centre(1)) .^ 2 + ...
    (columns - centre(2)) .^ 2 <= radius ^ 2);
end

function planes = toUint16(planes)
planes = cellfun(@(plane) uint16(plane), planes, "UniformOutput", false);
end

function within = blockCentresWithin(centre, radius, gridSize)
% Grid pixels whose block centre (10*i - 4.5 in native pixels) lies in a disc.
[columns, rows] = meshgrid(10 * (1:gridSize(2)) - 4.5, ...
    10 * (1:gridSize(1)) - 4.5);
within = (rows - centre(1)) .^ 2 + (columns - centre(2)) .^ 2 <= radius ^ 2;
end

function position = specklePosition(centre, minimumDistance)
% A random speck centre in the 400 x 380 image, away from the disc.
while true
    position = [randi([5, 395]), randi([5, 375])];
    if sum((position - centre) .^ 2) > minimumDistance ^ 2
        return
    end
end
end

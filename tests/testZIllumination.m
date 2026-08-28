function testZIllumination()
%TESTZILLUMINATION Exercise the clear mathematical contracts of z correction.

addpath(fullfile(fileparts(fileparts(mfilename("fullpath"))), "src"));
cfg = testConfig();

% A single optical layer is always an exact identity.
singleLayer = {uint16(randi([100, 5000], 96, 112))};
[corrected, audit] = stpt.zillumination.apply(singleLayer, cfg);
assert(isequal(corrected{1}, singleLayer{1}));
assert(~audit(1).applied);

% Explicitly disabling correction preserves every layer.
planes = {uint16(randi([100, 5000], 96, 112)), ...
    uint16(randi([100, 5000], 96, 112))};
noneCfg = cfg;
noneCfg.zIllumination.method = "none";
corrected = stpt.zillumination.apply(planes, noneCfg);
assert(isequal(corrected, planes));

% A uniform two-fold attenuation has the exact gain and reconstruction.
reference = repmat(uint16(2000), 192, 224);
attenuated = repmat(uint16(1000), size(reference));
[corrected, audit, diagnostics] = stpt.zillumination.apply( ...
    {reference, attenuated}, cfg);
assert(isequal(corrected{1}, reference));
assert(isequal(corrected{2}, reference));
assert(~audit(1).applied && audit(2).applied);
assert(abs(audit(2).gainMedian - 2) < 1e-6);
assert(all(abs(diagnostics.gainFields{2}(:) - 2) < 1e-6));
assert(isequal(diagnostics.estimationSizePixels, size(reference)));
assert(audit(2).gaussianSigmaPixels == ...
    diagnostics.gaussianSigmaPixels);

fprintf("testZIllumination: PASS\n");
end

function cfg = testConfig()
cfg.zIllumination.method = "stitchitSmoothRatio";
cfg.zIllumination.referenceLayer = 1;
cfg.zIllumination.maxEstimationPixels = 1.5e6;
cfg.zIllumination.filterAreaFraction = 0.01;
end

function testZIllumination()
%TESTZILLUMINATION Exercise the clear mathematical contracts of z correction.

addpath(fullfile(fileparts(fileparts(mfilename("fullpath"))), "src"));
cfg = testConfig();

% A single optical layer is always an exact identity.
singleLayer = {uint16(randi([100, 5000], 96, 112))};
[corrected, audit] = stpt.zillumination.apply(singleLayer, cfg);
assert(isequal(corrected{1}, singleLayer{1}));
assert(~audit(1).applied);
assert(audit(1).reason == "singleLayer");

% Explicitly disabling correction preserves every layer.
planes = {uint16(randi([100, 5000], 96, 112)), ...
    uint16(randi([100, 5000], 96, 112))};
noneCfg = cfg;
noneCfg.zIllumination.method = "none";
[corrected, audit] = stpt.zillumination.apply(planes, noneCfg);
assert(isequal(corrected, planes));
assert(all(string({audit.reason}) == "disabled"));

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
assert(audit(1).reason == "referenceLayer" && audit(2).reason == "");

% Missing acquired support is excluded symmetrically from both smooth fields.
% A true two-fold attenuation therefore remains exactly correct outside the
% unsupported hole, while the hole itself remains zero.
targetWithHole = attenuated;
targetSupport = true(size(targetWithHole));
targetSupport(80:110, 95:125) = false;
targetWithHole(~targetSupport) = 0;
supportMasks = {true(size(reference)), targetSupport};
[maskedCorrected, maskedAudit, maskedDiagnostics] = ...
    stpt.zillumination.apply( ...
    {reference, targetWithHole}, cfg, supportMasks);
assert(all(maskedCorrected{2}(targetSupport) == 2000));
assert(all(maskedCorrected{2}(~targetSupport) == 0));
assert(abs(maskedAudit(2).gainMedian - 2) < 1e-6);
assert(all(abs(maskedDiagnostics.gainFields{2}(:) - 2) < 1e-6));

% Supplying complete masks follows the exact original numerical path.
completeMasks = {true(size(reference)), true(size(attenuated))};
explicitComplete = stpt.zillumination.apply( ...
    {reference, attenuated}, cfg, completeMasks);
assert(isequal(explicitComplete, corrected));

% Mathematical validity is decided independently for each target layer. A
% zero target uses exact identity while another valid target is still corrected.
zeroTarget = zeros(size(reference), "uint16");
thirdTarget = repmat(uint16(500), size(reference));
[mixedCorrected, mixedAudit, mixedDiagnostics] = ...
    stpt.zillumination.apply( ...
    {reference, zeroTarget, thirdTarget}, cfg);
assert(isequal(mixedCorrected{1}, reference));
assert(isequal(mixedCorrected{2}, zeroTarget));
assert(isequal(mixedCorrected{3}, reference));
assert(~mixedAudit(2).applied);
assert(mixedAudit(2).reason == "nonpositiveSmoothedField");
assert(mixedAudit(2).gainMedian == 1);
assert(isempty(mixedDiagnostics.gainFields{2}));
assert(mixedAudit(3).applied && mixedAudit(3).reason == "");
assert(abs(mixedAudit(3).gainMedian - 4) < 1e-6);

% An invalid reference makes every target ratio undefined but remains a clean
% identity operation rather than a division failure.
[zeroReferenceCorrected, zeroReferenceAudit] = ...
    stpt.zillumination.apply({zeroTarget, attenuated}, cfg);
assert(isequal(zeroReferenceCorrected, {zeroTarget, attenuated}));
assert(~zeroReferenceAudit(2).applied);
assert(zeroReferenceAudit(2).reason == "nonpositiveSmoothedField");

fprintf("testZIllumination: PASS\n");
end

function cfg = testConfig()
cfg.zIllumination.method = "stitchitSmoothRatio";
cfg.zIllumination.referenceLayer = 1;
cfg.zIllumination.maxEstimationPixels = 1.5e6;
cfg.zIllumination.filterAreaFraction = 0.01;
end

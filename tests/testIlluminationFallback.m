function testIlluminationFallback()
%TESTILLUMINATIONFALLBACK Verify fitted and identity XY models side by side.

addpath(fullfile(fileparts(fileparts(mfilename("fullpath"))), "src"));
[datasetIndex, cfg] = testInputs();

% ch1 has no usable PMT signal. ch2 has a simple positive field whose exact
% median-normalized gain remains unchanged by the fallback implementation.
templates = cell(2, 2);
for layer = 1:2
    templates{1, layer} = makeTemplate(zeros(6, 8, "single"));
    positive = single(reshape(1:48, 6, 8) + 10 * layer);
    templates{2, layer} = makeTemplate(positive);
end

model = stpt.illumination.buildModelFromTemplates( ...
    templates, datasetIndex, cfg);
stpt.illumination.validateModel(model, datasetIndex);

for layer = 1:2
    red = model.channels(1).layers(layer);
    assert(~red.correctionApplied);
    assert(red.correctionReason == "nonpositiveTemplate");
    assert(all(red.gain.oddRows(:) == 1));
    assert(all(red.gain.evenRows(:) == 1));
    assert(red.normalization.oddRows == 0);

    green = model.channels(2).layers(layer);
    expectedTemplate = templates{2, layer}.pooledRows;
    expectedNormalization = median(expectedTemplate(:));
    expectedCrop = expectedTemplate(2:5, 2:7);
    expectedGain = expectedNormalization ./ expectedCrop;
    assert(green.correctionApplied);
    assert(green.correctionReason == "");
    assert(isequal(green.gain.oddRows, expectedGain));
    assert(isequal(green.gain.evenRows, expectedGain));
end

% Identity fallback still uses the normal crop-and-apply path and therefore
% returns the retained raw values exactly as single precision.
raw = uint16(reshape(1:48, 6, 8));
redCorrected = stpt.illumination.applyModel(raw, model, 1, 1, 1);
assert(isequal(redCorrected, single(raw(2:5, 2:7))));

% Split-row correction is atomic within a layer. One unusable parity makes
% both row parities identity, avoiding an artificial alternating-row pattern.
splitCfg = cfg;
splitCfg.illumination.rowMode = "split";
splitTemplates = templates;
splitTemplates{2, 1}.oddRows = ones(6, 8, "single") * 20;
splitTemplates{2, 1}.evenRows = zeros(6, 8, "single");
splitModel = stpt.illumination.buildModelFromTemplates( ...
    splitTemplates, datasetIndex, splitCfg);
stpt.illumination.validateModel(splitModel, datasetIndex);
splitLayer = splitModel.channels(2).layers(1);
assert(~splitLayer.correctionApplied);
assert(splitLayer.correctionReason == "nonpositiveTemplate");
assert(all(splitLayer.gain.oddRows(:) == 1));
assert(all(splitLayer.gain.evenRows(:) == 1));

% There is deliberately no subjective brightness threshold: a finite positive
% template remains mathematically usable even when its absolute level is low.
positiveLowTemplates = templates;
for c = 1:2
    for layer = 1:2
        positiveLowTemplates{c, layer} = makeTemplate( ...
            ones(6, 8, "single") * eps("single"));
    end
end
positiveLowModel = stpt.illumination.buildModelFromTemplates( ...
    positiveLowTemplates, datasetIndex, cfg);
assert(all(arrayfun(@(channel) ...
    all([channel.layers.correctionApplied]), positiveLowModel.channels)));

% Nonfinite values indicate a malformed computation and remain fatal rather
% than being hidden by the scientifically narrow nonpositive fallback.
nonfiniteTemplates = positiveLowTemplates;
nonfiniteTemplates{1, 1}.pooledRows(1) = nan;
assertError(@() stpt.illumination.buildModelFromTemplates( ...
    nonfiniteTemplates, datasetIndex, cfg), "stpt:IlluminationTemplate");

% The deliberate no-correction QC model uses the same explicit status contract.
identity = stpt.illumination.identityModel(model);
stpt.illumination.validateModel(identity, datasetIndex);
assert(all(arrayfun(@(channel) ...
    all(~[channel.layers.correctionApplied]), identity.channels)));
assert(all(arrayfun(@(channel) ...
    all(string({channel.layers.correctionReason}) == "qcIdentity"), ...
    identity.channels)));

fprintf("testIlluminationFallback: PASS\n");
end

function template = makeTemplate(image)
template.oddRows = image;
template.evenRows = image;
template.pooledRows = image;
end

function assertError(action, expectedIdentifier)
try
    action();
catch exception
    assert(exception.identifier == expectedIdentifier);
    return
end
error("Expected error %s was not raised.", expectedIdentifier);
end

function [datasetIndex, cfg] = testInputs()
datasetIndex.channels = struct( ...
    "id", {1, 2}, "name", {"red", "green"});
datasetIndex.missingTiles = table();
datasetIndex.geometry.layersPerSection = 2;
datasetIndex.geometry.tileSizePixels = [8, 6];
datasetIndex.geometry.retainedTileSizePixels = [6, 4];

cfg.illumination.method = "tissueOtsu";
cfg.illumination.rowMode = "pool";
cfg.illumination.trainingSections = 1:10;
cfg.illumination.tissueReferenceChannel = 2;
cfg.preprocessing.cropPixels = [1, 1, 1, 1];
end

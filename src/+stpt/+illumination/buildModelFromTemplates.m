function model = buildModelFromTemplates(templates, datasetIndex, cfg)
%BUILDMODELFROMTEMPLATES Convert raw templates to the shared gain model.
%
% Both fitting algorithms use this function so cropping, median normalization,
% zero offset, and model layout are numerically identical.

model = struct();
model.schemaVersion = 1;
model.created = string(datetime("now"));
model.method = string(cfg.illumination.method);
model.rowMode = string(cfg.illumination.rowMode);
model.trainingSections = cfg.illumination.trainingSections(:)';
model.tissueReferenceChannel = cfg.illumination.tissueReferenceChannel;
model.cropPixels = cfg.preprocessing.cropPixels;
model.inputTileSizePixels = datasetIndex.geometry.tileSizePixels;
model.outputTileSizePixels = datasetIndex.geometry.retainedTileSizePixels;

nChannels = numel(datasetIndex.channels);
nLayers = datasetIndex.geometry.layersPerSection;
channels = repmat(struct("id", [], "name", "", "layers", struct([])), ...
    nChannels, 1);

% Construct one odd/even zero-offset gain pair for every channel and layer.
for c = 1:nChannels
    channels(c).id = datasetIndex.channels(c).id;
    channels(c).name = datasetIndex.channels(c).name;
    layers = repmat(emptyLayerModel(), nLayers, 1);
    for layer = 1:nLayers
        template = templates{c, layer};
        [layers(layer).gain.oddRows, ...
            layers(layer).normalization.oddRows] = templateGain( ...
            template.oddRows, model.cropPixels);
        [layers(layer).gain.evenRows, ...
            layers(layer).normalization.evenRows] = templateGain( ...
            template.evenRows, model.cropPixels);
    end
    channels(c).layers = layers;
end
model.channels = channels;
end

function layer = emptyLayerModel()
% This first model family estimates multiplicative correction only.
layer = struct();
layer.offset = struct("oddRows", single(0), "evenRows", single(0));
layer.gain = struct("oddRows", single([]), "evenRows", single([]));
layer.normalization = struct("oddRows", single(nan), ...
    "evenRows", single(nan));
end

function [gain, normalization] = templateGain(template, cropPixels)
% Normalize on the full raw template, then retain only reconstruction support.
template = single(template);
normalization = median(template(:));
cropped = template( ...
    cropPixels(3)+1:end-cropPixels(4), ...
    cropPixels(1)+1:end-cropPixels(2));
if ~isfinite(normalization) || normalization <= 0 || ...
        any(~isfinite(cropped(:))) || any(cropped(:) <= 0)
    error("stpt:IlluminationTemplate", ...
        "The illumination template is invalid within cropped support.");
end
gain = normalization ./ cropped;
end

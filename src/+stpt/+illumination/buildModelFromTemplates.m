function model = buildModelFromTemplates(templates, datasetIndex, cfg)
%BUILDMODELFROMTEMPLATES Convert raw templates to the shared gain model.
%
% Both fitting algorithms use this function so cropping, median normalization,
% zero offset, and model layout are numerically identical.

model = struct();
model.created = string(datetime("now"));
model.method = string(cfg.illumination.method);
model.rowMode = lower(string(cfg.illumination.rowMode));
model.trainingSections = cfg.illumination.trainingSections(:)';
model.tissueReferenceChannel = cfg.illumination.tissueReferenceChannel;
model.missingTiles = datasetIndex.missingTiles;
model.cropPixels = cfg.preprocessing.cropPixels;
model.inputTileSizePixels = datasetIndex.geometry.tileSizePixels;
model.outputTileSizePixels = datasetIndex.geometry.retainedTileSizePixels;

nChannels = numel(datasetIndex.channels);
nLayers = datasetIndex.geometry.layersPerSection;
channels = repmat(struct("id", [], "name", "", "layers", struct([])), ...
    nChannels, 1);

% Construct one zero-offset gain model for every channel and layer. A finite,
% positive template produces the usual median-normalized gain. A nonpositive
% template cannot define that ratio and therefore uses an explicit identity
% model instead of amplifying detector noise or stopping reconstruction.
for c = 1:nChannels
    channels(c).id = datasetIndex.channels(c).id;
    channels(c).name = datasetIndex.channels(c).name;
    layers = repmat(emptyLayerModel(), nLayers, 1);
    for layer = 1:nLayers
        template = templates{c, layer};
        if model.rowMode == "pool"
            [pooledGain, pooledNormalization, usable] = templateGain( ...
                template.pooledRows, model.cropPixels, ...
                model.inputTileSizePixels);
            layers(layer).normalization.oddRows = pooledNormalization;
            layers(layer).normalization.evenRows = pooledNormalization;
            if usable
                layers(layer).gain.oddRows = pooledGain;
                layers(layer).gain.evenRows = pooledGain;
                layers(layer).correctionApplied = true;
            else
                layers(layer) = useIdentityGain(layers(layer), ...
                    model.outputTileSizePixels, "nonpositiveTemplate");
            end
        else
            [oddGain, oddNormalization, oddUsable] = templateGain( ...
                template.oddRows, model.cropPixels, ...
                model.inputTileSizePixels);
            [evenGain, evenNormalization, evenUsable] = templateGain( ...
                template.evenRows, model.cropPixels, ...
                model.inputTileSizePixels);
            layers(layer).normalization.oddRows = oddNormalization;
            layers(layer).normalization.evenRows = evenNormalization;
            if oddUsable && evenUsable
                layers(layer).gain.oddRows = oddGain;
                layers(layer).gain.evenRows = evenGain;
                layers(layer).correctionApplied = true;
            else
                % Treat the complete layer atomically. Correcting only one row
                % parity would create an artificial alternating-row pattern.
                layers(layer) = useIdentityGain(layers(layer), ...
                    model.outputTileSizePixels, "nonpositiveTemplate");
            end
        end

        if ~layers(layer).correctionApplied
            warning("stpt:IlluminationIdentityFallback", ...
                "ch%d layer %d has a nonpositive illumination template; " + ...
                "using zero offset and unit gain.", channels(c).id, layer);
        end
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
layer.correctionApplied = false;
layer.correctionReason = "";
end

function [gain, normalization, usable] = templateGain( ...
        template, cropPixels, inputTileSizePixels)
% Normalize on the full raw template, then retain only reconstruction support.
template = single(template);
expectedSize = fliplr(inputTileSizePixels); % MATLAB [rows, columns]
if ~isequal(size(template), expectedSize) || any(~isfinite(template(:)))
    error("stpt:IlluminationTemplate", ...
        "The illumination template has invalid dimensions or values.");
end
normalization = median(template(:));
cropped = template( ...
    cropPixels(3)+1:end-cropPixels(4), ...
    cropPixels(1)+1:end-cropPixels(2));
usable = normalization > 0 && all(cropped(:) > 0);
if usable
    gain = normalization ./ cropped;
else
    gain = single([]);
end
end

function layer = useIdentityGain(layer, outputTileSizePixels, reason)
% Preserve measured normalizations while making the applied transform exact.
gainSize = fliplr(outputTileSizePixels); % MATLAB [rows, columns]
layer.offset.oddRows = single(0);
layer.offset.evenRows = single(0);
layer.gain.oddRows = ones(gainSize, "single");
layer.gain.evenRows = ones(gainSize, "single");
layer.correctionApplied = false;
layer.correctionReason = string(reason);
end

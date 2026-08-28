function validateModel(model, datasetIndex)
%VALIDATEMODEL Check the standard illumination-model contract.

required = ["schemaVersion", "method", "rowMode", "trainingSections", ...
    "tissueReferenceChannel", "cropPixels", "inputTileSizePixels", ...
    "outputTileSizePixels", "channels"];
for field = required
    if ~isfield(model, field)
        error("stpt:IlluminationModel", ...
            "Illumination model is missing field '%s'.", field);
    end
end

rowMode = lower(string(model.rowMode));
if ~ismember(rowMode, ["pool", "split"])
    error("stpt:IlluminationModel", ...
        "Illumination row mode must be 'pool' or 'split'.");
end
if ~isequal(model.inputTileSizePixels, ...
        datasetIndex.geometry.tileSizePixels) || ...
        ~isequal(model.outputTileSizePixels, ...
        datasetIndex.geometry.retainedTileSizePixels)
    error("stpt:IlluminationModel", ...
        "Illumination model dimensions do not match the dataset index.");
end
if ~isequal([model.channels.id], [datasetIndex.channels.id])
    error("stpt:IlluminationModel", ...
        "Illumination-model channels do not match the dataset index.");
end

expectedSize = fliplr(model.outputTileSizePixels); % MATLAB [rows, columns]
for c = 1:numel(model.channels)
    channel = model.channels(c);
    if numel(channel.layers) ~= datasetIndex.geometry.layersPerSection
        error("stpt:IlluminationModel", ...
            "Channel %d has the wrong number of layers.", channel.id);
    end
    for layerIndex = 1:numel(channel.layers)
        layer = channel.layers(layerIndex);
        validateParity(layer.offset.oddRows, layer.gain.oddRows, expectedSize);
        validateParity(layer.offset.evenRows, layer.gain.evenRows, expectedSize);
        if rowMode == "pool" && (~isequal(layer.offset.oddRows, ...
                layer.offset.evenRows) || ~isequal(layer.gain.oddRows, ...
                layer.gain.evenRows) || ...
                ~isequal(layer.normalization.oddRows, ...
                layer.normalization.evenRows))
            error("stpt:IlluminationModel", ...
                "A pooled model must use one identical field for all rows.");
        end
    end
end
end

function validateParity(offset, gain, expectedSize)
% Offsets may be scalar or spatial; gains are always spatial and positive.
if ~(isscalar(offset) || isequal(size(offset), expectedSize)) || ...
        any(~isfinite(offset(:)))
    error("stpt:IlluminationModel", ...
        "Offset must be finite and either scalar or the cropped tile size.");
end
if ~isequal(size(gain), expectedSize) || ...
        any(~isfinite(gain(:))) || any(gain(:) <= 0)
    error("stpt:IlluminationModel", ...
        "Gain must be finite, positive, and the cropped tile size.");
end
end

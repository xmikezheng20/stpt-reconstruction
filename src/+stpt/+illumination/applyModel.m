function corrected = applyModel(rawTile, model, channelId, layer, gridY)
%APPLYMODEL Crop and apply a fitted offset-and-gain illumination model.
%
% The returned image is single precision. Clipping and conversion to an output
% integer type are deliberately left to the later output-writing stage.

channelPosition = find([model.channels.id] == channelId, 1);
if isempty(channelPosition)
    error("stpt:IlluminationChannel", ...
        "Channel %d is absent from the illumination model.", channelId);
end
if layer < 1 || layer > numel(model.channels(channelPosition).layers)
    error("stpt:IlluminationLayer", ...
        "Layer %d is absent from the illumination model.", layer);
end
if size(rawTile, 2) ~= model.inputTileSizePixels(1) || ...
        size(rawTile, 1) ~= model.inputTileSizePixels(2)
    error("stpt:IlluminationSize", ...
        "Raw tile dimensions do not match the illumination model.");
end

% Cropping before pointwise correction is identical to correcting first and
% discarding the same edge pixels. The model therefore contains no invented
% values outside the region used by reconstruction.
crop = model.cropPixels;
cropped = single(rawTile( ...
    crop(3)+1:end-crop(4), crop(1)+1:end-crop(2)));

layerModel = model.channels(channelPosition).layers(layer);
% Pooled models deliberately store the same correction in both slots. The
% parity lookup therefore remains the sole application path for both modes.
if mod(gridY, 2) == 1
    offset = layerModel.offset.oddRows;
    gain = layerModel.gain.oddRows;
else
    offset = layerModel.offset.evenRows;
    gain = layerModel.gain.evenRows;
end
corrected = (cropped - offset) .* gain;
end

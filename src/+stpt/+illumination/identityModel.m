function identity = identityModel(model)
%IDENTITYMODEL Make crop-only illumination processing through the same interface.
%
% The returned model preserves the fitted model's dimensions and channel/layer
% layout, but applies D=0 and G=1 everywhere. This lets QC alternatives use the
% exact same tile-processing and fusion code as illumination-corrected output.

identity = model;
identity.method = "identity";
identity.created = string(datetime("now"));
identity.sourceMethod = string(model.method);
identity.trainingSections = [];

for c = 1:numel(identity.channels)
    for layer = 1:numel(identity.channels(c).layers)
        layerModel = identity.channels(c).layers(layer);
        layerModel.offset.oddRows = single(0);
        layerModel.offset.evenRows = single(0);
        layerModel.gain.oddRows = ones( ...
            size(layerModel.gain.oddRows), "single");
        layerModel.gain.evenRows = ones( ...
            size(layerModel.gain.evenRows), "single");
        layerModel.normalization.oddRows = single(1);
        layerModel.normalization.evenRows = single(1);
        identity.channels(c).layers(layer) = layerModel;
    end
end
end

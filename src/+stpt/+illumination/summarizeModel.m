function summary = summarizeModel(model)
%SUMMARIZEMODEL Record compact normalization and gain-range diagnostics.

nChannels = numel(model.channels);
nLayers = numel(model.channels(1).layers);
rows = cell(nChannels * nLayers, 1);
record = 0;

for c = 1:nChannels
    for layer = 1:nLayers
        record = record + 1;
        layerModel = model.channels(c).layers(layer);
        oddGain = layerModel.gain.oddRows;
        evenGain = layerModel.gain.evenRows;
        row = struct();
        row.channelId = model.channels(c).id;
        row.layer = layer;
        row.oddNormalization = layerModel.normalization.oddRows;
        row.evenNormalization = layerModel.normalization.evenRows;
        row.oddGainP01 = prctile(oddGain(:), 1);
        row.oddGainMedian = median(oddGain(:));
        row.oddGainP99 = prctile(oddGain(:), 99);
        row.oddGainMax = max(oddGain(:));
        row.evenGainP01 = prctile(evenGain(:), 1);
        row.evenGainMedian = median(evenGain(:));
        row.evenGainP99 = prctile(evenGain(:), 99);
        row.evenGainMax = max(evenGain(:));
        rows{record} = row;
    end
end
summary = struct2table(vertcat(rows{:}));
end

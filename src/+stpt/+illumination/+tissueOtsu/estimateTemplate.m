function template = estimateTemplate(datasetIndex, selection, channelId, ...
        layer, trimPercent)
%ESTIMATETEMPLATE Pool selected tiles directly across training sections.
%
% One full-size odd-row and even-row template is estimated for the requested
% channel/layer. Cropping is deferred to the shared model builder so both
% illumination methods use identical gain construction.

template = struct();
template.channel = channelId;
template.layer = layer;
template.correctionType = "directPooledTrimmean";
template.details.trimPercent = trimPercent;

for parity = ["odd", "even"]
    rows = selection.tiles.selectedForIllumination & ...
        selection.tiles.layer == layer & ...
        selection.tiles.gridParity == parity;
    selectedTiles = selection.tiles(rows, :);
    nSelected = height(selectedTiles);
    if nSelected == 0
        error("stpt:TissueOtsuTemplate", ...
            "No selected tiles are available for layer %d, %s rows.", ...
            layer, parity);
    end

    tileSize = datasetIndex.geometry.tileSizePixels;
    stack = zeros(tileSize(2), tileSize(1), nSelected, "uint16");
    for i = 1:nSelected
        stack(:, :, i) = stpt.io.loadTile(datasetIndex, ...
            selectedTiles.sectionNumber(i), layer, ...
            selectedTiles.acquisitionIndex(i), channelId);
    end

    averageImage = single(trimmean(stack, trimPercent, "round", 3));
    clear stack
    if parity == "odd"
        template.oddRows = averageImage;
        template.oddN = nSelected;
    else
        template.evenRows = averageImage;
        template.evenN = nSelected;
    end
end

template.poolN = template.oddN + template.evenN;
% Combine the parity templates into the single all-row field used by pool
% mode. Count weighting reflects the selected tile population when tissue
% selection leaves slightly different numbers of odd and even rows.
oddWeight = single(template.oddN / template.poolN);
evenWeight = single(template.evenN / template.poolN);
template.pooledRows = template.oddRows .* oddWeight + ...
    template.evenRows .* evenWeight;
end

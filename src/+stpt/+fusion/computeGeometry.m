function geometry = computeGeometry(datasetIndex, sectionNumber)
%COMPUTEGEOMETRY Convert the indexed target grid to stitched pixel bounds.
%
% Pixel placement is derived from target movement and pixel size. Overlap is
% therefore a consequence of retained tile support, never a separate input.

sectionPosition = find([datasetIndex.sections.number] == sectionNumber, 1);
if isempty(sectionPosition)
    error("stpt:FusionSection", "Section %d is not indexed.", sectionNumber);
end

indexGeometry = datasetIndex.geometry;
step = indexGeometry.targetStepPixels;       % [x, y]
tileSize = indexGeometry.retainedTileSizePixels; % [width, height]
canvasSize = indexGeometry.nominalCanvasSizePixels;
if any(mod(step, 1) ~= 0) || any(mod(canvasSize, 1) ~= 0)
    error("stpt:FusionGeometry", ...
        "Target placement and canvas dimensions must be integer pixels.");
end

positions = datasetIndex.sections(sectionPosition).positions;
placements = table(positions.acquisitionIndex, positions.gridX, positions.gridY, ...
    'VariableNames', {'acquisitionIndex', 'gridX', 'gridY'});
placements.xStart = 1 + (placements.gridX - 1) * step(1);
placements.yStart = 1 + (placements.gridY - 1) * step(2);
placements.xEnd = placements.xStart + tileSize(1) - 1;
placements.yEnd = placements.yStart + tileSize(2) - 1;

% Use one deterministic traversal for both fusion algorithms. Reverse order
% gives lower acquisition indices priority in the overwrite control; normalized
% blending is mathematically independent of traversal order.
[~, reverseOrder] = sort(placements.acquisitionIndex, "descend");
placements.placementOrder = zeros(height(placements), 1);
placements.placementOrder(reverseOrder) = (1:height(placements))';

if max(placements.xEnd) ~= canvasSize(1) || ...
        max(placements.yEnd) ~= canvasSize(2) || ...
        min(placements.xStart) ~= 1 || min(placements.yStart) ~= 1
    error("stpt:FusionGeometry", ...
        "Target-grid placements do not exactly fill the nominal canvas.");
end

geometry = struct();
geometry.sectionNumber = sectionNumber;
geometry.tileSizePixels = tileSize;
geometry.targetStepPixels = step;
geometry.overlapPixels = tileSize - step;
geometry.canvasSizePixels = canvasSize;
geometry.placements = placements;
geometry.reverseAcquisitionOrder = reverseOrder;
end

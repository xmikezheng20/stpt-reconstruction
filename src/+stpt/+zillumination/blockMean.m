function reduced = blockMean(plane, block)
%BLOCKMEAN Mean of each block(1) x block(2) tile of a plane.
%
% The canvas is extended with zeros (background) to whole blocks, so every
% grid pixel has the same footprint and native pixel (r, c) belongs to grid
% pixel (ceil(r / block(1)), ceil(c / block(2))).

gridSize = ceil(size(plane) ./ block);
padded = zeros(gridSize .* block, "single");
padded(1:size(plane, 1), 1:size(plane, 2)) = plane;
blocks = reshape(padded, block(1), gridSize(1), block(2), gridSize(2));
reduced = reshape(mean(blocks, [1, 3]), gridSize);
end

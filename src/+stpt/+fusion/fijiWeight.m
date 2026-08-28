function weight = fijiWeight(tileSizePixels, alpha)
%FIJIWEIGHT Build OpenSTP's Fiji-style distance-to-edge weight field.
%
% TILESIZEPIXELS is [width, height]. OpenSTP computes the distance to the
% nearest left/right edge and top/bottom edge, adds one to each distance, then
% uses ((dx + 1) * (dy + 1) + 1)^alpha. A global normalization leaves the
% final weighted average unchanged and keeps single-precision sums compact.

width = tileSizePixels(1);
height = tileSizePixels(2);
xDistance = min(0:width-1, width-1:-1:0) + 1;
yDistance = min(0:height-1, height-1:-1:0)' + 1;
weight = (yDistance .* xDistance + 1) .^ alpha;
weight = single(weight ./ max(weight(:)));
end

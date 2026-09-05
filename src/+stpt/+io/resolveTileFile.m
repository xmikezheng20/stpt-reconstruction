function [filePath, isPresent] = resolveTileFile( ...
        datasetIndex, sectionNumber, layer, ...
        acquisitionIndex, channelId)
%RESOLVETILEFILE Resolve one logical tile without changing the native layout.
%
% ACQUISITIONINDEX is one-based within the 14-by-18 scan. Native TIFF indices
% are zero-based, with all tiles from layer 1 followed by all tiles from layer 2.
% A missing acquisition slot returns filePath="" and isPresent=false; later
% slots retain their exact logical coordinates.

% Resolve user-facing section/channel identifiers to positions in the index.
sectionPosition = find([datasetIndex.sections.number] == sectionNumber, 1);
channelPosition = find([datasetIndex.channels.id] == channelId, 1);
if isempty(sectionPosition) || isempty(channelPosition)
    error("stpt:TileLookup", "Unknown section or channel.");
end

% Validate the two coordinates that address a tile within one section.
nTiles = datasetIndex.geometry.tilesPerLayer;
if layer < 1 || layer > datasetIndex.geometry.layersPerSection || ...
        acquisitionIndex < 1 || acquisitionIndex > nTiles
    error("stpt:TileLookup", "Layer or acquisition index is out of range.");
end

% Convert (layer, acquisition index) to the section-local filename offset. The
% stored filename itself retains the acquisition's global native TIFF index.
sectionFileOffset = (layer - 1) * nTiles + acquisitionIndex - 1;
section = datasetIndex.sections(sectionPosition);
fileName = section.channelFiles{channelPosition}(sectionFileOffset + 1);
isPresent = strlength(fileName) > 0;
if isPresent
    filePath = string(fullfile(datasetIndex.channels(channelPosition).root, ...
        section.channelDirectories(channelPosition), fileName));
else
    filePath = "";
end
end

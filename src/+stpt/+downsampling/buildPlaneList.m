function [inputFiles, orderedRows] = buildPlaneList( ...
        reconstructionManifest, channelId, sections, layersPerSection)
%BUILDPLANELIST Adapt the Stage 3 manifest to one physical z-ordered series.
%
% Optical layers are consecutive acquisition planes. Sorting by physical
% section and then layer therefore produces the z order consumed by the
% generic resampler.

rows = reconstructionManifest.channelId == channelId;
orderedRows = sortrows(reconstructionManifest(rows, :), ...
    ["sectionNumber", "layer"]);

sections = sections(:);
expectedSections = repelem(sections, layersPerSection);
expectedLayers = repmat((1:layersPerSection)', numel(sections), 1);
if height(orderedRows) ~= numel(expectedSections) || ...
        ~isequal(orderedRows.sectionNumber, expectedSections) || ...
        ~isequal(orderedRows.layer, expectedLayers)
    error("stpt:DownsamplingInput", ...
        "Channel %d does not contain one complete ordered plane series.", ...
        channelId);
end

inputFiles = string(orderedRows.filePath);
if ~all(isfile(inputFiles))
    error("stpt:DownsamplingInput", ...
        "One or more Stage 3 TIFFs are missing for channel %d.", channelId);
end
end

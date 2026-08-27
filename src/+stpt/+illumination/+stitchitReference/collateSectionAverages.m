function template = collateSectionAverages(sectionAverages, referenceConfig)
%COLLATESECTIONAVERAGES Combine section averages into a reference template.
%
% Closely adapted from StitchIt/code/stitching/collateAverageImages.m at
% commit 383b9fbd5f0664bf232c897a87759d8da43b725c. It retains the separate
% 10-percent trimmed means for odd and even mosaic rows.

sectionAverages = sectionAverages(:);
if isempty(sectionAverages) || any(cellfun(@isempty, sectionAverages))
    error("stpt:MissingSectionAverage", ...
        "Every pilot section must provide an illumination average.");
end

first = sectionAverages{1};
nSections = numel(sectionAverages);
imageSize = size(first.oddRows);
oddStack = zeros(imageSize(1), imageSize(2), nSections, "single");
evenStack = zeros(imageSize(1), imageSize(2), nSections, "single");
oddCounts = zeros(nSections, 1);
evenCounts = zeros(nSections, 1);
sections = zeros(nSections, 1);

for i = 1:nSections
    avData = sectionAverages{i};
    oddStack(:, :, i) = avData.oddRows;
    evenStack(:, :, i) = avData.evenRows;
    oddCounts(i) = avData.oddN;
    evenCounts(i) = avData.evenN;
    sections(i) = avData.section;
end

trimPercent = referenceConfig.acrossSectionTrimPercent;
template = struct();
template.oddRows = single(trimmean(oddStack, trimPercent, "round", 3));
template.evenRows = single(trimmean(evenStack, trimPercent, "round", 3));
template.pooledRows = (template.oddRows + template.evenRows) / 2;
template.oddN = sum(oddCounts);
template.evenN = sum(evenCounts);
template.poolN = template.oddN + template.evenN;
template.correctionType = "bruteAverageTrimmean";
template.channel = first.channel;
template.layer = first.layer;
template.details.sections = sections;
template.details.acrossSectionTrimPercent = trimPercent;
end

function [avData, tileStatistics, summary] = estimateSectionAverage( ...
        imageStack, tileStatistics, referenceConfig)
%ESTIMATESECTIONAVERAGE Build odd/even averages for one image stack.
%
% Closely adapted from StitchIt/code/preProcessTiles/private/
% calcAverageMatFiles.m at commit
% 383b9fbd5f0664bf232c897a87759d8da43b725c.
%
% Deliberate deviations: input comes from the native TIFF index; rejected-row
% guards run after rejection; compact statistics replace per-tile histograms;
% output is returned to the caller rather than written beside raw data.

selection = stpt.illumination.stitchitReference.estimateFloorTileMask( ...
    tileStatistics.tileMean, referenceConfig);
nTiles = height(tileStatistics);

% Attach every selection decision to the per-tile audit table.
tileStatistics.floorThreshold = repmat(selection.threshold, nTiles, 1);
tileStatistics.thresholdFallback = repmat(selection.usedFallback, nTiles, 1);
tileStatistics.rejectedAtFloor = selection.rejectedAtFloor;
tileStatistics.retainedForIllumination = selection.retained;
tileStatistics.gridParity = repmat("odd", nTiles, 1);
tileStatistics.gridParity(mod(tileStatistics.gridY, 2) == 0) = "even";

if selection.floorRejectedFraction > referenceConfig.maxRejectedFraction
    error("stpt:ExcessiveFloorRejection", ...
        "Detector-floor rejection removed %.1f%% of a section stack.", ...
        selection.floorRejectedFraction * 100);
end

oddIndices = find(selection.retained & mod(tileStatistics.gridY, 2) == 1);
evenIndices = find(selection.retained & mod(tileStatistics.gridY, 2) == 0);
minimumCount = referenceConfig.minimumTilesPerParity;
if numel(oddIndices) < minimumCount || numel(evenIndices) < minimumCount
    error("stpt:IlluminationParity", ...
        "Need at least %d retained tiles in each parity; found %d odd/%d even.", ...
        minimumCount, numel(oddIndices), numel(evenIndices));
end

% StitchIt chooses a trim percentage intended to remove roughly one tile from
% each tail of the pixelwise distribution within each parity group.
[oddRows, oddTrimPercent] = trimmedMeanForTiles(imageStack, oddIndices);
[evenRows, evenTrimPercent] = trimmedMeanForTiles(imageStack, evenIndices);

avData = struct();
avData.oddRows = single(oddRows);
avData.evenRows = single(evenRows);
avData.pooledRows = [];
avData.oddN = numel(oddIndices);
avData.evenN = numel(evenIndices);
avData.poolN = [];
avData.correctionType = "bruteAverageTrimmean";
avData.channel = tileStatistics.channelId(1);
avData.layer = tileStatistics.layer(1);
avData.section = tileStatistics.sectionNumber(1);
avData.details.oddTrimPercent = oddTrimPercent;
avData.details.evenTrimPercent = evenTrimPercent;
avData.details.floorRejectedAcquisitionIndices = ...
    tileStatistics.acquisitionIndex(selection.rejectedAtFloor);
avData.details.selection = selection;

summary = struct();
summary.sectionNumber = avData.section;
summary.channelId = avData.channel;
summary.layer = avData.layer;
summary.threshold = selection.threshold;
summary.bottomStd = selection.bottomStd;
summary.thresholdFallback = selection.usedFallback;
summary.thresholdReason = selection.thresholdReason;
summary.floorRejectedCount = selection.floorRejectedCount;
summary.retainedCount = selection.retainedCount;
summary.oddRetainedCount = avData.oddN;
summary.evenRetainedCount = avData.evenN;
summary.oddTrimPercent = oddTrimPercent;
summary.evenTrimPercent = evenTrimPercent;
end

function [averageImage, trimPercent] = trimmedMeanForTiles(stack, indices)
% Preserve StitchIt's per-section trim-percentage calculation.
trimPercent = round((2 / numel(indices)) * 100);
if trimPercent >= 100 || trimPercent <= 0 || isnan(trimPercent)
    trimPercent = 1;
end
averageImage = trimmean(stack(:, :, indices), trimPercent, 3);
end

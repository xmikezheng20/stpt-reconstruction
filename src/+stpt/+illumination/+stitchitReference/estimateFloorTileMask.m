function selection = estimateFloorTileMask(tileMeans, illuminationConfig)
%ESTIMATEFLOORTILEMASK Reproduce StitchIt's low detector-floor threshold.
%
% Adapted from StitchIt/code/preProcessTiles/private/writeTileStats.m at
% commit 383b9fbd5f0664bf232c897a87759d8da43b725c. The calculation is kept
% explicit so its conservative fallback (which rejects no tiles) is visible.
% This is not a tissue classifier: retained tiles may still contain only
% background.

tileMeans = double(tileMeans(:));
sortedMeans = sort(tileMeans);

% StitchIt characterizes the lowest five percent as a possible floor plateau.
bottomCount = max(1, round(numel(sortedMeans) * ...
    illuminationConfig.bottomFraction));
bottomMeans = sortedMeans(1:bottomCount);
bottomStd = std(bottomMeans);

if bottomStd > illuminationConfig.bottomStdLimit
    % StitchIt's fallback threshold equals the minimum. Because rejection uses
    % strict "<", this branch necessarily rejects zero tiles.
    threshold = sortedMeans(1);
    usedFallback = true;
    thresholdReason = "minimumFallback";
else
    cumulativeStd = zeros(size(sortedMeans));
    for i = 1:numel(sortedMeans)
        cumulativeStd(i) = std(sortedMeans(1:i));
    end
    plateau = find(cumulativeStd < illuminationConfig.prefixStdLimit);
    threshold = sortedMeans(plateau(end)) * ...
        illuminationConfig.thresholdScale;
    usedFallback = false;
    thresholdReason = "lowIntensityPlateau";
end

rejected = tileMeans < threshold;
selection = struct();
selection.threshold = threshold;
selection.rejectedAtFloor = rejected;
selection.retained = ~rejected;
selection.bottomCount = bottomCount;
selection.bottomStd = bottomStd;
selection.usedFallback = usedFallback;
selection.thresholdReason = thresholdReason;
selection.floorRejectedCount = nnz(rejected);
selection.retainedCount = nnz(~rejected);
selection.floorRejectedFraction = mean(rejected);
end

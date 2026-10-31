function [corrected, audit, diagnostics] = ...
        localTissueRatio(planes, parameters, supportMasks, tissue)
%LOCALTISSUERATIO Match deeper optical layers to the reference layer locally.
%
% Each non-reference layer k is multiplied by the gain field
%
%     T = G * (M .* Rref) ./ G * (M .* Rk)  on M, and 1 elsewhere,
%
% where R are block means on the estimation grid, M is tissue present and
% acquired in both layers (TISSUE comes from stage 2's tissue reference channel
% and is shared by all channels), and G is a Gaussian of windowSigmaUm. T is
% the ratio of the two layers' local mean brightness over shared tissue, and
% stays 1 where either layer has no signal within the window. It is upsampled
% bilinearly by exactly the block factor, so each grid value sits at the
% centre of its own block, and applied as a gain: zeros stay zero and tissue
% seen by only one layer is left as fused.

nLayers = numel(planes);
referenceLayer = parameters.referenceLayer;
imageSize = size(planes{referenceLayer});
sigma = parameters.windowSigmaUm ./ tissue.gridUm;
filterSize = 2 * ceil(3 * sigma) + 1;
windowArea = 2 * pi * prod(sigma);

reference = stpt.zillumination.blockMean(planes{referenceLayer}, tissue.block);
referenceCovered = stpt.zillumination.coveredBlocks( ...
    supportMasks{referenceLayer}, tissue.block, tissue.gridSize);

corrected = planes;
audit = repmat(emptyAudit(), nLayers, 1);
diagnostics = struct();
diagnostics.method = "localTissueRatio";
diagnostics.referenceLayer = referenceLayer;
diagnostics.estimationSizePixels = tissue.gridSize;
diagnostics.gaussianSigmaPixels = mean(sigma);
diagnostics.gainFields = cell(1, nLayers);
diagnostics.correctionApplied = false(1, nLayers);
diagnostics.correctionReason = strings(1, nLayers);

for layer = 1:nLayers
    started = tic;
    audit(layer).method = "localTissueRatio";
    audit(layer).referenceLayer = referenceLayer;
    audit(layer).preMean = mean(planes{layer}, "all");
    audit(layer).estimationHeightPixels = tissue.gridSize(1);
    audit(layer).estimationWidthPixels = tissue.gridSize(2);
    audit(layer).gaussianSigmaPixels = mean(sigma);

    if layer == referenceLayer
        [audit(layer), diagnostics] = recordIdentity(audit(layer), ...
            diagnostics, layer, "referenceLayer", toc(started));
        continue
    end

    target = stpt.zillumination.blockMean(planes{layer}, tissue.block);
    shared = tissue.layers{referenceLayer} & tissue.layers{layer} & ...
        referenceCovered & stpt.zillumination.coveredBlocks( ...
        supportMasks{layer}, tissue.block, tissue.gridSize);
    if nnz(shared) < windowArea
        [audit(layer), diagnostics] = recordIdentity(audit(layer), ...
            diagnostics, layer, "noCommonTissue", toc(started));
        continue
    end

    % Gaussian-weighted sums over shared tissue; the mask weight cancels in
    % their ratio, which is the ratio of the two local means. Spatial
    % filtering keeps a window without signal exactly zero.
    referenceSum = imgaussfilt(reference .* shared, sigma, ...
        "FilterSize", filterSize, "Padding", 0, "FilterDomain", "spatial");
    targetSum = imgaussfilt(target .* shared, sigma, ...
        "FilterSize", filterSize, "Padding", 0, "FilterDomain", "spatial");
    gain = ones(tissue.gridSize, "single");
    valid = shared & referenceSum > 0 & targetSum > 0;
    gain(valid) = referenceSum(valid) ./ targetSum(valid);

    % Exact block-factor enlargement, then crop the zero padding of blockMean.
    fullGain = imresize(gain, tissue.gridSize .* tissue.block, "bilinear");
    scaled = single(planes{layer}) .* ...
        fullGain(1:imageSize(1), 1:imageSize(2));
    scaled(~supportMasks{layer}) = 0;

    tissueGain = gain(shared);
    audit(layer).applied = true;
    audit(layer).reason = "";
    audit(layer).gainP01 = prctile(tissueGain, 1);
    audit(layer).gainMedian = median(tissueGain);
    audit(layer).gainP99 = prctile(tissueGain, 99);
    audit(layer).clippedHighPixels = nnz(scaled > 65535);
    corrected{layer} = uint16(round(min(max(scaled, 0), 65535)));
    audit(layer).postMean = mean(corrected{layer}, "all");
    audit(layer).correctionSeconds = toc(started);
    diagnostics.gainFields{layer} = gain;
    diagnostics.correctionApplied(layer) = true;
    diagnostics.correctionReason(layer) = "";
end
end

function [audit, diagnostics] = recordIdentity( ...
        audit, diagnostics, layer, reason, elapsedSeconds)
% Leave the fused plane exactly unchanged and record why.
audit.applied = false;
audit.reason = string(reason);
audit.postMean = audit.preMean;
audit.gainP01 = 1;
audit.gainMedian = 1;
audit.gainP99 = 1;
audit.correctionSeconds = elapsedSeconds;
diagnostics.correctionApplied(layer) = false;
diagnostics.correctionReason(layer) = string(reason);
end

function value = emptyAudit()
value = struct("method", "", "applied", false, ...
    "reason", "", ...
    "referenceLayer", nan, "preMean", nan, "postMean", nan, ...
    "gainP01", nan, "gainMedian", nan, "gainP99", nan, ...
    "estimationHeightPixels", nan, "estimationWidthPixels", nan, ...
    "gaussianSigmaPixels", nan, ...
    "clippedHighPixels", 0, ...
    "correctionSeconds", 0);
end

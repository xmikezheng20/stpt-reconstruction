function [corrected, audit, diagnostics] = ...
        stitchitSmoothRatio(planes, parameters, supportMasks)
%STITCHITSMOOTHRATIO Match deeper optical layers to a smoothed reference.
%
% This is a close port of the numerical core in StitchIt's
% correctZilluminationInDirectory. The gain for every non-reference layer is
% the ratio of broadly smoothed, reduced-resolution reference and target planes.

nLayers = numel(planes);
referenceLayer = parameters.referenceLayer;
imageSize = size(planes{referenceLayer});
targetSize = estimationSize(imageSize, parameters.maxEstimationPixels);

% StitchIt defines the Gaussian scale from a fixed fraction of the reduced
% image area. Keep the same formula and default zero-padded imfilter behavior.
nEstimationPixels = prod(targetSize);
sigma = round(2 * sqrt( ...
    nEstimationPixels * parameters.filterAreaFraction / pi));
gaussian = fspecial("gaussian", sigma * 3, sigma);
completeSupport = all(cellfun(@(mask) all(mask(:)), supportMasks));
if completeSupport
    referenceStarted = tic;
    referenceField = smoothReduced( ...
        planes{referenceLayer}, targetSize, gaussian);
    referenceSeconds = toc(referenceStarted);
else
    referenceField = [];
    referenceSeconds = 0;
end

corrected = planes;
audit = repmat(emptyAudit(), nLayers, 1);
diagnostics = struct();
diagnostics.method = "stitchitSmoothRatio";
diagnostics.referenceLayer = referenceLayer;
diagnostics.estimationSizePixels = targetSize;
diagnostics.gaussianSigmaPixels = sigma;
diagnostics.gainFields = cell(1, nLayers);
diagnostics.correctionApplied = false(1, nLayers);
diagnostics.correctionReason = strings(1, nLayers);

for layer = 1:nLayers
    preMean = mean(planes{layer}, "all");
    audit(layer).method = "stitchitSmoothRatio";
    audit(layer).referenceLayer = referenceLayer;
    audit(layer).preMean = preMean;
    audit(layer).estimationHeightPixels = targetSize(1);
    audit(layer).estimationWidthPixels = targetSize(2);
    audit(layer).gaussianSigmaPixels = sigma;

    if layer == referenceLayer
        audit(layer).reason = "referenceLayer";
        audit(layer).postMean = preMean;
        audit(layer).gainP01 = 1;
        audit(layer).gainMedian = 1;
        audit(layer).gainP99 = 1;
        audit(layer).correctionSeconds = referenceSeconds;
        diagnostics.correctionReason(layer) = "referenceLayer";
        continue
    end

    started = tic;
    if completeSupport
        layerReferenceField = referenceField;
        targetField = smoothReduced(planes{layer}, targetSize, gaussian);
    else
        % Use identical valid support in both smooth fields. Zeroing the common
        % missing region in numerator and denominator excludes that absent
        % observation without treating it as true darkness; the common local
        % mask normalization would cancel from their ratio.
        commonSupport = supportMasks{referenceLayer} & supportMasks{layer};
        if ~any(commonSupport(:))
            [audit(layer), diagnostics] = recordIdentityFallback( ...
                audit(layer), diagnostics, layer, planes{layer}, ...
                "noCommonSupport", toc(started));
            continue
        end
        referenceForEstimation = planes{referenceLayer};
        targetForEstimation = planes{layer};
        referenceForEstimation(~commonSupport) = 0;
        targetForEstimation(~commonSupport) = 0;
        layerReferenceField = smoothReduced( ...
            referenceForEstimation, targetSize, gaussian);
        targetField = smoothReduced( ...
            targetForEstimation, targetSize, gaussian);
    end

    fieldReason = invalidFieldReason(layerReferenceField, targetField);
    if strlength(fieldReason) > 0
        [audit(layer), diagnostics] = recordIdentityFallback( ...
            audit(layer), diagnostics, layer, planes{layer}, ...
            fieldReason, toc(started));
        continue
    end

    gain = layerReferenceField ./ targetField;
    if any(~isfinite(gain(:))) || any(gain(:) <= 0)
        [audit(layer), diagnostics] = recordIdentityFallback( ...
            audit(layer), diagnostics, layer, planes{layer}, ...
            "invalidGainField", toc(started));
        continue
    end

    gainPercentiles = prctile(double(gain(:)), [1, 50, 99]);
    fullGain = imresize(gain, "OutputSize", imageSize);
    if any(~isfinite(fullGain(:))) || any(fullGain(:) <= 0)
        [audit(layer), diagnostics] = recordIdentityFallback( ...
            audit(layer), diagnostics, layer, planes{layer}, ...
            "invalidUpsampledGain", toc(started));
        continue
    end
    scaled = single(planes{layer}) .* fullGain;
    scaled(~supportMasks{layer}) = 0;

    audit(layer).applied = true;
    audit(layer).reason = "";
    audit(layer).gainP01 = gainPercentiles(1);
    audit(layer).gainMedian = gainPercentiles(2);
    audit(layer).gainP99 = gainPercentiles(3);
    audit(layer).clippedHighPixels = nnz(scaled > 65535);

    scaled = min(max(scaled, 0), 65535);
    corrected{layer} = uint16(round(scaled));
    audit(layer).postMean = mean(corrected{layer}, "all");
    audit(layer).correctionSeconds = toc(started);
    diagnostics.gainFields{layer} = gain;
    diagnostics.correctionApplied(layer) = true;
end
end

function reason = invalidFieldReason(referenceField, targetField)
% Distinguish undefined correction data from structural input errors.
if any(~isfinite(referenceField(:))) || any(~isfinite(targetField(:)))
    reason = "nonfiniteSmoothedField";
elseif any(referenceField(:) <= 0) || any(targetField(:) <= 0)
    reason = "nonpositiveSmoothedField";
else
    reason = "";
end
end

function [audit, diagnostics] = recordIdentityFallback( ...
        audit, diagnostics, layer, plane, reason, elapsedSeconds)
% Preserve the fused plane exactly when its multiplicative ratio is undefined.
audit.applied = false;
audit.reason = string(reason);
audit.postMean = mean(plane, "all");
audit.gainP01 = 1;
audit.gainMedian = 1;
audit.gainP99 = 1;
audit.correctionSeconds = elapsedSeconds;
diagnostics.correctionApplied(layer) = false;
diagnostics.correctionReason(layer) = string(reason);
end

function targetSize = estimationSize(imageSize, maxPixels)
% Preserve aspect ratio while reproducing StitchIt's maximum-pixel rule.
imageSize = imageSize(1:2);
nPixels = prod(imageSize);
if nPixels > maxPixels
    reduction = nPixels / maxPixels;
    targetSize = floor(imageSize / sqrt(reduction));
else
    targetSize = imageSize;
end
end

function field = smoothReduced(image, targetSize, gaussian)
reduced = imresize(single(image), "OutputSize", targetSize);
field = single(imfilter(reduced, gaussian));
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

function signature = buildSignature(datasetIndex, model, cfg, sections)
%BUILDSIGNATURE Record the scientific inputs to a reconstruction stage.

signature = struct();
signature.experimentId = string(cfg.experiment.id);
signature.rawRoot = string(datasetIndex.rawRoot);
signature.configuredProcessingSections = datasetIndex.processingSections;
signature.reconstructionSections = sections(:)';
signature.channelIds = [datasetIndex.channels.id];
signature.channelNames = string({datasetIndex.channels.name});
signature.missingTiles = datasetIndex.missingTiles;
signature.gridSize = datasetIndex.geometry.gridSize;
signature.tileSizePixels = datasetIndex.geometry.tileSizePixels;
signature.retainedTileSizePixels = ...
    datasetIndex.geometry.retainedTileSizePixels;
signature.targetStepPixels = datasetIndex.geometry.targetStepPixels;
signature.canvasSizePixels = datasetIndex.geometry.nominalCanvasSizePixels;
signature.cropPixels = datasetIndex.geometry.cropPixels;
signature.tileOrientation = string(cfg.preprocessing.tileOrientation);
signature.modelCreated = string(model.created);
signature.modelMethod = string(model.method);
signature.modelRowMode = string(model.rowMode);
signature.modelTrainingSections = model.trainingSections;
signature.xyIlluminationApplied = arrayfun( ...
    @(channel) [channel.layers.correctionApplied], ...
    model.channels, "UniformOutput", false);
signature.xyIlluminationReason = arrayfun( ...
    @(channel) string({channel.layers.correctionReason}), ...
    model.channels, "UniformOutput", false);
signature.fusionMode = string(cfg.fusion.mode);
if strcmpi(cfg.fusion.mode, "fijiBlend")
    signature.blendingMethod = string(cfg.fusion.blending.method);
    signature.blendingAlpha = cfg.fusion.blending.alpha;
end
signature.zIlluminationMethod = string(cfg.zIllumination.method);
signature.zReferenceLayer = cfg.zIllumination.referenceLayer;
signature.zMaxEstimationPixels = ...
    cfg.zIllumination.maxEstimationPixels;
signature.zFilterAreaFraction = ...
    cfg.zIllumination.filterAreaFraction;
signature.outputClass = "uint16";
signature.compression = lower(string(cfg.fusion.compression));
signature.finalOrientation = "none";
end

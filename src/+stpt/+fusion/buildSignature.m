function signature = buildSignature(datasetIndex, model, cfg)
%BUILDSIGNATURE Record the inputs that make fused planes reusable.

signature = struct();
signature.schemaVersion = 1;
signature.experimentId = string(cfg.experiment.id);
signature.rawRoot = string(datasetIndex.rawRoot);
signature.processingSections = datasetIndex.processingSections;
signature.channelIds = [datasetIndex.channels.id];
signature.channelNames = string({datasetIndex.channels.name});
signature.gridSize = datasetIndex.geometry.gridSize;
signature.tileSizePixels = datasetIndex.geometry.tileSizePixels;
signature.retainedTileSizePixels = ...
    datasetIndex.geometry.retainedTileSizePixels;
signature.targetStepPixels = datasetIndex.geometry.targetStepPixels;
signature.canvasSizePixels = datasetIndex.geometry.nominalCanvasSizePixels;
signature.cropPixels = datasetIndex.geometry.cropPixels;
signature.tileOrientation = string(cfg.preprocessing.tileOrientation);
signature.modelSchemaVersion = model.schemaVersion;
signature.modelCreated = string(model.created);
signature.modelMethod = string(model.method);
signature.modelTrainingSections = model.trainingSections;
signature.fusionMode = string(cfg.fusion.mode);
signature.outputClass = "uint16";
signature.compression = lower(string(cfg.fusion.compression));
signature.finalOrientation = "none";
end

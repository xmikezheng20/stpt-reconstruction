function signature = buildReconstructionStepSignature( ...
        datasetIndex, model, cfg, sectionNumber)
%BUILDRECONSTRUCTIONSTEPSIGNATURE Record inputs to the three-step pilot QC.

signature = struct();
signature.schemaVersion = 1;
signature.sectionNumber = sectionNumber;
signature.processingSections = datasetIndex.processingSections;
signature.channelIds = [datasetIndex.channels.id];
signature.channelNames = string({datasetIndex.channels.name});
signature.layersPerSection = datasetIndex.geometry.layersPerSection;
signature.gridSize = datasetIndex.geometry.gridSize;
signature.tileSizePixels = datasetIndex.geometry.tileSizePixels;
signature.retainedTileSizePixels = ...
    datasetIndex.geometry.retainedTileSizePixels;
signature.targetStepPixels = datasetIndex.geometry.targetStepPixels;
signature.cropPixels = datasetIndex.geometry.cropPixels;
signature.tileOrientation = string(cfg.preprocessing.tileOrientation);
signature.modelSchemaVersion = model.schemaVersion;
signature.modelCreated = string(model.created);
signature.modelMethod = string(model.method);
signature.modelTrainingSections = model.trainingSections;
signature.variants = [ ...
    "01_no_correction_no_blend", ...
    "02_xy_correction_no_blend", ...
    "03_xy_correction_fiji_blend"];
signature.blendingMethod = string(cfg.fusion.blending.method);
signature.blendingAlpha = cfg.fusion.blending.alpha;
signature.outputClass = "uint16";
signature.compression = lower(string(cfg.fusion.compression));
signature.qcPreviewScale = cfg.fusion.qcPreviewScale;
end

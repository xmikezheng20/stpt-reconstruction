function cfg = config_260812_MikeZ_PO431109_F_01_production()
%CONFIG_260812_MIKEZ_PO431109_F_01_PRODUCTION Minimal standalone production config.
%
% Copy this file for a standard dataset, then update the experiment paths,
% channels, acquisition geometry, and processing range before running it.

% Dataset identity and native channel roots.
cfg.experiment.id = "260812_MikeZ_PO431109_F_01";
cfg.experiment.dataPrefix = "MikeZ_PO431109_F_01";
cfg.paths.rawRoot = ...
    "/mnt/data/xizheng/Mike/stpt/260812_MikeZ_PO431109_F_01";
cfg.paths.outputRoot = fullfile(cfg.paths.rawRoot, "processed", ...
    "reconstruction");
cfg.channels = struct( ...
    "id",        {1, 2}, ...
    "name",      {"red", "green"}, ...
    "directory", {cfg.experiment.dataPrefix + "_ch1", ...
                  cfg.experiment.dataPrefix + "_ch2"}, ...
    "fileCode",  {"01", "02"});

% Acquisition geometry to verify for every dataset.
cfg.acquisition.metadataChannel = 1;
cfg.acquisition.sectionCount = 300;
cfg.acquisition.layersPerSection = 2;
cfg.acquisition.planeSpacingUm = 25;
cfg.acquisition.pixelSizeUm = [1, 1];        % [x, y]
cfg.acquisition.tileSizePixels = [832, 832]; % [width, height]
cfg.acquisition.gridSize = [14, 18];         % [tiles x, tiles y]

% Native TissueCyte geometry established for this acquisition system.
cfg.stitching.positionSource = "target";
cfg.stitching.targetStepUm = [700, 700];
cfg.preprocessing.cropPixels = [15, 15, 15, 15];
cfg.preprocessing.tileOrientation = "rot90cw";

% Use the full planned acquisition unless the complete range is shorter.
cfg.processing.sectionStart = 1;
cfg.processing.sectionStop = cfg.acquisition.sectionCount;
cfg.sampling.illuminationEveryNSections = 10;
cfg.sampling.qcEveryNSections = 50;

% Accepted reconstruction algorithms and parameters.
cfg.illumination.method = "tissueOtsu";
cfg.illumination.rowMode = "pool";
cfg.illumination.tissueReferenceChannel = 2;
cfg.illumination.tissueOtsu.templateTrimPercent = 10;

cfg.fusion.mode = "fijiBlend";
cfg.fusion.compression = "lzw";
cfg.fusion.qcPreviewScale = 0.10;
cfg.fusion.blending.method = "fijiDistance";
cfg.fusion.blending.alpha = 1.5;

cfg.zIllumination.method = "stitchitSmoothRatio";
cfg.zIllumination.referenceLayer = 1;
cfg.zIllumination.maxEstimationPixels = 1.5e6;
cfg.zIllumination.filterAreaFraction = 0.01;

cfg.downsampling.outputVoxelSizeUm = [25, 25, 25]; % [z, y, x]
cfg.downsampling.compression = "lzw";

% Routine production runs all stages with four section workers.
cfg.execution.stopAfter = "downsampling";
cfg.execution.reconstructionWorkers = 4;
cfg.execution.overwrite = false;
end

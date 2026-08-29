function cfg = config_260812_MikeZ_PO431109_F_01()
%CONFIG_260812_MIKEZ_PO431109_F_01 Configuration for this STPT experiment.
%
% Acquisition geometry is stated explicitly here so that a reconstruction is
% auditable without relying on hidden defaults. Mosaic metadata is parsed in
% Stage 1 and compared with these values.

cfg.experiment.id = "260812_MikeZ_PO431109_F_01";
cfg.experiment.dataPrefix = "MikeZ_PO431109_F_01";

cfg.paths.rawRoot = ...
    "/mnt/data/xizheng/Mike/stpt/260812_MikeZ_PO431109_F_01";
cfg.paths.outputRoot = fullfile(cfg.paths.rawRoot, "processed", ...
    "reconstruction");

% Explicit channel-to-root mapping. The absent blue channel (ch3) is not part
% of the reconstruction, even though the acquisition metadata reports three
% configured detector channels.
cfg.channels = struct( ...
    "id",        {1, 2}, ...
    "name",      {"red", "green"}, ...
    "directory", {cfg.experiment.dataPrefix + "_ch1", ...
                  cfg.experiment.dataPrefix + "_ch2"}, ...
    "fileCode",  {"01", "02"});

cfg.acquisition.metadataChannel = 1;
cfg.acquisition.sectionCount = 300; % Planned count recorded in Mosaic metadata
cfg.acquisition.layersPerSection = 2;
cfg.acquisition.planeSpacingUm = 25;
cfg.acquisition.pixelSizeUm = [1, 1];       % [x, y]
cfg.acquisition.tileSizePixels = [832, 832]; % [width, height]
cfg.acquisition.gridSize = [14, 18];         % [tiles x, tiles y]

% Use the recorded target movement (700 um) as the nominal placement step.
% Actual stage positions are retained for QC, but do not drive placement.
cfg.stitching.positionSource = "target";
cfg.stitching.targetStepUm = [700, 700];     % [x, y]

% Retain OpenSTP's established symmetric 15-pixel crop for this microscope.
% StitchIt's proportional default would round to 18 pixels for an 832-pixel
% tile. Cropping changes retained support, but does not define tile placement.
cfg.preprocessing.cropPixels = [15, 15, 15, 15]; % [left right top bottom]

% Native TissueCyte TIFF axes do not match the target-stage grid. The legacy
% OpenSTP conversion used fliplr(image'), which is a 90-degree clockwise turn.
% Illumination is fitted/applied in raw orientation before this transform.
cfg.preprocessing.tileOrientation = "rot90cw";

% Process the complete planned acquisition by default. For a partial dataset,
% explicitly move sectionStop back to the last section known to be complete.
cfg.processing.sectionStart = 1;
cfg.processing.sectionStop = cfg.acquisition.sectionCount;

% Illumination fitting uses a denser volume sample than diagnostic plots and
% the later reconstruction pilot. Final sections are not appended to either
% sequence.
cfg.sampling.illuminationEveryNSections = 10;
cfg.sampling.qcEveryNSections = 50;

% The tissue-aware method uses one global log-Otsu threshold on cropped green
% tiles to select tissue-bearing locations.
cfg.illumination.method = "tissueOtsu";
% A pooled model applies one correction field to every scan row. Set this to
% "split" only when odd/even acquisition directions differ materially.
cfg.illumination.rowMode = "pool";
cfg.illumination.tissueReferenceChannel = 2;

% Direct pooled template estimator used after the tissue-selection checkpoint.
cfg.illumination.tissueOtsu.templateTrimPercent = 10;

% Parameters used only by the StitchIt-reference algorithm.
cfg.illumination.stitchitReference.bottomFraction = 0.05;
cfg.illumination.stitchitReference.bottomStdLimit = 0.6;
cfg.illumination.stitchitReference.prefixStdLimit = 0.085;
cfg.illumination.stitchitReference.thresholdScale = 1.01;
cfg.illumination.stitchitReference.maxRejectedFraction = 0.85;
cfg.illumination.stitchitReference.minimumTilesPerParity = 2;
cfg.illumination.stitchitReference.acrossSectionTrimPercent = 10;
% Reconstruction uses the same scientific and file-writing settings in pilot
% and production. The pilot section is derived from the processing range.
cfg.fusion.mode = "fijiBlend";
cfg.fusion.compression = "lzw";
cfg.fusion.qcPreviewScale = 0.10;
cfg.fusion.blending.method = "fijiDistance";
cfg.fusion.blending.alpha = 1.5;

% Match deeper optical layers to the broadly smoothed first layer after fusion.
% These are StitchIt's defaults. For this 1 um/pixel mosaic, 0.01 gives a
% Gaussian sigma of about 1.26 mm; maxEstimationPixels controls computation.
cfg.zIllumination.method = "stitchitSmoothRatio";
cfg.zIllumination.referenceLayer = 1;
cfg.zIllumination.maxEstimationPixels = 1.5e6;
cfg.zIllumination.filterAreaFraction = 0.01;

% Stage 4 resamples the ordered final planes to one compact registration
% volume per channel. Voxel vectors use [z, y, x] order throughout.
cfg.downsampling.outputVoxelSizeUm = [25, 25, 25];
cfg.downsampling.compression = "lzw";

% Reconstruct the ordered additions of XY correction, blending, and z correction.
cfg.qc.comparisons.reconstructionSteps = true;

% Keep the validated center-section pilot as the default during development.
% Use "reconstructionProduction" to reconstruct cfg.processing.sections.
cfg.execution.stopAfter = "reconstructionPilot";
cfg.execution.overwrite = false;
end

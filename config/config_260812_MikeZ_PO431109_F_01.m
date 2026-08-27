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
cfg.acquisition.sectionCount = 300;
cfg.acquisition.layersPerSection = 2;
cfg.acquisition.sectionThicknessUm = 25;
cfg.acquisition.pixelSizeUm = [1, 1];       % [x, y]
cfg.acquisition.tileSizePixels = [832, 832]; % [width, height]
cfg.acquisition.gridSize = [14, 18];         % [tiles x, tiles y]

% Use the recorded target movement (700 um) as the nominal placement step.
% Actual stage positions are retained for QC, but do not drive placement.
cfg.stitching.positionSource = "target";
cfg.stitching.targetStepUm = [700, 700];     % [x, y]

% Experiment-specific starting value for later stitching tests. StitchIt's
% proportional default would round to 18 pixels for an 832-pixel tile; our
% explicit 15-pixel value must therefore be validated on this TissueCyte data.
% Cropping changes retained support, but does not define tile placement.
cfg.preprocessing.cropPixels = [15, 15, 15, 15]; % [left right top bottom]

% Shared illumination interface. Green is the default structural reference for
% future tissue selection, but the StitchIt-reference method does not use it.
cfg.illumination.method = "stitchitReference";
cfg.illumination.rowMode = "split";
cfg.illumination.tissueReferenceChannel = 2;
cfg.illumination.trainingSections = [1, 51, 101, 151, 201, 251];

% Parameters used only by the StitchIt-reference algorithm.
cfg.illumination.stitchitReference.bottomFraction = 0.05;
cfg.illumination.stitchitReference.bottomStdLimit = 0.6;
cfg.illumination.stitchitReference.prefixStdLimit = 0.085;
cfg.illumination.stitchitReference.thresholdScale = 1.01;
cfg.illumination.stitchitReference.maxRejectedFraction = 0.85;
cfg.illumination.stitchitReference.minimumTilesPerParity = 2;
cfg.illumination.stitchitReference.acrossSectionTrimPercent = 10;
cfg.fusion.mode = "overwrite";

cfg.qc.representativeSections = [1, 51, 101, 151, 201, 251];

% Development checkpoint: stop after the representative-section illumination
% pilot. Completed Stage 1 output is loaded as a prerequisite, not regenerated.
cfg.execution.stopAfter = "illuminationPilot";
cfg.execution.overwrite = false;
end

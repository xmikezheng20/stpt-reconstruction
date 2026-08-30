# stpt-reconstruction

A lightweight MATLAB pipeline for reconstructing native TissueCyte-style STPT datasets using illumination correction and stitching algorithms from StitchIt.

The motivation is to provide a small, auditable bridge from the native
OpenSTP/TissueCyte acquisition layout used by our microscope to StitchIt's
offline reconstruction algorithms, without adopting the full BakingTray
acquisition workflow or repackaging the raw TIFFs.

The pipeline reads the native TIFF and Mosaic files in place and writes every
derived artifact under the experiment's `processed/reconstruction` directory.
Raw acquisition files are never renamed or rewritten.

## Implemented stages

Stage 1 builds and validates the requested dataset index. It parses acquisition
metadata, maps each TIFF to section/layer/tile/channel coordinates, reconstructs
the commanded 14-by-18 scan grid, and writes auditable tables and QC plots. The
default range is the complete planned acquisition, but an explicit start/stop
range can exclude an incomplete acquisition tail.

Stage 2 estimates illumination on regularly sampled sections. The default
`tissueOtsu` method pools cropped green-tile means, applies one binary Otsu
threshold to `log(1 + mean)`, and records the resulting physical tile mask. It
then directly pools the selected locations across sections to fit odd/even
illumination templates for each channel and layer. By default, their
count-weighted pooled field supplies one correction for all tile rows; `split`
remains available when odd/even scan directions differ materially. The
estimator uses a 10% pixelwise trimmed mean, zero additive offset, and StitchIt's
median-normalized gain construction. It does not write corrected TIFFs or
perform stitching.

For auditability, Stage 2 retains separate selection and model subdirectories,
but the master runner executes them as one operational stage. The optional
`stitchitReference` method remains available as a detector-floor baseline; its
retained tiles are not a tissue classification.

Illumination fitting is method-specific, but every method returns the same cropped
offset-and-gain model. `fitModel` dispatches fitting, `validateModel` enforces the
model contract, and `applyModel` applies the clear pointwise calculation
`(croppedRaw - offset) .* gain`. Green/ch2 is the configurable tissue-reference
channel for `tissueOtsu`; the optional StitchIt-reference method does not use
tissue classification.

Stage 3 provides independent pilot and production targets through the same
section-level worker. The pilot reconstructs the section at the center of the
configured processing range; production reconstructs every requested section.
Both stream native tiles, apply crop and illumination correction in raw
orientation, rotate each corrected tile 90 degrees clockwise to match the
target-stage axes, and place retained
802-by-802 tiles at the recorded 700-pixel target step. This explicit transform
reproduces OpenSTP's `fliplr(image')`; no final mosaic transform is applied.
Overlapping corrected tiles are combined with OpenSTP's Fiji-style normalized
distance weights using `alpha=1.5`. The four channel/layer planes are canonical
uint16 TIFFs with lossless LZW compression; no corrected tile intermediates are
made. After fusion, deeper optical layers are matched to the broadly smoothed
first layer using StitchIt's spatial-ratio z-illumination correction. All layers
of one physical section/channel are processed together, and only final
z-corrected TIFFs are written. A one-layer acquisition passes through unchanged.

The pilot and production reconstruction share the same geometry, plane
fusion, TIFF writer, and manifest schema. They intentionally use independent
output trees: the pilot is a small validation product, not partial production
output. Production can therefore begin from one unambiguous clean stage after
the pilot settings have been accepted.

Production dispatches complete physical sections with
`cfg.execution.reconstructionWorkers`; the supplied production config uses four
local process workers. Each worker still handles all channels and optical layers
of its section, so z correction remains a section-local operation. The pilot is
one section and therefore runs serially. Parallel scheduling is absent from the
scientific signature and published manifest order, and a failed production stage
is discarded and rerun in full rather than resumed section by section.

Production writes only canonical final TIFFs under
`03_reconstruction/production/stitched`. Minimal QC reads the published TIFFs
at `cfg.sampling.qcSections` using one fixed display range per channel and plots
the z-gain percentile trend across the complete volume. It does not run pilot
comparisons or retain full gain fields.

Stage 4 adapts the completed production manifest to one ordered plane series
per channel by sorting physical section first and optical layer second. It then
resamples every channel with an explicit separable calculation: bicubic,
antialiased XY resizing is applied to each final mosaic, followed by bicubic,
antialiased z resizing through the reduced YZ slices. The intermediate volume
is single precision and remains in RAM; uint16 rounding and saturation occur
once, when the final lossless LZW multipage TIFF is written. The default
`[z,y,x]` voxel change is `[25,1,1]` to `[25,25,25]` um, producing a
600-by-508-by-396 volume for this dataset without a z interpolation pass.
Requested and realized voxel sizes are both recorded because integer output
dimensions can make them differ slightly. Central XY, XZ, and YZ sections
provide compact full-volume QC.

The optional `cfg.qc.comparisons.reconstructionSteps` flag independently
reconstructs four versions of every pilot channel/layer plane: no correction
with overwrite, XY correction with overwrite, XY correction with Fiji-style
blending, and the complete XY-corrected/Fiji-blended/z-corrected result. All four
use the same crop, model-application interface, tile orientation, section
processor, and lossless writer. Full-resolution TIFFs, a combined manifest, a
complete-field overview, native-resolution junctions, and z-gain fields are
kept together under
`03_reconstruction/pilot/qc/comparisons/reconstruction_steps`.
Comparison variants are never copied from or linked to canonical output.

Fiji blending follows OpenSTP's `fusionMethod=3`: each corrected tile is
weighted by `((dx+1)*(dy+1)+1)^alpha`, accumulated on the recorded target grid,
and divided by the accumulated weights. The current `alpha=1.5` matches
OpenSTP. The common weight image is scaled to a maximum of one before
single-precision accumulation; this global scale cancels exactly in the
normalized result. Clipping and uint16 conversion happen only after blending.

The comprehensive experiment config exposes every scientific and QC decision
and defaults to the center-section development pilot:

```matlab
addpath('config');
runStptReconstruction(config_260812_MikeZ_PO431109_F_01());
```

Routine production uses a separate, deliberately concise standalone config. It
contains the accepted active algorithms, selects four workers, and runs through
the final downsampling stage:

```matlab
addpath('config');
runStptReconstruction(config_260812_MikeZ_PO431109_F_01_production());
```

The production file is intended to be copied for each standard dataset and then
edited directly: update paths and channels, verify the section range and major
acquisition geometry, and adjust an active algorithm parameter only when needed.
The comprehensive config remains an independent experimental version with
additional alternatives and explanatory context. There is no config inheritance
or hidden defaults between them. The master runner builds absent prerequisites
and then runs production reconstruction and downsampling; a pilot is never a
production prerequisite.

To run production without running the pilot:

```matlab
cfg = config_260812_MikeZ_PO431109_F_01_production();
cfg.execution.stopAfter = "reconstructionProduction";
runStptReconstruction(cfg);
```

To load the completed production reconstruction and write the downsampled
channel volumes:

```matlab
runStptReconstruction(config_260812_MikeZ_PO431109_F_01_production());
```

Computation and visualization have independent regular samples. With
`illuminationEveryNSections = 10`, Stage 2 fitting uses sections
`1, 11, ..., 291`; with `qcEveryNSections = 50`, Stage 1/2 plots use
`1, 51, 101, 151, 201, 251`. Final sections are not appended automatically.
The reconstruction pilot section is
`round((sectionStart + sectionStop)/2)`, which is
section 151 for the default 1:300 range. Production uses the same every-50
sequence for compact final-volume QC.

The planned metadata count remains `cfg.acquisition.sectionCount`. To process
only a complete prefix or subset, override the reconstruction range explicitly:

```matlab
cfg = config_260812_MikeZ_PO431109_F_01_production();
cfg.processing.sectionStart = 1;
cfg.processing.sectionStop = 260;
runStptReconstruction(cfg);
```

Sections outside this range are ignored. Every requested section must still be
complete and present in every configured channel.

Completed scientific stages may be loaded as prerequisites. Incomplete stage
directories are disposable and are removed before that stage is rerun from the
beginning; there is no plane-level resume or recovery state. A completed
requested stage remains protected from accidental replacement. Set
`cfg.execution.overwrite = true` to remove and intentionally rerun that complete
terminal stage. When the tissue-Otsu model is requested and its completed
selection checkpoint is absent, the master runner builds that prerequisite
first. A completed illumination model is reused only when its training sample,
QC sample, crop, row mode, and selected estimator parameters match the current
configuration. Parallel production follows the same rule: workers write unique
section files, but there are no per-section completion markers or resume logic.

To stop after Stage 1:

```matlab
cfg = config_260812_MikeZ_PO431109_F_01();
cfg.execution.stopAfter = "index";
runStptReconstruction(cfg);
```

The comprehensive experiment config stops after the Stage 3 reconstruction
pilot with one worker; the production config stops after downsampling with four
workers. The terminal names are `reconstructionPilot`,
`reconstructionProduction`, and `downsampling`. Tissue
selection is stored under `02_illumination/tissue_otsu/01_selection`; the fitted
model is stored under `02_illumination/tissue_otsu/02_model`; canonical pilot
planes and QC are stored under `03_reconstruction/pilot`. Neither Stage 2
substep writes corrected TIFFs. The optional StitchIt-reference model uses the
parallel path `02_illumination/stitchit_reference/02_model`. Production planes,
manifest, summary, and minimal QC are stored under
`03_reconstruction/production`. Downsampled channel volumes, their manifest,
summary, and orthogonal QC are stored under `04_downsampling`.

## Code organization

The package is divided by responsibility:

| Package | Responsibility |
| --- | --- |
| `stpt.io` | Parse native Mosaic files, resolve indexed TIFF paths, and load individual tiles or tile stacks. |
| `stpt.index` | Build the read-only dataset index and write Stage 1 QC. |
| `stpt.illumination` | Define the shared fit, validation, and correction-model interface. |
| `stpt.illumination.stitchitReference` | Implement only the StitchIt-reference estimation algorithm and its QC. |
| `stpt.illumination.tissueOtsu` | Select tissue-bearing tiles with green-channel log-Otsu and fit direct pooled templates. |
| `stpt.preprocessing` | Apply the explicit native-TIFF-to-target-grid tile orientation after illumination correction. |
| `stpt.fusion` | Compute target-grid geometry, prepare native tiles, and dispatch overwrite or Fiji-style mosaic fusion. |
| `stpt.zillumination` | Apply the shared within-section optical-layer interface and StitchIt smooth-ratio correction. |
| `stpt.reconstruction` | Process complete physical sections, dispatch production serially or in parallel, apply z correction, publish final TIFFs and manifests, and generate pilot or production QC. |
| `stpt.resampling` | Resample an ordered TIFF series with the generic single-precision XY-first, z-second calculation. |
| `stpt.downsampling` | Adapt the production manifest to ordered channel series, publish compact multipage volumes, and write Stage 4 QC. |

The master runner owns stage order and derived-output directories; scientific
algorithms do not rename or reorganize raw files.

## Relationship to StitchIt

This repository has no runtime dependency on StitchIt and never calls a
`stitchit.*` function. The reference snapshot below identifies the historical
source of adapted algorithms; the local repository commit remains the executable
runtime provenance.

StitchIt source reference: `383b9fbd5f0664bf232c897a87759d8da43b725c`

| Local function | StitchIt source | Relationship and deviations |
| --- | --- | --- |
| `stpt.io.loadTileStack` | `stitching/tileLoad.m` | Independent native-TissueCyte loader; no BakingTray, INI, or multipage-stack assumptions. |
| `stitchitReference.estimateFloorTileMask` | `preProcessTiles/private/writeTileStats.m` | Adapted detector-floor calculation; exposes the conservative fallback and does not interpret retained tiles as tissue. |
| `stitchitReference.estimateSectionAverage` | `preProcessTiles/private/calcAverageMatFiles.m` | Close port of rejection, row-parity splitting, and per-section trimmed means; adds post-rejection guards and omits unused 1,000-bin histograms. |
| `stitchitReference.collateSectionAverages` | `stitching/collateAverageImages.m` | Close port of the 10% across-section trimmed means for odd/even rows. |
| `stitchitReference.fit` | `+stitchit/+tileload/illuminationCorrector.m`, `+stitchit/+tools/divideByImage.m` | Preserves median-normalized gain on retained pixels and emits the shared cropped model; reference offset remains zero. |
| `stitchitReference.writeQC` | None | Independent method-specific diagnostic plots and tables. |
| `tissueOtsu.classifyTiles` | None | Independent method: one global binary Otsu threshold on cropped green-tile log means. |
| `tissueOtsu.writeQC` | None | Independent selection tables, histogram, and spatial tile maps. |
| `tissueOtsu.estimateTemplate` | None | Independent direct 10% trimmed mean across selected tiles; no within-section averages. |
| `tissueOtsu.fit` | None | Reuses the completed selection and assembles all channel/layer/parity templates. |
| `stpt.fusion.computeGeometry` | `stitching/gridPos2Pixels.m`, `utils/stagePos2PixelPos.m` | Independent target-grid implementation using the indexed 700-pixel commands; overlap is derived from retained support. |
| `stpt.preprocessing.applyTileOrientation` | OpenSTP `readSectionParamFile3D.m` | Reproduces `fliplr(image')` as an explicit 90-degree clockwise turn after raw-orientation illumination correction. |
| `stpt.fusion.fuseOverwritePlane` | `stitching/stitcher.m` | Adapts reverse-acquisition, last-tile-wins overwrite; omits BakingTray auto-ROI and marker values. |
| `stpt.fusion.fuseFijiBlendPlane` | OpenSTP `stitchMosaic.c`, `calcWeightImageAsInFiji.m` | Implements normalized Fiji-style distance weighting on our recorded target-grid placement; uses normalized single-precision weights and blockwise final casting. |
| `stpt.zillumination.stitchitSmoothRatio` | `+stitchit/+artifactCorrection/correctZilluminationInDirectory.m` | Close port of the reduced-resolution broad Gaussian and reference/target ratio; omits StitchIt's directory parsing, overwrite behavior, parallel pool logic, and uncompressed writer. |
| `stpt.reconstruction.writePilotQC` | `stitcher.m` chessboard mode (concept only) | Independent final center-section previews, channel overlay, and lightweight red/green tile checkerboard. |
| `stpt.reconstruction.writeProductionQC` | None | Independent fixed-scale representative sections, manifest-based z-gain trends, and production summary. |
| `stpt.resampling.resampleVolume` | `stitchedStackManipulation/resampleVolume.m` | Preserves StitchIt's XY-first and z-second bicubic organization, while accepting an explicit file list and voxel vectors, using single precision, recording realized spacing, and omitting the already completed z-illumination correction. |

Shared interface functions contain no StitchIt estimation logic:

| Function | Contract |
| --- | --- |
| `stpt.illumination.fitModel` | Dispatch the configured method and return `model` plus `audit`. |
| `stpt.illumination.buildModelFromTemplates` | Apply the shared crop, zero offset, median normalization, and pooled-or-split gain construction. |
| `stpt.illumination.validateModel` | Require complete channel/layer coverage and finite positive cropped gains. |
| `stpt.illumination.applyModel` | Crop, subtract the selected offset, and multiply by the model gain; return `single` without hidden clipping or casting. |
| `stpt.illumination.identityModel` | Preserve the model contract while replacing every offset and gain with `D=0` and `G=1` for crop-only comparisons. |
| `stpt.zillumination.apply` | Apply the configured method to all optical layers from one physical section/channel; treat one layer as identity. |
| `stpt.reconstruction.processSection` | Fuse every channel/layer group in one physical section, apply z illumination in memory, and publish only final planes. |
| `stpt.reconstruction.processSections` | Dispatch the same section worker serially or in parallel and assemble one canonically ordered manifest. |
| `stpt.reconstruction.writeReconstructionStepComparison` | Independently reconstruct the four ordered correction/blending/z-correction variants and assemble matched visual QC. |
| `stpt.downsampling.buildPlaneList` | Sort one channel by physical section and optical layer and require a complete final-plane series. |
| `stpt.resampling.resampleVolume` | Convert an ordered TIFF list plus input/output `[z,y,x]` voxel sizes to one single-precision `[y,x,z]` volume. |

In `pool` mode, one correction is stored identically in both slots of the common
model interface and is therefore applied to every tile row. In optional `split`
mode, odd/even fields refer to reconstructed target-grid row parity. In this
dataset that parity exactly separates the two alternating directions of the
serpentine acquisition; the group names are otherwise arbitrary.

## Relationship to OpenSTP

The legacy OpenSTP script crops 15 pixels, writes cropped and corrected tile
trees, estimates one pooled channel/layer average from all tiles, and defaults
to Fiji-style weighted blending with `alpha=1.5`. Its configured 12% overlap
places an 802-pixel retained tile at `floor(0.88 * 802) = 705` pixels. This
pipeline keeps the crop, normalized Fiji weight formula, and lossless LZW final
output, but applies correction in memory and uses the recorded 700-pixel target
step. Fiji blending is the canonical fusion mode; reverse-order overwrite is
retained only for the two controlled pilot comparisons. As in OpenSTP and
StitchIt, downsampling is a separate final operation rather than part of fusion.
The recorded 700-pixel placement gives a 508-by-396 XY lattice at 25 um; the
legacy OpenSTP warping volumes are 512-by-399 because their 705-pixel placement
produces a slightly larger stitched field of view.

The remaining planned performance extension is section-level reconstruction
parallelism; downsampling remains serial because its runtime and memory cost are
already modest at registration resolution.

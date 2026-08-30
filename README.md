# stpt-reconstruction

A lightweight MATLAB pipeline for reconstructing native TissueCyte-style STPT
datasets using illumination correction and stitching algorithms from StitchIt.

The pipeline bridges the native OpenSTP/TissueCyte file layout used by our
microscope to a small offline reconstruction workflow. It does not use
BakingTray acquisition, StitchIt sync/crunch, or repackaged multipage raw
stacks. Native TIFFs and Mosaic metadata are read in place and never modified;
all derived products go under `processed/reconstruction`.

## Production workflow

For this development dataset, two standalone configs coexist:

- `config_260812_MikeZ_PO431109_F_01.m` is the comprehensive experimental
  version. It exposes alternative algorithms and defaults to the reconstruction
  pilot.
- `config_260812_MikeZ_PO431109_F_01_production.m` is the concise production
  version. It contains only active settings, uses four reconstruction workers,
  and runs through downsampling.

The `_production` suffix is only needed here to keep both versions together.
For a new routinely acquired brain, copy the concise repository template into
the experiment directory and give it the ordinary dataset name:

```bash
cp config/config_260812_MikeZ_PO431109_F_01_production.m \
  /path/to/experiment/config_YYMMDD_Experiment_Name.m
```

Change the function declaration inside the copied file to match its filename:

```matlab
function cfg = config_YYMMDD_Experiment_Name()
```

That unsuffixed file beside the experiment data is then the dataset's only
production config. From the repository root, add the experiment directory—not
the repository's template directory—to the MATLAB path:

```bash
cd /home/xizheng/Projects/stpt-reconstruction

matlab -batch "addpath('/path/to/experiment'); runStptReconstruction(config_YYMMDD_Experiment_Name());"
```

The master runner validates the config, builds missing Stage 1/2 prerequisites,
reconstructs the production volume, and downsamples it. The reconstruction
pilot is independent and is never a production prerequisite.

For the current dataset, whose two configs still coexist, the equivalent command
is:

```bash
matlab -batch "addpath('config'); runStptReconstruction(config_260812_MikeZ_PO431109_F_01_production());"
```

## New-dataset checklist

Before starting a standard production run, copy the concise config into the
experiment directory and verify these fields against the acquisition and Mosaic
metadata:

1. Dataset identity

   - `cfg.experiment.id`
   - `cfg.experiment.dataPrefix`
   - `cfg.paths.rawRoot`
   - `cfg.paths.outputRoot`

2. Channel mapping

   - One entry for every channel that physically exists
   - Correct channel ID, color/name, directory, and filename code
   - No deleted or empty channel such as the absent blue channel in this dataset

3. Acquisition extent

   - Planned `sectionCount`
   - Actual complete `sectionStart:sectionStop`
   - `layersPerSection`
   - Physical `planeSpacingUm`

4. XY acquisition geometry

   - `pixelSizeUm`
   - `tileSizePixels`
   - `gridSize`
   - Recorded `targetStepUm`
   - Symmetric `cropPixels`
   - Native-to-grid `tileOrientation`

5. Reconstruction policy

   - Green or another appropriate tissue-reference channel
   - Illumination and QC section intervals
   - Fiji blending and z correction enabled as intended
   - One-layer acquisitions use `layersPerSection = 1`; z correction then becomes
     an identity operation automatically

6. Output and execution

   - Desired `[z,y,x]` downsampled voxel size
   - Available `reconstructionWorkers`; four is validated on this machine
   - `overwrite = false` for the first run

The config can be checked without creating output:

```bash
matlab -batch "addpath('src','/path/to/experiment'); stpt.validateConfig(config_YYMMDD_Experiment_Name());"
```

## Pipeline stages and mathematics

### Stage 1: native-data index

Stage 1 parses the Mosaic metadata and maps every native TIFF to explicit
section, optical-layer, tile, and channel coordinates. It reconstructs the
commanded tile grid, checks the config against the recorded acquisition, and
writes inventories plus representative target-versus-actual position plots.

The configured processing range may be shorter than the planned acquisition.
For example, an acquisition planned for 300 sections but stopped early can use
only a known-complete prefix such as sections 1–260. Every requested section
must still be complete in every configured channel.

### Stage 2: XY illumination model

The production `tissueOtsu` method samples sections regularly across the
requested volume. For every cropped green tile, it computes a scalar mean and
applies one binary Otsu threshold to

```text
log(1 + tile mean).
```

Tiles above the global threshold are retained as tissue-bearing observations.
Selected tile locations are then pooled directly across sampled sections. A 10%
pixelwise trimmed mean estimates a template for every channel, optical layer,
and scan-row parity.

With the default `rowMode = "pool"`, odd/even templates are combined by their
observation counts and one correction is applied to every tile row. Given
template `T`, the zero-offset multiplicative model is

```text
D = 0
G = median(T) / T
corrected = (cropped raw - D) .* G.
```

The common model interface also supports `rowMode = "split"` and the retained
`stitchitReference` estimator in the comprehensive config. Stage 2 writes the
selection and fitted model as separate auditable checkpoints, but it writes no
corrected TIFF tiles.

### Stage 3: reconstruction

Each raw 832-by-832 tile is corrected in its native orientation, cropped by 15
pixels per side, and rotated 90 degrees clockwise to reproduce OpenSTP's
`fliplr(image')` mapping to target-stage axes. The retained support is 802 by
802 pixels.

Tiles are placed at the recorded 700-pixel target step. Therefore the overlap is
derived from the acquisition geometry rather than specified independently:

```text
overlap = 802 - 700 = 102 pixels
overlap fraction of retained support = 102 / 802 = 12.72%.
```

Fiji-style fusion assigns each retained tile the separable distance-to-edge
weight

```text
w(x,y) = ((dx + 1) * (dy + 1) + 1)^alpha,
alpha = 1.5,
```

and evaluates the normalized weighted mosaic

```text
fused(x,y) = sum_i(w_i * corrected_i) / sum_i(w_i).
```

The common weight image is divided by its maximum before accumulation. That
global scale cancels between numerator and denominator and does not alter the
result. Clipping and uint16 conversion occur only after fusion.

For multi-layer sections, the deeper fused layers are corrected against the
first layer before any final TIFF is published. The StitchIt smooth-ratio method
reduces the fused planes, broadly Gaussian-smooths the reference and target,
and applies their spatial ratio as a multiplicative gain. A one-layer dataset
passes through this interface unchanged.

The complete physical section is the parallel work unit: all channels and
optical layers needed by that section remain together. Production uses
`cfg.execution.reconstructionWorkers`; the current value of four produced
byte-identical output to serial reconstruction. Only final z-corrected uint16
LZW TIFFs are written—there are no cropped-tile, corrected-tile, or pre-z TIFF
trees.

### Stage 4: downsampling

The completed production manifest is sorted by physical section and then
optical layer to make one ordered series per channel. Resampling is separable:

1. Each native XY mosaic is resized with bicubic interpolation and antialiasing.
2. If needed, the already reduced volume is resized through YZ slices using the
   same bicubic/antialiased calculation.

The intermediate array is single precision and held in RAM. Rounding,
saturation, and conversion to uint16 happen once at the final lossless-LZW TIFF
write. Requested and realized voxel sizes are both recorded because integer
output dimensions can introduce a small spacing difference.

For this dataset, `[z,y,x]` changes from `[25,1,1]` to `[25,25,25]` µm. The
output is 600 by 508 by 396 voxels; z already has the requested spacing and is
not interpolated.

## Stage-by-stage comparison

The three pipelines share the same broad scientific sequence but differ in data
adapters, parameter estimation, intermediate storage, and defaults.

| Major step | This repository | OpenSTP reference pipeline | StitchIt/BakingTray |
| --- | --- | --- | --- |
| Input organization | Reads native per-channel TissueCyte TIFF roots and Mosaic metadata in place. | Native TissueCyte-specific filenames and Mosaic parsing. | Expects BakingTray acquisition metadata and multipage tile stacks; sync/crunch belong to the acquisition workflow. |
| Indexing | Explicit read-only table maps every file to section/layer/tile/channel coordinates. | TissueCyte indexing is embedded in the legacy reconstruction scripts and compiled helpers. | Directory and INI conventions encode acquisition geometry. |
| Tissue/empty-tile selection | Green-channel global log-Otsu removes complete background before template estimation. | Current reference estimator averages all tiles and does not reject empty tiles. | Detector-floor and variability rules reject tiles before per-section averages; this is not explicitly a tissue classifier. |
| XY illumination template | Direct 10% trimmed pooling of selected native tiles across sampled sections; pooled rows by default. | One pooled channel/layer average tile from the available volume. | Per-section odd/even trimmed averages are collated across sections; `pool` is normally sufficient. |
| XY correction | Explicit `D=0`, median-normalized multiplicative gain, applied in memory. | Pooled average-tile division in the legacy corrected-tile workflow. | Offset/gain correction through `illuminationCorrector` and `divideByImage`. |
| Crop and orientation | Symmetric 15-pixel crop; correction in raw orientation; explicit 90-degree clockwise tile rotation. | Same 15-pixel crop and `fliplr(image')` orientation. | Crop is acquisition/config driven; BakingTray tiles already follow StitchIt's expected organization. |
| Placement and overlap | Recorded 700-pixel target step; 102-pixel/12.72% overlap follows from retained support. | Configured 12% rule gives `floor(0.88 * 802) = 705` pixels and a slightly larger field. | Grid/stage positions are converted to pixels; overlap follows tile support and placement. |
| Fusion | Canonical normalized Fiji-style blending with `alpha=1.5`; reverse overwrite is retained only as a pilot control. | Fiji-style blending with `alpha=1.5`. | Default reverse-acquisition overwrite (`fusionWeight=0`); alternative weighting is available. |
| Z illumination | StitchIt smooth spatial ratio applied section/channel-wise before publishing final planes. | The current reference warping output retains the layer-2 attenuation. | `correctZilluminationInDirectory` applies the smooth reference/target ratio as a post-fusion operation. |
| Full-resolution outputs | Only final z-corrected uint16/LZW section TIFFs. | Cropped/corrected tile intermediates plus stitched outputs. | Preprocessed acquisition products and stitched outputs follow the BakingTray directory tree. |
| Downsampling | Separate final XY-first, z-second bicubic/antialiased resampling with explicit voxel vectors. | Separate bilinear reduction used for the legacy `p05` warping TIFFs. | Separate `resampleVolume` with the same XY-first, z-second bicubic organization. |
| Execution lifecycle | Completed stages are reusable prerequisites; incomplete stages are discarded and rerun. No plane-level resume state. | Script-driven legacy workflow. | Full acquisition workflow includes its own sync, crunch, preprocessing, and directory markers. |

The target-step difference explains the final XY size difference: this pipeline
produces 508 by 396 at 25 µm, while the OpenSTP warping volumes are 512 by 399.
On the reference brain, whole-volume comparisons found median layer-1 Pearson
correlations of 0.959 in red and 0.983 in green. A matched section-151 control
with z correction disabled agreed even more closely with OpenSTP in layer 2
(`r=0.981` red and `r=0.995` green), confirming that the expected production
layer-2 difference comes from z illumination correction rather than geometry or
ordering.

## QC, lifecycle, and outputs

Stage checkpoints contain resolved configs, code provenance, logs, manifests,
summaries, and compact plots. Production QC includes representative final
sections, z-gain trends, and central orthogonal sections of each downsampled
channel volume.

The output tree is:

```text
processed/reconstruction/
├── 01_index/
├── 02_illumination/
│   └── tissue_otsu/
│       ├── 01_selection/
│       └── 02_model/
├── 03_reconstruction/
│   ├── pilot/                 # optional, independent development product
│   └── production/
│       └── stitched/
└── 04_downsampling/
    └── volumes/
```

Completed prerequisite stages are loaded only when their scientific signatures
match the current config. An incomplete stage directory is disposable and is
removed before that stage is rerun. A completed requested terminal stage is
protected unless `cfg.execution.overwrite = true`. Parallel production follows
the same rule: workers write unique section files, but there are no per-section
completion markers or resume logic.

To process a complete subset, edit the production config before the first run:

```matlab
cfg.processing.sectionStart = 1;
cfg.processing.sectionStop = 260;
```

To intentionally replace only a completed downsampling stage:

```matlab
cfg = config_YYMMDD_Experiment_Name();
cfg.execution.overwrite = true;
runStptReconstruction(cfg);
```

To stop at production reconstruction without downsampling:

```matlab
cfg = config_YYMMDD_Experiment_Name();
cfg.execution.stopAfter = "reconstructionProduction";
runStptReconstruction(cfg);
```

## Development and pilot workflow

The comprehensive example config defaults to a single center-section pilot:

```bash
matlab -batch "addpath('config'); runStptReconstruction(config_260812_MikeZ_PO431109_F_01());"
```

Its optional `cfg.qc.comparisons.reconstructionSteps = true` reconstructs four
matched full-resolution conditions for every pilot channel and layer:

1. No XY illumination correction, overwrite fusion
2. XY correction, overwrite fusion
3. XY correction, Fiji blending
4. XY correction, Fiji blending, z illumination correction

These comparison files live together under
`03_reconstruction/pilot/qc/comparisons/reconstruction_steps` and are never
copied into production. Other development terminal stages are `index`,
`illuminationSelection`, `illuminationModel`, `reconstructionPilot`,
`reconstructionProduction`, and `downsampling`.

## Code organization

| Package | Responsibility |
| --- | --- |
| `stpt.io` | Parse Mosaic metadata, resolve native paths, and load tiles or tile stacks. |
| `stpt.index` | Build and validate the read-only native-data index. |
| `stpt.illumination` | Define the common fit, model validation, and application interfaces. |
| `stpt.illumination.tissueOtsu` | Select tissue-bearing observations and estimate direct pooled templates. |
| `stpt.illumination.stitchitReference` | Retain the StitchIt-style detector-floor/reference estimator for controlled comparisons. |
| `stpt.preprocessing` | Apply the explicit native-TIFF-to-target-grid tile orientation. |
| `stpt.fusion` | Compute placement geometry and implement overwrite or Fiji-style fusion. |
| `stpt.zillumination` | Apply the within-section optical-layer correction interface. |
| `stpt.reconstruction` | Process complete sections, dispatch serial/parallel production, publish TIFFs, and write QC. |
| `stpt.resampling` | Perform the generic single-precision XY-first, z-second resampling calculation. |
| `stpt.downsampling` | Adapt the production manifest, publish channel volumes, and write Stage 4 QC. |

The master runner owns stage order and derived-output directories. Scientific
functions never rename, reorganize, or write into the raw acquisition roots.

## Algorithm provenance

This repository has no runtime dependency on StitchIt and calls no
`stitchit.*` function. The StitchIt source snapshot used as a numerical
reference is:

```text
383b9fbd5f0664bf232c897a87759d8da43b725c
```

| Local implementation | Reference source | Relationship |
| --- | --- | --- |
| `stitchitReference.estimateFloorTileMask` | `preProcessTiles/private/writeTileStats.m` | Adapted detector-floor calculation. |
| `stitchitReference.estimateSectionAverage` | `preProcessTiles/private/calcAverageMatFiles.m` | Close port of rejection, parity splitting, and within-section trimmed averages. |
| `stitchitReference.collateSectionAverages` | `stitching/collateAverageImages.m` | Close port of across-section trimmed collation. |
| `stpt.illumination.buildModelFromTemplates` | `tileload/illuminationCorrector.m`, `tools/divideByImage.m` | Preserves median-normalized multiplicative gain construction. |
| `stpt.fusion.fuseOverwritePlane` | `stitching/stitcher.m` | Adapts reverse-acquisition last-tile-wins overwrite. |
| `stpt.zillumination.stitchitSmoothRatio` | `artifactCorrection/correctZilluminationInDirectory.m` | Close port of reduced broad smoothing and reference/target gain. |
| `stpt.resampling.resampleVolume` | `stitchedStackManipulation/resampleVolume.m` | Preserves XY-first, z-second bicubic organization. |
| `stpt.preprocessing.applyTileOrientation` | OpenSTP `readSectionParamFile3D.m` | Reproduces `fliplr(image')`. |
| `stpt.fusion.fuseFijiBlendPlane` | OpenSTP `stitchMosaic.c`, `calcWeightImageAsInFiji.m` | Implements the same normalized Fiji-style weighting on recorded target placement. |
| `tissueOtsu.*` | Independent | Adds green-channel log-Otsu tissue selection and direct cross-volume pooling. |

## Tests

Run the repository tests from its root:

```bash
matlab -batch "addpath('tests'); testZIllumination; testDownsampling;"
```

The reference-dataset integration checks additionally established that four
sections reconstructed with four workers produced 16 TIFFs that were both
pixel-identical and byte-identical to the validated serial production output.

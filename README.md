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

The index contains one fixed slot for every expected native TIFF. An acquired
slot stores its filename; a missing acquisition remains an explicit empty slot,
so later filenames can never shift onto the wrong tile coordinates. Missing
TIFFs are reported but are not fatal. Malformed names, wrong channel codes,
duplicate indices, out-of-span indices, and inconsistent Mosaic geometry remain
errors because their logical interpretation is ambiguous.

The configured processing range may be shorter than the planned acquisition.
For example, an acquisition planned for 300 sections but stopped early can use
only a known-complete prefix such as sections 1–260. Every requested section
must have its Mosaic metadata and section directory, but individual missing
TIFFs are represented explicitly and processed as absent observations.

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

Only physically acquired TIFFs enter Otsu fitting or template estimation. A
missing tile is neither background nor tissue and contributes no synthetic zero
image to an illumination average.

With the default `rowMode = "pool"`, odd/even templates are combined by their
observation counts and one correction is applied to every tile row. Given
template `T`, the zero-offset multiplicative model is

```text
D = 0
G = median(T) / T
corrected = (cropped raw - D) .* G.
```

This gain is fitted only when the finite template has a positive median and
strictly positive cropped support. If a finite template is nonpositive, as can
happen when a channel PMT fails, that channel/layer uses the exact identity
model `D = 0, G = 1`. The fallback is recorded in the model summary and gain
plot. Malformed dimensions, nonfinite values, and absent input observations
remain errors rather than being hidden by the fallback.

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

The sum runs only over acquired tiles. A missing tile contributes neither
intensity nor weight, so neighboring overlap remains correctly normalized.
Pixels with no acquired coverage remain zero, and an in-memory support mask
distinguishes those pixels from true zero-valued fluorescence.

The common weight image is divided by its maximum before accumulation. That
global scale cancels between numerator and denominator and does not alter the
result. Clipping and uint16 conversion occur only after fusion.

For multi-layer sections, the deeper fused layers are corrected against the
first layer before any final TIFF is published. The StitchIt smooth-ratio method
reduces the fused planes, broadly Gaussian-smooths the reference and target,
and applies their spatial ratio as a multiplicative gain. A one-layer dataset
passes through this interface unchanged.

When either layer contains missing coverage, the reference and target fields
are estimated over their common support. This excludes the same absent region
from both sides of the ratio and prevents a missing tile from creating an
artificial z-gain halo. The unsupported output region remains zero.

Z validity is decided independently for every fused reference/target pair. A
finite, positive smoothed field and gain are corrected normally; an undefined
ratio uses unit gain and leaves that target plane unchanged. This decision does
not inherit the XY-model status. The reconstruction manifest records separate
XY and Z applied flags and reasons, making both identity decisions explicit.

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

Stage 4 needs no special sparse-data path: Stage 3 still publishes every
expected full-size output plane, and the documented zero-valued unsupported
regions are resampled normally.

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

## Missing-tile interfaces

Missing acquisition data crosses stage boundaries through explicit metadata,
not placeholder TIFFs or imputed fluorescence. No new config option is needed.

| Stage | Input contract | Output contract | Persistent audit artifacts | Missing-data behavior |
| --- | --- | --- | --- | --- |
| 1. Index | Config, Mosaic files, and native channel roots. | `datasetIndex.sections(...).channelFiles` has one fixed slot per expected native index; absent slots are empty. `datasetIndex.missingTiles` gives their logical coordinates. | `section_inventory.csv`, `missing_tiles.csv`, `stage_summary.txt`, and one `qc/missing_tiles/*.png` grid map per affected plane. | Reports missing TIFFs and completes. Ambiguous filenames, duplicates, unexpected indices, or invalid geometry still stop the stage. |
| 2. Illumination | Completed sparse-aware index; real TIFFs returned by `loadTileStack`. | Tissue selection and illumination model record the same missing-tile inventory and whether each channel/layer gain was fitted or replaced by identity. | Existing selection/model tables, MAT files, summaries, and plots. | Missing observations are excluded from thresholds and averages. A selected reference-channel location is also omitted from a channel template if that channel's TIFF is absent. A finite nonpositive template receives exact identity gain. |
| 3. Reconstruction | Completed index and matching illumination model. | One ordinary full-size final TIFF per section/channel/layer plus a manifest recording tile completeness and separate XY/Z correction decisions. | `manifest.csv`, reconstruction signature, summaries, and normal pilot/production QC. | Fusion omits both signal and weight from absent tiles. Its transient support masks are passed to z correction and are not written as full-resolution files. Unsupported pixels remain zero. An undefined Z ratio leaves the fused target plane unchanged. |
| 4. Downsampling | The complete ordered Stage 3 TIFF manifest. | One resampled multipage TIFF per channel and the existing volume manifest/QC. | Existing volumes, manifest, summary, and orthogonal-section plots. | No special case is required because Stage 3 preserves plane count and dimensions. |

The key shared I/O contracts are:

- `resolveTileFile` returns `(filePath, isPresent)`; a missing logical slot gives
  `""` and `false`.
- `loadTile` loads one known-present TIFF and treats a direct request for a
  missing slot as an error.
- `loadTileStack` returns only acquired images, with their original acquisition
  indices and target-grid coordinates in `tileStatistics`.
- `fusePlane` returns `(stitched, audit, supportMask)`. Scalar `true` denotes
  complete canvas support without allocating a plane-sized mask; an affected
  plane returns its explicit logical mask. Support exists only in memory and
  accompanies the layer group into `zillumination.apply`.

Missingness is included in illumination-model and reconstruction signatures.
If a raw TIFF is later recovered, rerun Stage 1 and its dependent stages from a
clean output tree so the new observation is incorporated.

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
matlab -batch "addpath('tests'); testIlluminationFallback; testZIllumination; testDownsampling; testMissingTiles;"
```

The reference-dataset integration checks additionally established that four
sections reconstructed with four workers produced 16 TIFFs that were both
pixel-identical and byte-identical to the validated serial production output.

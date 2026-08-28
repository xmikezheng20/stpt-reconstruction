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

Stage 3 uses the completed model to reconstruct the section at the center of the
configured processing range. It streams native tiles, applies crop and
illumination correction in raw orientation, rotates each corrected tile 90
degrees clockwise to match the target-stage axes, and places retained
802-by-802 tiles at the recorded 700-pixel target step. This explicit transform
reproduces OpenSTP's `fliplr(image')`; no final mosaic transform is applied.
Overlapping corrected tiles are combined with OpenSTP's Fiji-style normalized
distance weights using `alpha=1.5`. The four channel/layer planes are canonical
uint16 TIFFs with lossless LZW compression; no corrected tile intermediates are
made.

The pilot and future production reconstruction share the same geometry, plane
fusion, writer, output paths, and manifest. The pilot differs only by supplying
one derived center section and requesting detailed QC. Its completed planes can
therefore be reused when production expands to all processing sections.

The optional `cfg.qc.comparisons.reconstructionSteps` flag independently
reconstructs three versions of every pilot channel/layer plane: no correction
with overwrite, XY correction with overwrite, and XY correction with Fiji-style
blending. All three use the same crop, model-application interface, tile
orientation, plane processor, and lossless writer. Full-resolution TIFFs, a
combined manifest and input signature, a complete-field overview, and
native-resolution junctions are kept together under
`03_fusion/qc/comparisons/reconstruction_steps`.
Comparison variants are never copied from or linked to canonical output.

Fiji blending follows OpenSTP's `fusionMethod=3`: each corrected tile is
weighted by `((dx+1)*(dy+1)+1)^alpha`, accumulated on the recorded target grid,
and divided by the accumulated weights. The current `alpha=1.5` matches
OpenSTP. The common weight image is scaled to a maximum of one before
single-precision accumulation; this global scale cancels exactly in the
normalized result. Clipping and uint16 conversion happen only after blending.

Run it from the repository root:

```matlab
addpath('config');
runStptReconstruction(config_260812_MikeZ_PO431109_F_01());
```

The master runner orchestrates the implemented stages from the same experiment
config.

Computation and visualization have independent regular samples. With
`illuminationEveryNSections = 10`, Stage 2 fitting uses sections
`1, 11, ..., 291`; with `qcEveryNSections = 50`, Stage 1/2 plots use
`1, 51, 101, 151, 201, 251`. Final sections are not appended automatically.
The fusion pilot section is `round((sectionStart + sectionStop)/2)`, which is
section 151 for the default 1:300 range. The same every-50 sequence is reserved
for compact QC during future production fusion.

The planned metadata count remains `cfg.acquisition.sectionCount`. To process
only a complete prefix or subset, override the reconstruction range explicitly:

```matlab
cfg = config_260812_MikeZ_PO431109_F_01();
cfg.processing.sectionStart = 1;
cfg.processing.sectionStop = 260;
runStptReconstruction(cfg);
```

Sections outside this range are ignored. Every requested section must still be
complete and present in every configured channel.

Completed stage directories are protected from accidental replacement. To
intentionally replace the requested terminal stage, set
`cfg.execution.overwrite = true`; its old derived directory is removed before the
new run starts. Completed prerequisite stages are loaded without modification.
When the tissue-Otsu model is requested and its selection checkpoint is absent,
the master runner creates that prerequisite before fitting the model.

To stop after Stage 1:

```matlab
cfg = config_260812_MikeZ_PO431109_F_01();
cfg.execution.stopAfter = "index";
runStptReconstruction(cfg);
```

The experiment config currently stops after the Stage 3 fusion pilot. Tissue
selection is stored under `02_illumination/tissue_otsu/01_selection`; the fitted
model is stored under `02_illumination/tissue_otsu/02_model`; canonical fused
planes and pilot QC are stored under `03_fusion`. Neither Stage 2 substep writes
corrected TIFFs. The optional StitchIt-reference model uses the parallel path
`02_illumination/stitchit_reference/02_model`.

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
| `stpt.fusion` | Compute target-grid geometry, prepare native tiles, dispatch overwrite or Fiji-style fusion, write lossless TIFFs, and generate fusion QC. |

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
| `stpt.fusion.writePilotQC` | `stitcher.m` chessboard mode (concept only) | Independent center-section previews, channel overlay, and lightweight red/green tile checkerboard. |

Shared interface functions contain no StitchIt estimation logic:

| Function | Contract |
| --- | --- |
| `stpt.illumination.fitModel` | Dispatch the configured method and return `model` plus `audit`. |
| `stpt.illumination.buildModelFromTemplates` | Apply the shared crop, zero offset, median normalization, and pooled-or-split gain construction. |
| `stpt.illumination.validateModel` | Require complete channel/layer coverage and finite positive cropped gains. |
| `stpt.illumination.applyModel` | Crop, subtract the selected offset, and multiply by the model gain; return `single` without hidden clipping or casting. |
| `stpt.illumination.identityModel` | Preserve the model contract while replacing every offset and gain with `D=0` and `G=1` for crop-only comparisons. |
| `stpt.fusion.processPlanes` | Apply one supplied model and fusion configuration, then reconstruct requested planes into an explicit output root and manifest. |
| `stpt.fusion.writeReconstructionStepComparison` | Independently reconstruct the ordered correction/blending variants and assemble matched visual QC. |

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
retained only for the two controlled pilot comparisons. Production downsampling
will remain a separate final stage.

Planned extensions are production-wide fusion with compact every-50-section QC,
z illumination correction on the fused volume, final downsampling, and
plane-level parallelism.

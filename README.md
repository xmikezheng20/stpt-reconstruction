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
illumination templates for each channel and layer. The estimator uses a 10%
pixelwise trimmed mean, zero additive offset, and StitchIt's median-normalized
gain construction. It does not write corrected TIFFs or perform stitching.

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

Run it from the repository root:

```matlab
addpath('config');
runStptReconstruction(config_260812_MikeZ_PO431109_F_01());
```

The master runner will eventually orchestrate all reconstruction stages from the
same experiment config.

Computation and visualization have independent regular samples. With
`illuminationEveryNSections = 10`, Stage 2 fitting uses sections
`1, 11, ..., 291`; with `qcEveryNSections = 50`, Stage 1/2 plots and the later
fusion pilot use `1, 51, 101, 151, 201, 251`. Final sections are not appended
automatically.

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

The experiment config currently stops after Stage 2. Tissue selection is
stored under `02_illumination/tissue_otsu/01_selection`; the fitted model is
stored separately under `02_illumination/tissue_otsu/02_model`. Neither substep
writes corrected TIFFs.

## Code organization

The package is divided by responsibility:

| Package | Responsibility |
| --- | --- |
| `stpt.io` | Parse native Mosaic files, resolve indexed TIFF paths, and load individual tiles or tile stacks. |
| `stpt.index` | Build the read-only dataset index and write Stage 1 QC. |
| `stpt.illumination` | Define the shared fit, validation, and correction-model interface. |
| `stpt.illumination.stitchitReference` | Implement only the StitchIt-reference estimation algorithm and its QC. |
| `stpt.illumination.tissueOtsu` | Select tissue-bearing tiles with green-channel log-Otsu and fit direct pooled templates. |

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

Shared interface functions contain no StitchIt estimation logic:

| Function | Contract |
| --- | --- |
| `stpt.illumination.fitModel` | Dispatch the configured method and return `model` plus `audit`. |
| `stpt.illumination.buildModelFromTemplates` | Apply the shared crop, zero offset, median normalization, and gain construction. |
| `stpt.illumination.validateModel` | Require complete channel/layer coverage and finite positive cropped gains. |
| `stpt.illumination.applyModel` | Crop, subtract the selected offset, and multiply by the selected odd/even gain; return `single` without hidden clipping or casting. |

Odd/even fields refer to the parity of the reconstructed target-grid row. In
this dataset that parity exactly separates the two alternating directions of the
serpentine acquisition; the names of the two groups are otherwise arbitrary.

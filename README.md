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

Stage 1 builds and validates the complete dataset index. It parses acquisition
metadata, maps each TIFF to section/layer/tile/channel coordinates, reconstructs
the commanded 14-by-18 scan grid, and writes auditable tables and QC plots.

Stage 2 is an illumination-calibration pilot on representative sections. It
calculates compact tile statistics, applies StitchIt's detector-floor rule,
estimates uncropped odd/even row templates, and collates provisional correction
fields. It does not write corrected TIFFs or perform stitching. A retained
tile is merely above the estimated detector floor; it is not classified as tissue.

Stage 2 is a reference baseline, not an accepted final calibration. Its compact QC
shows the sorted tile means, their spatial distribution, representative raw tiles,
and the agreement between odd/even template fields.

Illumination fitting is method-specific, but every method returns the same cropped
offset-and-gain model. `fitModel` dispatches fitting, `validateModel` enforces the
model contract, and `applyModel` applies the clear pointwise calculation
`(croppedRaw - offset) .* gain`. Green/ch2 is the configurable default tissue-
reference channel for future tissue-aware methods; the current reference method
does not use tissue classification.

Run it from the repository root:

```matlab
addpath('config');
runStptReconstruction(config_260812_MikeZ_PO431109_F_01());
```

The master runner will eventually orchestrate all reconstruction stages from the
same experiment config.

Completed stage directories are protected from accidental replacement. To
intentionally replace the requested terminal stage, set
`cfg.execution.overwrite = true`; its old derived directory is removed before the
new run starts. Completed prerequisite stages are loaded without modification.

To stop after Stage 1:

```matlab
cfg = config_260812_MikeZ_PO431109_F_01();
cfg.execution.stopAfter = "index";
runStptReconstruction(cfg);
```

## Code organization

The package is divided by responsibility:

| Package | Responsibility |
| --- | --- |
| `stpt.io` | Parse native Mosaic files, resolve indexed TIFF paths, and load tile stacks. |
| `stpt.index` | Build the read-only dataset index and write Stage 1 QC. |
| `stpt.illumination` | Define the shared fit, validation, and correction-model interface. |
| `stpt.illumination.stitchitReference` | Implement only the StitchIt-reference estimation algorithm and its QC. |

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

Shared interface functions contain no StitchIt estimation logic:

| Function | Contract |
| --- | --- |
| `stpt.illumination.fitModel` | Dispatch the configured method and return `model` plus `audit`. |
| `stpt.illumination.validateModel` | Require complete channel/layer coverage and finite positive cropped gains. |
| `stpt.illumination.applyModel` | Crop, subtract the selected offset, and multiply by the selected odd/even gain; return `single` without hidden clipping or casting. |

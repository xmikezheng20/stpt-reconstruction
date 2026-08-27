function writeQC(audit, datasetIndex, cfg, stageDir)
%WRITEQC Write the small set of StitchIt-reference checkpoint plots.
%
% The detector-floor plots explain the threshold without implying that retained
% tiles contain tissue. Template plots focus only on whether the split odd/even
% illumination fields agree. This QC code is independent of StitchIt.

qcDir = string(fullfile(stageDir, "qc"));
if ~isfolder(qcDir)
    mkdir(qcDir);
end

% One compact detector-floor diagnostic per section/channel/layer combination.
for c = 1:numel(datasetIndex.channels)
    channelId = datasetIndex.channels(c).id;
    for layer = 1:datasetIndex.geometry.layersPerSection
        for sectionNumber = audit.qcSections
            keep = audit.tileStatistics.sectionNumber == sectionNumber & ...
                audit.tileStatistics.channelId == channelId & ...
                audit.tileStatistics.layer == layer;
            stats = audit.tileStatistics(keep, :);
            outputPath = fullfile(qcDir, sprintf( ...
                "section_%03d_ch%d_layer%d_floor_qc.png", ...
                sectionNumber, channelId, layer));
            plotFloorDiagnostic(stats, outputPath);
        end

        template = audit.templates{c, layer};
        outputPath = fullfile(qcDir, sprintf( ...
            "ch%d_layer%d_template_qc.png", channelId, layer));
        plotTemplateComparison(template, cfg.preprocessing.cropPixels, ...
            outputPath);
    end
end
end

function plotFloorDiagnostic(stats, outputPath)
% Show the threshold, its mosaic context, and three representative raw tiles.
fig = figure("Visible", "off", "Color", "w", ...
    "Position", [100, 100, 1200, 800]);
tiledlayout(2, 2, "Padding", "compact", "TileSpacing", "compact");

% A sorted log-scale curve makes the narrow detector-floor plateau visible.
[sortedMeans, order] = sort(stats.tileMean);
sortedRejected = stats.rejectedAtFloor(order);
rank = (1:height(stats))';
ax = nexttile;
semilogy(rank, max(sortedMeans, eps), "k-", "LineWidth", 1, ...
    "HandleVisibility", "off");
hold on
scatter(rank(sortedRejected), max(sortedMeans(sortedRejected), eps), 24, ...
    [0.85, 0.15, 0.1], "filled", "DisplayName", "floor-rejected");
scatter(rank(~sortedRejected), max(sortedMeans(~sortedRejected), eps), 14, ...
    [0.1, 0.4, 0.75], "filled", "DisplayName", "retained");
yline(stats.floorThreshold(1), "r--", "LineWidth", 1.5, ...
    "DisplayName", "floor threshold");
xlabel("Tile rank");
ylabel("Tile mean (raw units, log scale)");
title(sprintf("Floor %.3g; rejects %d/%d; retained is not tissue", ...
    stats.floorThreshold(1), nnz(stats.rejectedAtFloor), height(stats)));
legend("Location", "northwest");
grid on
colormap(ax, parula(256));

% Map continuous tile means onto the physical mosaic grid; rejected tiles are
% marked without converting all other tiles into a binary tissue label.
ax = nexttile;
meanMap = nan(max(stats.gridY), max(stats.gridX));
mapIndices = sub2ind(size(meanMap), stats.gridY, stats.gridX);
meanMap(mapIndices) = stats.tileMean;
imagesc(log10(meanMap + 0.1));
axis image
set(gca, "YDir", "reverse");
hold on
floorRows = stats.rejectedAtFloor;
plot(stats.gridX(floorRows), stats.gridY(floorRows), "rx", ...
    "LineWidth", 1.25, "MarkerSize", 7);
xlabel("Grid x");
ylabel("Grid y");
title("Tile means in mosaic coordinates; x = floor-rejected");
cb = colorbar;
cb.Label.String = "log10(tile mean + 0.1)";
colormap(ax, turbo(256));

% Raw examples reveal what the numerical categories actually look like.
nexttile([1, 2]);
[exampleRows, exampleLabels] = selectExamples(stats);
tiles = cell(numel(exampleRows), 1);
for i = 1:numel(exampleRows)
    tiles{i} = imread(stats.filePath(exampleRows(i)));
end
composite = cat(2, tiles{:});
displayImage = log1p(double(composite));
imagesc(displayImage);
axis image
colormap(gca, gray(256));
displayLimits = prctile(displayImage(:), [0.5, 99.8]);
clim(displayLimits);
tileWidth = size(tiles{1}, 2);
centers = tileWidth * ((1:numel(tiles)) - 0.5);
xticks(centers);
xticklabels(exampleLabels);
yticks([]);
for i = 1:numel(tiles)-1
    xline(i * tileWidth + 0.5, "w-", "LineWidth", 1);
end
title("Representative raw tiles (shared log1p display; not adjacent)");

sgtitle(sprintf("Section %03d, ch%d, layer %d", ...
    stats.sectionNumber(1), stats.channelId(1), stats.layer(1)));
exportgraphics(fig, outputPath, "Resolution", 150);
close(fig);
end

function [rows, labels] = selectExamples(stats)
% Select the highest rejected, lowest retained, and bright retained tiles.
rejected = find(stats.rejectedAtFloor);
retained = find(stats.retainedForIllumination);

if isempty(rejected)
    [~, rejectedRow] = min(stats.tileMean);
    rejectedLabel = "dimmest";
else
    [~, position] = max(stats.tileMean(rejected));
    rejectedRow = rejected(position);
    rejectedLabel = "highest rejected";
end

[~, position] = min(stats.tileMean(retained));
lowestRetainedRow = retained(position);
target = prctile(stats.tileMean(retained), 95);
[~, position] = min(abs(stats.tileMean(retained) - target));
brightRow = retained(position);

rows = [rejectedRow, lowestRetainedRow, brightRow];
category = [rejectedLabel, "lowest retained", "95th percentile"];
[rows, uniquePositions] = unique(rows, "stable");
category = category(uniquePositions);
labels = strings(size(rows));
for i = 1:numel(rows)
    labels(i) = sprintf("%s | tile %d | mean %.3g", category(i), ...
        stats.acquisitionIndex(rows(i)), stats.tileMean(rows(i)));
end
end

function plotTemplateComparison(template, cropPixels, outputPath)
% Compare normalized odd/even fields only within support retained after crop.
retained = retainedMask(size(template.oddRows), cropPixels);
odd = double(template.oddRows) / median(template.oddRows(retained));
even = double(template.evenRows) / median(template.evenRows(retained));
differencePct = 200 * (odd - even) ./ (odd + even);
differencePct(~retained) = nan;

fieldLimits = prctile([odd(retained); even(retained)], [1, 99]);
differenceLimit = max(0.1, prctile(abs(differencePct(retained)), 99));
fieldCorrelation = corr(odd(retained), even(retained));
medianDifference = median(abs(differencePct(retained)));

fig = figure("Visible", "off", "Color", "w", ...
    "Position", [100, 100, 1250, 430]);
tiledlayout(1, 3, "Padding", "compact", "TileSpacing", "compact");

ax = nexttile;
imagesc(odd); axis image off; clim(fieldLimits); colorbar
title("Odd-row field / median");
colormap(ax, parula(256));

ax = nexttile;
imagesc(even); axis image off; clim(fieldLimits); colorbar
title("Even-row field / median");
colormap(ax, parula(256));

ax = nexttile;
imagesc(differencePct); axis image off
clim([-differenceLimit, differenceLimit]); colorbar
title("Odd-even difference (%)");
colormap(ax, redWhiteBlue(256));

sgtitle(sprintf("Pilot template: ch%d, layer %d | correlation %.4f | median |difference| %.2f%%", ...
    template.channel, template.layer, fieldCorrelation, medianDifference));
exportgraphics(fig, outputPath, "Resolution", 150);
close(fig);
end

function mask = retainedMask(imageSize, cropPixels)
% Return the pixels that will survive the configured later crop.
mask = false(imageSize);
mask(cropPixels(3)+1:end-cropPixels(4), ...
    cropPixels(1)+1:end-cropPixels(2)) = true;
end

function map = redWhiteBlue(n)
% Small diverging map for signed odd/even differences.
half = ceil(n / 2);
blueToWhite = [linspace(0.1, 1, half)', linspace(0.3, 1, half)', ...
    ones(half, 1)];
whiteToRed = [ones(half, 1), linspace(1, 0.2, half)', ...
    linspace(1, 0.1, half)'];
map = [blueToWhite; whiteToRed(2:end, :)];
map = map(round(linspace(1, size(map, 1), n)), :);
end

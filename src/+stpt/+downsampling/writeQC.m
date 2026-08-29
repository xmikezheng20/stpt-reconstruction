function writeQC(volume, channel, realizedVoxelSizeUm, outputPath)
%WRITEQC Plot central orthogonal sections from one resampled channel volume.
%
% Array order is [y, x, z]. All panels preserve increasing array coordinates
% from top to bottom, so z in the orthogonal panels follows the TIFF page order.

sizeY = size(volume, 1);
sizeX = size(volume, 2);
sizeZ = size(volume, 3);
centerY = round((sizeY + 1) / 2);
centerX = round((sizeX + 1) / 2);
centerZ = round((sizeZ + 1) / 2);

xy = volume(:, :, centerZ);
xz = squeeze(volume(centerY, :, :))';
yz = squeeze(volume(:, centerX, :))';
limits = commonDisplayLimits({xy, xz, yz});

xUm = (0:sizeX - 1) * realizedVoxelSizeUm(3);
yUm = (0:sizeY - 1) * realizedVoxelSizeUm(2);
zUm = (0:sizeZ - 1) * realizedVoxelSizeUm(1);

fig = figure("Visible", "off", "Color", "w", ...
    "Position", [100, 100, 1500, 500]);
tiledlayout(1, 3, "Padding", "compact", "TileSpacing", "compact");

nexttile
imagesc(xUm, yUm, xy);
formatAxes(limits, "x (um)", "y (um)", ...
    sprintf("XY | z plane %d", centerZ));

nexttile
imagesc(xUm, zUm, xz);
formatAxes(limits, "x (um)", "z (um)", ...
    sprintf("XZ | y row %d", centerY));

nexttile
imagesc(yUm, zUm, yz);
formatAxes(limits, "y (um)", "z (um)", ...
    sprintf("YZ | x column %d", centerX));

sgtitle(sprintf("Stage 4 | ch%d %s | central orthogonal sections", ...
    channel.id, channel.name));
exportgraphics(fig, outputPath, "Resolution", 160);
close(fig);
end

function formatAxes(limits, xLabel, yLabel, panelTitle)
axis image
colormap(gca, gray(256));
clim(limits);
xlabel(xLabel);
ylabel(yLabel);
title(panelTitle);
end

function limits = commonDisplayLimits(images)
values = cellfun(@(image) double(image(:)), images, ...
    "UniformOutput", false);
values = vertcat(values{:});
values = values(values > 0);
if isempty(values)
    limits = [0, 1];
else
    limits = prctile(values, [0.5, 99.8]);
    if limits(1) == limits(2)
        limits(2) = limits(1) + 1;
    end
end
end

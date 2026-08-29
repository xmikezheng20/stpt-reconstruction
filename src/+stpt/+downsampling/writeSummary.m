function writeSummary(manifest, outputPath)
%WRITESUMMARY Record the compact scientific and storage contract of Stage 4.

fid = fopen(outputPath, "w");
if fid < 0
    error("stpt:DownsamplingOutput", "Could not write %s.", outputPath);
end
cleanup = onCleanup(@() fclose(fid));

first = manifest(1, :);
fprintf(fid, "STPT downsampling completed\n");
fprintf(fid, "Channels: %s\n", mat2str(manifest.channelId'));
fprintf(fid, "Input order: physical section, then optical layer\n");
fprintf(fid, "Input size [z y x]: [%d %d %d]\n", ...
    first.inputZPixels, first.inputYPixels, first.inputXPixels);
fprintf(fid, "Output size [z y x]: [%d %d %d]\n", ...
    first.outputZPixels, first.outputYPixels, first.outputXPixels);
fprintf(fid, "Input voxel [z y x]: [%g %g %g] um\n", ...
    first.inputVoxelZUm, first.inputVoxelYUm, first.inputVoxelXUm);
fprintf(fid, "Requested voxel [z y x]: [%g %g %g] um\n", ...
    first.requestedVoxelZUm, first.requestedVoxelYUm, ...
    first.requestedVoxelXUm);
fprintf(fid, "Realized voxel [z y x]: [%.9g %.9g %.9g] um\n", ...
    first.realizedVoxelZUm, first.realizedVoxelYUm, ...
    first.realizedVoxelXUm);
fprintf(fid, "Method: XY first, z second; bicubic interpolation; antialiasing on\n");
fprintf(fid, "Output: one uint16 multipage TIFF per channel, lossless LZW\n");
fprintf(fid, "Output size: %.3f GiB\n", sum(manifest.outputBytes) / 1024^3);
fprintf(fid, "Pixels below zero before output casting: %.0f\n", ...
    sum(manifest.clippedLowPixels));
fprintf(fid, "Pixels above uint16 before output casting: %.0f\n", ...
    sum(manifest.clippedHighPixels));
fprintf(fid, "XY resampling time: %.1f seconds\n", sum(manifest.xySeconds));
fprintf(fid, "z resampling time: %.1f seconds\n", sum(manifest.zSeconds));
fprintf(fid, "LZW writing time: %.1f seconds\n", sum(manifest.writeSeconds));
fprintf(fid, "Completed: %s\n", string(datetime("now")));
end

function writePlane(image, outputPath, compression)
%WRITEPLANE Atomically publish one final lossless reconstruction TIFF.

% Write beside the final path, then rename only after imwrite succeeds.
[folder, stem, extension] = fileparts(outputPath);
partialPath = fullfile(folder, stem + ".partial" + extension);
imwrite(image, partialPath, "tif", "Compression", compression);
movefile(partialPath, outputPath);
end

function writePlane(image, outputPath, compression)
%WRITEPLANE Write one lossless TIFF through the shared fusion interface.

% Write beside the final path, then rename only after imwrite succeeds.
[folder, stem, extension] = fileparts(outputPath);
partialPath = fullfile(folder, stem + ".partial" + extension);
if isfile(partialPath)
    delete(partialPath);
end
imwrite(image, partialPath, "tif", "Compression", compression);
movefile(partialPath, outputPath);
end

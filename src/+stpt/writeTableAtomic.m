function writeTableAtomic(value, outputPath)
%WRITETABLEATOMIC Publish a table only after the complete file is written.

[folder, stem, extension] = fileparts(outputPath);
partialPath = fullfile(folder, stem + ".partial" + extension);
writetable(value, partialPath);
movefile(partialPath, outputPath);
end

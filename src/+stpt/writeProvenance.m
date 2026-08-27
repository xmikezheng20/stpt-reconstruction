function writeProvenance(provenance, outputPath)
%WRITEPROVENANCE Write a human-readable companion to saved provenance data.

fid = fopen(outputPath, "w");
if fid < 0
    error("stpt:WriteOutput", "Could not write %s.", outputPath);
end

% Keep the text file compact while preserving every value needed to identify
% the local reconstruction code that produced the outputs.
fprintf(fid, "STPT reconstruction provenance\n");
fprintf(fid, "Captured: %s\n", provenance.captured);
fprintf(fid, "MATLAB: %s\n\n", provenance.matlabVersion);

fprintf(fid, "stpt-reconstruction\n");
fprintf(fid, "  root: %s\n", provenance.repository.root);
fprintf(fid, "  branch: %s\n", provenance.repository.branch);
fprintf(fid, "  commit: %s\n", provenance.repository.commit);
fprintf(fid, "  dirty: %s\n", logicalText(provenance.repository.isDirty));
fclose(fid);
end

function value = logicalText(tf)
% Render booleans consistently for easy inspection and parsing.
if tf
    value = "true";
else
    value = "false";
end
end

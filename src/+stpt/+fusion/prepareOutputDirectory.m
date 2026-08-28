function stageDir = prepareOutputDirectory(outputRoot, signature, overwrite)
%PREPAREOUTPUTDIRECTORY Create or resume the canonical fusion tree.

stageDir = string(fullfile(outputRoot, "03_fusion"));
signaturePath = fullfile(stageDir, "fusion_signature.mat");

if isfolder(stageDir) && overwrite
    rmdir(stageDir, "s");
end

if ~isfolder(stageDir)
    mkdir(stageDir);
    save(signaturePath, "signature");
    return
end

if ~isfile(signaturePath)
    error("stpt:FusionSignature", ...
        "Existing fusion output has no signature. Use explicit overwrite: %s", ...
        stageDir);
end
saved = load(signaturePath, "signature");
if ~isequaln(saved.signature, signature)
    error("stpt:FusionSignature", ...
        "Existing fusion output was created from different inputs.");
end
end

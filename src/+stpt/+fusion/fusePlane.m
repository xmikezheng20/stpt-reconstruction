function [stitched, audit, geometry] = fusePlane( ...
        datasetIndex, model, cfg, sectionNumber, layer, channelId)
%FUSEPLANE Dispatch one plane to the configured fusion algorithm.
%
% Tile loading, illumination correction, orientation, and output writing remain
% independent of the fusion policy. This keeps canonical and QC alternatives
% comparable while each fusion implementation stays small and explicit.

geometry = stpt.fusion.computeGeometry(datasetIndex, sectionNumber);
switch lower(string(cfg.fusion.mode))
    case "overwrite"
        [stitched, audit] = stpt.fusion.fuseOverwritePlane( ...
            datasetIndex, model, cfg, sectionNumber, layer, channelId, ...
            geometry);
    case "fijiblend"
        [stitched, audit] = stpt.fusion.fuseFijiBlendPlane( ...
            datasetIndex, model, cfg, sectionNumber, layer, channelId, ...
            geometry);
    otherwise
        error("stpt:FusionMode", ...
            "Unknown fusion mode: %s", cfg.fusion.mode);
end
end

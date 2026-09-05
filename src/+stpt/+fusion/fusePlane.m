function [stitched, audit, supportMask] = fusePlane( ...
        datasetIndex, model, cfg, sectionNumber, layer, channelId, geometry)
%FUSEPLANE Dispatch one plane to the configured fusion algorithm.
%
% Tile loading, illumination correction, orientation, and output writing remain
% independent of the fusion policy. This keeps canonical and QC alternatives
% comparable while each fusion implementation stays small and explicit.
% SUPPORTMASK is scalar true for a complete canvas or a logical image when raw
% acquisition gaps leave unsupported pixels.

switch lower(string(cfg.fusion.mode))
    case "overwrite"
        [stitched, audit, supportMask] = stpt.fusion.fuseOverwritePlane( ...
            datasetIndex, model, cfg, sectionNumber, layer, channelId, ...
            geometry);
    case "fijiblend"
        [stitched, audit, supportMask] = stpt.fusion.fuseFijiBlendPlane( ...
            datasetIndex, model, cfg, sectionNumber, layer, channelId, ...
            geometry);
    otherwise
        error("stpt:FusionMode", ...
            "Unknown fusion mode: %s", cfg.fusion.mode);
end
end

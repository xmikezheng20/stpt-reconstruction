function image = applyTileOrientation(image, orientation)
%APPLYTILEORIENTATION Map corrected native TIFF axes onto the target grid.
%
% Illumination correction is fitted in the raw TIFF orientation and must happen
% before this operation. ROT90CW reproduces OpenSTP's fliplr(image').

switch lower(string(orientation))
    case "none"
        return
    case "rot90cw"
        image = rot90(image, -1);
    otherwise
        error("stpt:TileOrientation", ...
            "Unknown tile orientation: %s", orientation);
end
end

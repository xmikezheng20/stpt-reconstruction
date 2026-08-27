function mosaic = readMosaicFile(filePath)
%READMOSAICFILE Parse a native TissueCyte/OpenSTP Mosaic text file.
%
% Header entries are exposed both as an original key/value table and as a
% convenient parameters struct. Section Mosaic files additionally contain
% alternating XPos/YPos records. Movement suffixes and position values are
% stored in tenths of a micrometre, so they are converted to micrometres here.

% Normalize the path and read the small text file without touching image data.
filePath = string(filePath);
if ~isfile(filePath)
    error("stpt:MissingMosaic", "Mosaic file does not exist: %s", filePath);
end

text = fileread(filePath);
lines = regexp(text, "\r\n|\n|\r", "split")';
lines = lines(~cellfun(@isempty, lines));

% Split on the first colon only because values such as acquisition timestamps
% may themselves contain additional colons.
keys = strings(numel(lines), 1);
values = strings(numel(lines), 1);
for i = 1:numel(lines)
    separator = find(lines{i} == ':', 1, "first");
    if isempty(separator)
        error("stpt:MalformedMosaic", ...
            "Malformed line %d in %s.", i, filePath);
    end
    keys(i) = strtrim(string(lines{i}(1:separator-1)));
    values(i) = strtrim(string(lines{i}(separator+1:end)));
end

% Position records are distinguished by their XPos/YPos keys; everything else
% belongs to the ordinary metadata header.
isPosition = ~cellfun(@isempty, ...
    regexp(cellstr(keys), "^[XY]Pos-?[0-9]+$", "once"));

headerKeys = keys(~isPosition);
headerValues = values(~isPosition);

% Preserve original key/value strings and also expose MATLAB-friendly fields.
% Numeric-looking values become doubles; descriptive values remain strings.
parameters = struct();
for i = 1:numel(headerKeys)
    fieldName = matlab.lang.makeValidName(char(headerKeys(i)));
    numericValue = str2double(headerValues(i));
    if ~isnan(numericValue) || strcmpi(headerValues(i), "NaN")
        parameters.(fieldName) = numericValue;
    else
        parameters.(fieldName) = headerValues(i);
    end
end

% Section files store one X record followed by one Y record for every acquired
% tile. Master Mosaic files simply produce an empty position table.
positionKeys = keys(isPosition);
positionValues = values(isPosition);
if mod(numel(positionKeys), 2) ~= 0
    error("stpt:PositionPairs", ...
        "Position records are not complete X/Y pairs in %s.", filePath);
end

nPositions = numel(positionKeys) / 2;
commandedDXUm = zeros(nPositions, 1);
commandedDYUm = zeros(nPositions, 1);
actualXUm = zeros(nPositions, 1);
actualYUm = zeros(nPositions, 1);

% Decode both the commanded relative movement embedded in each key and the
% measured absolute stage position stored after the colon.
for i = 1:nPositions
    xRow = 2*i - 1;
    yRow = 2*i;
    xToken = regexp(positionKeys(xRow), "^XPos(-?[0-9]+)$", ...
        "tokens", "once");
    yToken = regexp(positionKeys(yRow), "^YPos(-?[0-9]+)$", ...
        "tokens", "once");
    if isempty(xToken) || isempty(yToken)
        error("stpt:PositionOrder", ...
            "Expected alternating XPos/YPos records in %s.", filePath);
    end

    commandedDXUm(i) = str2double(xToken{1}) / 10;
    commandedDYUm(i) = str2double(yToken{1}) / 10;
    actualXUm(i) = str2double(positionValues(xRow)) / 10;
    actualYUm(i) = str2double(positionValues(yRow)) / 10;
end

% Return stable tables so downstream code can retain the original metadata and
% append derived grid coordinates without reparsing the text.
mosaic = struct();
mosaic.path = filePath;
mosaic.header = table(headerKeys, headerValues, ...
    'VariableNames', {'key', 'value'});
mosaic.parameters = parameters;
mosaic.positions = table((1:nPositions)', commandedDXUm, commandedDYUm, ...
    actualXUm, actualYUm, 'VariableNames', ...
    {'acquisitionIndex', 'commandedDXUm', 'commandedDYUm', ...
     'actualXUm', 'actualYUm'});
end

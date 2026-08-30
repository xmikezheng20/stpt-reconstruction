function [manifest, diagnostics] = processSections( ...
        datasetIndex, model, cfg, sections, outputRoot)
%PROCESSSECTIONS Dispatch complete physical sections for reconstruction.
%
% A section is the independent work unit because z illumination couples its
% optical layers. Serial and parallel execution call the same section worker
% and therefore differ only in scheduling, never in reconstruction math.

if isfolder(outputRoot)
    error("stpt:ReconstructionOutput", ...
        "Reconstruction output already exists; start the stage clean: %s", ...
        outputRoot);
end
mkdir(outputRoot);

sections = sections(:)';
nLayers = datasetIndex.geometry.layersPerSection;
nChannels = numel(datasetIndex.channels);
nPlanes = numel(sections) * nLayers * nChannels;
collectDiagnostics = nargout > 1;

% Create shared channel directories before dispatch. Every section writes a
% unique filename, so workers never coordinate or mutate common files.
channelDirectories = strings(nChannels, 1);
for c = 1:nChannels
    channel = datasetIndex.channels(c);
    channelDirectories(c) = string(fullfile(outputRoot, ...
        sprintf("ch%02d_%s", channel.id, channel.name)));
    mkdir(channelDirectories(c));
end

requestedWorkers = cfg.execution.reconstructionWorkers;
workerCount = min(requestedWorkers, numel(sections));
useParallel = workerCount > 1;

fprintf("Reconstruction: %d sections x %d layers x %d channels = %d planes.\n", ...
    numel(sections), nLayers, nChannels, nPlanes);
fprintf("Fusion: %s; z illumination: %s.\n", ...
    cfg.fusion.mode, cfg.zIllumination.method);
if useParallel
    fprintf("Execution: parallel, %d workers; one complete section per task.\n", ...
        workerCount);
else
    fprintf("Execution: serial; one complete section at a time.\n");
end
fprintf("Output: %s\n", outputRoot);

sectionManifests = cell(numel(sections), 1);
sectionDiagnostics = cell(numel(sections), 1);
if useParallel
    poolCleanup = openPool(workerCount); %#ok<NASGU>
    parfor sectionIndex = 1:numel(sections)
        [sectionManifests{sectionIndex}, sectionDiagnostics{sectionIndex}] = ...
            stpt.reconstruction.processSection(datasetIndex, model, cfg, ...
            sections(sectionIndex), channelDirectories, collectDiagnostics);
    end
else
    for sectionIndex = 1:numel(sections)
        [sectionManifests{sectionIndex}, sectionDiagnostics{sectionIndex}] = ...
            stpt.reconstruction.processSection(datasetIndex, model, cfg, ...
            sections(sectionIndex), channelDirectories, collectDiagnostics);
    end
end

% Scheduling order is deliberately absent from all published products.
manifest = vertcat(sectionManifests{:});
manifest = sortrows(manifest, ["sectionNumber", "channelId", "layer"]);
validateManifest(manifest, nPlanes);

if collectDiagnostics
    diagnostics = vertcat(sectionDiagnostics{:});
    [~, order] = sortrows([[diagnostics.sectionNumber]', ...
        [diagnostics.channelId]']);
    diagnostics = diagnostics(order);
else
    diagnostics = struct([]);
end
end

function poolCleanup = openPool(workerCount)
% Create a stage-owned local process pool and close it after reconstruction.
if ~license('test', 'Distrib_Computing_Toolbox')
    error("stpt:ParallelReconstruction", ...
        "Parallel reconstruction requires Parallel Computing Toolbox.");
end

pool = gcp("nocreate");
if ~isempty(pool)
    if pool.NumWorkers ~= workerCount
        error("stpt:ParallelReconstruction", ...
            "The existing pool has %d workers; configured reconstructionWorkers=%d.", ...
            pool.NumWorkers, workerCount);
    end
    fprintf("Using existing parallel pool with %d workers.\n", workerCount);
    poolCleanup = onCleanup(@() []);
    return
end

fprintf("Starting local parallel pool with %d workers.\n", workerCount);
pool = parpool("local", workerCount);
poolCleanup = onCleanup(@() delete(pool));
end

function validateManifest(manifest, expectedPlanes)
% A successful call publishes exactly one existing file per requested plane.
keyNames = ["sectionNumber", "layer", "channelId"];
keys = unique(manifest(:, keyNames), "rows");
if height(manifest) ~= expectedPlanes || height(keys) ~= expectedPlanes || ...
        ~all(isfile(manifest.filePath))
    error("stpt:ReconstructionOutput", ...
        "Reconstruction did not produce one file for every requested plane.");
end
end

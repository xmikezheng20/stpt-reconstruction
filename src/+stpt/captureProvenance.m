function provenance = captureProvenance(repoRoot, cfg)
%CAPTUREPROVENANCE Record the exact code revisions used for a pipeline run.
%
% The reconstruction repository and the pinned StitchIt reference are recorded
% separately. A dirty flag is essential because a commit hash alone does not
% identify code containing uncommitted changes.

% Record the execution environment alongside source-control state.
provenance = struct();
provenance.captured = string(datetime("now"));
provenance.matlabVersion = string(version);
provenance.repository = inspectGitRepository(repoRoot);

% Capture both the expected StitchIt revision from config and the revision that
% is actually present on disk. A mismatch is recorded rather than hidden.
provenance.stitchIt = inspectGitRepository(cfg.references.stitchIt.root);
provenance.stitchIt.expectedCommit = ...
    string(cfg.references.stitchIt.expectedCommit);
provenance.stitchIt.matchesExpectedCommit = ...
    provenance.stitchIt.commit == provenance.stitchIt.expectedCommit;
end

function info = inspectGitRepository(repoPath)
% Query Git without modifying the repository or its working tree.
repoPath = string(repoPath);
if ~isfolder(repoPath)
    error("stpt:MissingReferenceRepository", ...
        "Reference repository does not exist: %s", repoPath);
end

info = struct();
info.root = repoPath;
info.commit = runGit(repoPath, "rev-parse HEAD");
info.branch = runGit(repoPath, "branch --show-current");
statusText = runGit(repoPath, "status --porcelain=v1");
info.isDirty = strlength(strtrim(statusText)) > 0;
end

function output = runGit(repoPath, arguments)
% Paths are quoted because repository roots may contain spaces.
quotedPath = '"' + replace(repoPath, '"', '\"') + '"';
command = "git -C " + quotedPath + " " + arguments;
[status, output] = system(command);
if status ~= 0
    error("stpt:GitProvenance", ...
        "Git provenance command failed for %s: %s", repoPath, command);
end
output = strtrim(string(output));
end

function provenance = captureProvenance(repoRoot)
%CAPTUREPROVENANCE Record the exact code revisions used for a pipeline run.
%
% A dirty flag is essential because a commit hash alone does not identify code
% containing uncommitted changes. External reference repositories are not runtime
% dependencies; algorithm sources are documented in local function headers.

% Record the execution environment alongside source-control state.
provenance = struct();
provenance.captured = string(datetime("now"));
provenance.matlabVersion = string(version);
provenance.repository = inspectGitRepository(repoRoot);
end

function info = inspectGitRepository(repoPath)
% Query Git without modifying the repository or its working tree.
repoPath = string(repoPath);
if ~isfolder(repoPath)
    error("stpt:MissingRepository", ...
        "Reconstruction repository does not exist: %s", repoPath);
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

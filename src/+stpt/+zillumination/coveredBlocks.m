function covered = coveredBlocks(supportMask, block, gridSize)
%COVEREDBLOCKS Grid pixels whose every native pixel was acquired.
%
% A missing tile is neither background nor tissue, so a block that is only
% partly acquired never enters a z-illumination estimate. Scalar true means
% complete coverage.

if isscalar(supportMask)
    covered = true(gridSize);
else
    covered = stpt.zillumination.blockMean(single(supportMask), block) == 1;
end
end

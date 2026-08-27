function [model, audit] = fit(datasetIndex, cfg, stageDir)
%FIT Fit direct pooled templates from the completed log-Otsu selection.

stageDir = string(stageDir);
templateDir = fullfile(stageDir, "templates");
mkdir(templateDir);

selectionPath = fullfile(cfg.paths.outputRoot, "02_illumination", ...
    "tissue_otsu", "01_selection", "tissueSelection.mat");
selection = stpt.illumination.tissueOtsu.loadSelection( ...
    selectionPath, datasetIndex, cfg);

trimPercent = cfg.illumination.tissueOtsu.templateTrimPercent;
nChannels = numel(datasetIndex.channels);
nLayers = datasetIndex.geometry.layersPerSection;
templates = cell(nChannels, nLayers);
templatePaths = strings(nChannels, nLayers);
countRows = cell(nChannels * nLayers, 1);
record = 0;

fprintf("Method: tissueOtsu\n");
fprintf("Using completed selection: %s\n", selectionPath);
fprintf("Fitting %d channel/layer template pairs with %.1f%% trimming.\n", ...
    nChannels * nLayers, trimPercent);
fprintf("No corrected TIFFs are written.\n\n");

% Fit one channel/layer at a time so only one selected tile stack is resident.
for c = 1:nChannels
    channelId = datasetIndex.channels(c).id;
    for layer = 1:nLayers
        record = record + 1;
        fprintf("  ch%d, layer %d (%d/%d)\n", ...
            channelId, layer, record, nChannels * nLayers);
        template = stpt.illumination.tissueOtsu.estimateTemplate( ...
            datasetIndex, selection, channelId, layer, trimPercent);
        templates{c, layer} = template;

        templatePath = fullfile(templateDir, ...
            sprintf("ch%d_layer%d.mat", channelId, layer));
        save(templatePath, "template", "-v7.3");
        templatePaths(c, layer) = templatePath;

        countRows{record} = struct("channelId", channelId, "layer", layer, ...
            "oddSelectedCount", template.oddN, ...
            "evenSelectedCount", template.evenN, ...
            "trimPercent", trimPercent);
    end
end

model = stpt.illumination.buildModelFromTemplates(templates, datasetIndex, cfg);
model.methodDetails = struct( ...
    "selectionThresholdLog", selection.thresholdLog, ...
    "selectionThresholdRawEquivalent", selection.thresholdRawEquivalent, ...
    "templateTrimPercent", trimPercent);

templateCounts = struct2table(vertcat(countRows{:}));
templateSummary = stpt.illumination.summarizeModel(model);
writetable(templateCounts, fullfile(stageDir, "template_counts.csv"));
writetable(templateSummary, fullfile(stageDir, "template_summary.csv"));

audit = struct();
audit.schemaVersion = 1;
audit.created = string(datetime("now"));
audit.method = string(cfg.illumination.method);
audit.trainingSections = cfg.illumination.trainingSections(:)';
audit.qcSections = cfg.illumination.qcSections(:)';
audit.selectionPath = string(selectionPath);
audit.selectionThresholdLog = selection.thresholdLog;
audit.selectionThresholdRawEquivalent = selection.thresholdRawEquivalent;
audit.selectionSummary = selection.summary;
audit.templateCounts = templateCounts;
audit.templateSummary = templateSummary;
audit.templatePaths = templatePaths;

stpt.illumination.tissueOtsu.writeModelQC(audit, model, stageDir);
end

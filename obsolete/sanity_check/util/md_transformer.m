function md_transformer(transformer_fill_table, T, kVA_known, kVA_imputed, ...
    N_tot_all, N_ok_all, N_zer_all, R_mean_all, R_std_all, ...
    X_mean_all, Uk_known, Psc_known, kVA_vals)
% MD_TRANSFORMER  Generates markdown files for transformer parameter analysis.
%
%   Writes:
%     sanity-check-website/docs/Transformer_summary.md
%     sanity-check-website/docs/Transformer_details.md

docs_dir = fullfile('sanity-check-website', 'docs');

% ── FILE 1: Summary ───────────────────────────────────────────────────────
fid = fopen(fullfile(docs_dir, 'Transformer_summary.md'), 'w');

fprintf(fid, '# Transformer Parameter Analysis\n\n');


fprintf(fid, '## Portfolio Overview\n\n');
fprintf(fid, '| Metric | Value |\n');
fprintf(fid, '|--------|-------|\n');
fprintf(fid, '| Total transformers | %d |\n',            height(T));
fprintf(fid, '| Unique kVA ratings | %d |\n',            length(kVA_vals));
fprintf(fid, '| Types with valid R/X pairs | %d |\n',    length(kVA_known));
fprintf(fid, '| Types with imputed R/X | %d |\n',        length(kVA_imputed));
fprintf(fid, '| Total missing R (0 or NaN) | %d |\n',    sum(T.R_pu == 0 | isnan(T.R_pu)));
fprintf(fid, '| Total missing X (0 or NaN) | %d |\n',    sum(T.X_pu == 0 | isnan(T.X_pu)));
fprintf(fid, '| Uk%% range (known types) | %.2f – %.2f |\n', min(Uk_known), max(Uk_known));
fprintf(fid, '| Psc range (known types, W) | %.0f – %.0f |\n', min(Psc_known), max(Psc_known));
fprintf(fid, '\n');

fprintf(fid, '## Fill Table — All kVA Types\n\n');
fprintf(fid, 'Values used to fill missing R and X in the dataset. ');
fprintf(fid, '`measured_mean` = mean of valid entries in data. ');
fprintf(fid, '`imputed` = interpolated from neighboring known types.\n\n');
fprintf(fid, '| kVA | R\\_pu\\_fill | X\\_pu\\_fill | Uk%% | Psc (W) | Source |\n');
fprintf(fid, '|-----|------------|------------|------|---------|--------|\n');

for i = 1:height(transformer_fill_table)
    fprintf(fid, '| %.0f | %.6f | %.6f | %.3f | %.1f | %s |\n', ...
        transformer_fill_table.kVA(i), ...
        transformer_fill_table.R_pu_fill(i), ...
        transformer_fill_table.X_pu_fill(i), ...
        transformer_fill_table.Uk_pct(i), ...
        transformer_fill_table.Psc_W(i), ...
        transformer_fill_table.source{i});
end

fprintf(fid,'\n');
fprintf(fid, '![Transformer Analysis](transformer_analysis.png)\n\n');
fprintf(fid, '\n');
fprintf(fid, 'See [Transformer Details](Transformer_details.md) for per-type validation statistics.\n');
fclose(fid);

% ── FILE 2: Details ───────────────────────────────────────────────────────
fid = fopen(fullfile(docs_dir, 'Transformer_details.md'), 'w');

fprintf(fid, '# Transformer Parameter Details\n\n');
fprintf(fid, '**Total transformers: %d across %d unique kVA ratings**\n\n', ...
    height(T), length(kVA_vals));

fprintf(fid, '**Filter:**\n');
fprintf(fid, '<select id="trFilter" onchange="applyTrFilter()">\n');
fprintf(fid, '  <option value="">All types</option>\n');
fprintf(fid, '  <option value="imputed">Imputed only</option>\n');
fprintf(fid, '  <option value="measured">Measured only</option>\n');
fprintf(fid, '  <option value="highCoV">High CoV (>20%%)</option>\n');
fprintf(fid, '  <option value="missingAll">All missing R</option>\n');
fprintf(fid, '</select>\n');
fprintf(fid, '<p id="trFilterCount"></p>\n\n');

fprintf(fid, '| kVA | N\\_tot | N\\_ok | N\\_zer | R\\_mean | R\\_std | X\\_mean | CoV R (%%) | Source |\n');
fprintf(fid, '|-----|--------|-------|--------|---------|--------|---------|-----------|--------|\n');

for i = 1:length(kVA_vals)
    kva = kVA_vals(i);

    % Determine source
    if ismember(kva, kVA_known)
        src = 'measured\_mean';
    elseif ismember(kva, kVA_imputed)
        src = 'imputed';
    else
        src = 'no\_data';
    end

    % CoV
    R_v = T.R_pu(T.kVA == kva & T.R_pu > 0);
    if numel(R_v) >= 2 && mean(R_v) > 0
        CoV = (std(R_v) / mean(R_v)) * 100;
    else
        CoV = NaN;
    end

    if isnan(R_mean_all(i))
        fprintf(fid, '| %.0f | %d | %d | %d | — | — | %.4f | — | %s |\n', ...
            kva, N_tot_all(i), N_ok_all(i), N_zer_all(i), ...
            X_mean_all(i), src);
    elseif isnan(CoV)
        fprintf(fid, '| %.0f | %d | %d | %d | %.5f | %.5f | %.4f | — | %s |\n', ...
            kva, N_tot_all(i), N_ok_all(i), N_zer_all(i), ...
            R_mean_all(i), R_std_all(i), X_mean_all(i), src);
    else
        fprintf(fid, '| %.0f | %d | %d | %d | %.5f | %.5f | %.4f | %.1f | %s |\n', ...
            kva, N_tot_all(i), N_ok_all(i), N_zer_all(i), ...
            R_mean_all(i), R_std_all(i), X_mean_all(i), CoV, src);
    end
end

fprintf(fid, '\n');

% JS filter
fprintf(fid, '<script>\n');
fprintf(fid, 'function applyTrFilter() {\n');
fprintf(fid, '  var filterValue = document.getElementById("trFilter").value;\n');
fprintf(fid, '  var table = document.querySelector("table");\n');
fprintf(fid, '  var tr = table.getElementsByTagName("tr");\n');
fprintf(fid, '  var count = 0;\n');
fprintf(fid, '  for (var i = 1; i < tr.length; i++) {\n');
fprintf(fid, '    var cells = tr[i].getElementsByTagName("td");\n');
fprintf(fid, '    if (cells.length < 8) continue;\n');
fprintf(fid, '    var src    = cells[7].textContent.trim();\n');
fprintf(fid, '    var n_zer  = parseInt(cells[3].textContent.trim());\n');
fprintf(fid, '    var cov    = parseFloat(cells[6].textContent.trim());\n');
fprintf(fid, '    var show   = false;\n');
fprintf(fid, '    if      (filterValue === "")           show = true;\n');
fprintf(fid, '    else if (filterValue === "imputed"     && src.includes("imputed"))       show = true;\n');
fprintf(fid, '    else if (filterValue === "measured"    && src.includes("measured"))      show = true;\n');
fprintf(fid, '    else if (filterValue === "highCoV"     && cov > 20)                     show = true;\n');
fprintf(fid, '    else if (filterValue === "missingAll"  && n_zer > 0)                    show = true;\n');
fprintf(fid, '    tr[i].style.display = show ? "" : "none";\n');
fprintf(fid, '    if (show) count++;\n');
fprintf(fid, '  }\n');
fprintf(fid, '  document.getElementById("trFilterCount").textContent =\n');
fprintf(fid, '    `Showing ${count} transformer types`;\n');
fprintf(fid, '}\n');
fprintf(fid, '</script>\n');

fclose(fid);
disp('Transformer markdown files written successfully');
end
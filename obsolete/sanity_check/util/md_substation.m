function md_substation(results)

% ── FILE 1: Summary ─────────────────────────────────────────────────────
fid = fopen('./sanity-check-website/docs/Substation_summary.md', 'w');
fprintf(fid, '# Substation Analysis\n\n');
fprintf(fid, '**Total networks analysed: %d**\n\n', height(results));
fprintf(fid, '## Portfolio Summary\n\n');
fprintf(fid, '| Metric | Value |\n');
fprintf(fid, '|--------|-------|\n');
fprintf(fid, '| Total transformers | %d |\n',                    sum(results.n_transformers));
fprintf(fid, '| Networks with >1 transformer | %d |\n',          sum(results.n_transformers > 1));
fprintf(fid, '| Networks with no transformer | %d |\n', sum(results.n_transformers == 0));
fprintf(fid, '| Networks with missing rated power | %d |\n',     sum(results.missing_power > 0));
fprintf(fid, '| Networks with missing R (p.u.) | %d |\n',        sum(results.missing_R > 0));
fprintf(fid, '| Networks with missing X (p.u.) | %d |\n',        sum(results.missing_X > 0));
fprintf(fid, '| Networks with open switches | %d |\n',           sum(results.n_open_switches > 0));
fprintf(fid, '| Total installed capacity (kVA) | %.0f |\n',      sum(results.total_rated_power));
fprintf(fid, '| Mean capacity per network (kVA) | %.1f |\n',     mean(results.total_rated_power(results.total_rated_power > 0)));
fprintf(fid, '| Max capacity single network (kVA) | %.0f |\n',   max(results.total_rated_power));
fprintf(fid, '\n');
fprintf(fid, '\n');
fprintf(fid, '** See [Network-Level Details](Substation_details.md) for per-network breakdown.\n');
fclose(fid);

% ── FILE 2: Details ──────────────────────────────────────────────────────
fid = fopen('./sanity-check-website/docs/Substation_details.md', 'w');
fprintf(fid, '# Substation Network-Level Details\n\n');

% Filter dropdown
fprintf(fid, '**Filter:**\n');
fprintf(fid, '<select id="subFilter" onchange="applySubFilter()">\n');
fprintf(fid, '  <option value="">Select Filter</option>\n');
fprintf(fid, '  <option value="missingPower">Missing Rated Power</option>\n');
fprintf(fid, '  <option value="missingR">Missing R (p.u.)</option>\n');
fprintf(fid, '  <option value="missingX">Missing X (p.u.)</option>\n');
fprintf(fid, '  <option value="multiTransformer">Multiple Transformers</option>\n');
fprintf(fid, '  <option value="openSwitches">Has Open Switches</option>\n');
fprintf(fid, '  <option value="noTransformer">No Transformer</option>\n');
fprintf(fid, '</select>\n');
fprintf(fid, '<p id="subFilterCount"></p>\n\n');
fprintf(fid, '**Total networks: %d**\n\n', height(results));

% Table
fprintf(fid, '| Substation ID | Objects | Transformers | Switches | Fuses | Open Switches | Total kVA | Max kVA | Missing R | Missing X | Missing Power | HV (kV) | LV (kV) |\n');
fprintf(fid, '|--------------|---------|--------------|----------|-------|--------------|-----------|---------|-----------|-----------|---------------|---------|--------|\n');

for i = 1:height(results)
    fprintf(fid, '| %d | %d | %d | %d | %d | %d | %.0f | %.0f | %d | %d | %d | %.1f | %.3f |\n', ...
        results.substation_ID(i), results.n_total_objects(i), results.n_transformers(i), ...
        results.n_switches(i), results.n_fuses(i), results.n_open_switches(i), ...
        results.total_rated_power(i), results.max_rated_power(i), ...
        results.missing_R(i), results.missing_X(i), results.missing_power(i), ...
        results.hv_voltage(i), results.lv_voltage(i));
end
fclose(fid);

disp('Substation md files written successfully');
end
function generate_line_parameter_details(line_data)
% GENERATE_LINE_PARAMETER_DETAILS  Generates Line_parameter_details.html and
%   line_data.json for the MkDocs website. Called at the end of line_parameter_analysis.
%
%   INPUT:
%     line_data  - MATLAB table with fields:
%                  substation_ID, Length, Resistance, Reactance, ampacity,
%                  section, material, cable_id, cable_type

    docs_dir  = fullfile(pwd, 'sanity-check-website', 'docs');
    html_path = fullfile(docs_dir, 'Line_parameter_details.html');
    json_path = fullfile(docs_dir, 'line_data.json');

    %% --- Write JSON data file ---
    fprintf('Writing line_data.json (%d rows)...\n', height(line_data));
    fid = fopen(json_path, 'w');
    if fid == -1
        error('Could not open line_data.json for writing.');
    end

    fprintf(fid, '[\n');
    for i = 1:height(line_data)
        sid   = line_data.substation_ID(i);
        len   = line_data.Length(i);
        res   = line_data.Resistance(i);
        rea   = line_data.Reactance(i);
        amp   = line_data.ampacity(i);
        sec   = line_data.section(i);
        mat   = strrep(line_data.material{i}, '"', '\"');
        cid   = line_data.cable_id(i);
        ctype = strrep(string(line_data.cable_type(i)), '"', '\"');

        % Format numbers — use null for NaN
        fmt = @(v) format_num(v);

        fprintf(fid, '  [%d,%s,%s,%s,%s,%s,"%s",%d,"%s"]', ...
            sid, fmt(len), fmt(res), fmt(rea), fmt(amp), fmt(sec), mat, cid, ctype);

        if i < height(line_data)
            fprintf(fid, ',\n');
        else
            fprintf(fid, '\n');
        end
    end
    fprintf(fid, ']\n');
    fclose(fid);
    fprintf('line_data.json written successfully.\n');

    %% --- Write HTML file ---
    fid = fopen(html_path, 'w');
    if fid == -1
        error('Could not open Line_parameter_details.html for writing.');
    end

    fprintf(fid, '%s\n', [
    "<!DOCTYPE html>"
    "<html lang=""en"">"
    "<head>"
    "<meta charset=""UTF-8"">"
    "<meta name=""viewport"" content=""width=device-width, initial-scale=1.0"">"
    "<title>Line Parameter Details</title>"
    "<style>"
    "  body { font-family: sans-serif; font-size: 14px; padding: 1.5rem; color: #1a1a1a; }"
    "  h1 { font-size: 20px; font-weight: 500; margin-bottom: 0.25rem; }"
    "  .subtitle { color: #666; font-size: 13px; margin-bottom: 1.5rem; }"
    "  .controls { display: flex; gap: 12px; align-items: center; margin-bottom: 1rem; flex-wrap: wrap; }"
    "  select { font-size: 13px; padding: 6px 10px; border: 0.5px solid #ccc; border-radius: 6px; }"
    "  #filterCount { font-size: 13px; color: #666; }"
    "  table { width: 100%; border-collapse: collapse; font-size: 13px; table-layout: fixed; }"
    "  th { text-align: left; padding: 7px 8px; font-weight: 500; font-size: 12px; color: #555;"
    "       border-bottom: 1px solid #e0e0e0; background: #fafafa; }"
    "  td { padding: 6px 8px; border-bottom: 0.5px solid #efefef; overflow: hidden;"
    "       text-overflow: ellipsis; white-space: nowrap; }"
    "  tr:hover td { background: #f5f5f5; }"
    "  .missing { color: #c0392b; font-style: italic; }"
    "  .pager { display: flex; gap: 8px; align-items: center; margin-top: 1rem; font-size: 13px; color: #555; }"
    "  .pager button { padding: 4px 12px; border: 0.5px solid #ccc; border-radius: 6px;"
    "                  background: white; cursor: pointer; font-size: 13px; }"
    "  .pager button:hover { background: #f0f0f0; }"
    "  .pager button:disabled { opacity: 0.4; cursor: default; }"
    "  #loading { color: #666; font-size: 14px; padding: 2rem 0; }"
    "</style>"
    "</head>"
    "<body>"
    "<h1>Line Parameter Details</h1>"
    "<div class=""subtitle"">Full line-level dataset — all LV networks (Sion &amp; Sierre). Duplicates removed.</div>"
    ""
    "<div id=""loading"">Loading data...</div>"
    "<div id=""main"" style=""display:none"">"
    "  <div class=""controls"">"
    "    <strong>Filter:</strong>"
    "    <select id=""dataFilter"" onchange=""applyFilter()"">"
    "      <option value="""">Select Filter</option>"
    "      <option value=""missingAmpacity"">Show Missing Ampacity (0 or NaN)</option>"
    "      <option value=""missingImpedance"">Show Missing Impedance (Resistance or Reactance = 0 or NaN)</option>"
    "      <option value=""missingLength"">Show Missing Length (0 or NaN)</option>"
    "      <option value=""missingCrossSection"">Show Missing Cross-Section (0 or NaN)</option>"
    "      <option value=""missingCrossSectionAmpacity"">Show Missing Cross-Section &amp; Ampacity</option>"
    "      <option value=""missingCrossSectionAmpacityImpedance"">Show Missing Cross-Section, Ampacity &amp; Impedance</option>"
    "    </select>"
    "    <p id=""filterCount""></p>"
    "  </div>"
    ""
    "  <table>"
    "    <thead>"
    "      <tr>"
    "        <th style=""width:90px"">Station ID</th>"
    "        <th style=""width:90px"">Length (m)</th>"
    "        <th style=""width:90px"">R (Ω/km)</th>"
    "        <th style=""width:90px"">X (Ω/km)</th>"
    "        <th style=""width:90px"">Ampacity (A)</th>"
    "        <th style=""width:100px"">Section (mm²)</th>"
    "        <th style=""width:70px"">Material</th>"
    "        <th style=""width:70px"">Cable ID</th>"
    "        <th style=""width:80px"">Cable type</th>"
    "      </tr>"
    "    </thead>"
    "    <tbody id=""tableBody""></tbody>"
    "  </table>"
    ""
    "  <div class=""pager"">"
    "    <button id=""btnPrev"" onclick=""prevPage()"">← Prev</button>"
    "    <span id=""pageInfo""></span>"
    "    <button id=""btnNext"" onclick=""nextPage()"">Next →</button>"
    "    <span style=""margin-left:auto; color:#999"">100 rows per page</span>"
    "  </div>"
    "</div>"
    ""
    "<script>"
    "const ROWS_PER_PAGE = 100;"
    "let allData = [], filtered = [], currentPage = 0;"
    ""
    "const isMissing = v => v === null || v === 0 || (typeof v === 'number' && isNaN(v));"
    "const fmt = v => isMissing(v) ? '<span class=""missing"">missing</span>' : v;"
    ""
    "fetch('line_data.json')"
    "  .then(r => r.json())"
    "  .then(data => {"
    "    allData = data;"
    "    document.getElementById('loading').style.display = 'none';"
    "    document.getElementById('main').style.display = '';"
    "    applyFilter();"
    "  })"
    "  .catch(e => {"
    "    document.getElementById('loading').textContent = 'Error loading data: ' + e.message;"
    "  });"
    ""
    "function applyFilter() {"
    "  const f = document.getElementById('dataFilter').value;"
    "  filtered = allData.filter(r => {"
    "    const [sid,len,res,rea,amp,sec,mat,cid,ctype] = r;"
    "    if (!f) return true;"
    "    if (f === 'missingAmpacity') return isMissing(amp);"
    "    if (f === 'missingImpedance') return isMissing(res) || isMissing(rea);"
    "    if (f === 'missingLength') return isMissing(len);"
    "    if (f === 'missingCrossSection') return isMissing(sec);"
    "    if (f === 'missingCrossSectionAmpacity') return isMissing(sec) && isMissing(amp);"
    "    if (f === 'missingCrossSectionAmpacityImpedance') return isMissing(sec) && isMissing(amp) && (isMissing(res) || isMissing(rea));"
    "    return true;"
    "  });"
    "  currentPage = 0;"
    "  document.getElementById('filterCount').textContent ="
    "    f ? filtered.length + ' matching rows' : allData.length + ' total rows';"
    "  renderPage();"
    "}"
    ""
    "function renderPage() {"
    "  const start = currentPage * ROWS_PER_PAGE;"
    "  const slice = filtered.slice(start, start + ROWS_PER_PAGE);"
    "  const tb = document.getElementById('tableBody');"
    "  tb.innerHTML = slice.map(r =>"
    "    '<tr>' + r.map(v => '<td>' + fmt(v) + '</td>').join('') + '</tr>'"
    "  ).join('');"
    "  const total = Math.max(1, Math.ceil(filtered.length / ROWS_PER_PAGE));"
    "  document.getElementById('pageInfo').textContent ="
    "    'Page ' + (currentPage + 1) + ' of ' + total;"
    "  document.getElementById('btnPrev').disabled = currentPage === 0;"
    "  document.getElementById('btnNext').disabled = currentPage >= total - 1;"
    "}"
    ""
    "function prevPage() { if (currentPage > 0) { currentPage--; renderPage(); } }"
    "function nextPage() { if ((currentPage+1)*ROWS_PER_PAGE < filtered.length) { currentPage++; renderPage(); } }"
    "</script>"
    "</body>"
    "</html>"
    ]);

    fclose(fid);
    fprintf('Line_parameter_details.html written successfully.\n');
end

function s = format_num(v)
% Returns JSON-safe number string — null for NaN
    if isnan(v)
        s = 'null';
    else
        s = num2str(v, '%g');
    end
end
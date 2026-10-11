# Transformer Parameter Details

**Total transformers: 1346 across 27 unique kVA ratings**

**Filter:**
<select id="trFilter" onchange="applyTrFilter()">
  <option value="">All types</option>
  <option value="imputed">Imputed only</option>
  <option value="measured">Measured only</option>
  <option value="highCoV">High CoV (>20%)</option>
  <option value="missingAll">All missing R</option>
</select>
<p id="trFilterCount"></p>

| kVA | N\_tot | N\_ok | N\_zer | R\_mean | R\_std | X\_mean | CoV R (%) | Source |
|-----|--------|-------|--------|---------|--------|---------|-----------|--------|
| 10 | 13 | 0 | 13 | — | — | 0.0400 | — | imputed |
| 50 | 2 | 1 | 1 | 0.02078 | 0.00000 | 0.0380 | — | measured\_mean |
| 60 | 1 | 0 | 1 | — | — | 0.0340 | — | imputed |
| 75 | 1 | 0 | 1 | — | — | 0.0400 | — | imputed |
| 100 | 22 | 13 | 9 | 0.01843 | 0.00409 | 0.0380 | 22.2 | measured\_mean |
| 105 | 1 | 0 | 1 | — | — | 0.0420 | — | imputed |
| 115 | 3 | 0 | 3 | — | — | 0.0410 | — | imputed |
| 150 | 2 | 0 | 2 | — | — | 0.0393 | — | imputed |
| 160 | 42 | 33 | 9 | 0.01165 | 0.00127 | 0.0391 | 10.9 | measured\_mean |
| 200 | 16 | 8 | 8 | 0.01805 | 0.00108 | 0.0391 | 6.0 | measured\_mean |
| 250 | 97 | 88 | 9 | 0.01063 | 0.00167 | 0.0410 | 15.7 | measured\_mean |
| 280 | 1 | 0 | 1 | — | — | 0.0400 | — | imputed |
| 300 | 10 | 7 | 3 | 0.01437 | 0.00440 | 0.0403 | 30.6 | measured\_mean |
| 315 | 2 | 0 | 2 | — | — | 0.0400 | — | imputed |
| 320 | 1 | 0 | 1 | — | — | 0.0400 | — | imputed |
| 350 | 1 | 0 | 1 | — | — | 0.0400 | — | imputed |
| 400 | 264 | 238 | 26 | 0.00884 | 0.00147 | 0.0428 | 16.6 | measured\_mean |
| 500 | 7 | 6 | 1 | 0.01328 | 0.00053 | 0.0399 | 4.0 | measured\_mean |
| 600 | 2 | 1 | 1 | 0.01250 | 0.00000 | 0.0443 | — | measured\_mean |
| 630 | 724 | 696 | 28 | 0.00717 | 0.00100 | 0.0453 | 14.0 | measured\_mean |
| 800 | 4 | 4 | 0 | 0.00781 | 0.00051 | 0.0482 | 6.5 | measured\_mean |
| 1000 | 124 | 124 | 0 | 0.00663 | 0.00071 | 0.0512 | 10.8 | measured\_mean |
| 1250 | 2 | 2 | 0 | 0.00664 | 0.00001 | 0.0461 | 0.2 | measured\_mean |
| 1400 | 1 | 0 | 1 | — | — | 0.0400 | — | imputed |
| 1600 | 1 | 0 | 1 | — | — | 0.0400 | — | imputed |
| 2000 | 1 | 0 | 1 | — | — | 0.0400 | — | imputed |
| 2500 | 1 | 0 | 1 | — | — | 0.0400 | — | imputed |

<script>
function applyTrFilter() {
  var filterValue = document.getElementById("trFilter").value;
  var table = document.querySelector("table");
  var tr = table.getElementsByTagName("tr");
  var count = 0;
  for (var i = 1; i < tr.length; i++) {
    var cells = tr[i].getElementsByTagName("td");
    if (cells.length < 8) continue;
    var src    = cells[7].textContent.trim();
    var n_zer  = parseInt(cells[3].textContent.trim());
    var cov    = parseFloat(cells[6].textContent.trim());
    var show   = false;
    if      (filterValue === "")           show = true;
    else if (filterValue === "imputed"     && src.includes("imputed"))       show = true;
    else if (filterValue === "measured"    && src.includes("measured"))      show = true;
    else if (filterValue === "highCoV"     && cov > 20)                     show = true;
    else if (filterValue === "missingAll"  && n_zer > 0)                    show = true;
    tr[i].style.display = show ? "" : "none";
    if (show) count++;
  }
  document.getElementById("trFilterCount").textContent =
    `Showing ${count} transformer types`;
}
</script>

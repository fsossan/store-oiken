// Function to filter rows by voltage value
function filterByVoltage() {
    var input = document.getElementById("voltageFilter").value;
    var filter = parseFloat(input) || 0;
    var table = document.querySelector("table");
    var tr = table.getElementsByTagName("tr");
    var count = 0;

    for (var i = 1; i < tr.length; i++) {
        var td = tr[i].getElementsByTagName("td")[2];
        if (td) {
            var cellText = td.textContent.trim();

            // Skip error/NaN rows
            if (cellText.startsWith("NaN")) {
                tr[i].style.display = "none";
                continue;
            }

            // Parse just the voltage number (before the space + node ID)
            var voltage = parseFloat(cellText.split(" ")[0]);

            if (!isNaN(voltage) && voltage <= filter) {
                tr[i].style.display = "";
                count++;
            } else {
                tr[i].style.display = "none";
            }
        }
    }
    document.getElementById("voltageCount").textContent = 
        `Total Networks fitting criteria: ${count}`;
}

// Function to filter rows by line ampacity
function filterByLineAmpacity() {
    var input = document.getElementById("ampacityfilter").value;
    var filter = parseFloat(input) || 0;
    var table = document.querySelector("table");
    var tr = table.getElementsByTagName("tr");
    var count = 0;

    for (var i = 1; i < tr.length; i++) {
        var td = tr[i].getElementsByTagName("td")[4];
        if (td) {
            var cellText = td.textContent.trim();

            // Skip error/NaN rows
            if (cellText.startsWith("NaN")) {
                tr[i].style.display = "none";
                continue;
            }

            // Parse just the current number (before the space + line ID)
            var current = parseFloat(cellText.split(" ")[0]);

            if (!isNaN(current) && current > filter) {
                tr[i].style.display = "";
                count++;
            } else {
                tr[i].style.display = "none";
            }
        }
    }
    document.getElementById("ampacityCount").textContent = 
        `Total Networks fitting criteria: ${count}`;
}

// Function to search in the table by Substation ID
function searchTable() {
    var input = document.getElementById("searchInput").value.toUpperCase().trim();
    var table = document.querySelector("table");
    var tr = table.getElementsByTagName("tr");

    for (var i = 1; i < tr.length; i++) {
        var td = tr[i].getElementsByTagName("td")[0];
        if (td) {
            var txtValue = td.textContent || td.innerText;
            if (txtValue.toUpperCase().trim() === input) {
                tr[i].style.display = "";
            } else {
                tr[i].style.display = "none";
            }
        }
    }
}

// Function to filter by Network Type
function filterByNetworkType() {
    var input = document.getElementById("networkTypeFilter").value.toLowerCase().trim();
    var rows = document.querySelectorAll("table tr");
    var count = 0;

    for (var i = 1; i < rows.length; i++) {
        var cells = rows[i].querySelectorAll("td");
        if (cells.length > 0) {
            var networkType = cells[9]?.textContent.toLowerCase().trim();

            if (networkType === input) {
                rows[i].style.display = "";
                count++;
            } else {
                rows[i].style.display = "none";
            }
        }
    }
    document.getElementById("networkTypeCount").textContent = 
        `Total Networks matching type: ${count}`;
}

// Function to apply data quality filters
function applyFilter() {
    var filterValue = document.getElementById("dataFilter").value;
    var table = document.querySelector("table");
    var tr = table.getElementsByTagName("tr");
    var count = 0;
    var uniqueStations = new Set();

    for (var i = 1; i < tr.length; i++) {
        var ampacity_td       = tr[i].getElementsByTagName("td")[4];
        var resistance_td     = tr[i].getElementsByTagName("td")[2];
        var reactance_td      = tr[i].getElementsByTagName("td")[3];
        var length_td         = tr[i].getElementsByTagName("td")[1];
        var cross_section_td  = tr[i].getElementsByTagName("td")[5];

        var showRow = false;

        if (ampacity_td && resistance_td && reactance_td && length_td && cross_section_td) {
            // Parse values - split to handle "value nodeID" format
            var ampacity     = ampacity_td.textContent.trim().split(" ")[0];
            var resistance   = resistance_td.textContent.trim().split(" ")[0];
            var reactance    = reactance_td.textContent.trim().split(" ")[0];
            var length       = length_td.textContent.trim().split(" ")[0];
            var cross_section = cross_section_td.textContent.trim().split(" ")[0];

            var isMissingAmpacity = (
                ampacity === "" || ampacity === "0" || 
                isNaN(parseFloat(ampacity)) || ampacity === "NaN"
            );
            var isMissingImpedance = (
                (resistance === "" || resistance === "0" || 
                 isNaN(parseFloat(resistance)) || resistance === "NaN") ||
                (reactance === "" || reactance === "0" || 
                 isNaN(parseFloat(reactance)) || reactance === "NaN")
            );
            var isMissingLength = (
                length === "" || length === "0" || 
                isNaN(parseFloat(length)) || length === "NaN"
            );
            var isMissingCrossSection = (
                !cross_section || cross_section.trim() === "" ||
                cross_section.trim() === "0" || 
                isNaN(parseFloat(cross_section)) || cross_section === "NaN"
            );

            var isMissingCrossSectionAmpacity = (
                isMissingCrossSection && isMissingAmpacity
            );
            var isMissingCrossSectionAmpacityImpedance = (
                isMissingCrossSection && isMissingAmpacity && isMissingImpedance
            );
            var isMissingCrossSectionAmpacityorImpedance = (
                isMissingCrossSection || isMissingAmpacity || isMissingImpedance
            );

            if      (filterValue === "missingAmpacity"                          && isMissingAmpacity)                          showRow = true;
            else if (filterValue === "missingImpedance"                         && isMissingImpedance)                         showRow = true;
            else if (filterValue === "missingLength"                            && isMissingLength)                            showRow = true;
            else if (filterValue === "missingCrossSection"                      && isMissingCrossSection)                      showRow = true;
            else if (filterValue === "missingCrossSectionAmpacity"              && isMissingCrossSectionAmpacity)              showRow = true;
            else if (filterValue === "missingCrossSectionAmpacityImpedance"     && isMissingCrossSectionAmpacityImpedance)     showRow = true;
            else if (filterValue === "missingCrossSectionAmpacityorImpedance"   && isMissingCrossSectionAmpacityorImpedance)   showRow = true;

            tr[i].style.display = showRow ? "" : "none";

            if (showRow) {
                count++;
                var stationId = tr[i].getElementsByTagName("td")[0].textContent.trim();
                uniqueStations.add(stationId);
            }
        }
    }
    document.getElementById("filterCount").textContent =
        `Total rows matching filter: ${count} | Unique station IDs affected: ${uniqueStations.size}`;
}

// transformer filter
function applySubFilter() {
    var filterValue = document.getElementById("subFilter").value;
    var table = document.querySelector("table");
    var tr = table.getElementsByTagName("tr");
    var count = 0;
    var totalTransformers = 0;

    for (var i = 1; i < tr.length; i++) {
        var cells = tr[i].getElementsByTagName("td");
        if (cells.length < 13) continue;

        var n_transformers  = parseInt(cells[2].textContent.trim());
        var open_switches   = parseInt(cells[5].textContent.trim());
        var missing_R       = parseInt(cells[8].textContent.trim());
        var missing_X       = parseInt(cells[9].textContent.trim());
        var missing_power   = parseInt(cells[10].textContent.trim());

        var show = false;
        if      (filterValue === "missingPower"      && missing_power > 0)   show = true;
        else if (filterValue === "missingR"           && missing_R > 0)       show = true;
        else if (filterValue === "missingX"           && missing_X > 0)       show = true;
        else if (filterValue === "multiTransformer"   && n_transformers > 1)  show = true;
        else if (filterValue === "openSwitches"       && open_switches > 0)   show = true;
        else if (filterValue === "noTransformer" && n_transformers === 0) show = true;

        tr[i].style.display = show ? "" : "none";
        if (show) {
            count++;
            totalTransformers += n_transformers;
        }
    }
    document.getElementById("subFilterCount").textContent =
        `Total networks matching filter: ${count} | Transformers affected: ${totalTransformers}`;
}

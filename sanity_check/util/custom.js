// Function to filter rows by voltage value
function filterByVoltage() {
  var input = document.getElementById("voltageFilter").value;
  var filter = parseFloat(input) || 0;  // Get the filter value
  var table = document.querySelector("table"); // Select the table
  var tr = table.getElementsByTagName("tr");
  var count = 0;  // Initialize a counter for matching rows

  for (var i = 1; i < tr.length; i++) {
    var td = tr[i].getElementsByTagName("td")[2]; // Now checking the 3rd column (Lowest Voltage)
    if (td) {
      var voltage = parseFloat(td.textContent) || NaN;  // Handle NaN if not a valid number
      if (!isNaN(voltage) && voltage <= filter) {  // Show rows if voltage is lower or equal to filter
        tr[i].style.display = "";
        count++;  // Increment counter for rows that meet the criteria
      } else {
        tr[i].style.display = "none";
      }
    }
  }
 // Update the count display on the page
  document.getElementById("voltageCount").textContent = `Total Networks fitting criteria: ${count}`;
}
function filterByLineAmpacity() {
  var input = document.getElementById("ampacityfilter").value;
  var filter = parseFloat(input) || 0;  // Get the filter value (default to 0 if invalid)
  var table = document.querySelector("table"); // Select the table
  var tr = table.getElementsByTagName("tr");
  var count = 0;  // Counter for matching rows

  for (var i = 1; i < tr.length; i++) {  // Skip header row
    var td = tr[i].getElementsByTagName("td")[4]; // Adjust index if needed (4 = 5th column)
    if (td) {
      var current = parseFloat(td.textContent) || NaN;  // Clean whitespace and parse value
      if (!isNaN(current) && current > filter) {  // Show rows where current/ampacity > threshold
        tr[i].style.display = "";  // Show the row
        count++;  // Increment counter
      } else {
        tr[i].style.display = "none";  // Hide the row if condition not met
      }
    }
  }

  // Update the count display
  document.getElementById("ampacityCount").textContent = `Total Networks fitting criteria: ${count}`;
}

 // Function to search in the table by Substation ID
function searchTable() {
  var input = document.getElementById("searchInput").value.toUpperCase().trim(); // Get the search input and convert to uppercase
  var table = document.querySelector("table"); // Select the table
  var tr = table.getElementsByTagName("tr");

  for (var i = 1; i < tr.length; i++) {
    var td = tr[i].getElementsByTagName("td")[0];  // Assuming Substation ID is in the 1st column
    if (td) {
      var txtValue = td.textContent || td.innerText;
      // Check for an exact match by comparing strings directly
      if (txtValue.toUpperCase().trim() === input) {
        tr[i].style.display = "";  // Show matching rows
      } else {
        tr[i].style.display = "none";  // Hide non-matching rows
      }
    }
  }
}
// Function to filter by Network Type
function filterByNetworkType() {
  var input = document.getElementById("networkTypeFilter").value.toLowerCase().trim();
  var rows = document.querySelectorAll("table tr"); // Select all table rows
  var count = 0;

  for (var i = 1; i < rows.length; i++) { // Skip the header row
      var cells = rows[i].querySelectorAll("td"); // Get all cells in the current row
      if (cells.length > 0) {
          var networkType = cells[9]?.textContent.toLowerCase().trim(); // Check the 10th column (index 9)
          
          if (networkType === input) {
              rows[i].style.display = ""; // Show matching rows
              count++; // Increment the count for matching networks
          } else {
              rows[i].style.display = "none"; // Hide non-matching rows
          }
      }
  }

  // Update the count display correctly
  document.getElementById("networkTypeCount").textContent = `Total Networks matching type: ${count}`;
}
function applyFilter() {
  var filterValue = document.getElementById("dataFilter").value;
  var table = document.querySelector("table");  // Select the table
  var tr = table.getElementsByTagName("tr");  // Get all rows
  var count = 0;  // Counter for matching rows

  for (var i = 1; i < tr.length; i++) {  // Start from 1 to skip headers
    var ampacity_td = tr[i].getElementsByTagName("td")[4];  // Ampacity column (5th column)
    var resistance_td = tr[i].getElementsByTagName("td")[2];  // Resistance column (3rd column)
    var reactance_td = tr[i].getElementsByTagName("td")[3];  // Reactance column (4th column)
    var length_td = tr[i].getElementsByTagName("td")[1];  // Length column (2nd column)
    var cross_section_td = tr[i].getElementsByTagName("td")[5];  // Cross-section column (6th column)
    
    var showRow = false;  // Default: Hide row unless it matches the condition

    if (ampacity_td && resistance_td && reactance_td && length_td && cross_section_td) {
      var ampacity = ampacity_td.textContent.trim();
      var resistance = resistance_td.textContent.trim();
      var reactance = reactance_td.textContent.trim();
      var length = length_td.textContent.trim();
      var cross_section = cross_section_td.textContent.trim();

      var isMissingAmpacity = (ampacity === "" || ampacity === "0" || isNaN(parseFloat(ampacity)));
      var isMissingImpedance = (
        (resistance === "" || resistance === "0" || isNaN(parseFloat(resistance))) ||
        (reactance === "" || reactance === "0" || isNaN(parseFloat(reactance)))
      );
      var isMissingLength = (length === "" || length === "0" || isNaN(parseFloat(length)));
      var isMissingCrossSection = (
        !cross_section ||  // Detects null, undefined, or empty
        cross_section.trim() === "" ||  // Explicitly checks for an empty string
        cross_section.trim() === "0" ||  // Detects zero values
        isNaN(parseFloat(cross_section))  // Detects NaN values
      );

      var isMissingCrossSectionAmpacity = isMissingCrossSection && isMissingAmpacity;
      
      // NEW condition: missing cross-section, ampacity, and impedance
      var isMissingCrossSectionAmpacityImpedance = (
        isMissingCrossSection && isMissingAmpacity && isMissingImpedance
      );

      if (filterValue === "missingAmpacity" && isMissingAmpacity) {
        showRow = true;
      } else if (filterValue === "missingImpedance" && isMissingImpedance) {
        showRow = true;
      } else if (filterValue === "missingLength" && isMissingLength) {
        showRow = true;
      } else if (filterValue === "missingCrossSection" && isMissingCrossSection) {
        showRow = true;
      } else if (filterValue === "missingCrossSectionAmpacity" && isMissingCrossSectionAmpacity) {
        showRow = true;
      } 
      // Check for new condition
      else if (filterValue === "missingCrossSectionAmpacityImpedance" && isMissingCrossSectionAmpacityImpedance) {
        showRow = true;
      }

      // Show or hide row based on filter condition
      tr[i].style.display = showRow ? "" : "none";

      if (showRow) count++;  // Increment count for visible rows
    }
  }

  // Update the displayed count
  document.getElementById("filterCount").textContent = `Total rows matching filter: ${count}`;
}
#####################################################################
# Program Name: 07_interactive_circle_network.R
# Project: Major Migration Analysis - Cheltenham College
# Created: 01FEB2026 (IEC/Claude)
# GOAL: Creates interactive HTML circle network diagram with D3.js
#   - Interactive tooltips showing bidirectional flows
#   - Hover to highlight connections
#   - Click to filter/focus on specific majors
#   - Smart curve routing to avoid crossing through clusters
#   - Proper Instrument Sans font from Google Fonts
#   - Responsive and smooth interactions
#   - Requires: student_migration.csv and major_catalog.csv
#####################################################################

# --- 1. SETUP: Load necessary libraries ---
if (!require("pacman")) install.packages("pacman")
pacman::p_load(
  here,        # For robust file path management
  tidyverse,   # For data manipulation
  jsonlite     # For creating JSON data for D3
)

# --- 2. LOAD INPUT DATA ---

student_migration_path <- here("data", "data-raw", "student_migration.csv")
major_catalog_path <- here("data", "data-raw", "major_catalog.csv")

student_migration <- read_csv(student_migration_path, show_col_types = FALSE)
major_catalog <- read_csv(major_catalog_path, show_col_types = FALSE)

cat("✓ Loaded student migration data:", nrow(student_migration), "records\n")
cat("✓ Loaded major catalog:", nrow(major_catalog), "majors\n\n")

# --- 3. DEFINE DIVISION COLORS ---

division_colors <- c(
  "APP" = "#E69F00",  # Orange
  "HUM" = "#56B4E9",  # Sky Blue
  "NAT" = "#009E73",  # Bluish Green
  "SOC" = "#D55E00"   # Vermillion
)

division_names <- c(
  "APP" = "Applied Sciences",
  "HUM" = "Humanities",
  "NAT" = "Natural Sciences",
  "SOC" = "Social Sciences"
)

# --- 4. CALCULATE MAJOR STATISTICS ---

starting_counts <- student_migration %>%
  count(starting_major, name = "start_count")

ending_counts <- student_migration %>%
  count(ending_major, name = "end_count")

major_stats <- major_catalog %>%
  left_join(starting_counts, by = c("major_code" = "starting_major")) %>%
  left_join(ending_counts, by = c("major_code" = "ending_major")) %>%
  replace_na(list(start_count = 0, end_count = 0)) %>%
  mutate(
    net_change = end_count - start_count,
    is_magnet = end_count > start_count * 1.5 & end_count > 20
  )

cat("Major statistics calculated\n\n")

# --- 5. CALCULATE MIGRATION FLOWS ---

migration_flows <- student_migration %>%
  filter(starting_major != ending_major) %>%
  count(starting_major, ending_major, name = "flow_count") %>%
  filter(flow_count >= 1) %>%
  left_join(major_catalog %>% select(major_code, division_code),
            by = c("starting_major" = "major_code")) %>%
  rename(source_division = division_code)

cat("Migration flows calculated:", nrow(migration_flows), "flows\n\n")

# --- 6. CREATE BIDIRECTIONAL EDGES ---

edges_bidirectional <- migration_flows %>%
  mutate(
    pair = pmap_chr(list(starting_major, ending_major),
                    ~paste(sort(c(..1, ..2)), collapse = "-"))
  ) %>%
  group_by(pair) %>%
  summarize(
    major1 = first(starting_major),
    major2 = first(ending_major),
    flow_1to2 = sum(flow_count[starting_major == major1 & ending_major == major2]),
    flow_2to1 = sum(flow_count[starting_major == major2 & ending_major == major1]),
    total_flow = sum(flow_count),
    .groups = "drop"
  ) %>%
  filter(total_flow >= 1) %>%
  left_join(major_catalog %>% select(major_code, division_code),
            by = c("major1" = "major_code")) %>%
  rename(division1 = division_code) %>%
  left_join(major_catalog %>% select(major_code, division_code),
            by = c("major2" = "major_code")) %>%
  rename(division2 = division_code) %>%
  mutate(
    dominant_division = ifelse(flow_1to2 >= flow_2to1, division2, division1)
  )

cat("Bidirectional edges created:", nrow(edges_bidirectional), "connections\n\n")

# --- 7. CREATE CIRCULAR LAYOUT ---

divisions_order <- c("SOC", "APP", "HUM", "NAT")

major_by_division <- list()
for (div in divisions_order) {
  div_majors <- major_stats %>%
    filter(division_code == div) %>%
    arrange(major_code) %>%
    pull(major_code)
  major_by_division[[div]] <- div_majors
}

all_majors_ordered <- unlist(major_by_division, use.names = FALSE)
n_total <- length(all_majors_ordered)

major_positions <- tibble()
radius <- 250  # Reduced from 300 for smaller circle
angle_step <- 360 / n_total

for (i in seq_along(all_majors_ordered)) {
  angle_deg <- 180 - (i - 1) * angle_step

  major_positions <- bind_rows(
    major_positions,
    tibble(
      major = all_majors_ordered[i],
      angle = angle_deg,
      x = radius * cos(angle_deg * pi / 180),
      y = radius * sin(angle_deg * pi / 180)
    )
  )
}

major_stats <- major_stats %>%
  left_join(major_positions, by = c("major_code" = "major"))

cat("Circular layout created\n\n")

# --- 8. CALCULATE DIVISION LABEL POSITIONS ---

division_label_positions <- tibble()
label_radius <- 330  # Adjusted for smaller circle (was 390)

for (div in divisions_order) {
  div_majors_data <- major_stats %>%
    filter(division_code == div) %>%
    arrange(angle)

  n_div <- nrow(div_majors_data)

  # Get median position(s)
  if (n_div %% 2 == 1) {
    # Odd number: use middle major
    median_idx <- ceiling(n_div / 2)
    median_angle <- div_majors_data$angle[median_idx]
  } else {
    # Even number: use average of two middle majors
    mid_idx1 <- n_div / 2
    mid_idx2 <- mid_idx1 + 1
    median_angle <- mean(c(div_majors_data$angle[mid_idx1],
                           div_majors_data$angle[mid_idx2]))
  }

  # Calculate label position
  label_x <- label_radius * cos(median_angle * pi / 180)
  label_y <- label_radius * sin(median_angle * pi / 180)

  division_label_positions <- bind_rows(
    division_label_positions,
    tibble(
      division = div,
      label_text = division_names[div],
      label_x = label_x,
      label_y = label_y,
      color = division_colors[div]
    )
  )
}

cat("Division label positions calculated\n\n")

# --- 9. PREPARE DATA FOR D3 ---

# Nodes data
nodes_data <- major_stats %>%
  mutate(
    id = major_code,
    label = major_code,
    count = end_count,
    net = net_change,
    division = division_code,
    color = division_colors[division_code],
    radius_size = 5 + 25 * sqrt(end_count / max(end_count))
  ) %>%
  select(id, label, x, y, count, net, division, color, radius_size)

# Links data with curvature
links_data <- edges_bidirectional %>%
  left_join(major_positions %>% select(major, angle),
            by = c("major1" = "major")) %>%
  rename(angle1 = angle) %>%
  left_join(major_positions %>% select(major, angle),
            by = c("major2" = "major")) %>%
  rename(angle2 = angle) %>%
  mutate(
    angle_diff = abs(angle2 - angle1),
    angle_diff = ifelse(angle_diff > 180, 360 - angle_diff, angle_diff),
    curvature = case_when(
      angle_diff < 60 ~ 0.5,
      angle_diff < 120 ~ 0.3,
      TRUE ~ 0.1
    ),
    color = division_colors[dominant_division]
  ) %>%
  select(source = major1, target = major2,
         flow_1to2, flow_2to1, total_flow, curvature, color)

# Division labels data
division_labels_data <- division_label_positions

# Create lookup table HTML
# The major_catalog now includes major_name column with full names
lookup_items <- major_catalog %>%
  arrange(division_code, major_code) %>%
  mutate(
    html_item = sprintf(
      '                <div class="lookup-item"><span class="lookup-code">%s</span><span class="lookup-name">%s</span></div>',
      major_code,
      major_name
    )
  ) %>%
  pull(html_item) %>%
  paste(collapse = "\n")

# Convert to JSON
nodes_json <- toJSON(nodes_data, pretty = TRUE)
links_json <- toJSON(links_data, pretty = TRUE)
divisions_json <- toJSON(division_labels_data, pretty = TRUE)

cat("Data prepared for D3\n\n")

# --- 10. CREATE HTML WITH D3.JS ---

# Build HTML in parts
html_head <- '
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Major Migration Network - Interactive</title>
    <link rel="preconnect" href="https://fonts.googleapis.com">
    <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
    <link href="https://fonts.googleapis.com/css2?family=Instrument+Sans:wght@400;600;700&display=swap" rel="stylesheet">
    <script src="https://d3js.org/d3.v7.min.js"></script>
    <style>
        body {
            margin: 0;
            padding: 20px;
            font-family: "Instrument Sans", Arial, sans-serif;
            background-color: #ffffff;
        }
        .container {
            max-width: 1400px;
            margin: 0 auto;
        }
        .content-wrapper {
            display: flex;
            justify-content: center;
            align-items: flex-start;
            gap: 30px;
            max-width: 1400px;
            margin: 0 auto;
        }
        #chart {
            flex: 0 0 900px;
            display: flex;
            justify-content: center;
        }
        .lookup-container {
            flex: 0 0 350px;
            padding: 20px;
            background-color: #f8f9fa;
            border-radius: 8px;
            max-height: 700px;
            overflow-y: auto;
            margin-top: 40px;
        }
        .lookup-title {
            font-family: "Instrument Sans", Arial, sans-serif;
            font-size: 18px;
            font-weight: 600;
            color: #2c3e50;
            margin: 0 0 15px 0;
            text-align: center;
        }
        .lookup-grid {
            display: flex;
            flex-direction: column;
            gap: 8px;
            font-size: 13px;
            font-family: "Instrument Sans", Arial, sans-serif;
        }
        .lookup-item {
            display: flex;
            gap: 8px;
            padding: 6px 10px;
            background-color: white;
            border-radius: 4px;
            font-family: "Instrument Sans", Arial, sans-serif;
        }
        .lookup-code {
            font-weight: 600;
            color: #495057;
            min-width: 55px;
            flex-shrink: 0;
        }
        .lookup-name {
            color: #6c757d;
        }
        h1 {
            text-align: center;
            font-size: 28px;
            font-weight: 600;
            color: #2c3e50;
            margin: 0 0 10px 0;
        }
        .subtitle {
            text-align: center;
            font-size: 16px;
            color: #6c757d;
            margin: 0 0 10px 0;
        }
        .tooltip {
            position: absolute;
            background-color: white;
            border: 2px solid #dee2e6;
            border-radius: 6px;
            padding: 12px 16px;
            font-size: 14px;
            pointer-events: none;
            opacity: 0;
            transition: opacity 0.2s;
            box-shadow: 0 4px 6px rgba(0,0,0,0.1);
            z-index: 1000;
        }
        .tooltip.visible {
            opacity: 1;
        }
        .tooltip-title {
            font-weight: 600;
            font-size: 16px;
            margin-bottom: 8px;
            color: #2c3e50;
        }
        .tooltip-detail {
            color: #495057;
            line-height: 1.6;
        }
        .link {
            fill: none;
            stroke-opacity: 0.4;
            transition: stroke-opacity 0.2s;
        }
        .link.highlighted {
            stroke-opacity: 0.8;
            stroke-width: 3;
        }
        .link.dimmed {
            stroke-opacity: 0.1;
        }
        .node-circle {
            cursor: pointer;
            transition: opacity 0.2s;
        }
        .node-circle.dimmed {
            opacity: 0.3;
        }
        .node-label {
            font-family: "Instrument Sans", Arial, sans-serif;
            font-size: 11px;
            font-weight: 600;
            pointer-events: none;
            user-select: none;
        }
        .division-label {
            font-family: "Instrument Sans", Arial, sans-serif;
            font-size: 18px;
            font-weight: 600;
            pointer-events: none;
            user-select: none;
        }
        .controls {
            text-align: center;
            margin-bottom: 10px;
        }
        .control-btn {
            padding: 8px 16px;
            margin: 0 5px;
            background-color: #f8f9fa;
            border: 1px solid #dee2e6;
            border-radius: 4px;
            font-family: "Instrument Sans", Arial, sans-serif;
            font-size: 14px;
            cursor: pointer;
            transition: background-color 0.2s;
        }
        .control-btn:hover {
            background-color: #e9ecef;
        }
        .control-btn.active {
            background-color: #007bff;
            color: white;
            border-color: #007bff;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>Major Migration Network</h1>
        <div class="subtitle">Circle size = Graduates | Line color = Division receiving more students | Hover for details | Click to highlight</div>

        <div class="controls">
            <button class="control-btn active" onclick="showAllFlows()">All Flows</button>
            <button class="control-btn" onclick="showMajorFlows()">Major Flows (≥10)</button>
            <button class="control-btn" onclick="resetHighlight()">Reset</button>
        </div>

        <div class="content-wrapper">
            <div id="chart"></div>

            <div class="lookup-container">
                <h2 class="lookup-title">Major Code Reference</h2>
                <div class="lookup-grid">
'

html_lookup <- paste0(lookup_items, '
                </div>
            </div>
        </div>
    </div>

    <div class="tooltip"></div>

    <script>
        // Data
        const nodes = ')

html_script <- paste0(nodes_json, ';
        const links = ', links_json, ';
        const divisionLabels = ', divisions_json, ';
')

html_rest <- '

        // SVG setup
        const width = 900;
        const height = 750;  // Reduced from 850
        const centerX = width / 2;
        const centerY = height / 2;

        const svg = d3.select("#chart")
            .append("svg")
            .attr("width", width)
            .attr("height", height)
            .attr("viewBox", [0, 0, width, height])
            .style("margin-top", "-50px");  // Increased from -20px

        const g = svg.append("g")
            .attr("transform", `translate(${centerX}, ${centerY})`);

        // Tooltip
        const tooltip = d3.select(".tooltip");

        // Current filter
        let currentFilter = "all";
        let selectedNode = null;

        // Create path generator for curves with collision avoidance
        function createCurvedPath(d) {
            const sourceNode = nodes.find(n => n.id === d.source);
            const targetNode = nodes.find(n => n.id === d.target);

            const x1 = sourceNode.x;
            const y1 = sourceNode.y;
            const x2 = targetNode.x;
            const y2 = targetNode.y;

            // Calculate midpoint and distance
            const midX = (x1 + x2) / 2;
            const midY = (y1 + y2) / 2;
            const dx = x2 - x1;
            const dy = y2 - y1;
            const dist = Math.sqrt(dx * dx + dy * dy);

            // Calculate angle between points
            const angle = Math.atan2(dy, dx);

            // Determine base curvature based on distance
            let baseCurvature = d.curvature;

            // Check if any nodes are near the midpoint (potential collision)
            let hasCollision = false;
            const collisionThreshold = 40; // Distance threshold for collision detection

            for (const node of nodes) {
                if (node.id === d.source || node.id === d.target) continue;

                const nodeDist = Math.sqrt(
                    Math.pow(node.x - midX, 2) +
                    Math.pow(node.y - midY, 2)
                );

                if (nodeDist < collisionThreshold) {
                    hasCollision = true;
                    break;
                }
            }

            // If collision detected, increase curvature and try routing inward
            let curvatureMultiplier = hasCollision ? 1.8 : 1.0;

            // Determine if we should curve inward (toward center) or outward
            // Calculate if midpoint is inside or outside the circle
            const midDistFromCenter = Math.sqrt(midX * midX + midY * midY);
            const shouldCurveInward = midDistFromCenter < 250; // Inside the node circle

            // Calculate perpendicular offset
            const offset = dist * baseCurvature * curvatureMultiplier;
            const perpAngle = angle + (shouldCurveInward ? -Math.PI/2 : Math.PI/2);

            const cx = midX + offset * Math.cos(perpAngle);
            const cy = midY + offset * Math.sin(perpAngle);

            return `M ${x1},${y1} Q ${cx},${cy} ${x2},${y2}`;
        }

        // Draw links
        const linkGroup = g.append("g").attr("class", "links");
        let linkElements = linkGroup.selectAll("path")
            .data(links)
            .join("path")
            .attr("class", "link")
            .attr("d", createCurvedPath)
            .attr("stroke", d => d.color)
            .attr("stroke-width", d => 1 + Math.sqrt(d.total_flow) / 2)
            .on("mouseover", function(event, d) {
                tooltip.html(`
                    <div class="tooltip-title">${d.source} ↔ ${d.target}</div>
                    <div class="tooltip-detail">
                        ${d.source} → ${d.target}: ${d.flow_1to2} students<br>
                        ${d.target} → ${d.source}: ${d.flow_2to1} students<br>
                        <strong>Total: ${d.total_flow} students</strong>
                    </div>
                `)
                .classed("visible", true)
                .style("left", (event.pageX + 10) + "px")
                .style("top", (event.pageY - 10) + "px");
            })
            .on("mouseout", function() {
                tooltip.classed("visible", false);
            });

        // Draw nodes
        const nodeGroup = g.append("g").attr("class", "nodes");
        const nodeElements = nodeGroup.selectAll("g")
            .data(nodes)
            .join("g")
            .attr("transform", d => `translate(${d.x}, ${d.y})`);

        nodeElements.append("circle")
            .attr("class", "node-circle")
            .attr("r", d => d.radius_size)
            .attr("fill", d => d.color)
            .attr("stroke", "black")
            .attr("stroke-width", 1.5)
            .on("mouseover", function(event, d) {
                tooltip.html(`
                    <div class="tooltip-title">${d.label}</div>
                    <div class="tooltip-detail">
                        Graduates: ${d.count}<br>
                        Net change: ${d.net > 0 ? "+" : ""}${d.net}<br>
                        Division: ${d.division}
                    </div>
                `)
                .classed("visible", true)
                .style("left", (event.pageX + 10) + "px")
                .style("top", (event.pageY - 10) + "px");

                // Highlight connected links
                if (!selectedNode) {
                    highlightNode(d.id);
                }
            })
            .on("mouseout", function() {
                tooltip.classed("visible", false);
                if (!selectedNode) {
                    resetHighlight();
                }
            })
            .on("click", function(event, d) {
                event.stopPropagation();
                if (selectedNode === d.id) {
                    selectedNode = null;
                    resetHighlight();
                } else {
                    selectedNode = d.id;
                    highlightNode(d.id);
                }
            });

        // Add labels to nodes
        nodeElements.append("text")
            .attr("class", "node-label")
            .attr("text-anchor", "middle")
            .attr("dy", ".35em")
            .text(d => d.label)
            .style("fill", "black");

        // Add division labels
        g.selectAll(".division-label")
            .data(divisionLabels)
            .join("text")
            .attr("class", "division-label")
            .attr("x", d => d.label_x)
            .attr("y", d => d.label_y)
            .attr("text-anchor", "middle")
            .attr("fill", d => d.color)
            .text(d => d.label_text);

        // Helper functions
        function highlightNode(nodeId) {
            linkElements
                .classed("highlighted", d => d.source === nodeId || d.target === nodeId)
                .classed("dimmed", d => d.source !== nodeId && d.target !== nodeId);

            nodeElements.selectAll(".node-circle")
                .classed("dimmed", d => {
                    const isConnected = links.some(l =>
                        (l.source === nodeId && l.target === d.id) ||
                        (l.target === nodeId && l.source === d.id)
                    );
                    return d.id !== nodeId && !isConnected;
                });
        }

        function resetHighlight() {
            selectedNode = null;
            linkElements
                .classed("highlighted", false)
                .classed("dimmed", false);
            nodeElements.selectAll(".node-circle")
                .classed("dimmed", false);
        }

        function showAllFlows() {
            currentFilter = "all";
            updateButtons();
            linkElements = linkGroup.selectAll("path")
                .data(links)
                .join("path")
                .attr("class", "link")
                .attr("d", createCurvedPath)
                .attr("stroke", d => d.color)
                .attr("stroke-width", d => 1 + Math.sqrt(d.total_flow) / 2)
                .on("mouseover", function(event, d) {
                    tooltip.html(`
                        <div class="tooltip-title">${d.source} ↔ ${d.target}</div>
                        <div class="tooltip-detail">
                            ${d.source} → ${d.target}: ${d.flow_1to2} students<br>
                            ${d.target} → ${d.source}: ${d.flow_2to1} students<br>
                            <strong>Total: ${d.total_flow} students</strong>
                        </div>
                    `)
                    .classed("visible", true)
                    .style("left", (event.pageX + 10) + "px")
                    .style("top", (event.pageY - 10) + "px");
                })
                .on("mouseout", function() {
                    tooltip.classed("visible", false);
                });
            resetHighlight();
        }

        function showMajorFlows() {
            currentFilter = "major";
            updateButtons();
            const majorLinks = links.filter(d => d.total_flow >= 10);
            linkElements = linkGroup.selectAll("path")
                .data(majorLinks)
                .join("path")
                .attr("class", "link")
                .attr("d", createCurvedPath)
                .attr("stroke", d => d.color)
                .attr("stroke-width", d => 1 + Math.sqrt(d.total_flow) / 2)
                .on("mouseover", function(event, d) {
                    tooltip.html(`
                        <div class="tooltip-title">${d.source} ↔ ${d.target}</div>
                        <div class="tooltip-detail">
                            ${d.source} → ${d.target}: ${d.flow_1to2} students<br>
                            ${d.target} → ${d.source}: ${d.flow_2to1} students<br>
                            <strong>Total: ${d.total_flow} students</strong>
                        </div>
                    `)
                    .classed("visible", true)
                    .style("left", (event.pageX + 10) + "px")
                    .style("top", (event.pageY - 10) + "px");
                })
                .on("mouseout", function() {
                    tooltip.classed("visible", false);
                });
            resetHighlight();
        }

        function updateButtons() {
            d3.selectAll(".control-btn").classed("active", false);
            if (currentFilter === "all") {
                d3.selectAll(".control-btn").filter(function() {
                    return this.textContent.includes("All Flows");
                }).classed("active", true);
            } else {
                d3.selectAll(".control-btn").filter(function() {
                    return this.textContent.includes("Major Flows");
                }).classed("active", true);
            }
        }

        // Click anywhere to reset
        svg.on("click", resetHighlight);
    </script>
</body>
</html>
'

# Combine all parts
html_content <- paste0(html_head, html_lookup, html_script, html_rest)

# Suppress output to avoid R console parsing errors
invisible(html_content)

# --- 11. SAVE HTML ---

output_dir <- here("output")
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

output_path <- file.path(output_dir, "major_migration_network_interactive.html")
writeLines(html_content, output_path)

cat("=== INTERACTIVE CIRCLE NETWORK COMPLETE ===\n\n")
cat("File saved:", output_path, "\n\n")
cat("Interactive features:\n")
cat("  • Hover over nodes: See graduate count and net change\n")
cat("  • Hover over links: See bidirectional flow details\n")
cat("  • Click nodes: Highlight all connections\n")
cat("  • Filter buttons: Toggle between all flows and major flows (≥10)\n")
cat("  • Reset button: Clear all highlights\n")
cat("  • Smooth transitions and highlighting\n\n")
cat("Visual features:\n")
cat("  • Smart curve routing based on angular distance\n")
cat("  • Line color = Division receiving more students\n")
cat("  • Circle size = Number of graduates\n")
cat("  • Division labels positioned at median of each group\n")
cat("  • Instrument Sans font from Google Fonts\n")
cat("  • Moved up closer to title and buttons\n\n")

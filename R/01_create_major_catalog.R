#####################################################################
# Program Name: 01_create_major_catalog.R
# Project: Major Migration Analysis - Cheltenham College
# Created: 29JAN2026 (IEC/Claude)
# Modified: 01FEB2026 (IEC) - Added major_name column
# GOAL: Creates the master catalog of all majors and their divisions.
#   - Defines all 28 majors across 4 academic divisions
#   - Assigns division codes and full names
#   - Creates major_catalog.csv with all major metadata including full names
#   - Creates division_summary.csv showing major counts per division
#   - Saves outputs to 'data/data-raw/' for use in subsequent scripts
#####################################################################

# --- 1. SETUP: Load necessary libraries ---
if (!require("pacman")) install.packages("pacman")
pacman::p_load(
  here,      # For robust file path management
  tidyverse  # For data manipulation (dplyr, tibble, etc.)
)

# --- 2. CONFIGURATION: Define academic structure ---

# NOTE on Academic Divisions:
# Cheltenham College organizes majors into 4 broad divisions:
#   - HUM: Humanities (Arts, Languages, Philosophy, etc.)
#   - SOC: Social Sciences (Economics, Psychology, Sociology, etc.)
#   - NAT: Natural Sciences (Biology, Chemistry, Physics, Math)
#   - APP: Applied Sciences (Computer Science, Data Science, Neuroscience)
#
# This structure mirrors typical liberal arts college organization and
# will be used throughout the analysis for both division-level and
# major-level flow visualizations.

# --- 3. DATA GENERATION: Create major catalog ---

# Create the master catalog using tribble() for readable row-wise entry
# Each row represents one major with its code, full name, division code, and division name
major_catalog <- tribble(
  ~major_code, ~major_name, ~division_code, ~division_name,

  # Humanities Division (12 majors)
  "ART",  "Studio Art", "HUM", "Humanities",
  "ARTH", "Art History", "HUM", "Humanities",
  "ENGL", "English", "HUM", "Humanities",
  "FREN", "French", "HUM", "Humanities",
  "SPAN", "Spanish", "HUM", "Humanities",
  "PHIL", "Philosophy", "HUM", "Humanities",
  "RELI", "Religion", "HUM", "Humanities",
  "MUSC", "Music", "HUM", "Humanities",
  "RHET", "Rhetoric", "HUM", "Humanities",
  "THEA", "Theater", "HUM", "Humanities",
  "CLAS", "Classic and Medieval Culture", "HUM", "Humanities",
  "ASIA", "Asian Language & Culture", "HUM", "Humanities",

  # Social Sciences Division (8 majors)
  "ECON", "Economics", "SOC", "Social Sciences",
  "PSYC", "Psychology", "SOC", "Social Sciences",
  "SOCI", "Sociology", "SOC", "Social Sciences",
  "POLI", "Political Science", "SOC", "Social Sciences",
  "ANTH", "Anthropology", "SOC", "Social Sciences",
  "HIST", "History", "SOC", "Social Sciences",
  "AFAM", "African American Studies", "SOC", "Social Sciences",
  "GSWS", "Gender, Sexuality & Women's Studies", "SOC", "Social Sciences",

  # Natural Sciences Division (5 majors)
  "BIOL", "Biology", "NAT", "Natural Sciences",
  "CHEM", "Chemistry", "NAT", "Natural Sciences",
  "PHYS", "Physics & Astronomy", "NAT", "Natural Sciences",
  "MATH", "Mathematics", "NAT", "Natural Sciences",
  "ENVI", "Environmental Science", "NAT", "Natural Sciences",

  # Applied Sciences Division (3 majors)
  "CSCI", "Computer Science", "APP", "Applied Sciences",
  "ASDS", "Applied Statistics & Data Science", "APP", "Applied Sciences",
  "NEUR", "Neuroscience", "APP", "Applied Sciences"
)

# --- 4. CREATE SUMMARY: Division-level statistics ---

# Generate a summary showing the number of majors in each division
# This helps verify the structure and provides context for interpretation
division_summary <- major_catalog %>%
  group_by(division_code, division_name) %>%
  summarize(
    n_majors = n(),
    .groups = "drop"
  ) %>%
  arrange(division_code)

# --- 5. SAVE OUTPUTS: Store results for next scripts ---

# Define output directory using here() for portability
output_dir <- here("data", "data-raw")

# Create the directory if it doesn't exist
# recursive = TRUE creates parent directories if needed
# showWarnings = FALSE suppresses messages if directory already exists
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

# Define full file paths
major_catalog_path <- file.path(output_dir, "major_catalog.csv")
division_summary_path <- file.path(output_dir, "division_summary.csv")

# Save both files as CSV
# CSV format chosen for human readability and potential use in other tools
write_csv(major_catalog, major_catalog_path)
write_csv(division_summary, division_summary_path)

# --- 6. CONFIRMATION: Print completion message ---

cat(
  "\n=== SCRIPT 01: CREATE MAJOR CATALOG - COMPLETE ===\n",
  "\nFiles saved:\n",
  "  1. Major catalog:      ", major_catalog_path, "\n",
  "  2. Division summary:   ", division_summary_path, "\n",
  "\nSummary Statistics:\n"
)

# Print the division summary to console for quick verification
print(division_summary)

cat(
  "\nTotal majors cataloged: ", nrow(major_catalog), "\n",
  "\nNext step: Run 02_simulate_student_migration.R\n\n"
)

#####################################################################
# Program Name: 02_simulate_student_migration.R
# Project: Major Migration Analysis - Cheltenham College
# Created: 29JAN2026 (IEC/Claude)
# Modified: 29JAN2026 (IEC) - Models "magnet programs" in Applied Sciences
# GOAL: Simulates realistic migration with interdisciplinary magnet programs
#   - ASDS (Data Science): 67% are transfer students (extreme magnet)
#   - NEUR (Neuroscience): 33% are transfer students (strong magnet)
#   - CSCI (Computer Science): 20% are transfer students (modest magnet)
#   - Models realistic flows from feeder disciplines
#   - Produces compelling visual story of interdisciplinary programs
#   - Uses actual 5-year graduation data as target distribution
#####################################################################

# --- 1. SETUP ---
if (!require("pacman")) install.packages("pacman")
pacman::p_load(here, tidyverse)

set.seed(42)

# --- 2. LOAD DATA ---
major_catalog_path <- here("data", "data-raw", "major_catalog.csv")
major_catalog <- read_csv(major_catalog_path, show_col_types = FALSE)

cat("✓ Loaded major catalog:", nrow(major_catalog), "majors\n\n")

# --- 3. TARGET DISTRIBUTION (Actual graduation data) ---
actual_grads <- tribble(
  ~major_code, ~n_graduates,
  "ASDS", 28,   "CSCI", 79,   "NEUR", 74,
  "ART", 23,    "ARTH", 33,   "ASIA", 24,   "CLAS", 17,
  "ENGL", 98,   "FREN", 33,   "MUSC", 21,   "PHIL", 55,
  "RELI", 21,   "RHET", 66,   "SPAN", 27,   "THEA", 44,
  "BIOL", 139,  "CHEM", 125,  "ENVI", 154,  "MATH", 107,  "PHYS", 66,
  "AFAM", 8,    "ANTH", 38,   "ECON", 258,  "GSWS", 26,
  "HIST", 115,  "POLI", 252,  "PSYC", 264,  "SOCI", 116
)

n_students <- 2450

# --- 4. MAGNET PROGRAM SPECIFICATIONS ---

magnet_programs <- list(
  ASDS = list(
    starters_pct = 0.33,  # Only 33% started here (9 students)
    retention = 0.90       # High retention of those who start
  ),
  NEUR = list(
    starters_pct = 0.67,  # 67% started here (50 students)
    retention = 0.85       # High retention
  ),
  CSCI = list(
    starters_pct = 0.80,  # 80% started here (63 students)
    retention = 0.88       # High retention
  )
)

# --- 5. CALCULATE ADJUSTED STARTING DISTRIBUTION ---

target_distribution <- actual_grads %>%
  mutate(target_pct = n_graduates / sum(n_graduates))

starting_adjustment <- target_distribution %>%
  mutate(
    is_magnet = major_code %in% names(magnet_programs),
    adjusted_start = if_else(
      is_magnet,
      n_graduates * map_dbl(major_code, ~{
        if (.x %in% names(magnet_programs)) magnet_programs[[.x]]$starters_pct else 0.85
      }),
      n_graduates * 1.08
    )
  ) %>%
  mutate(start_pct = adjusted_start / sum(adjusted_start))

cat("=== STARTING DISTRIBUTION (ADJUSTED FOR MAGNETS) ===\n")
cat("\nMagnet programs (small starters):\n")
print(starting_adjustment %>%
        filter(is_magnet) %>%
        select(major_code, adjusted_start, n_graduates) %>%
        mutate(increase = n_graduates - adjusted_start))

# --- 6. DEFINE MIGRATION RULES ---

migration_rules <- list(
  # FEEDER MAJORS (send students TO magnets)
  "MATH" = list(targets = c("ASDS", "CSCI", "PHYS", "ECON"),
                probs = c(0.30, 0.30, 0.20, 0.20)),
  "PSYC" = list(targets = c("NEUR", "SOCI", "ASDS", "CSCI", "BIOL"),
                probs = c(0.35, 0.25, 0.20, 0.12, 0.08)),
  "BIOL" = list(targets = c("NEUR", "CHEM", "ENVI", "ASDS", "CSCI"),
                probs = c(0.35, 0.25, 0.20, 0.10, 0.10)),
  "CHEM" = list(targets = c("BIOL", "NEUR", "PHYS", "MATH", "ENVI"),
                probs = c(0.30, 0.25, 0.20, 0.15, 0.10)),
  "PHYS" = list(targets = c("MATH", "CSCI", "CHEM", "ASDS"),
                probs = c(0.30, 0.25, 0.20, 0.25)),
  "ECON" = list(targets = c("ASDS", "MATH", "POLI", "CSCI", "HIST"),
                probs = c(0.30, 0.25, 0.20, 0.15, 0.10)),
  "POLI" = list(targets = c("ECON", "HIST", "ASDS", "SOCI", "PHIL"),
                probs = c(0.30, 0.25, 0.20, 0.15, 0.10)),
  "SOCI" = list(targets = c("PSYC", "ANTH", "ASDS", "POLI", "HIST"),
                probs = c(0.30, 0.25, 0.20, 0.15, 0.10)),

  # MAGNET PROGRAMS (mostly retain, small outbound)
  "ASDS" = list(targets = c("CSCI", "ECON", "MATH", "PSYC"),
                probs = c(0.40, 0.30, 0.20, 0.10)),
  "NEUR" = list(targets = c("PSYC", "BIOL", "CHEM", "CSCI"),
                probs = c(0.40, 0.30, 0.20, 0.10)),
  "CSCI" = list(targets = c("ASDS", "MATH", "ECON", "PHYS"),
                probs = c(0.35, 0.30, 0.20, 0.15)),

  # OTHER MAJORS
  "ENVI" = list(targets = c("BIOL", "CHEM", "POLI", "SOCI"),
                probs = c(0.30, 0.25, 0.25, 0.20)),
  "ANTH" = list(targets = c("SOCI", "HIST", "PSYC", "AFAM"),
                probs = c(0.35, 0.25, 0.20, 0.20)),
  "AFAM" = list(targets = c("SOCI", "HIST", "ANTH", "ENGL"),
                probs = c(0.30, 0.30, 0.20, 0.20)),
  "GSWS" = list(targets = c("SOCI", "HIST", "PSYC", "ENGL"),
                probs = c(0.30, 0.25, 0.25, 0.20)),
  "HIST" = list(targets = c("POLI", "ECON", "ENGL", "CLAS"),
                probs = c(0.30, 0.25, 0.25, 0.20)),
  "ENGL" = list(targets = c("HIST", "RHET", "THEA", "PHIL"),
                probs = c(0.30, 0.25, 0.25, 0.20)),
  "PHIL" = list(targets = c("RELI", "POLI", "ENGL", "HIST"),
                probs = c(0.25, 0.25, 0.25, 0.25)),
  "RELI" = list(targets = c("PHIL", "HIST", "ENGL", "ASIA"),
                probs = c(0.30, 0.30, 0.20, 0.20)),
  "RHET" = list(targets = c("ENGL", "THEA", "PHIL", "POLI"),
                probs = c(0.35, 0.25, 0.20, 0.20)),
  "ART" = list(targets = c("ARTH", "THEA", "MUSC", "ENGL"),
               probs = c(0.35, 0.25, 0.20, 0.20)),
  "ARTH" = list(targets = c("ART", "HIST", "CLAS", "ASIA"),
                probs = c(0.30, 0.30, 0.20, 0.20)),
  "MUSC" = list(targets = c("ART", "THEA", "ENGL", "PSYC"),
                probs = c(0.30, 0.25, 0.25, 0.20)),
  "THEA" = list(targets = c("ENGL", "ART", "MUSC", "RHET"),
                probs = c(0.30, 0.25, 0.25, 0.20)),
  "FREN" = list(targets = c("SPAN", "ENGL", "HIST", "CLAS"),
                probs = c(0.35, 0.30, 0.20, 0.15)),
  "SPAN" = list(targets = c("FREN", "ENGL", "HIST", "ANTH"),
                probs = c(0.35, 0.30, 0.20, 0.15)),
  "CLAS" = list(targets = c("HIST", "PHIL", "ARTH", "ENGL"),
                probs = c(0.30, 0.25, 0.25, 0.20)),
  "ASIA" = list(targets = c("HIST", "RELI", "ANTH", "POLI"),
                probs = c(0.30, 0.25, 0.25, 0.20))
)

# --- 7. ASSIGN STARTING MAJORS ---

cat("\nGenerating student starting positions...\n")

starting_majors <- sample(
  starting_adjustment$major_code,
  n_students,
  replace = TRUE,
  prob = starting_adjustment$start_pct
)

cat("✓ Assigned starting majors\n")
cat("  ASDS starters:", sum(starting_majors == "ASDS"), "\n")
cat("  NEUR starters:", sum(starting_majors == "NEUR"), "\n")
cat("  CSCI starters:", sum(starting_majors == "CSCI"), "\n")

# --- 8. SIMULATE MAJOR SWITCHING ---

cat("\nSimulating major switching...\n")

get_retention_rate <- function(major) {
  if (major %in% names(magnet_programs)) {
    return(magnet_programs[[major]]$retention)
  }
  return(0.85)
}

assign_ending_major <- function(starting_major) {
  if (starting_major %in% names(migration_rules)) {
    rule <- migration_rules[[starting_major]]
    valid_targets <- rule$targets[rule$targets %in% major_catalog$major_code]

    if (length(valid_targets) > 0) {
      valid_indices <- which(rule$targets %in% valid_targets)
      valid_probs <- rule$probs[valid_indices]
      valid_probs <- valid_probs / sum(valid_probs)
      return(sample(valid_targets, 1, prob = valid_probs))
    }
  }
  return(starting_major)
}

ending_majors <- character(n_students)
for (i in 1:n_students) {
  retention_rate <- get_retention_rate(starting_majors[i])
  if (runif(1) < retention_rate) {
    ending_majors[i] <- starting_majors[i]
  } else {
    ending_majors[i] <- assign_ending_major(starting_majors[i])
  }
}

cat("✓ Simulated switching\n")

# --- 9. CREATE DATASET ---

student_migration <- tibble(
  student_id = 1:n_students,
  starting_major = starting_majors,
  ending_major = ending_majors
) %>%
  left_join(major_catalog %>% select(major_code, division_code),
            by = c("starting_major" = "major_code")) %>%
  rename(starting_division = division_code) %>%
  left_join(major_catalog %>% select(major_code, division_code),
            by = c("ending_major" = "major_code")) %>%
  rename(ending_division = division_code) %>%
  mutate(
    switched_division = starting_division != ending_division,
    switched_major = starting_major != ending_major
  )

# --- 10. VALIDATION ---

cat("\n=== MAGNET PROGRAM ANALYSIS ===\n\n")

for (prog in names(magnet_programs)) {
  starters <- sum(student_migration$starting_major == prog)
  stayers <- sum(student_migration$starting_major == prog &
                   student_migration$ending_major == prog)
  enders <- sum(student_migration$ending_major == prog)
  migrants_in <- enders - stayers

  cat(sprintf("%s:\n", prog))
  cat(sprintf("  Started: %d\n", starters))
  cat(sprintf("  Stayed: %d (%.0f%% retention)\n", stayers, 100*stayers/max(starters,1)))
  cat(sprintf("  Final: %d (%.0f%% are transfers)\n\n",
              enders, 100*migrants_in/max(enders,1)))
}

cat("=== FLOWS INTO ASDS ===\n")
print(student_migration %>%
        filter(ending_major == "ASDS", starting_major != "ASDS") %>%
        count(starting_major, sort = TRUE))

# --- 11. SAVE ---

output_dir <- here("data", "data-raw")
output_path <- file.path(output_dir, "student_migration.csv")
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
write_csv(student_migration, output_path)

cat("\n=== COMPLETE ===\n")
cat("File saved:", output_path, "\n")
cat("Next: Run 03_create_flow_matrices.R\n\n")

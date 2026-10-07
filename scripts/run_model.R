# scripts/run_model.R
# ------------------------------------------------------------
# OVER-ONLY NFL prop model (no unders)
# - One row in props.csv = ONE over bet candidate
# - Adds a required `side` column (must be "OVER")
# - Stable pick_id includes side so results always attach
# - Results persist: keeps the non-NA result if it exists
# ------------------------------------------------------------

rm(list = ls())
library(tidyverse)

cat("NFL prop model (OVER-only) is running.\n")
cat("Working directory: ", getwd(), "\n", sep = "")

# -----------------------------
# Load data
# -----------------------------
props <- read_csv("data/props.csv", show_col_types = FALSE)

# -----------------------------
# Helper functions
# -----------------------------
implied_prob_american <- function(odds) {
  ifelse(odds < 0, (-odds) / ((-odds) + 100), 100 / (odds + 100))
}

expected_value <- function(p, odds) {
  # EV per 1 unit risked
  win <- ifelse(odds < 0, 100 / (-odds), odds / 100)  # net win per 1 risk
  loss <- 1
  p * win - (1 - p) * loss
}

kelly_fraction <- function(p, odds, kelly_mult = 0.25) {
  b <- ifelse(odds < 0, 100 / (-odds), odds / 100)
  q <- 1 - p
  f <- (b * p - q) / b
  pmax(0, f) * kelly_mult
}

stake_for_unit_win <- function(odds, unit_win = 100) {
  # Stake needed to win `unit_win` dollars
  ifelse(odds < 0, unit_win * (-odds) / 100, unit_win)
}

# -----------------------------
# Output folder
# -----------------------------
dir.create("output", showWarnings = FALSE)

# -----------------------------
# Validate / enforce OVER-only
# -----------------------------
# Require side column; if missing, create as OVER (so script doesn't break)
if (!("side" %in% names(props))) {
  props <- props %>% mutate(side = "OVER")
}

# Enforce OVER-only rows
props <- props %>%
  mutate(
    side = toupper(trimws(side))
  ) %>%
  filter(side == "OVER")

if (nrow(props) == 0) {
  stop("No rows found after enforcing side == 'OVER'. Check data/props.csv.")
}

# -----------------------------
# Create stable pick_id (prevents duplicates)
# pick_id identifies the exact OVER prop
# -----------------------------
props <- props %>%
  mutate(
    pick_id = paste(game_id, player, prop_type, line, side, sep = "|")
  ) %>%
  group_by(pick_id) %>%
  slice_tail(n = 1) %>%  # if you pasted a duplicate row, keep last
  ungroup()

# -----------------------------
# Basic type safety for numerics
# (prevents silent NA math if columns read as character)
# -----------------------------
num_cols <- c("spread_team", "total", "line", "odds", "l3_usage", "season_usage", "opp_allow")
for (cc in num_cols) {
  if (cc %in% names(props)) {
    props[[cc]] <- suppressWarnings(as.numeric(props[[cc]]))
  }
}

# -----------------------------
# Feature engineering
# -----------------------------
props <- props %>%
  mutate(
    implied_prob = implied_prob_american(odds),
    usage_index  = 0.6 * l3_usage + 0.4 * season_usage,
    team_total   = (total / 2) + (-spread_team / 2)
  )

# -----------------------------
# Prop-type configuration
# (weights are simple + interpretable; you can tune later)
# -----------------------------
prop_cfg <- tibble(
  prop_type = c("pass_yds", "rush_yds", "rec_yds"),
  w_usage   = c(0.0012,     0.0018,     0.0015),
  w_opp     = c(-0.0008,    -0.0012,    -0.0010),
  w_total   = c(0.0010,     0.0006,     0.0009),
  ev_bet    = c(0.020,      0.025,      0.020),
  edge_bet  = c(0.020,      0.025,      0.020),
  ev_small  = c(0.010,      0.012,      0.010),
  usage_min_small = c(28,   10,          6),  # pass att / carries / targets (approx)
  usage_min_bet   = c(30,   12,          7),  # slightly higher bar for full BET
  team_total_min  = c(18,   18,          18)
)

# -----------------------------
# Model + decision (OVER-only)
# -----------------------------
props <- props %>%
  left_join(prop_cfg, by = "prop_type") %>%
  mutate(
    # defaults if a prop_type is new/unknown
    w_usage  = ifelse(is.na(w_usage),  0.0015, w_usage),
    w_opp    = ifelse(is.na(w_opp),   -0.0010, w_opp),
    w_total  = ifelse(is.na(w_total),  0.0008, w_total),
    ev_bet   = ifelse(is.na(ev_bet),   0.03,   ev_bet),
    edge_bet = ifelse(is.na(edge_bet), 0.03,   edge_bet),
    ev_small = ifelse(is.na(ev_small), 0.01,   ev_small),
    usage_min_small = ifelse(is.na(usage_min_small), 8, usage_min_small),
    usage_min_bet   = ifelse(is.na(usage_min_bet),   10, usage_min_bet),
    team_total_min  = ifelse(is.na(team_total_min),  18, team_total_min),
    
    # Over probability: market implied prob + small adjustments
    over_prob = pmin(
      pmax(
        implied_prob +
          w_usage * (usage_index - mean(usage_index, na.rm = TRUE)) +
          w_opp   * (opp_allow   - mean(opp_allow,   na.rm = TRUE)) +
          w_total * (team_total  - mean(team_total,  na.rm = TRUE)),
        0.05
      ),
      0.95
    ),
    
    edge = over_prob - implied_prob,
    ev   = expected_value(over_prob, odds),
    
    # OVER-only filters
    passes_filters = (usage_index >= usage_min_small) & (team_total >= team_total_min),
    
    decision = case_when(
      passes_filters & ev > ev_bet   & edge > edge_bet & usage_index >= usage_min_bet ~ "BET",
      passes_filters & ev > ev_small                                         ~ "SMALL BET",
      TRUE                                                                   ~ "PASS"
    )
  )

# -----------------------------
# Bet sizing (Kelly -> Units)
# -----------------------------
bankroll <- 10000

props <- props %>%
  mutate(
    kelly       = kelly_fraction(over_prob, odds, kelly_mult = 0.25),
    stake_1u    = stake_for_unit_win(odds, unit_win = 100),
    units_kelly = (kelly * bankroll) / stake_1u,
    units = case_when(
      decision == "PASS" ~ 0,
      TRUE ~ pmin(2, round(units_kelly * 2) / 2)  # cap at 2u, round to 0.5
    )
  )

# -----------------------------
# Output table (includes side + result)
# -----------------------------
top_picks <- props %>%
  arrange(desc(ev)) %>%
  select(
    pick_id, game_id, date, team, opp, home, spread_team, total,
    player, prop_type, side, line, odds,
    implied_prob, over_prob, edge, ev,
    decision, kelly, units, stake_1u,
    team_total, usage_index, opp_allow
  )

# -----------------------------
# Create / update editable results file
# result: 1 = win, 0 = loss, NA = pending
# Keeps your filled result if it exists.
# -----------------------------
results_path <- "output/results_manual.csv"

results_template <- top_picks %>%
  transmute(
    pick_id, game_id, date, player, prop_type, side, line,
    result = NA_integer_
  )

if (!file.exists(results_path)) {
  write_csv(results_template, results_path)
  cat("Created: output/results_manual.csv (fill result as 1/0)\n")
} else {
  old_res <- read_csv(results_path, show_col_types = FALSE)
  
  # Normalize types
  old_res <- old_res %>%
    mutate(
      result = suppressWarnings(as.integer(result)),
      side   = if ("side" %in% names(old_res)) toupper(trimws(side)) else "OVER"
    )
  
  # Merge and keep the row with a non-NA result if it exists
  res_updated <- bind_rows(old_res, results_template) %>%
    mutate(result = suppressWarnings(as.integer(result))) %>%
    group_by(pick_id) %>%
    arrange(is.na(result)) %>%   # non-NA first
    slice_head(n = 1) %>%
    ungroup()
  
  write_csv(res_updated, results_path)
}

results_manual <- read_csv(results_path, show_col_types = FALSE) %>%
  mutate(result = suppressWarnings(as.integer(result)))

# Attach results to printed table
top_picks <- top_picks %>%
  left_join(results_manual %>% select(pick_id, result), by = "pick_id")

print(top_picks)

# -----------------------------
# Save latest picks
# -----------------------------
write_csv(top_picks, "output/top_picks.csv")
cat("Saved: output/top_picks.csv\n")

# -----------------------------
# Log picks (dedupe exact pick_id + run_id)
# -----------------------------
log_path <- "output/picks_log.csv"

# Always store run_id as character to avoid datetime parsing issues
run_id <- as.character(format(Sys.time(), "%Y-%m-%d %H:%M:%S"))

log_rows <- top_picks %>%
  mutate(run_id = run_id) %>%
  select(run_id, everything())

if (!file.exists(log_path)) {
  write_csv(log_rows, log_path)
} else {
  old_log <- read_csv(log_path, show_col_types = FALSE) %>%
    mutate(run_id = as.character(run_id))
  
  # If old log doesn't have pick_id (from earlier versions), reset clean
  if (!("pick_id" %in% names(old_log))) {
    write_csv(log_rows, log_path)
  } else {
    updated_log <- bind_rows(old_log, log_rows) %>%
      mutate(run_id = as.character(run_id)) %>%
      group_by(pick_id, run_id) %>%
      slice_tail(n = 1) %>%
      ungroup()
    
    write_csv(updated_log, log_path)
  }
}

cat("Logged picks to: output/picks_log.csv\n")


# NFL Player Prop Model

An R-based NFL player prop betting model designed to identify value in player prop markets using market-implied probabilities, player usage, matchup data, and game environment.

The model currently evaluates **OVER** opportunities for passing yards, rushing yards, and receiving yards.

## Overview

The model compares a calculated probability of a player going over their prop line against the sportsbook's implied probability.

Each prop is evaluated using:

- American odds and market-implied probability
- Recent player usage
- Season-long player usage
- Opponent allowance
- Team spread and game total
- Expected value (EV)
- Model edge over the market

The model then classifies each opportunity as:

- **BET**
- **SMALL BET**
- **PASS**

## Model Methodology

### Usage

Recent performance receives greater weight than season-long usage:

`Usage Index = 0.60 × Last 3 Games Usage + 0.40 × Season Usage`

Usage represents the relevant opportunity metric for each prop type, such as pass attempts, carries, or targets.

### Game Environment

The model estimates each team's implied point total using the game total and team spread:

`Team Total = (Game Total / 2) + (-Team Spread / 2)`

This allows the model to account for the expected offensive environment surrounding each player.

### Probability and Edge

Sportsbook American odds are converted into implied probabilities.

The model adjusts that baseline probability using:

- Player usage
- Opponent allowance
- Implied team total

The resulting probability is compared with the market-implied probability:

`Edge = Model Over Probability - Market Implied Probability`

Expected value is then calculated for each prop based on the model probability and available odds.

## Bet Selection

Prop-specific thresholds are used for passing, rushing, and receiving markets.

A play must satisfy minimum usage and team-total requirements before qualifying as a bet.

Qualifying plays are categorized as **BET**, **SMALL BET**, or **PASS** based on expected value, model edge, and usage thresholds.

## Example Results

The repository includes a sample week of model output to demonstrate the prediction and selection process. All qualifying plays shown below were evaluated as **OVER** bets.

| Player | Prop | Line | Result | Outcome |
|---|---|---:|---:|---|
| Rhamondre Stevenson | Rushing Yards | 39.5 | 70 | Win |
| Kyren Williams | Rushing Yards | 59.5 | 87 | Win |
| RJ Harvey | Rushing Yards | 55.5 | 20 | Loss |
| James Cook | Rushing Yards | 76.5 | 117 | Win |
| Christian McCaffrey | Rushing Yards | 52.5 | 35 | Loss |
| Kenneth Walker | Rushing Yards | 59.5 | 116 | Win |
| Zach Charbonnet | Rushing Yards | 50.5 | 20 | Loss |
| D'Andre Swift | Rushing Yards | 54.5 | 76 | Win |

**Sample performance: 5–3 (62.5% accuracy)**

This sample is provided to demonstrate model output and does not represent the model's full-season performance.

## Bankroll Management

The model uses a **quarter-Kelly criterion** for position sizing.

Recommended stakes are:

- Calculated using 25% Kelly
- Rounded to the nearest 0.5 unit
- Capped at 2 units per play

The current model assumes a $10,000 reference bankroll and defines one unit based on the stake required to win $100.

## Project Structure

```text
nfl-prop-model/
├── data/
│   └── props.csv
├── output/
│   ├── picks_log.csv
│   ├── results_manual.csv
│   └── top_picks.csv
├── scripts/
│   └── run_model.R
├── .gitignore
└── nfl_prop_model.Rproj
```

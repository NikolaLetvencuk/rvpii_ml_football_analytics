# Clustering and Classification of Football Players from StatsBomb Data

Analysis of football players' playing styles and positions using machine
learning on the StatsBomb Open Data set, in R. Project for the course
*High Performance Computing in Information Engineering* (FTN Novi Sad).

## Dataset

- **Source:** [StatsBomb Open Data](https://github.com/statsbomb/open-data) —
  freely and publicly available, with no access procedures (non-commercial,
  research use with attribution).
- **Nature:** detailed event data — each record is one on-pitch action
  (pass, shot, dribble, pressure, ball recovery...) with coordinates, player,
  team, outcome, and xG.
- **Size:** 350+ matches from 4 leagues (Premier League, La Liga, Ligue 1,
  Serie A), > 1 GB in JSON format (~1.3 million events).

## Technologies

- **R** — full pipeline: processing, analysis, and modeling
- **Markdown** — reporting
- Packages: `jsonlite`, `dplyr`, `tidyr`, `readr`, `ggplot2`, `graphics`,
  `caret`, `class`, `rpart`, `rpart.plot`, `randomForest`, `cluster`,
  `factoextra`

## Project structure

```
projekat/
├── data/
│   ├── raw/statsbomb/events/        # 356 raw JSON files (~1 GB)
│   ├── raw/statsbomb/matches/       # match metadata
│   └── processed/                   # processed tables (CSV)
├── scripts/
│   ├── 00_data_collection.R         # download event data
│   ├── 01_build_feature_table.R     # JSON -> per-player feature table
│   ├── 02_prep_and_analysis.R       # preparation + preliminary analysis
│   ├── 04_classification.R          # KNN, decision tree, random forest
│   └── 05_clustering.R              # k-Means
├── figures/                         # generated plots
└── README.md
```

## Workflow and status

### ✅ Data collection (`00`)
Downloaded 356 matches (round-robin across leagues) up to ~1 GB of event data.

### ✅ Feature table construction (`01`)
Parsing and aggregation of ~1.3M events into a per-player table:
**770 players × 25+ numeric features**, normalized per 90 minutes
(passes, shots, xG, dribbles, pressures, ball recoveries, tackles...).
Minimum 450 minutes filter applied. Output: `data/processed/player_features.csv`.

### ✅ Preparation and preliminary analysis (`02`)
- loading and tidying (types, factors)
- missing-value inspection (no true NAs; features are counters, so absence of
  an action yields 0; the only 0/0 case in success-rate features is set to 0
  with a note)
- descriptive statistics per feature
- distribution visualization (histogram, density, boxplot, Q-Q, bar chart) —
  both `graphics` and `ggplot2`
- feature relationships (scatter plots, correlation matrix)

Output: `data/processed/player_features_clean.csv`, `figures/`

### ✅ Classification [15p] (`04`)
Target: **position group (6 classes: GK/CB/FB/DM_CM/AM_W/FW)**.
Three methods, each with 3 parameter scenarios:
- **KNN** — parameter `k` (1 / 15 / 50)
- **Decision Tree** — parameter `cp` (0 / 0.01 / 0.05)
- **Random Forest** — parameter `mtry` (2 / √p / p)

Evaluation: 10-fold cross-validation, metrics ACC/PREC/SENS/SPEC/F1
(macro-averaged), parameter-vs-performance relationship, selection of the best
solution per method and overall. Output: `data/processed/classification_results.csv`

### ✅ Clustering [6p] (`05`)
**k-Means**, two scenarios for the number of clusters (k), examination of
cluster structure (profiles, silhouette, comparison against positions),
visualization of the relationship between feature values and cluster membership.
Output: `data/processed/player_clusters.csv`

## Running

Order (from the project root folder):

```bash
Rscript scripts/00_data_collection.R      # ~1 GB, takes a while
Rscript scripts/01_build_feature_table.R  # JSON parsing
Rscript scripts/02_prep_and_analysis.R
Rscript scripts/04_classification.R
Rscript scripts/05_clustering.R
```

> Note: scripts `04` and `05` have parameters chosen based on helper plots
> (elbow/silhouette for k, k-vs-accuracy for KNN) — run once, inspect the
> plots, adjust if needed, and run again.

## Remaining

- [ ] Interpretation of results and naming of clusters (archetypes)
- [ ] Final Markdown report

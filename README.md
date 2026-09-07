# Football Player Analytics on StatsBomb Open Data

Classification and clustering of football players by positional role, built on
**Apache Spark 3.5 via `sparklyr`** in R. 5.3 million match events are processed
into a player-level feature table, three classifiers are tuned by 10-fold
cross-validation, and an unsupervised k-means analysis is run over the same
features.

Project for the course *High Performance Computing in Information Engineering*
(FTN Novi Sad) — Nikola Letvenčuk, E2 46-2025.

---

## Headline results

| | |
|---|---|
| Raw data | 1,517 matches · 4.25 GB JSON · **5,321,459 events** |
| Modelling table | **1,702 players** × **29 numeric features** |
| Target | 6 positional classes — `GK`, `CB`, `FB`, `DM_CM`, `AM_W`, `FW` |
| Best classifier | **Random forest** — 500 trees, depth 5, `sqrt` feature subset |
| Test-set accuracy | **0.9415** (κ = 0.9284, macro F1 = 0.9476, multiclass AUC = 0.9966) |
| Clustering | **k = 3**, silhouette 0.476 — 95.5% of players fall in the cluster matching their positional supergroup |

Three substantive findings:

1. **Spatial features determine position.** The strongest spatial feature
   (`d3_share`, ANOVA F = 8,586) has 5.6× the discriminative power of the
   strongest event counter (`clearances_p90`, F = 1,523). *Where* a player moves
   predicts their role better than *which* actions they perform.
2. **Positional roles form a continuum, not discrete categories.** Confirmed
   independently by the PCA plot, by the error structure of all three
   classifiers, and by the clustering.
3. **The residual error is a property of the data, not of the methods.** All
   three classifiers — a single rule tree, a 500-tree ensemble, and a
   distance-based method in 29 dimensions — fail on the same class pairs, in the
   same proportions. No method ever confuses classes at opposite ends of the
   defence–attack spectrum.

---

## Dataset

- **Source:** [StatsBomb Open Data](https://github.com/statsbomb/open-data) —
  publicly available; non-commercial research use with mandatory attribution.
- **Nature:** event-level data. One record is one on-pitch action (pass, shot,
  carry, pressure, duel, ball recovery, …) with pitch coordinates, player, team,
  outcome and StatsBomb xG.
- **Selection:** for each of four leagues (Premier League, La Liga, Ligue 1,
  Serie A) the season with the most matches; downloads alternate round-robin
  across leagues so the leagues stay evenly represented.
- **Volume:** 1,517 match files, 4.25 GB of JSON, flattened to 5,321,459 event
  rows over 18 columns.

Raw data is **not** committed to the repository (see `.gitignore`); run
`scripts/00_preuzmi_podatke.R` to fetch it.

---

## Pipeline

```
StatsBomb JSON (4.25 GB, 1,517 files)
        │  00_preuzmi_podatke.R
        ▼
data/interim/events_flat/          Parquet · 5,321,459 rows × 18 cols
        │  01_data_processing_with_sparklyr.R
        │    · minutes played reconstructed from Half End / Starting XI / Substitution
        │    · 22 counters aggregated in a single pass, normalised per 90 minutes
        │    · spatial features: mean_x/y, sd_x/y, f3_share, d3_share
        │    · filter: minutes >= 450
        ▼
data/processed/player_features_labeled.csv     1,702 players × 31 numeric cols
        │  02_purity_correction.R   (modal position + label purity over 6 classes)
        │  03_null_values_analysis.R, 04_EDA.R
        │  05_train_test_split.R    (stratified 80/20 via percent_rank, seed 42)
        ▼
data/interim/{train,test}/         1,360 / 342 rows, ≤0.3 pp deviation per class
        │
        ├── 06_decision_tree.R   ┐  Spark ML pipeline:
        ├── 07_random_forest.R   ┤  string_indexer → vector_assembler → standard_scaler → model
        ├── 08_knn.R             ┘  10-fold CV on weighted F1, 3 parameter scenarios each
        └── 09_kmeans.R             k-means over 29 features and over 11 principal components
```

**Design decisions worth noting**

- Standardisation lives *inside* the `ml_pipeline`, so scaler parameters are
  refitted per CV fold — no information leakage from the held-out fold.
- The 80/20 split is stratified with a window function (`percent_rank(rand(42))`
  within class), because `sdf_random_split` gives no class guarantees and the
  smallest class has only 125 rows.
- Spark MLlib has no k-NN classifier, so k-NN runs in R via `kknn`, with the
  weighted-F1 metric reimplemented to match
  `MulticlassClassificationEvaluator(metric_name = "f1")` exactly, and with the
  same Parquet split loaded from Spark.
- `passes_completed_p90` and `dribbles_completed_p90` are dropped (products of a
  counter and its success rate → double counting in distance-based methods),
  leaving 29 features.

---

## Results

### Classification — method comparison

| Metric | Decision tree | **Random forest** | k-NN |
|---|---|---|---|
| CV F1 (10-fold) | 0.8857 | 0.9244 | **0.9292** |
| Test accuracy | 0.9123 | **0.9415** | 0.9357 |
| Cohen's κ | 0.8926 | **0.9284** | 0.9214 |
| Macro F1 | 0.9226 | **0.9476** | 0.9416 |
| Balanced accuracy | 0.9504 | **0.9663** | 0.9658 |
| Multiclass AUC (Hand–Till) | 0.9776 | **0.9966** | 0.9962 |
| Errors (of 342) | 30 | **20** | 22 |
| Selected scenario | S3 — entropy, depth 5 | S1 — 500 trees | S3 — k = 21, Manhattan |
| Fit / predict time | 2.60 s / 0.50 s | 6.21 s / 0.42 s | 0.11 s / 0.32 s |
| Models trained in search | 273 | 263 | 451 |

Cross-validation ranks k-NN first, but by 0.0048 — less than one standard error
across folds, and over folds built by two different schemes (Spark's unstratified
folds vs. `caret::createFolds`). The random forest was selected because it wins
on **all nine** test-set indicators and in four of five non-trivial classes, its
prediction cost is independent of training-set size (k-NN's grows linearly), and
its importance measure is not distorted by correlated features.

### Per-class F1 (test set)

| Class | Tree | Random forest | k-NN |
|---|---|---|---|
| GK | 1.0000 | 1.0000 | 1.0000 |
| CB | 0.9655 | **0.9744** | 0.9587 |
| FB | 0.9385 | **0.9630** | 0.9538 |
| DM_CM | 0.8846 | **0.9342** | 0.9324 |
| AM_W | 0.8630 | 0.8966 | **0.9014** |
| FW | 0.8837 | **0.9176** | 0.9032 |

29 of the tree's 30 errors, and 19 of the forest's 20, fall between classes that
are **adjacent** on the defence–attack spectrum. The `AM_W`–`FW` pair alone
carries 7–10 errors in every method.

### Clustering — k-means

k = 3 is selected by the elbow rule (W drops 26.8% → 12.9% → 9.4%) and
independently by the silhouette maximum (0.476), and is confirmed again in the
11-component PCA space. The solution is stable: across 10 runs (two
initialisation modes × five seeds) W varies by 0.1 and the silhouette by 0.0002.

| Cluster | n | GK | CB | FB | DM_CM | AM_W | FW |
|---|---|---|---|---|---|---|---|
| C1 | 125 | **125** | 0 | 0 | 0 | 0 | 0 |
| C2 | 966 | 0 | **300** | **325** | **320** | 21 | 0 |
| C3 | 611 | 0 | 0 | 7 | 48 | **339** | **217** |

Purity 0.4636 and ARI 0.3465 look low, but no position is scattered: read as
supergroups (goalkeepers / own-half players / opposition-half players),
**1,626 of 1,702 players — 95.5% — land in the right cluster.** The unsupervised
structure is three coarse bands, not six positions; the adjusted Rand index only
peaks at k = 7 (0.6598), i.e. matching the labels needs more clusters than the
density structure offers.

---

## Reports

Two rendered reports, identical in content:

| File | Language | Notes |
|---|---|---|
| `documentation.Rmd` / `documentation.html` | English | Loads results from the per-method `results/` subdirectories |
| `dokumentacija.Rmd` / `dokumentacija.html` | Serbian | Original; expects the flat `results/*.csv` layout |

Both are self-contained HTML (floating TOC, code folding, embedded figures) and
include every project script verbatim in an appendix. Knit with:

```r
rmarkdown::render("documentation.Rmd")
```

Knitting does **not** start Spark: analysis chunks are `eval = FALSE`, tables are
read from `results/` and figures from `figures/`, so a full render takes seconds.

---

## Repository layout

```
ml_football_analytics/
├── scripts/
│   ├── 00_preuzmi_podatke.R                 # round-robin download, resumable
│   ├── 00_test_skripta.R                    # one-off Windows setup: winutils/hadoop.dll
│   ├── 01_data_processing_with_sparklyr.R   # JSON → Parquet → player feature table
│   ├── 02_data_analysis.R                   # early exploratory pass (superseded by 04)
│   ├── 02_purity_correction.R               # modal position + purity over 6 classes
│   ├── 03_null_values_analysis.R            # missing-value profile over the event layer
│   ├── 04_EDA.R                             # descriptives, correlations, ANOVA, PCA
│   ├── 05_train_test_split.R                # stratified 80/20 → Parquet
│   ├── 06_decision_tree.R                   # 3 scenarios, 10-fold CV, test evaluation
│   ├── 07_random_forest.R                   # 3 scenarios + importance vs. tree
│   ├── 08_knn.R                             # kknn in R + cross-method comparison
│   └── 09_kmeans.R                          # k-means, 2 scenarios, stability, profiles
├── data/
│   ├── raw/statsbomb/{events,matches}/      # 1,517 JSON files + manifest  (gitignored)
│   ├── interim/{events_flat,player_features,train,test}/   # Parquet       (gitignored)
│   └── processed/player_features_labeled.csv               #              (gitignored)
├── results/
│   ├── decision_tree/  random_forest/  knn/  km/    # scenario tables, metrics, importances
│   ├── decision_tree_old/                           # earlier DT run, kept for comparison
│   └── feat_cols.rds                                # the 29 feature names, shared by all models
├── figures/                                 # all report figures (+ per-method subfolders)
├── docs/                                    # assignment brief and notes
├── documentation.Rmd / .html                # report (English)
├── dokumentacija.Rmd / .html                # report (Serbian)
└── run_01.ps1                               # Windows launcher with a guaranteed JAVA_HOME
```

> The scripts write results **flat** into `results/` and `figures/`; the copies in
> this repository have been sorted into per-method subfolders after the fact.
> `documentation.Rmd` searches both layouts, so it renders either way.

---

## Setup

**Requirements**

| Component | Version used |
|---|---|
| R | 4.6.1 |
| Java (JDK) | 17 — Temurin (required by Spark 3.5) |
| Apache Spark | 3.5.8, Hadoop 3, installed locally by `sparklyr` |
| Pandoc | any recent (bundled with RStudio) |

**On Windows** Spark also needs `winutils.exe` and `hadoop.dll`.
`scripts/00_test_skripta.R` downloads them to `C:/hadoop/bin`, copies the DLL into
`System32` and writes `HADOOP_HOME` into `~/.Renviron`. Run it once.

**R packages**

```r
install.packages(c(
  "sparklyr", "dplyr", "tidyr", "readr", "jsonlite", "DBI",
  "ggplot2", "dbplot", "ggcorrplot", "scales",
  "caret", "kknn", "pROC", "cluster", "e1071",
  "rmarkdown", "knitr", "kableExtra"
))
sparklyr::spark_install(version = "3.5")
```

**Spark session** — every script connects as `local[*]` with 8 GB of driver
memory, a 2 GB result-size cap, and `spark.sql.shuffle.partitions = 32` (down
from the default 200, which is oversized for a single machine).

---

## Running

From the project root, in order:

```bash
Rscript scripts/00_preuzmi_podatke.R                # ~4.25 GB download, resumable
Rscript scripts/01_data_processing_with_sparklyr.R  # Spark: JSON → Parquet → features
Rscript scripts/02_purity_correction.R              # 6-class labels + purity
Rscript scripts/03_null_values_analysis.R
Rscript scripts/04_EDA.R
Rscript scripts/05_train_test_split.R
Rscript scripts/06_decision_tree.R                  # ~7 min parameter search
Rscript scripts/07_random_forest.R                  # ~10 min
Rscript scripts/08_knn.R                            # ~1 min
Rscript scripts/09_kmeans.R                         # ~2 min
```

On Windows, `./run_01.ps1` runs step 01 with `JAVA_HOME` and `PATH` reloaded from
the registry — useful when the terminal session predates the JDK install. The
same wrapper pattern works for the other steps.

Steps 05–09 depend only on `data/processed/player_features_labeled.csv`, so once
step 02 has run, the modelling stages can be re-run on their own.

---

## Reproducibility

- Every random operation is seeded with **42**: the train/test split, the CV fold
  assignment, the random forest's row and column sampling, k-means
  initialisation, and the k-NN permutation importance.
- `results/feat_cols.rds` fixes the 29 feature names, and all three classifiers
  plus the clustering read the identical Parquet split — so differences between
  methods come only from the methods.
- Result tables from all three classifiers share identical column names, so the
  cross-method comparison is a three-file merge.

---

## Known limitations

1. Labels come from the modal position; 25 genuinely multi-positional players
   (1.5%) therefore carry a less reliable label. They were kept, not removed.
2. Features are season aggregates — no match context, opponent, or score state.
3. Spatial features are means and dispersions of coordinates, so fine movement
   structure is lost.
4. Parameter scenarios were searched as separate units, never as a full
   combinatorial grid. For the random forest this demonstrably left something on
   the table: many trees combined with depth 10 was never tested, though both
   scenarios point at it.
5. CV folds differ between the Spark methods (unstratified) and k-NN
   (stratified), so sub-percentage-point CV differences between them are not
   directly comparable.
6. k-means assumes spherical, similarly sized clusters. A density-based method
   would add insight but has no distributed MLlib implementation.
7. `ml_bisecting_kmeans` returned a single cluster instead of the requested three
   in the `sparklyr` version used, so that comparison was dropped.

Possible extensions: more seasons, phase-of-play features, score-state context,
density-based clustering, gradient boosting.

---

## Legacy scaffolding

`main.R`, `reports/`, `tests/`, `outputs/`, `docs/nalazi_o_podacima.md` and the
message in `.Rprofile` are left over from an earlier, abandoned Airbnb-pricing
version of this assignment. They reference scripts and an `R/` directory that no
longer exist and are **not** part of the pipeline described above. The scripts in
`scripts/` are the project.

---

## License and attribution

Analysis code is coursework. The underlying data is
[StatsBomb Open Data](https://github.com/statsbomb/open-data), used under its
licence: free for non-commercial research and personal use, with attribution to
StatsBomb required in any write-up.

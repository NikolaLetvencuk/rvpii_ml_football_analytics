# ============================================================
# 02 — Priprema podataka i preliminarna analiza
#
# Pokriva stavke specifikacije:
#   PRIPREMA PODATAKA [3p]
#     - ucitavanje podataka
#     - uredjivanje ucitanih podataka
#     - ispitivanje prisustva nedostajucih vrednosti
#   PRELIMINARNA ANALIZA [3p]
#     - deskriptivne statistike po obelezjima
#     - vizualizacija raspodela po obelezjima
#     - ispitivanje odnosa izmedju obelezja
#
# INPUT : data/processed/player_features.csv
# OUTPUT: data/processed/player_features_clean.csv
#         figures/*.png  (base graphics + ggplot2)
#
# Paketi: readr, dplyr, tidyr, ggplot2 (tidyverse) + base graphics
# ============================================================

pkgs <- c("readr", "dplyr", "tidyr", "ggplot2")
for (p in pkgs) if (!requireNamespace(p, quietly = TRUE)) install.packages(p)
library(readr); library(dplyr); library(tidyr); library(ggplot2)

fig_dir <- "figures"
dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)
save_base <- function(name, expr, w = 1600, h = 1000, res = 150) {
  png(file.path(fig_dir, name), width = w, height = h, res = res)
  on.exit(dev.off()); force(expr)
}

# ============================================================
# 1) PRIPREMA — UCITAVANJE PODATAKA
# ============================================================
cat("=========== 1. UCITAVANJE PODATAKA ===========\n")
df <- read_csv("data/processed/player_features.csv", show_col_types = FALSE)

cat("\nDimenzije (redovi x kolone): ", nrow(df), "x", ncol(df), "\n\n")
cat("Struktura (glimpse):\n")
glimpse(df)

# ============================================================
# 2) PRIPREMA — UREDJIVANJE UCITANIH PODATAKA
# ============================================================
cat("\n=========== 2. UREDJIVANJE PODATAKA ===========\n")

# identifikatori / labele vs. numericka obelezja
id_cols   <- c("player_id", "player", "team", "position", "pos_purity", "minutes")
feat_cols <- setdiff(names(df), id_cols)   # 25 numerickih per-90 / rate obelezja

# tipovi: position kao faktor (kategoricka labela), player_id kao character (ID, ne broj)
df <- df %>%
  mutate(
    player_id = as.character(player_id),
    position  = as.factor(position),
    team      = as.factor(team)
  )

cat("Broj numerickih obelezja: ", length(feat_cols), "\n")
cat("Kategoricka labela: position (", nlevels(df$position), "nivoa )\n")
cat("Tipovi kolona posle uredjivanja:\n")
print(sapply(df[c("player_id","position","team","minutes","passes_p90")], class))

# ============================================================
# 3) PRIPREMA — NEDOSTAJUCE VREDNOSTI
# ============================================================
cat("\n=========== 3. NEDOSTAJUCE VREDNOSTI ===========\n")

na_by_col <- colSums(is.na(df))
cat("Broj NA po koloni:\n"); print(na_by_col)
cat("\nUkupno NA u skupu: ", sum(na_by_col), "\n")

# NaN (npr. 0/0) posebno — nastaje kod stopa (rate) obelezja
nan_by_col <- sapply(df[feat_cols], function(x) sum(is.nan(x)))
cat("\nBroj NaN po numerickom obelezju (npr. deljenje 0/0):\n")
print(nan_by_col[nan_by_col > 0])
if (all(nan_by_col == 0)) cat("  (nema NaN vrednosti)\n")

# --- Analiza "prikrivenih" nedostajucih vrednosti ---
# Obelezja su strukturni brojaci: igrac bez odbrane ima 0 (ne NA).
# Jedini suptilan slucaj: dribble_success_pct = 0 moze znaciti
# "0 uspesnih driblinga" ILI "nijedan dribling nije ni pokusan" (0/0 -> tretirano kao 0).
zero_dribblers <- sum(df$dribbles_p90 == 0)
cat(sprintf("\nIgraci koji NISU pokusali nijedan dribling: %d\n", zero_dribblers))
cat("  -> kod njih je dribble_success_pct nedefinisano (0/0) i postavljeno na 0.\n")
cat("  -> ovo je prikrivena nedostajuca vrednost; belezimo je kao napomenu.\n")

# Odluka (dokumentovana): zadrzavamo 0 jer za klaster/klasifikaciju
# "ne dribla" i "dribla neuspesno" oba opisuju stil bez driblinga.

# posto nema pravih NA, cist skup = uredjeni skup
df_clean <- df

out_clean <- "data/processed/player_features_clean.csv"
write_csv(df_clean, out_clean)
cat(sprintf("\nOcisceni skup sacuvan: %s (%d x %d)\n",
            out_clean, nrow(df_clean), ncol(df_clean)))

# ============================================================
# 4) PRELIMINARNA — DESKRIPTIVNE STATISTIKE PO OBELEZJIMA
# ============================================================
cat("\n=========== 4. DESKRIPTIVNE STATISTIKE ===========\n")

# base: summary za sva numericka obelezja
cat("\nsummary() po numerickim obelezjima:\n")
print(summary(df_clean[feat_cols]))

# rucna tabela kljucnih statistika (mean, median, sd, min, max)
desc <- df_clean %>%
  select(all_of(feat_cols)) %>%
  pivot_longer(everything(), names_to = "obelezje", values_to = "vrednost") %>%
  group_by(obelezje) %>%
  summarise(
    n      = n(),
    mean   = round(mean(vrednost), 3),
    median = round(median(vrednost), 3),
    sd     = round(sd(vrednost), 3),
    min    = round(min(vrednost), 3),
    max    = round(max(vrednost), 3),
    .groups = "drop"
  ) %>%
  arrange(desc(mean))
cat("\nTabela deskriptivnih statistika:\n")
print(as.data.frame(desc))
write_csv(desc, file.path("data", "processed", "descriptive_stats.csv"))

# deskriptivne statistike po grupi (poziciji) — primer za 3 kljucna obelezja
cat("\nProsek kljucnih obelezja po poziciji (izbor):\n")
by_pos <- df_clean %>%
  group_by(position) %>%
  summarise(
    n            = n(),
    passes_p90   = round(mean(passes_p90), 1),
    shots_p90    = round(mean(shots_p90), 2),
    tackles_p90  = round(mean(tackles_p90), 2),
    xg_p90       = round(mean(xg_p90), 3),
    .groups = "drop"
  ) %>%
  arrange(desc(n))
print(as.data.frame(by_pos))

# ============================================================
# 5) PRELIMINARNA — VIZUALIZACIJA RASPODELA PO OBELEZJIMA
# ============================================================
cat("\n=========== 5. VIZUALIZACIJA RASPODELA ===========\n")

# --- 5a. BASE GRAPHICS (lekcija: graphics paket) ---

# Histogram
save_base("hist_passes.png",
          hist(df_clean$passes_p90,
               main = "Histogram: dodavanja po 90 min",
               xlab = "Dodavanja / 90", ylab = "Broj igraca", col = "grey80"))

# Density
save_base("density_xg.png",
          plot(density(df_clean$xg_p90),
               main = "Funkcija gustine: xG po 90 min",
               xlab = "xG / 90", ylab = "Gustina"))

# Boxplot (jedno obelezje)
save_base("box_shots.png",
          boxplot(df_clean$shots_p90,
                  main = "Kutijasti dijagram: suterevi po 90 min",
                  ylab = "Suterevi / 90"))

# Boxplot po grupi — obelezje vs pozicija (samo cesce pozicije radi citljivosti)
top_pos <- names(sort(table(df_clean$position), decreasing = TRUE))[1:8]
sub <- df_clean[df_clean$position %in% top_pos, ]
sub$position <- droplevels(factor(sub$position))
save_base("box_passes_by_pos.png", w = 2000, h = 1100, {
  par(mar = c(10, 4, 3, 1))
  boxplot(passes_p90 ~ position, data = sub, las = 2,
          main = "Dodavanja/90 po poziciji (8 najcescih)",
          xlab = "", ylab = "Dodavanja / 90", col = "lightblue")
})

# QQ plot (provera normalnosti)
save_base("qq_passes.png", {
  qqnorm(df_clean$passes_p90, main = "Q-Q dijagram: dodavanja/90")
  qqline(df_clean$passes_p90, col = "red")
})

# Bar / dot chart: raspodela pozicija
save_base("bar_positions.png", w = 2000, h = 1100, {
  par(mar = c(11, 4, 3, 1))
  t <- sort(table(df_clean$position), decreasing = TRUE)
  barplot(t, las = 2, main = "Broj igraca po poziciji",
          ylab = "Broj igraca", col = "grey70")
})

# --- 5b. GGPLOT2 (lekcija: ggplot2 / grammar of graphics) ---

# Histogram + density preko njega
g1 <- ggplot(df_clean, aes(x = passes_p90)) +
  geom_histogram(aes(y = after_stat(density)), bins = 30,
                 fill = "steelblue", colour = "white", alpha = 0.8) +
  geom_density(colour = "darkred", linewidth = 1) +
  labs(title = "Raspodela: dodavanja po 90 minuta",
       x = "Dodavanja / 90", y = "Gustina") +
  theme_minimal()
ggsave(file.path(fig_dir, "gg_hist_passes.png"), g1, width = 8, height = 5, dpi = 150)

# Facet histogrami za nekoliko obelezja odjednom
few <- c("passes_p90","shots_p90","tackles_p90","xg_p90",
         "pressures_p90","carries_p90")
long_few <- df_clean %>%
  select(all_of(few)) %>%
  pivot_longer(everything(), names_to = "obelezje", values_to = "vrednost")
g2 <- ggplot(long_few, aes(x = vrednost)) +
  geom_histogram(bins = 25, fill = "steelblue", colour = "white") +
  facet_wrap(~ obelezje, scales = "free") +
  labs(title = "Raspodele izabranih obelezja", x = NULL, y = "Broj igraca") +
  theme_minimal()
ggsave(file.path(fig_dir, "gg_facet_hist.png"), g2, width = 10, height = 6, dpi = 150)

# Boxplot po poziciji (ggplot verzija)
g3 <- ggplot(sub, aes(x = reorder(position, passes_p90, median),
                      y = passes_p90, fill = position)) +
  geom_boxplot(show.legend = FALSE) +
  coord_flip() +
  labs(title = "Dodavanja/90 po poziciji", x = NULL, y = "Dodavanja / 90") +
  theme_minimal()
ggsave(file.path(fig_dir, "gg_box_by_pos.png"), g3, width = 9, height = 6, dpi = 150)

cat("Sacuvane slike u '", fig_dir, "/'\n", sep = "")

# ============================================================
# 6) PRELIMINARNA — ODNOSI IZMEDJU OBELEZJA
# ============================================================
cat("\n=========== 6. ODNOSI IZMEDJU OBELEZJA ===========\n")

# --- 6a. Scatter (base): odnos dva obelezja, obojeno po grupi ---
save_base("scatter_press_tackles.png", {
  cols <- as.integer(sub$position)
  plot(sub$pressures_p90, sub$tackles_p90,
       col = cols, pch = 19, cex = 0.7,
       main = "Odnos: pritisci vs osvajanja lopte (tackles) /90",
       xlab = "Pritisci / 90", ylab = "Tackles / 90")
})

# --- 6b. Scatter (ggplot): xG vs suterevi, boja = pozicija ---
g4 <- ggplot(df_clean, aes(x = shots_p90, y = xg_p90)) +
  geom_point(aes(colour = position), alpha = 0.6, show.legend = FALSE) +
  geom_smooth(method = "loess", se = FALSE, colour = "black") +
  labs(title = "Odnos: suterevi/90 vs xG/90", x = "Suterevi / 90", y = "xG / 90") +
  theme_minimal()
ggsave(file.path(fig_dir, "gg_scatter_shots_xg.png"), g4, width = 8, height = 5, dpi = 150)

# --- 6c. Korelaciona matrica (odnosi svih numerickih obelezja) ---
corr <- cor(df_clean[feat_cols], use = "complete.obs")
write_csv(as.data.frame(round(corr, 2)) %>% mutate(obelezje = rownames(corr)) %>%
            select(obelezje, everything()),
          file.path("data", "processed", "correlation_matrix.csv"))

# heatmap korelacija (base)
save_base("corr_heatmap.png", w = 1800, h = 1600, res = 150, {
  par(mar = c(11, 11, 3, 2))
  image(1:ncol(corr), 1:nrow(corr), t(corr[nrow(corr):1, ]),
        axes = FALSE, xlab = "", ylab = "",
        main = "Korelaciona matrica numerickih obelezja",
        col = colorRampPalette(c("blue","white","red"))(50), zlim = c(-1,1))
  axis(1, at = 1:ncol(corr), labels = colnames(corr), las = 2, cex.axis = 0.6)
  axis(2, at = 1:nrow(corr), labels = rev(rownames(corr)), las = 2, cex.axis = 0.6)
})

# najjace korelacije (parovi) — korisno za izvestaj
cp <- as.data.frame(as.table(corr)) %>%
  filter(as.character(Var1) < as.character(Var2)) %>%
  arrange(desc(abs(Freq)))
cat("\nNajjace korelacije izmedju obelezja (top 12):\n")
print(head(cp, 12), row.names = FALSE)

cat("\n=========== GOTOVO ===========\n")
cat("Sledeci korak: klasterizacija (k-Means / hijerarhijska / DBSCAN)\n")
cat("na skaliranim numerickim obelezjima iz player_features_clean.csv\n")
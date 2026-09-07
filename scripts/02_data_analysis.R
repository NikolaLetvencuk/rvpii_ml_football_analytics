library(readr)
library(dplyr)
library(tidyr)
library(ggplot2)

dir.create("figures", showWarnings = FALSE)

df <- read_csv("data/processed/player_features.csv")

cat("Redovi:", nrow(df), " Kolone:", ncol(df), "\n")
glimpse(df)

id_cols <- c("player_id", "player", "team", "position", "pos_purity", "minutes")
feat_cols <- setdiff(names(df), id_cols)

df$player_id <- as.character(df$player_id)
df$position  <- as.factor(df$position)
df$team      <- as.factor(df$team)

cat("Broj numerickih obelezja:", length(feat_cols), "\n")
cat("Broj pozicija:", nlevels(df$position), "\n")

cat("NA po koloni:\n")
print(colSums(is.na(df)))
cat("Ukupno NA:", sum(is.na(df)), "\n")

cat("Igraci bez ijednog driblinga:", sum(df$dribbles_p90 == 0), "\n")

write_csv(df, "data/processed/player_features_clean.csv")

print(summary(df[feat_cols]))

desc <- df %>%
  select(all_of(feat_cols)) %>%
  pivot_longer(everything(), names_to = "obelezje", values_to = "vrednost") %>%
  group_by(obelezje) %>%
  summarise(
    mean   = mean(vrednost),
    median = median(vrednost),
    sd     = sd(vrednost),
    min    = min(vrednost),
    max    = max(vrednost)
  )
print(as.data.frame(desc))

by_pos <- df %>%
  group_by(position) %>%
  summarise(
    n          = n(),
    passes_p90 = mean(passes_p90),
    shots_p90  = mean(shots_p90),
    tackles_p90 = mean(tackles_p90),
    xg_p90     = mean(xg_p90)
  )
print(as.data.frame(by_pos))

# histogram
png("figures/hist_passes.png")
hist(df$passes_p90, main = "Dodavanja po 90 min", xlab = "Dodavanja / 90", col = "grey80")
dev.off()

# density
png("figures/density_xg.png")
plot(density(df$xg_p90), main = "Gustina: xG po 90 min", xlab = "xG / 90")
dev.off()

# boxplot jednog obelezja
png("figures/box_shots.png")
boxplot(df$shots_p90, main = "Suterevi po 90 min", ylab = "Suterevi / 90")
dev.off()

# boxplot dodavanja po poziciji
png("figures/box_passes_by_pos.png", width = 2000, height = 1100, res = 150)
par(mar = c(10, 4, 3, 1))   
boxplot(passes_p90 ~ position, data = df, las = 2,
        main = "Dodavanja/90 po poziciji", xlab = "", ylab = "Dodavanja / 90",
        col = "lightblue")
dev.off()

# qq plot (provera normalnosti)
png("figures/qq_passes.png")
qqnorm(df$passes_p90, main = "Q-Q dijagram: dodavanja/90")
qqline(df$passes_p90, col = "red")
dev.off()

# broj igraca po poziciji
png("figures/bar_positions.png", width = 2000, height = 1100, res = 150)
par(mar = c(11, 4, 3, 1))
barplot(sort(table(df$position), decreasing = TRUE), las = 2,
        main = "Broj igraca po poziciji", ylab = "Broj igraca", col = "grey70")
dev.off()

# histogram + density
g1 <- ggplot(df, aes(x = passes_p90)) +
  geom_histogram(aes(y = after_stat(density)), bins = 30, fill = "steelblue", colour = "white") +
  geom_density(colour = "darkred") +
  labs(title = "Raspodela: dodavanja po 90 minuta", x = "Dodavanja / 90", y = "Gustina")
ggsave("figures/gg_hist_passes.png", g1)

# facet histogrami za vise obelezja odjednom
few <- c("passes_p90", "shots_p90", "tackles_p90", "xg_p90", "pressures_p90", "carries_p90")
long_few <- df %>%
  select(all_of(few)) %>%
  pivot_longer(everything(), names_to = "obelezje", values_to = "vrednost")
g2 <- ggplot(long_few, aes(x = vrednost)) +
  geom_histogram(bins = 25, fill = "steelblue", colour = "white") +
  facet_wrap(~ obelezje, scales = "free") +
  labs(title = "Raspodele izabranih obelezja", x = NULL, y = "Broj igraca")
ggsave("figures/gg_facet_hist.png", g2)

# boxplot po poziciji (ggplot)
g3 <- ggplot(df, aes(x = position, y = passes_p90)) +
  geom_boxplot() +
  coord_flip() +
  labs(title = "Dodavanja/90 po poziciji", x = NULL, y = "Dodavanja / 90")
ggsave("figures/gg_box_by_pos.png", g3)


# scatter (base): pritisci vs tackles
png("figures/scatter_press_tackles.png")
plot(df$pressures_p90, df$tackles_p90, pch = 19, cex = 0.7,
     main = "Pritisci vs tackles / 90", xlab = "Pritisci / 90", ylab = "Tackles / 90")
dev.off()

# scatter (ggplot): suterevi vs xG
g4 <- ggplot(df, aes(x = shots_p90, y = xg_p90)) +
  geom_point(alpha = 0.6) +
  geom_smooth(method = "loess", se = FALSE, colour = "black") +
  labs(title = "Suterevi/90 vs xG/90", x = "Suterevi / 90", y = "xG / 90")
ggsave("figures/gg_scatter_shots_xg.png", g4)

# korelaciona matrica
corr <- cor(df[feat_cols])

# heatmap korelacija
png("figures/corr_heatmap.png", width = 1800, height = 1600, res = 150)
par(mar = c(11, 11, 3, 2))
image(1:ncol(corr), 1:nrow(corr), t(corr[nrow(corr):1, ]),
      axes = FALSE, xlab = "", ylab = "", main = "Korelaciona matrica",
      col = colorRampPalette(c("blue", "white", "red"))(50), zlim = c(-1, 1))
axis(1, at = 1:ncol(corr), labels = colnames(corr), las = 2, cex.axis = 0.6)
axis(2, at = 1:nrow(corr), labels = rev(rownames(corr)), las = 2, cex.axis = 0.6)
dev.off()

# najjace korelacije (parovi)
cp <- as.data.frame(as.table(corr)) %>%
  filter(as.character(Var1) < as.character(Var2)) %>%
  arrange(desc(abs(Freq)))
cat("Najjace korelacije (top 12):\n")
print(head(cp, 12))
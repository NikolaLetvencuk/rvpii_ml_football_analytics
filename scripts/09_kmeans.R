library(sparklyr); library(dplyr); library(ggplot2); library(tidyr)

if (!requireNamespace("cluster", quietly = TRUE)) install.packages("cluster")

PROJEKAT <- normalizePath(".", winslash = "/", mustWork = TRUE)
sp <- function(p) paste0("file:///", file.path(PROJEKAT, p, fsep = "/"))
conf <- spark_config()
conf$`sparklyr.shell.driver-memory` <- "8G"
conf$spark.sql.shuffle.partitions   <- 32
sc <- spark_connect(master = "local[*]", version = "3.5", config = conf)

dir.create("results", showWarnings = FALSE)
dir.create("figures", showWarnings = FALSE)

K_RANGE  <- 2:10        
N_PCA    <- 11          
MAX_ITER <- 50         
SEME     <- 42         
lvl      <- c("GK","CB","FB","DM_CM","AM_W","FW")


feat_cols <- readRDS("results/feat_cols.rds")

train <- spark_read_parquet(sc, "train", sp("data/interim/train"))
test  <- spark_read_parquet(sc, "test",  sp("data/interim/test"))
dat   <- sdf_bind_rows(train, test)

cat("Ukupno igraca:", sdf_nrow(dat), "| Obelezja:", length(feat_cols), "\n")


dat_r <- dat %>% select(all_of(c(feat_cols, "position_group"))) %>% collect()
Xraw  <- as.matrix(dat_r[, feat_cols])
poz   <- factor(dat_r$position_group, levels = lvl)


Xs <- scale(Xraw, center = TRUE, scale = TRUE)

print(table(poz))




prep_std <- ml_pipeline(sc) %>%
  ft_vector_assembler(input_cols = feat_cols, output_col = "features_raw") %>%
  ft_standard_scaler("features_raw", "features",
                     with_mean = TRUE, with_std = TRUE)

prep_pca <- ml_pipeline(sc) %>%
  ft_vector_assembler(input_cols = feat_cols, output_col = "features_raw") %>%
  ft_standard_scaler("features_raw", "features_std",
                     with_mean = TRUE, with_std = TRUE) %>%
  ft_pca(input_col = "features_std", output_col = "features", k = N_PCA)

m_std <- ml_fit(prep_std, dat)
m_pca <- ml_fit(prep_pca, dat)

tbl_std <- ml_transform(m_std, dat)
tbl_pca <- ml_transform(m_pca, dat)

pca_stage <- ml_stage(m_pca, 3)
var_expl  <- tryCatch(as.numeric(pca_stage$explained_variance),
                      error = function(e) NA_real_)
if (!all(is.na(var_expl))) {
  cat("\nObjasnjena varijansa po komponenti:\n"); print(round(var_expl, 4))
  cat("Kumulativno (", N_PCA, "komponenti ):", round(sum(var_expl), 4), "\n")
}



evaluator_sil <- ml_clustering_evaluator(
  sc, features_col = "features", prediction_col = "prediction",
  metric_name = "silhouette")

sse <- function(X, cl) {
  sum(vapply(unique(cl), function(g) {
    Xi <- X[cl == g, , drop = FALSE]
    if (nrow(Xi) < 2) return(0)
    sum(sweep(Xi, 2, colMeans(Xi))^2)
  }, numeric(1)))
}

W_ukupno <- function(X, cl) 2 * sse(X, cl)


provera_W <- function(Xi) {
  d2 <- as.matrix(dist(Xi))^2
  W_par <- 2 * sum(d2[upper.tri(d2)]) / nrow(Xi)
  W_sse <- 2 * sum(sweep(Xi, 2, colMeans(Xi))^2)
  c(preko_parova = W_par, preko_sse = W_sse)
}

cistoca <- function(cl, klase) {
  tab <- table(cl, klase)
  sum(apply(tab, 1, max)) / sum(tab)
}


ari <- function(cl, klase) {
  tab <- table(cl, klase); n <- sum(tab)
  c2 <- function(x) x * (x - 1) / 2
  suma_ij <- sum(c2(tab)); suma_i <- sum(c2(rowSums(tab)))
  suma_j  <- sum(c2(colSums(tab)))
  ocek <- suma_i * suma_j / c2(n)
  (suma_ij - ocek) / (0.5 * (suma_i + suma_j) - ocek)
}

oceni_k <- function(tbl, X, k, oznaka, init_mode = "k-means||", seed = SEME) {
  model <- ml_kmeans(tbl, formula = NULL, k = k, features_col = "features",
                     init_mode = init_mode, max_iter = MAX_ITER, seed = seed)
  tr <- ml_transform(model, tbl)
  pr <- tr %>% select(prediction) %>% collect() %>% pull(prediction)
  
  data.frame(
    prostor  = oznaka,
    k        = k,
    W        = round(W_ukupno(X, pr), 1),
    SSE      = round(sse(X, pr), 1),
    silueta  = round(ml_evaluate(evaluator_sil, tr), 4),
    najmanji = min(table(pr)),
    najveci  = max(table(pr)),
    cistoca  = round(cistoca(pr, poz), 4),
    ari      = round(ari(pr, poz), 4),
    stringsAsFactors = FALSE
  )
}



cat("\nScenario 1: broj klastera (", length(K_RANGE), "vrednosti )...\n")
t1 <- system.time({
  vm1 <- bind_rows(lapply(K_RANGE, function(k) {
    cat("  k =", k, "\n"); oceni_k(tbl_std, Xs, k, "29 obelezja")
  }))
})

# Relativni pad W — brojcana dopuna vizuelnom pravilu lakta.
vm1 <- vm1 %>% mutate(pad_W = round(c(NA, -diff(W)) / lag(W) * 100, 1))

cat("\n--- S1: broj klastera ---\n"); print(vm1, row.names = FALSE)
cat("\nVreme (s):", round(t1[3], 1), "\n")
write.csv(vm1, "results/km_scenario1.csv", row.names = FALSE)

vm1 %>%
  select(k, `W (unutarklasterska varijabilnost)` = W, `Siluetni koeficijent` = silueta) %>%
  pivot_longer(-k, names_to = "mera", values_to = "vrednost") %>%
  ggplot(aes(k, vrednost)) +
  geom_line(linewidth = 0.8, color = "grey30") +
  geom_point(size = 2.5, color = "grey20") +
  facet_wrap(~ mera, scales = "free_y", ncol = 1) +
  scale_x_continuous(breaks = K_RANGE) +
  labs(title = "Metod k sredina, scenario 1: broj klastera",
       subtitle = "Prostor svih 29 standardizovanih obelezja; gornji panel je metod lakta",
       x = "Broj klastera k", y = NULL)
ggsave("figures/KM_S1.png", width = 7, height = 6, dpi = 150)



cat("\nScenario 2: prostor obelezja (", N_PCA, "glavnih komponenata )...\n")
Xp <- prcomp(Xs, center = FALSE, scale. = FALSE)$x[, 1:N_PCA]

t2 <- system.time({
  vm2_pca <- bind_rows(lapply(K_RANGE, function(k) {
    cat("  k =", k, "\n")
    oceni_k(tbl_pca, Xp, k, paste0(N_PCA, " komponenti"))
  }))
})

vm2 <- bind_rows(vm1 %>% select(-pad_W), vm2_pca)
cat("\n--- S2: poredjenje prostora obelezja ---\n"); print(vm2, row.names = FALSE)
cat("\nVreme (s):", round(t2[3], 1), "\n")
write.csv(vm2, "results/km_scenario2.csv", row.names = FALSE)

vm2 %>%
  select(prostor, k, `Siluetni koeficijent` = silueta, `Randov indeks` = ari) %>%
  pivot_longer(c(-prostor, -k), names_to = "mera", values_to = "vrednost") %>%
  ggplot(aes(k, vrednost, color = prostor)) +
  geom_line(linewidth = 0.8) + geom_point(size = 2.5) +
  facet_wrap(~ mera, scales = "free_y", ncol = 1) +
  scale_x_continuous(breaks = K_RANGE) +
  labs(title = "Metod k sredina, scenario 2: prostor obelezja",
       subtitle = "Silueta je kriterijum izbora; Randov indeks sluzi samo za tumacenje",
       x = "Broj klastera k", y = NULL, color = "Prostor")
ggsave("figures/KM_S2.png", width = 7.5, height = 6, dpi = 150)



k_izbor <- vm1$k[which.max(vm1$silueta)]
cat("\nProvera stabilnosti pri k =", k_izbor, "...\n")

stabilnost <- bind_rows(lapply(c("k-means||", "random"), function(im) {
  bind_rows(lapply(c(1, 7, 42, 2024, 31337), function(s) {
    r <- oceni_k(tbl_std, Xs, k_izbor, "29 obelezja", init_mode = im, seed = s)
    data.frame(init = im, seme = s, W = r$W, silueta = r$silueta, ari = r$ari)
  }))
}))
print(stabilnost, row.names = FALSE)
cat("\nRaspon W po pokretanjima:", round(diff(range(stabilnost$W)), 1),
    "| raspon siluete:", round(diff(range(stabilnost$silueta)), 4), "\n")
write.csv(stabilnost, "results/km_stabilnost.csv", row.names = FALSE)


najbolji <- vm2[which.max(vm2$silueta), ]
cat("\nNajvisa silueta:", najbolji$silueta,
    "| prostor:", najbolji$prostor, "| k =", najbolji$k, "\n")


K <- vm1$k[which.max(vm1$silueta)]
cat("Izabrano za analizu strukture: prostor 29 obelezja, k =", K, "\n")

model <- ml_kmeans(tbl_std, formula = NULL, k = K, features_col = "features",
                   init_mode = "k-means||", max_iter = MAX_ITER, seed = SEME)

klaster <- ml_transform(model, tbl_std) %>%
  select(prediction) %>% collect() %>% pull(prediction)
klaster <- factor(paste0("C", klaster + 1))   # C1..CK umesto 0..K-1

cat("\nVelicine klastera:\n"); print(table(klaster))

najmanji_g <- names(which.min(table(klaster)))
cat("\nProvera W(C) nad klasterom", najmanji_g, ":\n")
print(round(provera_W(Xs[klaster == najmanji_g, , drop = FALSE]), 2))


d2_Xs <- dist(Xs)^2

sil_r <- function(cl) {
  if (length(unique(cl)) < 2) return(NA_real_)
  mean(cluster::silhouette(as.integer(factor(cl)), d2_Xs)[, 3])
}

cat("\nBisekcioni metod k sredina pri k =", K, "...\n")
bis <- ml_bisecting_kmeans(tbl_std, formula = NULL, k = K,
                           features_col = "features",
                           max_iter = MAX_ITER, seed = SEME,
                           min_divisible_cluster_size = 1)
bis_tr <- ml_transform(bis, tbl_std)
bis_cl <- bis_tr %>% select(prediction) %>% collect() %>% pull(prediction)

cat("Trazeno klastera:", K, "| dobijeno:", length(unique(bis_cl)), "\n")
print(table(bis_cl))

if (length(unique(bis_cl)) < 2) {
  cat("\nBisekcioni metod nije podelio skup — poredjenje se preskace.\n")
  cat("Verovatan uzrok: parametar min_divisible_cluster_size ili\n",
      "argument k nije prosledjen Spark objektu.\n")
} else {
  bisekcioni <- data.frame(
    metod   = c("k sredina", "bisekcioni k sredina"),
    k_dobij = c(nlevels(klaster), length(unique(bis_cl))),
    W       = c(round(W_ukupno(Xs, klaster), 1), round(W_ukupno(Xs, bis_cl), 1)),
    silueta = c(round(sil_r(klaster), 4), round(sil_r(bis_cl), 4)),
    cistoca = c(round(cistoca(klaster, poz), 4), round(cistoca(bis_cl, poz), 4)),
    ari     = c(round(ari(klaster, poz), 4), round(ari(bis_cl, poz), 4))
  )
  print(bisekcioni, row.names = FALSE)
  cat("\nSlaganje dve podele (ARI izmedju njih):",
      round(ari(klaster, factor(bis_cl)), 4), "\n")
  write.csv(bisekcioni, "results/km_bisekcioni.csv", row.names = FALSE)
}


ukrstena <- table(klaster, poz)
cat("\n--- Klaster naspram pozicione klase ---\n"); print(ukrstena)
write.csv(as.data.frame.matrix(ukrstena), "results/km_ukrstena.csv")

cat("\nCistoca:", round(cistoca(klaster, poz), 4),
    "| Prilagodjeni Randov indeks:", round(ari(klaster, poz), 4), "\n")

dominantna <- apply(ukrstena, 1, function(r)
  paste0(names(r)[which.max(r)], " (", round(max(r)/sum(r)*100), "%)"))
cat("\nDominantna pozicija po klasteru:\n"); print(dominantna)

centroidi <- as.data.frame(t(sapply(levels(klaster), function(g)
  colMeans(Xs[klaster == g, , drop = FALSE]))))
centroidi$klaster <- rownames(centroidi)
write.csv(centroidi, "results/km_centroidi.csv", row.names = FALSE)

centroidi_orig <- as.data.frame(t(sapply(levels(klaster), function(g)
  colMeans(Xraw[klaster == g, , drop = FALSE]))))
centroidi_orig$klaster <- rownames(centroidi_orig)
centroidi_orig$n <- as.integer(table(klaster))
write.csv(centroidi_orig, "results/km_centroidi_original.csv", row.names = FALSE)

f_vred <- vapply(feat_cols, function(f)
  summary(aov(Xs[, f] ~ klaster))[[1]][["F value"]][1], numeric(1))
f_df <- data.frame(obelezje = names(f_vred), F_vrednost = round(f_vred, 1)) %>%
  arrange(desc(F_vrednost))
cat("\n--- Obelezja koja najvise razdvajaju klastere ---\n")
print(head(f_df, 12), row.names = FALSE)
write.csv(f_df, "results/km_obelezja_f.csv", row.names = FALSE)

# 9.5 Siluetni profil
sil <- cluster::silhouette(as.integer(klaster), dist(Xs))
cat("\nProsecna silueta po klasteru:\n")
print(round(tapply(sil[, 3], klaster, mean), 4))
cat("Udeo instanci sa negativnom siluetom:",
    round(mean(sil[, 3] < 0) * 100, 1), "%\n")

write.csv(data.frame(klaster = klaster, position_group = poz,
                     silueta = round(sil[, 3], 4)),
          "results/km_dodela.csv", row.names = FALSE)



pcs  <- prcomp(Xs, center = FALSE, scale. = FALSE)
udeo <- round(pcs$sdev^2 / sum(pcs$sdev^2) * 100, 1)
viz  <- data.frame(PC1 = pcs$x[, 1], PC2 = pcs$x[, 2],
                   klaster = klaster, pozicija = poz)

ggplot(viz, aes(PC1, PC2, color = klaster)) +
  geom_point(size = 1.6, alpha = 0.75) +
  labs(title = paste0("Klasteri u prostoru glavnih komponenata (k = ", K, ")"),
       x = paste0("PC1 (", udeo[1], "%)"), y = paste0("PC2 (", udeo[2], "%)"),
       color = "Klaster")
ggsave("figures/KM_pca_klasteri.png", width = 7, height = 5.5, dpi = 150)

ggplot(viz, aes(PC1, PC2, color = pozicija)) +
  geom_point(size = 1.6, alpha = 0.75) +
  labs(title = "Iste tacke obojene po pozicionoj klasi",
       subtitle = "Poredjenje sa prethodnom slikom pokazuje sta klasteri zaista hvataju",
       x = paste0("PC1 (", udeo[1], "%)"), y = paste0("PC2 (", udeo[2], "%)"),
       color = "Pozicija")
ggsave("figures/KM_pca_pozicije.png", width = 7, height = 5.5, dpi = 150)

top_f <- head(f_df$obelezje, 15)
centroidi %>%
  select(klaster, all_of(top_f)) %>%
  pivot_longer(-klaster, names_to = "obelezje", values_to = "z") %>%
  mutate(obelezje = factor(obelezje, levels = rev(top_f))) %>%
  ggplot(aes(klaster, obelezje, fill = z)) +
  geom_tile() +
  geom_text(aes(label = sprintf("%.1f", z), color = abs(z) > 1.2),
            size = 2.8, show.legend = FALSE) +
  scale_color_manual(values = c(`FALSE` = "grey20", `TRUE` = "white")) +
  scale_fill_gradient2(low = "steelblue4", mid = "white", high = "firebrick",
                       midpoint = 0) +
  labs(title = "Profili klastera",
       subtitle = "Centroidi u standardizovanim jedinicama; 0 je prosek celog skupa",
       x = "Klaster", y = NULL, fill = "z")
ggsave("figures/KM_centroidi.png", width = 7.5, height = 6.5, dpi = 150)

as.data.frame(ukrstena) %>%
  ggplot(aes(klaster, Freq, fill = poz)) +
  geom_col(position = "fill") +
  scale_y_continuous(labels = scales::percent) +
  labs(title = "Sastav klastera po pozicionim klasama",
       x = "Klaster", y = "Udeo", fill = "Pozicija")
ggsave("figures/KM_sastav.png", width = 7.5, height = 4.5, dpi = 150)

as.data.frame(Xraw[, head(f_df$obelezje, 8)]) %>%
  mutate(klaster = klaster) %>%
  pivot_longer(-klaster, names_to = "obelezje", values_to = "vrednost") %>%
  ggplot(aes(klaster, vrednost, fill = klaster)) +
  geom_boxplot(outlier.size = 0.6, show.legend = FALSE) +
  facet_wrap(~ obelezje, scales = "free_y", ncol = 4) +
  labs(title = "Raspodela obelezja po klasterima",
       subtitle = "Osam obelezja sa najvecom F vrednoscu; izvorne jedinice",
       x = "Klaster", y = NULL)
ggsave("figures/KM_boxplot.png", width = 10, height = 5.5, dpi = 150)

data.frame(klaster = klaster, s = sil[, 3]) %>%
  arrange(klaster, desc(s)) %>% mutate(i = row_number()) %>%
  ggplot(aes(i, s, fill = klaster)) +
  geom_col(width = 1) +
  geom_hline(yintercept = mean(sil[, 3]), linetype = "dashed") +
  labs(title = "Siluetni profil izabranog resenja",
       subtitle = paste0("Prosecna silueta ", round(mean(sil[, 3]), 4),
                         " (isprekidana linija)"),
       x = "Instance poredjane po klasteru", y = "Siluetni koeficijent",
       fill = "Klaster")
ggsave("figures/KM_silueta.png", width = 7.5, height = 4.5, dpi = 150)


km_best <- data.frame(
  metod          = "k sredina (k-Means)",
  prostor        = "29 standardizovanih obelezja",
  k              = K,
  W              = round(W_ukupno(Xs, klaster), 1),
  SSE            = round(sse(Xs, klaster), 1),
  silueta        = round(mean(sil[, 3]), 4),
  udeo_negativne = round(mean(sil[, 3] < 0), 4),
  cistoca        = round(cistoca(klaster, poz), 4),
  ari            = round(ari(klaster, poz), 4),
  najmanji       = min(table(klaster)),
  najveci        = max(table(klaster)),
  vreme_s1       = round(t1[3], 1),
  vreme_s2       = round(t2[3], 1),
  row.names = NULL
)
print(km_best)
write.csv(km_best, "results/km_best.csv", row.names = FALSE)

spark_disconnect(sc)
cat("\nGotovo.\n")
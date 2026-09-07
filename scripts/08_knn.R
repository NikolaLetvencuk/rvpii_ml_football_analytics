library(sparklyr); library(dplyr); library(ggplot2)

for (p in c("kknn", "caret", "pROC")) {
  if (!requireNamespace(p, quietly = TRUE)) install.packages(p)
}

PROJEKAT <- normalizePath(".", winslash = "/", mustWork = TRUE)
sp <- function(p) paste0("file:///", file.path(PROJEKAT, p, fsep = "/"))
conf <- spark_config()
conf$`sparklyr.shell.driver-memory` <- "8G"
conf$spark.sql.shuffle.partitions   <- 32
sc <- spark_connect(master = "local[*]", version = "3.5", config = conf)

dir.create("results", showWarnings = FALSE)
dir.create("figures", showWarnings = FALSE)


feat_cols <- readRDS("results/feat_cols.rds")
lvl <- c("GK","CB","FB","DM_CM","AM_W","FW")

train_df <- spark_read_parquet(sc, "train", sp("data/interim/train")) %>%
  select(all_of(c(feat_cols, "position_group"))) %>% collect()
test_df  <- spark_read_parquet(sc, "test",  sp("data/interim/test")) %>%
  select(all_of(c(feat_cols, "position_group"))) %>% collect()

cat("Trening:", nrow(train_df), "| Test:", nrow(test_df),
    "| Obelezja:", length(feat_cols), "\n")

spark_disconnect(sc)

Xtr <- as.matrix(train_df[, feat_cols])
Xte <- as.matrix(test_df[, feat_cols])
ytr <- factor(train_df$position_group, levels = lvl)
yte <- factor(test_df$position_group,  levels = lvl)

stopifnot(!anyNA(Xtr), !anyNA(Xte), !anyNA(ytr), !anyNA(yte))
print(table(ytr))


f1_weighted <- function(actual, predicted, levels_ = lvl) {
  tab  <- table(factor(predicted, levels = levels_),
                factor(actual,    levels = levels_))
  tp   <- diag(tab)
  prec <- tp / rowSums(tab)          # imenilac: koliko puta je klasa predvidjena
  rec  <- tp / colSums(tab)          # imenilac: koliko puta se klasa javlja
  f1   <- 2 * prec * rec / (prec + rec)
  f1[!is.finite(f1)] <- 0            # klasa koja nije ni predvidjena ni prisutna
  w    <- colSums(tab) / sum(tab)    # tezine po ucestalosti stvarne klase
  sum(w * f1)
}

scale_pair <- function(A, B) {
  m <- colMeans(A)
  s <- apply(A, 2, stats::sd)
  s[s == 0 | is.na(s)] <- 1
  list(A = scale(A, center = m, scale = s),
       B = scale(B, center = m, scale = s))
}

knn_predict <- function(Xa, ya, Xb, yb, k, distance, kernel) {
  dtr <- data.frame(Xa, y = ya, check.names = FALSE)
  dte <- data.frame(Xb, y = yb, check.names = FALSE)
  kknn::kknn(y ~ ., train = dtr, test = dte,
             k = k, distance = distance, kernel = kernel,
             scale = FALSE)   # skaliranje smo vec uradili sami
}


set.seed(42)
folds <- caret::createFolds(ytr, k = 10, list = TRUE, returnTrain = FALSE)
cat("\nVelicine preklopa:", sapply(folds, length), "\n")

cv_knn <- function(k, distance = 2, kernel = "rectangular") {
  vapply(folds, function(idx) {
    s  <- scale_pair(Xtr[-idx, , drop = FALSE], Xtr[idx, , drop = FALSE])
    fit <- knn_predict(s$A, ytr[-idx], s$B, ytr[idx], k, distance, kernel)
    f1_weighted(ytr[idx], fit$fitted.values)
  }, numeric(1))
}

run_grid <- function(grid) {
  bind_rows(lapply(seq_len(nrow(grid)), function(i) {
    f1s <- cv_knn(grid$k[i], grid$distance[i], grid$kernel[i])
    cbind(grid[i, , drop = FALSE],
          f1    = round(mean(f1s), 4),
          f1_sd = round(stats::sd(f1s), 4),
          f1_se = round(stats::sd(f1s) / sqrt(length(f1s)), 4))
  }))
}


g1 <- expand.grid(k = c(1, 3, 5, 7, 9, 11, 15, 21, 31, 51),
                  distance = 2, kernel = "rectangular",
                  stringsAsFactors = FALSE)

g2 <- expand.grid(k = c(5, 9, 15, 21, 31),
                  distance = 2,
                  kernel = c("rectangular", "triangular", "gaussian", "inv"),
                  stringsAsFactors = FALSE)

g3 <- expand.grid(k = c(5, 9, 15, 21, 31),
                  distance = c(1, 2, 3),
                  kernel = "rectangular",
                  stringsAsFactors = FALSE)

cat("\nPokretanje S1 (", nrow(g1), "kombinacija )...\n")
t1 <- system.time(vm1 <- run_grid(g1))
cat("Pokretanje S2 (", nrow(g2), "kombinacija )...\n")
t2 <- system.time(vm2 <- run_grid(g2))
cat("Pokretanje S3 (", nrow(g3), "kombinacija )...\n")
t3 <- system.time(vm3 <- run_grid(g3))

vm1 <- vm1 %>% arrange(desc(f1))
vm2 <- vm2 %>% arrange(desc(f1))
vm3 <- vm3 %>% arrange(desc(f1))

cat("\n--- S1: broj suseda ---\n");            print(vm1, row.names = FALSE)
cat("\n--- S2: ponderisanje suseda ---\n");    print(vm2, row.names = FALSE)
cat("\n--- S3: metrika rastojanja ---\n");     print(vm3, row.names = FALSE)
cat("\nVreme (s):", round(c(t1[3], t2[3], t3[3]), 1), "\n")

write.csv(vm1, "results/knn_scenario1.csv", row.names = FALSE)
write.csv(vm2, "results/knn_scenario2.csv", row.names = FALSE)
write.csv(vm3, "results/knn_scenario3.csv", row.names = FALSE)



ggplot(vm1, aes(k, f1)) +
  geom_errorbar(aes(ymin = f1 - f1_se, ymax = f1 + f1_se),
                width = 0.8, color = "grey55") +
  geom_line(linewidth = 0.8) + geom_point(size = 2.5) +
  scale_x_continuous(breaks = g1$k) +
  labs(title = "KNN, scenario 1: broj suseda",
       subtitle = "Tezinska F1 mera, 10-struka unakrsna validacija (+/- 1 SE)",
       x = "Broj suseda k", y = "F1")
ggsave("figures/KNN_S1.png", width = 7, height = 4.5, dpi = 150)

ggplot(vm2, aes(k, f1, color = kernel)) +
  geom_line(linewidth = 0.8) + geom_point(size = 2.5) +
  scale_x_continuous(breaks = unique(g2$k)) +
  labs(title = "KNN, scenario 2: ponderisanje glasova suseda",
       subtitle = "Tezinska F1 mera, 10-struka unakrsna validacija",
       x = "Broj suseda k", y = "F1", color = "Jezgro")
ggsave("figures/KNN_S2.png", width = 7.5, height = 4.5, dpi = 150)

ggplot(vm3, aes(k, f1, color = factor(distance))) +
  geom_line(linewidth = 0.8) + geom_point(size = 2.5) +
  scale_x_continuous(breaks = unique(g3$k)) +
  labs(title = "KNN, scenario 3: metrika rastojanja",
       subtitle = "Tezinska F1 mera, 10-struka unakrsna validacija",
       x = "Broj suseda k", y = "F1",
       color = "Minkowski p\n(1=Manhattan,\n2=Euklid)")
ggsave("figures/KNN_S3.png", width = 7.5, height = 4.5, dpi = 150)


best_f1 <- c(S1 = max(vm1$f1), S2 = max(vm2$f1), S3 = max(vm3$f1))
print(round(best_f1, 4))

best_scen <- names(which.max(best_f1))
best_row  <- list(S1 = vm1, S2 = vm2, S3 = vm3)[[best_scen]][1, ]
cat("\nNajbolji scenario:", best_scen, "| CV F1 =", round(max(best_f1), 4),
    "+/-", best_row$f1_se, "(SE)\n")
cat("Parametri: k =", best_row$k,
    "| distance =", best_row$distance,
    "| kernel =", best_row$kernel, "\n")

cat("\nRaspon svih ispitanih konfiguracija: ",
    round(min(c(vm1$f1, vm2$f1, vm3$f1)), 4), " - ",
    round(max(c(vm1$f1, vm2$f1, vm3$f1)), 4), "\n", sep = "")
cat("Tipicna standardna greska po preklopima: ",
    round(median(c(vm1$f1_se, vm2$f1_se, vm3$f1_se)), 4), "\n", sep = "")


s_full <- scale_pair(Xtr, Xte)

t_fit  <- system.time({
  ref <- data.frame(s_full$A, y = ytr, check.names = FALSE)
})
t_pred <- system.time({
  final <- knn_predict(s_full$A, ytr, s_full$B, yte,
                       best_row$k, best_row$distance, best_row$kernel)
})

pred_group <- factor(final$fitted.values, levels = lvl)
cm <- caret::confusionMatrix(pred_group, yte)
print(cm)


n_modela <- (nrow(g1) + nrow(g2) + nrow(g3)) * 10 + 1
cat("\n'Obucavanje' (priprema reference):", round(t_fit[3], 3), "s\n")
cat("Predvidjanje nad test skupom:", round(t_pred[3], 3), "s\n")
cat("Ukupno ocenjenih modela u pretrazi:", n_modela, "\n")


pmat <- final$prob[, lvl, drop = FALSE]
auc <- pROC::multiclass.roc(response = yte, predictor = pmat)
cat("Viseklasni AUC (Hand-Till):", round(as.numeric(auc$auc), 4), "\n")


metrike <- data.frame(
  metod            = "KNN",
  scenario         = best_scen,
  cv_f1            = round(max(best_f1), 4),
  test_tacnost     = round(unname(cm$overall["Accuracy"]), 4),
  test_kappa       = round(unname(cm$overall["Kappa"]), 4),
  makro_preciznost = round(mean(cm$byClass[, "Precision"], na.rm = TRUE), 4),
  makro_odziv      = round(mean(cm$byClass[, "Recall"],    na.rm = TRUE), 4),
  makro_f1         = round(mean(cm$byClass[, "F1"],        na.rm = TRUE), 4),
  bal_tacnost      = round(mean(cm$byClass[, "Balanced Accuracy"], na.rm = TRUE), 4),
  auc              = round(as.numeric(auc$auc), 4),
  vreme_fit_s      = round(t_fit[3], 3),
  vreme_pred_s     = round(t_pred[3], 3),
  broj_modela      = n_modela,
  vreme_pretrage_s = round(sum(t1[3], t2[3], t3[3]), 1),
  row.names = NULL
)
print(metrike)
write.csv(metrike, "results/knn_best.csv", row.names = FALSE)

po_klasi <- as.data.frame(cm$byClass[, c("Precision","Recall","F1","Balanced Accuracy")])
po_klasi$klasa <- gsub("Class: ", "", rownames(po_klasi))
print(po_klasi, row.names = FALSE)
write.csv(po_klasi, "results/knn_po_klasi.csv", row.names = FALSE)

write.csv(as.data.frame.matrix(cm$table), "results/knn_confusion.csv")

as.data.frame(cm$table) %>%
  ggplot(aes(Reference, Prediction, fill = Freq)) +
  geom_tile() + geom_text(aes(label = Freq), color = "white", size = 4) +
  scale_fill_gradient(low = "grey85", high = "darkorange3") +
  labs(title = "Matrica konfuzije — KNN (test skup)",
       x = "Stvarna klasa", y = "Predvidjena klasa")
ggsave("figures/KNN_confusion.png", width = 7, height = 5.5, dpi = 150)


set.seed(42)
REPS <- 5
base_f1 <- f1_weighted(yte, final$fitted.values)
cat("\nOsnovna F1 na test skupu:", round(base_f1, 4), "\n")
cat("Racunanje permutacionog znacaja (", length(feat_cols), "x", REPS, ")...\n")

t_imp <- system.time({
  drops <- vapply(seq_along(feat_cols), function(j) {
    mean(replicate(REPS, {
      Xp <- s_full$B
      Xp[, j] <- sample(Xp[, j])
      fp <- knn_predict(s_full$A, ytr, Xp, yte,
                        best_row$k, best_row$distance, best_row$kernel)
      base_f1 - f1_weighted(yte, fp$fitted.values)
    }))
  }, numeric(1))
})
cat("Vreme:", round(t_imp[3], 1), "s\n")

imp_df <- data.frame(obelezje = feat_cols,
                     znacaj = round(drops, 4)) %>%
  mutate(znacaj_norm = round(pmax(znacaj, 0) / sum(pmax(znacaj, 0)), 4)) %>%
  arrange(desc(znacaj))

print(head(imp_df, 15), row.names = FALSE)
write.csv(imp_df, "results/knn_importance.csv", row.names = FALSE)

head(imp_df, 15) %>%
  ggplot(aes(reorder(obelezje, znacaj), znacaj)) +
  geom_col(fill = "darkorange3") + coord_flip() +
  labs(title = "Znacaj obelezja — KNN (permutacioni)",
       subtitle = "Pad tezinske F1 mere pri nasumicnom mesanju obelezja",
       x = NULL, y = "Pad F1")
ggsave("figures/KNN_importance.png", width = 7, height = 5.5, dpi = 150)



putanje <- c(KNN = "results/knn_best.csv",
             DT  = "results/dt_best.csv",
             RF  = "results/rf_best.csv")
postoje <- putanje[file.exists(putanje)]

if (length(postoje) >= 2) {
  svi <- bind_rows(lapply(postoje, read.csv)) %>% arrange(desc(cv_f1))
  cat("\n=== Poredjenje svih metoda ===\n")
  print(svi[, c("metod","scenario","cv_f1","test_tacnost","test_kappa",
                "makro_f1","bal_tacnost","auc")], row.names = FALSE)
  cat("\n--- Cena ---\n")
  print(svi[, c("metod","vreme_fit_s","vreme_pred_s",
                "broj_modela","vreme_pretrage_s")], row.names = FALSE)
  
  pobednik <- svi$metod[which.max(svi$cv_f1)]
  cat("\nIzabrano resenje na nivou svih metoda:", pobednik,
      "| CV F1 =", max(svi$cv_f1), "\n")
  
  write.csv(svi, "results/poredjenje_metoda.csv", row.names = FALSE)
  
  svi %>%
    select(metod, cv_f1, test_tacnost, makro_f1, bal_tacnost) %>%
    tidyr::pivot_longer(-metod, names_to = "pokazatelj", values_to = "vrednost") %>%
    ggplot(aes(pokazatelj, vrednost, fill = metod)) +
    geom_col(position = "dodge") +
    geom_text(aes(label = sprintf("%.3f", vrednost)),
              position = position_dodge(width = 0.9),
              vjust = -0.3, size = 2.8) +
    coord_cartesian(ylim = c(0.8, 1.0)) +
    labs(title = "Poredjenje klasifikacionih metoda",
         subtitle = "CV F1 sa trening skupa, ostalo sa test skupa",
         x = NULL, y = NULL, fill = "Metod")
  ggsave("figures/POREDJENJE_metode.png", width = 8, height = 4.5, dpi = 150)
} else {
  cat("\nPreskacem poredjenje — pokreni prvo skripte za DT i RF.\n")
}

if (all(file.exists("results/dt_importance.csv", "results/rf_importance.csv"))) {
  dt_imp <- read.csv("results/dt_importance.csv")
  rf_imp <- read.csv("results/rf_importance.csv")
  ranglista <- imp_df %>%
    select(obelezje, znacaj_knn = znacaj_norm) %>%
    merge(rf_imp %>% select(obelezje, znacaj_rf = znacaj), by = "obelezje") %>%
    merge(dt_imp %>% select(obelezje, znacaj_dt = znacaj), by = "obelezje") %>%
    arrange(desc(znacaj_rf))
  print(head(ranglista, 15), row.names = FALSE)
  write.csv(ranglista, "results/importance_sve_metode.csv", row.names = FALSE)
}

cat("\nGotovo.\n")
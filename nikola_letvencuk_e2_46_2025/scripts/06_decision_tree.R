library(sparklyr); library(dplyr); library(ggplot2); library(tidyr)

PROJEKAT <- normalizePath(".", winslash = "/", mustWork = TRUE)
sp <- function(p) paste0("file:///", file.path(PROJEKAT, p, fsep = "/"))
conf <- spark_config()
conf$`sparklyr.shell.driver-memory` <- "8G"
conf$spark.sql.shuffle.partitions   <- 32
sc <- spark_connect(master = "local[*]", version = "3.5", config = conf)

dir.create("results", showWarnings = FALSE)
dir.create("figures", showWarnings = FALSE)

feat_cols <- readRDS("results/feat_cols.rds")
train <- spark_read_parquet(sc, "train", sp("data/interim/train"))
test  <- spark_read_parquet(sc, "test",  sp("data/interim/test"))
cat("Trening:", sdf_nrow(train), "| Test:", sdf_nrow(test),
    "| Obelezja:", length(feat_cols), "\n")


base_pipeline <- ml_pipeline(sc) %>%
  ft_string_indexer("position_group", "label") %>%
  ft_vector_assembler(input_cols = feat_cols, output_col = "features_raw") %>%
  ft_standard_scaler("features_raw", "features", with_mean = TRUE, with_std = TRUE)

pipe_dt <- base_pipeline %>%
  ml_decision_tree_classifier(features_col = "features", label_col = "label")

evaluator <- ml_multiclass_classification_evaluator(
  sc, label_col = "label", prediction_col = "prediction", metric_name = "f1")

run_cv <- function(grid) {
  cv <- ml_cross_validator(sc, estimator = pipe_dt, estimator_param_maps = grid,
                           evaluator = evaluator, num_folds = 10,
                           parallelism = 4, seed = 42)
  ml_fit(cv, train)
}


g1 <- list(decision_tree = list(max_depth = c(2,3,5,8,12,20)))
g2 <- list(decision_tree = list(min_instances_per_node = c(1,5,10,20,50),
                                min_info_gain = c(0, 0.001, 0.01)))
g3 <- list(decision_tree = list(impurity = c("gini","entropy"),
                                max_depth = c(5,10,15)))

t1 <- system.time(cv1 <- run_cv(g1))
t2 <- system.time(cv2 <- run_cv(g2))
t3 <- system.time(cv3 <- run_cv(g3))

# ml_validation_metrics vraca obican data.frame, ne tibble
vm1 <- ml_validation_metrics(cv1) %>% arrange(desc(f1))
vm2 <- ml_validation_metrics(cv2) %>% arrange(desc(f1))
vm3 <- ml_validation_metrics(cv3) %>% arrange(desc(f1))

cat("\n--- S1: dubina stabla ---\n");        print(vm1, row.names = FALSE)
cat("\n--- S2: uslovi zaustavljanja ---\n");  print(vm2, row.names = FALSE)
cat("\n--- S3: kriterijum grananja ---\n");   print(vm3, row.names = FALSE)
cat("\nNazivi kolona (za slucaj problema sa graficima):\n")
print(colnames(vm1)); print(colnames(vm2)); print(colnames(vm3))
cat("\nVreme (s):", round(c(t1[3], t2[3], t3[3]), 1), "\n")

write.csv(vm1, "results/dt_scenario1.csv", row.names = FALSE)
write.csv(vm2, "results/dt_scenario2.csv", row.names = FALSE)
write.csv(vm3, "results/dt_scenario3.csv", row.names = FALSE)


pick <- function(vm, pat) names(vm)[grepl(pat, names(vm), ignore.case = TRUE)][1]

ggplot(vm1, aes(.data[[pick(vm1,"max_depth")]], f1)) +
  geom_line(linewidth = 0.8) + geom_point(size = 2.5) +
  labs(title = "Stablo odlucivanja, scenario 1: dubina stabla",
       subtitle = "F1 mera, 10-struka unakrsna validacija",
       x = "Maksimalna dubina", y = "F1")
ggsave("figures/DT_S1.png", width = 7, height = 4.5, dpi = 150)

ggplot(vm2, aes(.data[[pick(vm2,"min_instances")]], f1,
                color = factor(.data[[pick(vm2,"min_info_gain")]]))) +
  geom_line(linewidth = 0.8) + geom_point(size = 2.5) +
  labs(title = "Stablo odlucivanja, scenario 2: uslovi zaustavljanja",
       subtitle = "F1 mera, 10-struka unakrsna validacija",
       x = "Minimalan broj instanci u cvoru", y = "F1",
       color = "Min. prirast\ninformacije")
ggsave("figures/DT_S2.png", width = 7.5, height = 4.5, dpi = 150)

ggplot(vm3, aes(.data[[pick(vm3,"max_depth")]], f1,
                color = .data[[pick(vm3,"impurity")]])) +
  geom_line(linewidth = 0.8) + geom_point(size = 2.5) +
  labs(title = "Stablo odlucivanja, scenario 3: kriterijum grananja",
       subtitle = "F1 mera, 10-struka unakrsna validacija",
       x = "Maksimalna dubina", y = "F1", color = "Kriterijum")
ggsave("figures/DT_S3.png", width = 7.5, height = 4.5, dpi = 150)


# Kriterijum: najvisa prosecna F1 iz unakrsne validacije.
best_f1 <- c(S1 = max(vm1$f1), S2 = max(vm2$f1), S3 = max(vm3$f1))
print(round(best_f1, 4))

best_scen  <- names(which.max(best_f1))
best_cv    <- list(S1 = cv1, S2 = cv2, S3 = cv3)[[best_scen]]
best_model <- best_cv$best_model
cat("\nNajbolji scenario:", best_scen, "| CV F1 =", round(max(best_f1), 4), "\n")


# test skup — vise pokazatelja
map_lab <- ml_transform(best_model, train) %>%
  select(position_group, label) %>% distinct() %>% collect()

preds <- ml_transform(best_model, test) %>%
  select(position_group, label, prediction) %>% collect() %>%
  left_join(map_lab, by = c("prediction" = "label"),
            suffix = c("", "_pred")) %>%
  rename(pred_group = position_group_pred)

lvl <- c("GK","CB","FB","DM_CM","AM_W","FW")
cm <- caret::confusionMatrix(factor(preds$pred_group, levels = lvl),
                             factor(preds$position_group, levels = lvl))
print(cm)

# zbirni pokazatelji
metrike <- data.frame(
  metod            = "Stablo odlucivanja",
  scenario         = best_scen,
  cv_f1            = round(max(best_f1), 4),
  test_tacnost     = round(cm$overall["Accuracy"], 4),
  test_kappa       = round(cm$overall["Kappa"], 4),
  makro_preciznost = round(mean(cm$byClass[, "Precision"], na.rm = TRUE), 4),
  makro_odziv      = round(mean(cm$byClass[, "Recall"],    na.rm = TRUE), 4),
  makro_f1         = round(mean(cm$byClass[, "F1"],        na.rm = TRUE), 4),
  bal_tacnost      = round(mean(cm$byClass[, "Balanced Accuracy"], na.rm = TRUE), 4),
  vreme_s          = round(sum(t1[3], t2[3], t3[3]), 1)
)
print(metrike)
write.csv(metrike, "results/dt_best.csv", row.names = FALSE)

# pokazatelji po klasi
po_klasi <- as.data.frame(cm$byClass[, c("Precision","Recall","F1","Balanced Accuracy")])
po_klasi$klasa <- gsub("Class: ", "", rownames(po_klasi))
print(po_klasi, row.names = FALSE)
write.csv(po_klasi, "results/dt_po_klasi.csv", row.names = FALSE)

# matrica konfuzije
write.csv(as.data.frame.matrix(cm$table), "results/dt_confusion.csv")

as.data.frame(cm$table) %>%
  ggplot(aes(Reference, Prediction, fill = Freq)) +
  geom_tile() + geom_text(aes(label = Freq), color = "white", size = 4) +
  scale_fill_gradient(low = "grey85", high = "steelblue4") +
  labs(title = "Matrica konfuzije — stablo odlucivanja (test skup)",
       x = "Stvarna klasa", y = "Predvidjena klasa")
ggsave("figures/DT_confusion.png", width = 7, height = 5.5, dpi = 150)

imp <- ml_stage(best_model, 4)$feature_importances
imp_df <- data.frame(obelezje = feat_cols, znacaj = round(imp, 4)) %>%
  arrange(desc(znacaj))
print(head(imp_df, 12), row.names = FALSE)
write.csv(imp_df, "results/dt_importance.csv", row.names = FALSE)

spark_disconnect(sc)
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

pipe_rf <- base_pipeline %>%
  ml_random_forest_classifier(features_col = "features", label_col = "label",
                              seed = 42)

evaluator <- ml_multiclass_classification_evaluator(
  sc, label_col = "label", prediction_col = "prediction", metric_name = "f1")

run_cv <- function(grid) {
  cv <- ml_cross_validator(sc, estimator = pipe_rf, estimator_param_maps = grid,
                           evaluator = evaluator, num_folds = 10,
                           parallelism = 4, seed = 42)
  ml_fit(cv, train)
}


# S1: num of trees
# S2: depth of threes combined with how many attributes we use in each tree
# S3: part of the data that we see and max instances per node
g1 <- list(random_forest = list(num_trees = c(20, 50, 100, 250, 500)))
g2 <- list(random_forest = list(max_depth = c(3, 5, 10, 15),
                                feature_subset_strategy = c("sqrt","log2","onethird")))
g3 <- list(random_forest = list(subsampling_rate = c(0.6, 0.8, 1.0),
                                min_instances_per_node = c(1, 5, 20)))

t1 <- system.time(cv1 <- run_cv(g1))
t2 <- system.time(cv2 <- run_cv(g2))
t3 <- system.time(cv3 <- run_cv(g3))

vm1 <- ml_validation_metrics(cv1) %>% arrange(desc(f1))
vm2 <- ml_validation_metrics(cv2) %>% arrange(desc(f1))
vm3 <- ml_validation_metrics(cv3) %>% arrange(desc(f1))

cat("\nS1:\n");                    
print(vm1, row.names = FALSE)
cat("\nS2:\n");        
print(vm2, row.names = FALSE)
cat("\nS3:\n");     
print(vm3, row.names = FALSE)
cat("\nNazivi kolona:\n")
print(colnames(vm1)); print(colnames(vm2)); print(colnames(vm3))
cat("\nVreme (s):", round(c(t1[3], t2[3], t3[3]), 1), "\n")

write.csv(vm1, "results/rf_scenario1.csv", row.names = FALSE)
write.csv(vm2, "results/rf_scenario2.csv", row.names = FALSE)
write.csv(vm3, "results/rf_scenario3.csv", row.names = FALSE)


pick <- function(vm, pat) names(vm)[grepl(pat, names(vm), ignore.case = TRUE)][1]

ggplot(vm1, aes(.data[[pick(vm1,"num_trees")]], f1)) +
  geom_line(linewidth = 0.8) + geom_point(size = 2.5) +
  labs(title = "Slucajna suma, scenario 1: broj stabala",
       subtitle = "F1 mera, 10-struka unakrsna validacija",
       x = "Broj stabala u ansamblu", y = "F1")
ggsave("figures/RF_S1.png", width = 7, height = 4.5, dpi = 150)

ggplot(vm2, aes(.data[[pick(vm2,"max_depth")]], f1,
                color = .data[[pick(vm2,"feature_subset")]])) +
  geom_line(linewidth = 0.8) + geom_point(size = 2.5) +
  labs(title = "Slucajna suma, scenario 2: dubina i podskup obelezja",
       subtitle = "F1 mera, 10-struka unakrsna validacija",
       x = "Maksimalna dubina", y = "F1",
       color = "Strategija\npodskupa")
ggsave("figures/RF_S2.png", width = 7.5, height = 4.5, dpi = 150)

ggplot(vm3, aes(.data[[pick(vm3,"subsampling")]], f1,
                color = factor(.data[[pick(vm3,"min_instances")]]))) +
  geom_line(linewidth = 0.8) + geom_point(size = 2.5) +
  labs(title = "Slucajna suma, scenario 3: uzorkovanje i velicina cvora",
       subtitle = "F1 mera, 10-struka unakrsna validacija",
       x = "Udeo uzorkovanja", y = "F1",
       color = "Min. instanci\nu cvoru")
ggsave("figures/RF_S3.png", width = 7.5, height = 4.5, dpi = 150)


best_f1 <- c(S1 = max(vm1$f1), S2 = max(vm2$f1), S3 = max(vm3$f1))
print(round(best_f1, 4))

best_scen  <- names(which.max(best_f1))
best_cv    <- list(S1 = cv1, S2 = cv2, S3 = cv3)[[best_scen]]
best_model <- best_cv$best_model
cat("\nNajbolji scenario:", best_scen, "| CV F1 =", round(max(best_f1), 4), "\n")

rf_stage <- ml_stage(best_model, 4)
cat("num_trees:",   invoke(spark_jobj(rf_stage), "getNumTrees"), "\n")
cat("max_depth:",   invoke(spark_jobj(rf_stage), "getMaxDepth"), "\n")
cat("subset:",      invoke(spark_jobj(rf_stage), "getFeatureSubsetStrategy"), "\n")
cat("subsampling:", invoke(spark_jobj(rf_stage), "getSubsamplingRate"), "\n")
cat("min_inst:",    invoke(spark_jobj(rf_stage), "getMinInstancesPerNode"), "\n")
cat("ukupno cvorova u ansamblu:", invoke(spark_jobj(rf_stage), "totalNumNodes"), "\n")


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



pipe_best <- base_pipeline %>%
  ml_random_forest_classifier(
    features_col = "features", label_col = "label", seed = 42,
    num_trees               = invoke(spark_jobj(rf_stage), "getNumTrees"),
    max_depth               = invoke(spark_jobj(rf_stage), "getMaxDepth"),
    feature_subset_strategy = invoke(spark_jobj(rf_stage), "getFeatureSubsetStrategy"),
    subsampling_rate        = invoke(spark_jobj(rf_stage), "getSubsamplingRate"),
    min_instances_per_node  = invoke(spark_jobj(rf_stage), "getMinInstancesPerNode"))

t_fit  <- system.time(final_model <- ml_fit(pipe_best, train))
t_pred <- system.time(ml_transform(final_model, test) %>% sdf_nrow())

n_modela <- (5 + 12 + 9) * 10 + 3
cat("\nObucavanje jednog modela:", round(t_fit[3], 3), "s\n")
cat("Predvidjanje nad test skupom:", round(t_pred[3], 3), "s\n")
cat("Ukupno obucenih modela u pretrazi:", n_modela, "\n")


probs <- ml_transform(best_model, test) %>%
  sdf_separate_column("probability", into = paste0("p", 0:5)) %>%
  select(label, p0, p1, p2, p3, p4, p5) %>%
  collect()

pmat <- as.matrix(probs[, paste0("p", 0:5)])
colnames(pmat) <- as.character(0:5)

auc <- pROC::multiclass.roc(response = factor(probs$label, levels = 0:5),
                            predictor = pmat)
cat("Viseklasni AUC (Hand-Till):", round(as.numeric(auc$auc), 4), "\n")


metrike <- data.frame(
  metod            = "Slucajna suma",
  scenario         = best_scen,
  cv_f1            = round(max(best_f1), 4),
  test_tacnost     = round(cm$overall["Accuracy"], 4),
  test_kappa       = round(cm$overall["Kappa"], 4),
  makro_preciznost = round(mean(cm$byClass[, "Precision"], na.rm = TRUE), 4),
  makro_odziv      = round(mean(cm$byClass[, "Recall"],    na.rm = TRUE), 4),
  makro_f1         = round(mean(cm$byClass[, "F1"],        na.rm = TRUE), 4),
  bal_tacnost      = round(mean(cm$byClass[, "Balanced Accuracy"], na.rm = TRUE), 4),
  auc              = round(as.numeric(auc$auc), 4),
  vreme_fit_s      = round(t_fit[3], 3),
  vreme_pred_s     = round(t_pred[3], 3),
  broj_modela      = n_modela,
  vreme_pretrage_s = round(sum(t1[3], t2[3], t3[3]), 1)
)
print(metrike)
write.csv(metrike, "results/rf_best.csv", row.names = FALSE)

po_klasi <- as.data.frame(cm$byClass[, c("Precision","Recall","F1","Balanced Accuracy")])
po_klasi$klasa <- gsub("Class: ", "", rownames(po_klasi))
print(po_klasi, row.names = FALSE)
write.csv(po_klasi, "results/rf_po_klasi.csv", row.names = FALSE)

write.csv(as.data.frame.matrix(cm$table), "results/rf_confusion.csv")

as.data.frame(cm$table) %>%
  ggplot(aes(Reference, Prediction, fill = Freq)) +
  geom_tile() + geom_text(aes(label = Freq), color = "white", size = 4) +
  scale_fill_gradient(low = "grey85", high = "darkgreen") +
  labs(title = "Matrica konfuzije — slucajna suma (test skup)",
       x = "Stvarna klasa", y = "Predvidjena klasa")
ggsave("figures/RF_confusion.png", width = 7, height = 5.5, dpi = 150)


imp <- spark_jobj(rf_stage) %>% invoke("featureImportances") %>% invoke("toArray")
imp_df <- data.frame(obelezje = feat_cols, znacaj = round(imp, 4)) %>%
  arrange(desc(znacaj))
print(head(imp_df, 15), row.names = FALSE)
write.csv(imp_df, "results/rf_importance.csv", row.names = FALSE)

head(imp_df, 15) %>%
  ggplot(aes(reorder(obelezje, znacaj), znacaj)) +
  geom_col(fill = "darkgreen") + coord_flip() +
  labs(title = "Znacaj obelezja — slucajna suma", x = NULL, y = "Znacaj")
ggsave("figures/RF_importance.png", width = 7, height = 5.5, dpi = 150)

if (file.exists("results/dt_importance.csv")) {
  dt_imp <- read.csv("results/dt_importance.csv")
  poredjenje <- merge(imp_df, dt_imp, by = "obelezje",
                      suffixes = c("_suma", "_stablo")) %>%
    arrange(desc(znacaj_suma))
  print(head(poredjenje, 12), row.names = FALSE)
  write.csv(poredjenje, "results/importance_poredjenje.csv", row.names = FALSE)
}

spark_disconnect(sc)
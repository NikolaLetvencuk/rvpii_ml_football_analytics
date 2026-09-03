library(sparklyr); library(dplyr); library(ggplot2); library(dbplot)

PROJEKAT <- normalizePath(".", winslash = "/", mustWork = TRUE)
sp <- function(p) paste0("file:///", file.path(PROJEKAT, p, fsep = "/"))
conf <- spark_config(); conf$`sparklyr.shell.driver-memory` <- "8G"
sc <- spark_connect(master = "local[*]", version = "3.5", config = conf)
ev <- spark_read_parquet(sc, "ev_p", sp("data/interim/events_flat"))
dir.create("figures", showWarnings = FALSE)


# event type proportion
ev %>% count(event_type, sort = TRUE) %>% collect() %>% print(n = 33)

# pass length
ev %>% filter(!is.na(pass_length)) %>%
  dbplot_histogram(pass_length, bins = 60) +
  labs(title = "Raspodela dužine dodavanja",
       subtitle = "1.481.813 dodavanja, agregacija izvršena u sistemu Spark",
       x = "Dužina dodavanja (jardi)", y = "Broj dodavanja")
ggsave("figures/A2_pass_length.png", width = 8, height = 5, dpi = 150)

# heatmap
ev %>% filter(!is.na(loc_x), !is.na(loc_y)) %>%
  dbplot_raster(loc_x, loc_y, resolution = 60) +
  scale_fill_viridis_c() +
  labs(title = "Gustina dodira po terenu", subtitle = "5,28 miliona zapisa",
       x = "Dužina terena", y = "Širina terena")
ggsave("figures/A3_heatmap.png", width = 9, height = 6, dpi = 150)

# heatmap per positions
grid <- sdf_sql(sc, "
  SELECT CASE
    WHEN position_name='Goalkeeper' THEN 'GK'
    WHEN position_name IN ('Right Center Back','Left Center Back','Center Back') THEN 'CB'
    WHEN position_name IN ('Left Back','Right Back','Left Wing Back','Right Wing Back') THEN 'FB'
    WHEN position_name IN ('Right Defensive Midfield','Left Defensive Midfield',
         'Center Defensive Midfield','Right Center Midfield','Left Center Midfield') THEN 'DM_CM'
    WHEN position_name IN ('Right Wing','Left Wing','Center Attacking Midfield',
         'Right Attacking Midfield','Right Midfield','Left Midfield') THEN 'AM_W'
    WHEN position_name IN ('Center Forward','Right Center Forward','Left Center Forward') THEN 'FW'
  END AS pos_grp,
  FLOOR(loc_x/4)*4 AS gx, FLOOR(loc_y/4)*4 AS gy, COUNT(*) AS n
  FROM ev_p WHERE loc_x IS NOT NULL AND position_name IS NOT NULL
  GROUP BY 1,2,3") %>% collect()

grid$pos_grp <- factor(grid$pos_grp, levels = c("GK","CB","FB","DM_CM","AM_W","FW"))
ggplot(grid, aes(gx, gy, fill = n)) + geom_tile() +
  facet_wrap(~pos_grp) + scale_fill_viridis_c(trans = "sqrt") +
  labs(title = "Gustina dodira po pozicionoj klasi", x = NULL, y = NULL)
ggsave("figures/A4_heatmap_pozicije.png", width = 11, height = 7, dpi = 150)

spark_disconnect(sc)


d <- read.csv("data/processed/player_features_labeled.csv", stringsAsFactors = FALSE)
d$position_group <- factor(d$position_group, levels = c("GK","CB","FB","DM_CM","AM_W","FW"))

num <- names(d)[sapply(d, is.numeric)]
num <- setdiff(num, c("player_id","pos_purity","purity6","minutes"))

# descriptive statistics
desc <- data.frame(
  obelezje = num,
  sredina  = sapply(d[num], mean),
  medijana = sapply(d[num], median),
  sd       = sapply(d[num], sd),
  min      = sapply(d[num], min),
  max      = sapply(d[num], max),
  asimetrija = sapply(d[num], function(x) e1071::skewness(x))
)
desc[, -1] <- round(desc[, -1], 3)
print(desc[order(-abs(desc$asimetrija)), ], row.names = FALSE)
write.csv(desc, "results/deskriptiva.csv", row.names = FALSE)

# attributes
library(tidyr)
d %>% select(all_of(num)) %>% pivot_longer(everything()) %>%
  ggplot(aes(value)) + geom_histogram(bins = 40) +
  facet_wrap(~name, scales = "free", ncol = 5) +
  labs(title = "Raspodela obeležja na nivou igrača")
ggsave("figures/B2_raspodele.png", width = 15, height = 12, dpi = 130)

# coreration matrix
library(ggcorrplot)
cm <- cor(d[num])
ggcorrplot(cm, hc.order = TRUE, type = "lower", tl.cex = 7) +
  labs(title = "Korelacije između obeležja")
ggsave("figures/B3_korelacije.png", width = 11, height = 10, dpi = 150)

cp <- as.data.frame(as.table(cm))
cp <- cp[cp$Var1 != cp$Var2 & abs(cp$Freq) > 0.8, ]
cp <- cp[!duplicated(t(apply(cp[,1:2], 1, sort))), ]
print(cp[order(-abs(cp$Freq)), ], row.names = FALSE)

# attributes that devide positions — ANOVA F
fvals <- sapply(num, function(v) summary(aov(d[[v]] ~ d$position_group))[[1]][1,4])
print(head(sort(fvals, decreasing = TRUE), 12))

# box-plot top 8 attributes per position
top8 <- names(head(sort(fvals, decreasing = TRUE), 8))
d %>% select(position_group, all_of(top8)) %>%
  pivot_longer(-position_group) %>%
  ggplot(aes(position_group, value, fill = position_group)) +
  geom_boxplot(outlier.size = 0.4) + facet_wrap(~name, scales = "free_y") +
  theme(legend.position = "none") +
  labs(title = "Obeležja koja najbolje razdvajaju pozicione klase", x = NULL)
ggsave("figures/B5_boxplot.png", width = 12, height = 8, dpi = 150)

# PCA
pca <- prcomp(d[num], scale. = TRUE)
ve <- round(100 * summary(pca)$importance[2, 1:5], 1); print(ve)
print(which(cumsum(summary(pca)$importance[2,]) >= 0.9)[1])

ggplot(data.frame(PC1 = pca$x[,1], PC2 = pca$x[,2], poz = d$position_group),
       aes(PC1, PC2, color = poz)) +
  geom_point(alpha = 0.6, size = 1.6) +
  labs(title = sprintf("PCA — PC1 %.1f%%, PC2 %.1f%%", ve[1], ve[2]))
ggsave("figures/B6_pca.png", width = 8, height = 6, dpi = 150)
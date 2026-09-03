dir.create("C:/hadoop/bin", recursive = TRUE, showWarnings = FALSE)

base <- "https://raw.githubusercontent.com/cdarlint/winutils/master/hadoop-3.3.6/bin/"
for (f in c("winutils.exe", "hadoop.dll", "hdfs.dll")) {
  download.file(paste0(base, f), file.path("C:/hadoop/bin", f), mode = "wb")
}

file.copy("C:/hadoop/bin/hadoop.dll", "C:/Windows/System32/hadoop.dll", overwrite = TRUE)
list.files("C:/hadoop/bin")

renv <- file.path(Sys.getenv("HOME"), ".Renviron")
file.exists(renv)
if (file.exists(renv)) readLines(renv)

writeLines(
  c("HADOOP_HOME=C:/hadoop",
    "PATH=${PATH};C:/hadoop/bin"),
  renv
)

readLines(renv) 

sum(duplicated(d$player_id))

# koliko su "čiste" pozicije — igrači ispod 0.5 su lutalice
summary(d$pos_purity); sum(d$pos_purity < 0.5)

# veličine za P1.1 i P2.1 (nisi ih pustio)
round(sum(file.info(list.files("data/raw/statsbomb/events", full.names = TRUE))$size)/1024^3, 2)
round(sum(file.info(list.files("data/interim/events_flat", full.names = TRUE, recursive = TRUE))$size)/1024^2, 1)


library(ggplot2)
head(imp_df, 12) %>%
  ggplot(aes(reorder(obelezje, znacaj), znacaj)) +
  geom_col(fill = "steelblue4") + coord_flip() +
  labs(title = "Značaj obeležja — stablo odlučivanja",
       x = NULL, y = "Značaj")
ggsave("figures/DT_importance.png", width = 7, height = 5, dpi = 150)
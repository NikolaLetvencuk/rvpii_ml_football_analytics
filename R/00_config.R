# ---- Konfiguracija: putanje, konstante, seed --------------------------------
# Sve "magicne vrednosti" projekta na jednom mestu. Bez logike.

PUT <- list(
  raw       = file.path("data", "raw"),
  interim   = file.path("data", "interim"),
  processed = file.path("data", "processed"),
  modeli    = file.path("outputs", "models"),
  slike     = file.path("outputs", "figures"),
  tabele    = file.path("outputs", "tables"),
  logovi    = file.path("outputs", "logs")
)

# Ulazni fajlovi
FAJLOVI <- list(
  bcn_listings    = file.path(PUT$raw, "bcn_listings.csv.gz"),
  bcn_calendar    = file.path(PUT$raw, "bcn_calendar.csv.gz"),
  # London oglasi: raspakovan .csv (195 MB). Komprimovana verzija je
  # london_listings1.csv.gz -- isti sadrzaj, koristi jedno ILI drugo.
  london_listings = file.path(PUT$raw, "london_listings.csv"),
  london_calendar = file.path(PUT$raw, "london_calendar.csv.gz"),
  # Mali uzorci za brzi razvoj (ne za rezultate u izvestaju!)
  uzorak_london   = file.path(PUT$raw, "london_listings_uzorak.csv"),  # 10 redova
  uzorak_bcn      = file.path(PUT$raw, "bcn_listings_uzorak.csv")
)

# Rana provera: bolje pasti odmah sa jasnom porukom nego u sredini pipeline-a.
local({
  nema <- Filter(function(p) !file.exists(p), FAJLOVI)
  if (length(nema)) {
    warning("Nedostaju ulazni fajlovi:\n  ",
            paste(names(nema), unlist(nema), sep = " -> ", collapse = "\n  "),
            call. = FALSE)
  }
})

# PRIMARNI SKUP = LONDON.
# Razlog: u bcn_listings kolona `price` je prazna u svih 18.177 redova, a cena
# je prediktor po specifikaciji ideje. Detalji: docs/nalazi_o_podacima.md
PRIMARNI <- "london_listings"

# Ciljno obelezje klasifikacije (prema specifikaciji ideje)
CILJ <- "room_type"

# Ciljno obelezje je ekstremno neizbalansirano (London):
#   Entire home/apt 64.9% | Private room 34.7% | Shared room 0.22% | Hotel room 0.11%
# => tacnost sama po sebi je bezvredna (65% se dobija trivijalnim modelom),
#    stratifikacija po CILJ je OBAVEZNA, prijavljuj i macro i weighted F-meru.
STRATIFIKUJ <- TRUE

SEED    <- 2025      # reproducibilnost
CV_K    <- 5         # broj preklopa za unakrsnu validaciju
                     # (Hotel room => ~22 primera po preklopu, otuda stratifikacija)

# Smeštaj — Analiza Airbnb smeštaja na osnovu oglasa

Praktični deo predmeta *Računarstvo visokih performansi u informacionom inženjerstvu*.
Nikola Letvenčuk, E2 46-2025.

## Pokretanje

```r
# jednom, prvi put
Rscript scripts/00_instaliraj_pakete.R

# ceo pipeline
Rscript main.R

# ili pojedinačan korak (iz korena projekta!)
Rscript scripts/03_klasifikacija.R
```

## Struktura — gde se šta piše

| Folder / fajl | Šta ide unutra | Analogija (Java backend) |
|---|---|---|
| `main.R` | Samo `source()` pozivi — redosled izvršavanja. Bez logike. | `Main.java` |
| `R/` | **Funkcije.** Definicije, bez izvršavanja. Sve što ima `function(...)`. | `service/` + `util/` |
| `scripts/` | **Pozivi** funkcija — numerisani koraci pipeline-a. Ovo se pokreće. | `controller/` (orkestracija) |
| `data/raw/` | Originalni fajlovi. **Nikad se ne menjaju.** | baza / izvor podataka |
| `data/interim/` | Međurezultati (delimično obrađeno, kеš). | — |
| `data/processed/` | Finalni analitički skup, spreman za modele. | materijalizovan view |
| `outputs/models/` | Serijalizovani modeli (`.rds`). | — |
| `outputs/figures/` | Snimljeni grafici (`.png`). | — |
| `outputs/tables/` | Snimljene tabele rezultata (`.csv`). | — |
| `outputs/logs/` | Logovi i izmerena vremena izvršavanja. | — |
| `reports/` | `izvestaj.Rmd` — tekst + interpretacija rezultata. | prezentacioni sloj |
| `tests/testthat/` | Testovi funkcija iz `R/`. | `src/test/java` |
| `docs/` | Postavka zadatka, specifikacija ideje. | — |
| `.Rprofile` | Podešavanja sesije, učitava se automatski. | `application.properties` |
| `smestaj.Rproj` | RStudio projekat — postavlja radni direktorijum. | `pom.xml` (samo kao ulaz u projekat) |

### Pravilo razdvajanja `R/` vs `scripts/`

- Pišeš `f <- function(...)` → ide u **`R/`**
- Pišeš `rezultat <- f(podaci)` → ide u **`scripts/`**

Zato što `main.R` i `izvestaj.Rmd` oba učitavaju **ceo** `R/` folder, pa je svaka
funkcija dostupna na oba mesta bez kopiranja koda.

## Mapiranje na bodove iz specifikacije

| Celina | Bodovi | Fajl |
|---|---|---|
| Priprema podataka | 3 | `scripts/01_priprema_podataka.R` |
| Preliminarna analiza | 3 | `scripts/02_preliminarna_analiza.R` |
| Klasifikacija | 15 | `scripts/03_klasifikacija.R` |
| Klasterizacija | 6 | `scripts/04_klasterizacija.R` |
| Izveštavanje | 3 | `reports/izvestaj.Rmd` |

## Podaci

Inside Airbnb (CC licenca). Lokalno u `data/raw/`:
`bcn_listings.csv(.gz)`, `bcn_calendar.csv.gz`, `london_listings.csv.gz`,
`london_calendar.csv.gz`, `bcn_listings_uzorak.csv` (mali uzorak za razvoj).

Ciljno obeležje klasifikacije: `room_type`.

> **Pročitaj `docs/nalazi_o_podacima.md` pre početka.** Dve stvari menjaju plan:
> Barcelona nema cene (kolona `price` prazna u svih 18.177 redova), pa je
> **London primarni skup**; i `room_type` je ekstremno neizbalansiran
> (dve klase ispod 0,25%), pa tačnost sama po sebi ne meri ništa.

# ---- Grafici (ggplot2) ------------------------------------------------------
# Svaka funkcija VRACA ggplot objekat. Snimanje ide preko sacuvaj_sliku().
# Tako isti grafik moze i u izvestaj i u outputs/figures/.

# g_histogram(dt, obelezje)              -- raspodela numerickog obelezja
# g_boxplot(dt, obelezje, po = CILJ)     -- raspodela po klasama
# g_stubici(dt, obelezje)                -- frekvencije kategorickog obelezja
# g_korelacije(mat)                      -- heatmap korelacija
# g_rasejanje(dt, x, y, boja = CILJ)     -- odnos dva obelezja
# g_mapa(dt, boja)                       -- latitude/longitude
# g_performanse(rezultati)               -- parametar vs metrika (po scenariju)
# g_konfuziona(cm)                       -- matrica konfuzije kao heatmap
# g_klasteri(dt, klaster)                -- klasteri u prostoru 2 obelezja / PCA

# sacuvaj_sliku(g, ime, w = 8, h = 5) -> ggsave u PUT$slike

# Aomidori v2 (flat Tategaki): layer per Icon Composer

Regole (WWDC25 "Create icons with Icon Composer"): canvas 1024x1024, nessuna maschera, livelli piatti e opachi
(niente ombre, sfumature, glass o specular: li aggiunge Composer), file numerati in ordine di profondità, sfondo impostato sul canvas.

| File | Contenuto | Fill (Default) |
|---|---|---|
| 01-pages.svg | libro aperto (due pagine) | #FFFFFF |
| 02-lines.svg | 3 colonne verticali per pagina (tategaki), allineate in alto | #49C7AE (opacità layer circa 85%) |
| 00-background-reference.svg | solo riferimento, NON importarlo | canvas: colore base #49C7AE; gradiente lineare molto leggero #5DCDB7 -> #3ABCA3 (circa ±5% di luminosità, dall'alto verso il basso), oppure tinta unita #49C7AE |

Annotazioni:
- `dark/`: pagine #49C7AE, colonne #12302A; canvas #24332F -> #18221F.
- `mono/`: pagine #FFFFFF, colonne #8C8C8C.

Look piatto in Composer: specular basso o spento sul gruppo delle pagine, ombra neutra leggera, translucenza bassa;
specular spento sul gruppo delle colonne. Clear e Tinted (chiaro/scuro) li genera il sistema.
In Composer c'è una sola artwork per tutte le dimensioni; la versione 16 px semplificata vale solo per i PNG di ripiego.

# Italy ISTAT Boundary Fields — Note per Anno

## Campi output e disponibilità per anno

### Comuni (municipalities)

| Campo output | Campo ISTAT | Disponibile |
|---|---|---|
| `area_km2` | calcolato | tutti gli anni |
| `name` | `COMUNE` | tutti gli anni |
| `name_alt` | `COMUNE_A` | tutti gli anni (può essere vuoto) |
| `com_istat_code_num` | `PRO_COM` | tutti gli anni |
| `com_istat_code` | `PRO_COM_T` | ~2017+ (stringa a 6 cifre con zero-padding) |
| `prov_istat_code_num` | `COD_PROV` | tutti gli anni |
| `reg_istat_code_num` | `COD_REG` | tutti gli anni |
| `rip_istat_code_num` | `COD_RIP` | tutti gli anni |
| `cm_istat_code_num` | `COD_CM` | 2015+ |
| `uts_istat_code_num` | `COD_UTS` | 2015+ |
| `cc_uts` | `CC_UTS` | 2015+ (0=Provincia, 1=Città Metropolitana) |

### Province / Città Metropolitane (provinces)

| Campo output | Campo ISTAT | Disponibile |
|---|---|---|
| `area_km2` | calcolato | tutti gli anni |
| `name` | `DEN_UTS` | 2015+ |
| `prov_name` | `DEN_PROV` | tutti gli anni (pre-2015: usato come `name`) |
| `cm_name` | `DEN_CM` | 2015+ |
| `prov_acr` | `SIGLA` | tutti gli anni |
| `type` | `TIPO_UTS` | 2015+ (Provincia / Città metropolitana / Libero consorzio) |
| `uts_istat_code_num` | `COD_UTS` | 2015+ |
| `prov_istat_code_num` | `COD_PROV` | tutti gli anni |
| `cm_istat_code_num` | `COD_CM` | 2015+ |
| `reg_istat_code_num` | `COD_REG` | tutti gli anni |
| `rip_istat_code_num` | `COD_RIP` | tutti gli anni |

### Regioni (regions)

| Campo output | Campo ISTAT | Disponibile |
|---|---|---|
| `area_km2` | calcolato | tutti gli anni |
| `name` | `DEN_REG` | tutti gli anni |
| `reg_istat_code_num` | `COD_REG` | tutti gli anni |
| `rip_istat_code_num` | `COD_RIP` | tutti gli anni |

### Ripartizioni geografiche (macro_regions)

| Campo output | Campo ISTAT | Disponibile |
|---|---|---|
| `area_km2` | calcolato | tutti gli anni |
| `name` | `DEN_RIP` | tutti gli anni |
| `rip_istat_code_num` | `COD_RIP` | tutti gli anni |

---

## Cambiamenti strutturali significativi per anno

| Anno | Cambiamento |
|---|---|
| 2015 | Legge Delrio (56/2014): introdotte 10 Città Metropolitane. Aggiunto schema CM/UTS. Shapefile province: `Prov*` → `ProvCM*` |
| 2016 | Aggiunto campo `CC_UTS` (0/1 per distinguere Province da CM) |
| ~2017 | Aggiunto campo `PRO_COM_T` (codice comune come stringa a 6 cifre es. "001001") |
| 2026 | Sardegna riorganizzata: da 4 province a 4 liberi consorzi + CM Sassari = 7 UTS. Totale province/CM: 110 (erano 107) |

---

## Conteggi per anno

| Anno | Comuni | Province/CM | Regioni | Ripartizioni |
|---|---|---|---|---|
| 2011 | ~8.094 | 110 | 20 | 5 |
| 2012–2015 | variabile | 110 | 20 | 5 |
| 2016–2025 | 7.903→7.899 | 107 | 20 | 5 |
| 2026 | 7.896 | 110 | 20 | 5 |

> I conteggi esatti sono verificati al momento della generazione e riportati nell'output dello script.

---

## Struttura directory

```
italy/boundaries/
  italy_istat_*.geojson|topojson   ← flat = anno più recente (backward compat)
  latest/                          ← symlink → anno più recente
  {anno}/
    italy_istat_municipalities_4326.geojson      (~31MB, full)
    italy_istat_municipalities_4326.topojson
    italy_istat_municipalities_4326_100m.geojson (~15MB)
    italy_istat_municipalities_4326_100m.topojson
    italy_istat_municipalities_4326_500m.geojson
    italy_istat_municipalities_4326_500m.topojson
    italy_istat_municipalities_4326_1km.geojson
    italy_istat_municipalities_4326_1km.topojson
    italy_istat_provinces_4326.*   (× 4 risoluzioni)
    italy_istat_regions_4326.*     (× 4 risoluzioni)
    italy_istat_macro_regions_4326.* (× 4 risoluzioni)
```

**Nota LITE mode**: per anni storici (non latest), i file
`municipalities_4326.geojson` e `municipalities_4326_100m.geojson`
non vengono inclusi nel repo per contenere le dimensioni.
Sono disponibili i TopoJSON equivalenti.

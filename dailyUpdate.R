# Actualización diaria de precios.
#
# Descarga precios de CENACE, CAISO y ERCOT, los agrega a PostgreSQL, crea dos
# reportes en Excel y exporta dos series en CSV.

library(tidyr)
library(dplyr)
library(forecast)
library(stringr)
library(lubridate)
library(jsonlite)
library(siebanxicor)
library(rvest)
library(openxlsx)
library(cgwtools)
library(DBI)
library(RPostgres)

# Carga las funciones necesarias.

source("functions.R")

# Conexión a base de datos

con <- dbConnect(
  RPostgres::Postgres(),
  dbname = "Sumexdb",
  host = "localhost",
  port = 5432,
  user = "postgres", # Cambiar si es necesario
  password = "postgresql" # Cambiar si es necesario
)

# CENACE: MDA del día actual y MTR con siete días de desfase.

pml_mda <- rbind(getCENACE("BCA", "MDA", "07IVY-230,07OMS-230", today()), 
                 getCENACE("SIN", "MDA", "09LBR-230,06EAP-138,06CUF-230,06RRD-138", today())) %>% 
            arrange(fecha, hora, nodo)
nodos_mda <- rbind(getCENACE("SIN", "MDA", "QUERETARO", today()),
                   getCENACE("BCA", "MDA", "MEXICALI", today())) %>% 
  arrange(fecha, hora, nodo)
  
dbAppendTable(con, "pml_mda", pml_mda)
dbAppendTable(con, "nodos_distribuidos_mda", nodos_mda)


pml_mtr <- rbind(getCENACE("BCA", "MTR", "07IVY-230,07OMS-230", today()-7), 
                 getCENACE("SIN", "MTR", "09LBR-230,06EAP-138,06CUF-230,06RRD-138", today()-7)) %>% 
  arrange(fecha, hora, nodo)
nodos_mtr <- rbind(getCENACE("SIN", "MTR", "QUERETARO", today()-7),
                   getCENACE("BCA", "MTR", "MEXICALI", today()-7)) %>% 
  arrange(fecha, hora, nodo)

dbAppendTable(con, "pml_mtr", pml_mtr)
dbAppendTable(con, "nodos_distribuidos_mtr", nodos_mtr)

# CAISO: DAM del día actual y RTM del día anterior.

caiso_dam <- getCAISO("DAM", "ROA-230_2_N101,TJI-230_2_N101", today(), today())
caiso_rtm <- getCAISO("RTM", "ROA-230_2_N101,TJI-230_2_N101", today()-1, today()-1)

dbAppendTable(con, "caiso_dam", caiso_dam)
dbAppendTable(con, "caiso_rtm", caiso_rtm)

# ERCOT: DAM del día actual y RTM del día anterior.

ercot_dam <- getERCOT("DAM", c("DC_R", "DC_L", "GWEC_G1"), today(),today())
ercot_rtm <- getERCOT("RTM", c("DC_R", "DC_L", "GWEC_G1"), today()-1,today()-1)

dbAppendTable(con, "ercot_dam", ercot_dam)
dbAppendTable(con, "ercot_rtm", ercot_rtm)

# Reportes: DAM del día actual y RTM del día anterior para CAISO Y ERCOT.

fileName <- paste0("CAISO-ERCOT DAM ", format.Date(today(), format = "%d-%m-%Y"), ".xlsx")
report(caiso_dam,ercot_dam, fileName)

fileName <- paste0("CAISO-ERCOT RTM ", format.Date(today()-1, format = "%d-%m-%Y"), ".xlsx")
report(caiso_rtm,ercot_rtm, fileName)

# Series ercot: se generan DC_L.csv y DC_R.csv desde la base de datos.

gitReport(con)

# Cierre: desconexión de la base de datos.
dbDisconnect(con)
remove(caiso_dam, caiso_rtm, ercot_dam, ercot_rtm, fileName, con)

# Respaldo de la base de datos
system("cmd.exe", input="pg_dump -U postgres -d Sumexdb -F c -f Sumexdb.dump")
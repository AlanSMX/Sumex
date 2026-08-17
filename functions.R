# Funciones de consulta y generación de reportes para CENACE, CAISO y ERCOT.

require(dplyr)
require(lubridate)
require(tidyr)
require(stringr)
require(jsonlite)
require(httr)
require(openxlsx)

options(warn = -1)

# CENACE -----------------------------------------------------------------
# Consulta precios marginales locales publicados por CENACE.
#
# @param sistema Sistema eléctrico ("SIN" o "BCA").
# @param mercado Mercado ("MDA" o "MTR").
# @param nodo Uno o varios nodos dentro de un vector 
#   o en una sola cadena separados por comas y sin espacios.
# @param inicio,fin Fechas `Date` o texto en formato `AAAA/MM/DD`.
#   Período máximo de 7 días.
# @return `data.frame` ordenado con fecha, hora, nodo, PML y componentes;
#   vacío si no hay resultados.
getCENACE <- function(sistema, mercado, nodos, inicio = today()+1, fin = inicio)
{
  inicio <- ifelse(is.Date(inicio), format.Date(inicio, format = "%Y/%m/%d"), inicio)
  fin <- ifelse(is.Date(fin), format.Date(fin, format = "%Y/%m/%d"), fin)
  nodos <- paste(nodos, collapse = ",")
  servicio <- ifelse(str_detect(nodos, "\\d"), "SWPML", "SWPEND")
  
  json <- fromJSON(paste0("https://ws01.cenace.gob.mx:8082/",servicio,"/SIM/",sistema,"/",mercado,"/",nodos,"/",
                          inicio,"/", fin,"/","JSON"),
                   simplifyVector = FALSE)
  
  if (length(json) == 0)
  {
    return(data.frame())
  }
  
  else{
    data <- data.frame()
    
    for (x in json$Resultados) {
      nombre_nodo <- x[[1]]
      colNames <- c("fecha", "hora", "lmp", "comp_E", "comp_P", "comp_C")
      x <- setNames(do.call(rbind.data.frame, lapply(x[[2]], as.data.frame)), colNames)
      x <- data.frame(x[1:2], nodo = nombre_nodo, x[3:6])
      data <- rbind(data, x)
    }
    
    data$fecha <- as.Date(data$fecha)
    data$hora <- factor(as.factor(data$hora), levels = 1:25)
    data[4:7] <- as.data.frame(lapply(data[4:7], as.numeric))
    
    data <- arrange(data, fecha, hora, nodo)
    return(data)
  }
}

# CAISO ------------------------------------------------------------------
# Descarga precios LMP de CAISO OASIS.
#
# @param market "DAM" o "RTM".
# @param nodes Uno o varios nodos dentro de un vector 
#   o en una sola cadena separados por comas y sin espacios.
#   Admite hasta 4 nodos por consulta.
# @param startDate,endDate Fechas `Date` o texto en formato `AAAA/MM/DD`.
#   Período máximo de 28 días.
# @return `data.frame` ordenado con fecha, hora, nodo y precio.
getCAISO <- function(market, nodes, startDate = today(), endDate = startDate)
{
  startDate <- as.Date(startDate)
  endDate <- as.Date(endDate)
  startDateStr <- format.Date(startDate, format = "%Y%m%d")
  endDateStr <- format.Date(endDate+1, format = "%Y%m%d")
  nodes <- paste(nodes, collapse = ",")
  market <- ifelse(market == "RTM", "RTPD", market)
  
  getURL <- paste0("http://oasis.caiso.com/oasisapi/SingleZip?resultformat=6&",
                   "queryname=", ifelse(market == "DAM",
                                        "PRC_LMP&version=12",
                                        "PRC_SPTIE_LMP&version=5"),
                   "&startdatetime=", startDateStr, "T06:00-0000",
                   "&enddatetime=", endDateStr, "T08:00-0000",
                   "&market_run_id=", market,
                   "&node=", nodes)
  temp <- tempfile(tmpdir = ".", fileext = ".zip")
  try(download.file(getURL,temp, mode = "wb", quiet = TRUE), silent = TRUE)
  
  if(market == "DAM")
    {
    data <- read.csv(unzip(temp)) %>%
      filter(LMP_TYPE == "LMP", 
             between(as.Date(OPR_DT), startDate, endDate)) %>%
      select(OPR_DT, OPR_HR, NODE_ID, MW) %>%
      arrange(OPR_DT, OPR_HR, NODE_ID)
    
    unlink(temp)
    unlink(dir()[str_which(dir(), "PRC_LMP_DAM")])
  } else if(market == "RTPD")
    {
    data <- read.csv(unzip(temp)) %>%
      filter(LMP_TYPE == "LMP", 
             between(as.Date(OPR_DT), startDate, endDate)) %>%
      group_by(OPR_DT, OPR_HR, NODE_ID) %>%
      summarise(MW = mean(PRC)) %>%
      as.data.frame() %>%
      arrange(OPR_DT, OPR_HR, NODE_ID)
    
    unlink(temp)
    unlink(dir()[str_which(dir(), "PRC_SPTIE_LMP_RTPD")])
  }
  
  data <- setNames(data, str_to_lower(colnames(data)))
  return(data)
}


# ERCOT ------------------------------------------------------------------
# Consulta precios mediante la API pública de ERCOT.
#
# @param market "DAM" o "RTM".
# @param nodes Vector de nodos.
# @param startDate,endDate Fechas `Date` o texto en formato `AAAA-MM-DD`.
#   Período máximo de 28 días.
# @return `data.frame` ordenado con fecha, hora, nodo y precio.
getERCOT <- function(market, nodes, startDate, endDate)
{
  df <- data.frame()
  startDate <- as.Date(startDate)
  endDate <- as.Date(endDate)
  startDateStr = format.Date(startDate, format = "%Y-%m-%d")
  endDateStr = format.Date(endDate, format = "%Y-%m-%d")
  
  USERNAME <- "amartinez@energiasumex.com"
  PASSWORD <- "SumexERCOT2026"
  SUBSCRIPTION_KEY <- "739aa4ddfc5546dca4321e4b04eba233"
  
  AUTH_URL <- paste0("https://ercotb2c.b2clogin.com/ercotb2c.onmicrosoft.com/",
                     "B2C_1_PUBAPI-ROPC-FLOW/oauth2/v2.0/token?",
                     "username=", USERNAME,
                     "&password=",PASSWORD,
                     "&grant_type=password",
                     "&scope=openid+fec253ea-0d06-4272-a5e6-b478baeecd70+offline_access",
                     "&client_id=fec253ea-0d06-4272-a5e6-b478baeecd70",
                     "&response_type=id_token")
  
  auth_response <- POST(AUTH_URL)
  auth_content <- fromJSON(content(auth_response, "text", encoding = "UTF-8"))
  access_token <- auth_content$access_token
  
  for (node in nodes) {
    if(market=="RTM") {
      ARCHIVE_URL <- paste0(
        "https://api.ercot.com/api/public-reports/np6-788-cd/lmp_node_zone_hub",
        "?SCEDTimestampFrom=", startDate, "T00:00:00",
        "&SCEDTimestampTo=", endDate, "T23:59:59",
        "&settlementPoint=", node)
      
      headers <- add_headers(Authorization = paste("Bearer", access_token),
                             `Ocp-Apim-Subscription-Key` = SUBSCRIPTION_KEY)
      product_response <- GET(ARCHIVE_URL, headers)
      response_text <- content(product_response, "text", encoding = "UTF-8")
      response_json <- fromJSON(response_text)
      data <- as.data.frame(response_json$data)
      
      data <- data %>% 
        setNames(c("SCEDTimestamp", "HourEnding", "SettlementPoint", "SettlementPointPrice")) %>% 
        mutate(SCEDTimestamp = as_datetime(SCEDTimestamp),
               DeliveryDate = as.Date(SCEDTimestamp), 
               HourEnding = hour(SCEDTimestamp) + 1,
               SettlementPointPrice = as.numeric(SettlementPointPrice)) %>% 
        group_by(DeliveryDate, HourEnding, SettlementPoint) %>% 
        summarise(SettlementPointPrice = mean(SettlementPointPrice)) %>% 
        as.data.frame() %>% 
        select(DeliveryDate, HourEnding, SettlementPoint, SettlementPointPrice)
    } else if(market == "DAM") {
      ARCHIVE_URL <- paste0(
        "https://api.ercot.com/api/public-reports/np4-190-cd/dam_stlmnt_pnt_prices",
        "?deliveryDateFrom=", startDate,
        "&deliveryDateTo=", endDate,
        "&settlementPoint=", node)
      
      headers <- add_headers(Authorization = paste("Bearer", access_token),
                             `Ocp-Apim-Subscription-Key` = SUBSCRIPTION_KEY)
      product_response <- GET(ARCHIVE_URL, headers)
      response_text <- content(product_response, "text", encoding = "UTF-8")
      response_json <- fromJSON(response_text)
      data <- as.data.frame(response_json$data)
      
      data <- data %>% 
        setNames(c("DeliveryDate", "HourEnding", "SettlementPoint", "SettlementPointPrice", "DSTFlag")) %>% 
        mutate(DeliveryDate = as.Date(DeliveryDate),
               HourEnding = as.numeric(substring(HourEnding,1,2)),
               SettlementPointPrice = as.numeric(SettlementPointPrice)) %>%
        select(-DSTFlag)
    }
    df <- rbind(df, data)
  }
  df <- arrange(df, DeliveryDate, HourEnding, SettlementPoint)
  df <- setNames(df, str_to_lower(colnames(df)))
  return(df)
}


# Reportes ---------------------------------------------------------------
# Genera un libro Excel con precios CAISO y ERCOT.
#
# @param caiso Datos con OPR_DT, OPR_HR, NODE_ID y MW.
# @param ercot Datos con DeliveryDate, HourEnding, SettlementPoint y SettlementPointPrice.
# @param fileName Ruta del archivo .xlsx de salida.
# @return No devuelve valor; escribe o reemplaza el archivo indicado.
report <- function(caiso, ercot, fileName)
{
  caiso <- spread(caiso, node_id, mw)[-1]
  ercot <- spread(ercot, settlementpoint, settlementpointprice)[-1]
  wb <- buildWorkbook(caiso, startRow = 1, gridLines = F, borders = "columns")
  writeData(wb, 1, ercot, 5, 1, colNames = T, borders = "columns")
  setColWidths(wb, 1, cols = 1:8, widths = c(10, 15, 15, 10,
                                             10, 15, 15,15))
  setRowHeights(wb, 1, 1, 30)
  
  headers <- c("Hora", "ROA-230_2_N101", "TJI-230_2_N101", "",
               "Hora", "DC_L", "DC_R", "GWEC_G1") %>%
    as.data.frame() %>%
    t()
  
  writeData(wb, 1, headers, 1, 1, colNames = F)
  
  addStyle(wb, sheet = 1, createStyle(halign = "center", valign = "center"), 
           rows = 1:25, cols = 1:8, gridExpand = TRUE, stack = TRUE)
  addStyle(wb, sheet = 1, createStyle(border = c("bottom")), 
           rows = 25, cols = c(1:3, 5:8), gridExpand = TRUE, stack = TRUE)
  addStyle(wb, sheet = 1, rows = 1, cols = c(1:3,5:8), gridExpand = TRUE, stack = TRUE, 
           style = createStyle(fontColour = "white", textDecoration = "bold", wrapText = TRUE,
                               border = c("TopBottomLeftRight"), fgFill = "#4472C4"))
  addStyle(wb, sheet = 1, createStyle(numFmt = "CURRENCY"), 
           rows = 2:25, cols = c(2:3, 6:8), gridExpand = TRUE, stack = TRUE)
  
  saveWorkbook(wb, fileName, TRUE)
}

# Exporta las series DAM y RTM de DC_L y DC_R a archivos CSV.
#
# @param con Conexión PostgreSQL compatible con DBI.
# @return No devuelve valor; crea DC_L.csv y DC_R.csv en el directorio actual.
gitReport <- function(con)
{
  ercot_db <- dbGetQuery(con, 
                         'SELECT deliverydate, hourending, settlementpoint, 
                         ercot_dam.settlementpointprice AS \"DAM\", ercot_rtm.settlementpointprice as \"RTM\" 
                         FROM ercot_dam 
                         INNER JOIN ercot_rtm 
                         USING (deliverydate, hourending, settlementpoint) 
                         WHERE settlementpoint != \'GWEC_G1\'')
  
  ercot_db %>% 
    filter(SettlementPoint == 'DC_L') %>% 
    select(-SettlementPoint) %>% 
    setNames(c("Fecha", "Hora", "DAM", "RTM")) %>% 
    mutate(DAM = round(DAM,2),
           RTM = round(RTM,2)) %>% 
    write.csv('DC_L.csv', row.names = F)
  
  ercot_db %>% 
    filter(SettlementPoint == 'DC_R') %>% 
    select(-SettlementPoint) %>% 
    setNames(c("Fecha", "Hora", "DAM", "RTM")) %>% 
    mutate(DAM = round(DAM,2),
           RTM = round(RTM,2)) %>% 
    write.csv('DC_R.csv', row.names = F)
}
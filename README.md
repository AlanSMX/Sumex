# Actualización diaria de precios y reportes

## Archivos principales

- `functions.R`: consultas a las APIs y generación de reportes.
- `dailyUpdate.R`: descarga, inserción en base de datos y creación de archivos.

## Requisitos

* Instalación de R y con los paquetes empleados por los scripts.
* Instalación de PostgreSQL para el guardado de los precios configurada adecuadamente.

## Guía de uso

Para la generación de los reportes diarios del DAM y RTM basta con ejecutar "dailyUpdate.R".

El proceso consulta CENACE (MDA día actual y MTR con siete días de desfase), CAISO
(DAM día actual y RTM día previo) y ERCOT (DAM día actual y RTM día previo), y añade esos datos
a las tablas configuradas.

## Archivos generados

- `CAISO-ERCOT DAM DD-MM-AAAA.xlsx`
- `CAISO-ERCOT RTM DD-MM-AAAA.xlsx`
- `DC_L.csv`
- `DC_R.csv`

## Uso de funciones individuales

### getCENACE

Hace un llamado al [Servicio Web para descarga de Precios Marginales Locales (SW-PML)](https://www.cenace.gob.mx/DocsMEM/2022-06-24%20Manual%20T%C3%A9cnico%20SW-PML.pdf).

| Parámetro 	| Tipo                   	| Valores admitidos                                                                                 	|
|-----------	|------------------------	|---------------------------------------------------------------------------------------------------	|
| sistema   	| caracter               	| SIN, BCA, BCS                                                                                     	|
| mercado   	| caracter               	| MDA, MTR                                                                                          	|
| nodos     	| caracter o vector      	| Uno o varios nodos dentro de un vector o en una sola cadena separados por   comas y sin espacios. 	|
| inicio    	| caracter u objeto Date 	| Objeto Date o texto en formato `AAAA/MM/DD`                                                       	|
| fin       	| caracter u objeto Date 	| Objeto Date o texto en formato `AAAA/MM/DD`. Si no se especifica, se toma   igual a inicio.       	|                                                   	|

Ejemplos válidos:
* getCENACE("BCA", "MDA", "07IVY-230,07OMS-230", Sys.Date())
* getCENACE("BCA", "MTR", c("07IVY-230","07OMS-230"), "2026-05-12", "2026-05-15)

### getCAISO

Hace un llamado a la API de Oasis CAISO.
* DAM: Scheduling Point/Tie Combination Locational Marginal Prices (LMP)
* RTM: FMM Scheduling Point/Tie Combination Locational Marginal Prices (LMP)

| Parámetro 	| Tipo                   	| Valores admitidos                                                                                 	|
|-----------	|------------------------	|---------------------------------------------------------------------------------------------------	|
| market    	| caracter               	| DAM, RTM, RTPD (RTM y RTPD son lo mismo)                                                          	|
| nodes     	| caracter               	| Uno o varios nodos dentro de un vector o en una sola cadena separados por   comas y sin espacios. 	|
| startDate 	| caracter o vector      	| Objeto Date o texto en formato `AAAA/MM/DD`                                                       	|
| endDate   	| caracter u objeto Date 	| Objeto Date o texto en formato `AAAA/MM/DD`. Si no se especifica, se toma   igual a startDate     	|

Ejemplos válidos:
* getCAISO("DAM", "ROA-230_2_N101,TJI-230_2_N101", today(), today())
* getCAISO("RTM", c("ROA-230_2_N101","TJI-230_2_N101"), "2026-05-12", "2026-05-15)

### getERCOT

Hace un llamado a la [API de ERCOT](https://apiexplorer.ercot.com/).
* DAM: DAM Settlement Point Prices (EMIL ID: NP4-190-CD)
* RTM: LMPs by Resource Nodes, Load Zones and Trading Hubs (EMIL ID: NP6-788-CD)

* Usuario: 
* Contraseña: 

La API Key tiene una vigencia de 30 días. Si deja de funcionar debido a esto hay que dirigirse a https://apiexplorer.ercot.com. Una vez logeado, hay que dirigirse a Profile, dar click para regenerar la Primary Key y copiar y pegarla en el campo `SUBSCRIPTION_KEY` en el cuerpo de la función en el archivo functions.R. Para que surtan efecto os cambios, vuelvase a ejecutar el archivo functions.R.

| Parámetro 	| Tipo                   	| Valores admitidos                                                                             	|
|-----------	|------------------------	|-----------------------------------------------------------------------------------------------	|
| market    	| caracter               	| DAM, RTM                                                                                      	|
| nodes     	| caracter               	| Uno o varios nodos dentro de un vector. No admite nodos separados por   comas y sin espacios. 	|
| startDate 	| caracter o vector      	| Objeto Date o texto en formato `AAAA/MM/DD`                                                   	|
| endDate   	| caracter u objeto Date 	| Objeto Date o texto en formato `AAAA/MM/DD`. Si no se especifica, se toma   igual a startDate 	|

Ejemplos válidos:
* getERCOT("DAM", c("DC_R", "DC_L", "GWEC_G1"), today(), today())
* getCAISO("RTM", c("DC_R", "DC_L", "GWEC_G1"), "2026-05-12", "2026-05-15)

### report

Genera un libro Excel con los precios de CAISO y ERCOT.

La función está escrita para los nodos ROA-230_2_N101 y TJI-230_2_N101 de CAISO y DC_R, DC_L y GWEC_G1 de ERCOT. Para otros nodos hay que modificar la función.

El nombre del archivo (`fileName`) debe tener la extensión .xlsx para evitar problemas de compatibilidad. Sin embargo, Roberto no puede abrir este formato en su teléfono, por lo que hay que abrir el archivo generado y manualmente guardarlo con la extensión .xls antes de enviarlo.

| Parámetro 	| Tipo       	| Valores admitidos                        	|
|-----------	|------------	|------------------------------------------	|
| caiso     	| data.frame 	| Dataframe con los precios de CAISO       	|
| ercot     	| data.frame 	| Dataframe con los precios de ERCOT       	|
| fileName  	| caracter   	| Nombre con el que se guardara el archivo 	|

### gitReport

Toma como único parámetro la conexión a la base de datos para extraer los precios históricos de DC_L y DC_R y guardarlos en formato .csv. La subida al repositorio en GitHub se hace de manera manual.

### Respaldo en la base de datos

Después de cada consulta se ejecuta `dbAppendTable` para guardar los precios del día en la base de datos. Si no se configuró la base en PostgreSQL, se pueden eliminar estas líneas.

Para respaldar la base de datos diario de manera automática se ejecuta el comando `system("cmd.exe", input="pg_dump -U postgres -d Sumexdb -F c -f Sumexdb.dump")` desde R. Para ello es necesario crear una carpeta llamada `postgresql` en `Usuarios\Usuario\AppData\` y dentro de la carpeta `postgresql` un archivo llamado `pgpass.conf` que contenga la línea con el formato `hostname:port:database:username:password` (`localhost:5432:Sumexdb:postgres:postgresql` si se configuró la base de datos con el mismo usuario y contraseña).
Si no se quiere hacer todo este proceso, se puede sólo ejecutar el comando `pg_dump -U postgres -d Sumexdb -F c -f Sumexdb.dump` en la terminal e ingresar la contraseña manualmente.
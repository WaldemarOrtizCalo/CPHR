#   Script Details                                                          ####

# Author: Waldemar Ortiz-Calo

# Date:2023-01-08 

# Purpose: 

###############################################################################
#   Library / Functions / Data                                              ####

#      Library                                                              ####
library(terra)
library(tidyverse)
library(sf)
library(stringr)
library(foreach)
library(doParallel)
library(lubridate)

#      Functions                                                            ####

date2character <- function(x){
  year_string <- str_sub(x,start = 1,end = 4)
  day_string <- str_sub(x,start = 5,end = 8) %>% as.numeric()
  origin_string <- ymd(as.numeric(paste0(year_string,"0101")))
  
  date_final <- as.Date(day_string,origin = origin_string) %>% 
    as.character()
  return(date_final)
}

getSeason <- function(DATES) {
  WS <- as.Date("2012-12-21", format = "%Y-%m-%d") # Winter Solstice
  SE <- as.Date("2012-3-20",  format = "%Y-%m-%d") # Spring Equinox
  SS <- as.Date("2012-6-21",  format = "%Y-%m-%d") # Summer Solstice
  FE <- as.Date("2012-9-23",  format = "%Y-%m-%d") # Fall Equinox
  
  # Convert dates from any year to 2012 dates
  d <- as.Date(strftime(DATES, format="2012-%m-%d"))
  
  ifelse (d >= WS | d < SE, "winter",
          ifelse (d >= SE & d < SS, "spring",
                  ifelse (d >= SS & d < FE, "summer", "fall")))
}

season_year_locator <- function(input_date,ref_sheet) { 
  input_date %within% ref_sheet$int
  
  ref_sheet$season_year[which(input_date %within% ref_sheet$int)]
}


#      Data                                                                 ####

# Montana shapefile
shp_montana <- st_read("1.Data\\data_clean\\MontanaBoundaries\\MontanaCountyBoundaries.shp") %>% 
  vect()


# NDVI list and names
ndvi_list <- list.files("1.Data/data_raw/NDVI",
                        pattern = ".tif",
                        full.names = T) %>% 
  str_subset(pattern = "_NDVI_")

ndvi_names <- list.files("1.Data/data_raw/NDVI",
                         pattern = ".tif",
                         full.names = F) %>% 
  str_extract("doy\\d\\d\\d\\d\\d\\d\\d") %>% 
  str_remove("doy") %>% unique()

###############################################################################
#   NDVI Raster Cropping and Masking                                        ####

# Export Directory
export_dir <- "1.Data/data_clean/NDVI"

# Cropping and Export
for (i in 1:length(ndvi_names)) {
  
  # Making a List of Rasters 
  raster <- str_subset(ndvi_list,
                       pattern = ndvi_names[[i]]) %>% 
    rast()
  
  # Creating final NDVI layer
  ndvi_final <- raster %>% 
    project("EPSG:4326") %>% 
    mask(shp_montana) %>% 
    crop(shp_montana)
  
  # Exporting Raster
  writeRaster(ndvi_final,
              filename = paste0(export_dir,"/ndvi_",date2character(ndvi_names[[i]]),
                                ".tif"),
              overwrite = T)
  
  # Iteration Tracker
  print(paste0(i, " out of ", length(ndvi_names), " completed"))
  
}

###############################################################################
#   Mean Summary Rasters - Yearly and Seasonal                              ####
#      Yearly Summaries                                                     ####
#        Creating NDVI Master Database                                      ####

# List of NDVI tiles
ndvi_list <- list.files("1.Data/data_clean/NDVI",
                        full.names = T)

# Extracting Dates 
ndvi_dates <- list.files("1.Data/data_clean/NDVI",
                         full.names = F) %>% 
  str_remove("ndvi_") %>% 
  str_remove(".tif") %>% 
  ymd()

# Creating Database
ndvi_database <- data.frame(filepath = ndvi_list,
                            dates = ndvi_dates) %>% 
  mutate(year = year(dates)) %>% 
  filter(year != 2006)

#        Processing NDVI layers                                             ####

# Indicating Export Directory
export_dir <- "1.Data/data_clean/NDVI_summaries/summaries_yearly"

# Making list of unique years
years_unique <- unique(ndvi_database$year)

for (i in 1:length(years_unique)) {
  
  # Extracting a certain year
  target_year <- years_unique[i]
  
  # Subsetting Database for target ndvi files
  target_layers <- ndvi_database %>% 
    filter(year == target_year) %>% 
    .$filepath
  
  # Stacking NDVI tiles and summarizing across
  ndvi_summary <- rast(target_layers) %>% 
    app(fun=mean,na.rm = T)
  
  # Exporting NDVI summary raster
  writeRaster(ndvi_summary,
              filename = paste0(export_dir,
                                "/ndvi_avg_yr_",
                                target_year,"_250m.tif"),
              overwrite = T)
  
  # Iteration Tracker
  print(paste0(i, " out of ", length(years_unique), " completed"))
}


#      Seasonal Summaries                                                   ####
#        Creating Seasonal Reference                                        ####
#           Period Settings                                                 ####

period_buffer <- 3

study_period_start <- min(unique(ndvi_database$year))- period_buffer
study_period_end <- max(unique(ndvi_database$year))+ period_buffer

#           Season 1: Winter                                                ####

s_start <- expand.grid(season = "winter",
                       year = seq(study_period_start,study_period_end),
                       month = "12",
                       day = "21") %>% 
  mutate(date_str = paste(year,month,day,sep = "-"),.keep = "unused") %>% 
  mutate(start_date = ymd(date_str),.keep = "unused")



s_end <- expand.grid(year = seq(study_period_start,study_period_end)+1,
                     month = "03",
                     day = "19") %>% 
  mutate(date_str = paste(year,month,day,sep = "-"),.keep = "unused") %>% 
  mutate(end_date = ymd(date_str),.keep = "unused") %>% pull()


winter_matrix <- s_start %>% mutate(end_date = s_end)

#           Season 2: Spring                                                ####
s_start <- expand.grid(season = "spring",
                       year = seq(study_period_start,study_period_end),
                       month = "03",
                       day = "20") %>% 
  mutate(date_str = paste(year,month,day,sep = "-"),.keep = "unused") %>% 
  mutate(start_date = ymd(date_str),.keep = "unused")



s_end <- expand.grid(year = seq(study_period_start,study_period_end),
                     month = "06",
                     day = "20") %>% 
  mutate(date_str = paste(year,month,day,sep = "-"),.keep = "unused") %>% 
  mutate(end_date = ymd(date_str),.keep = "unused") %>% pull()


spring_matrix <- s_start %>% mutate(end_date = s_end)



#           Season 2: summer                                                ####
s_start <- expand.grid(season = "summer",
                       year = seq(study_period_start,study_period_end),
                       month = "06",
                       day = "21") %>% 
  mutate(date_str = paste(year,month,day,sep = "-"),.keep = "unused") %>% 
  mutate(start_date = ymd(date_str),.keep = "unused")



s_end <- expand.grid(year = seq(study_period_start,study_period_end),
                     month = "09",
                     day = "22") %>% 
  mutate(date_str = paste(year,month,day,sep = "-"),.keep = "unused") %>% 
  mutate(end_date = ymd(date_str),.keep = "unused") %>% pull()


summer_matrix <- s_start %>% mutate(end_date = s_end)



#           Season 4: fall                                                  ####
s_start <- expand.grid(season = "fall",
                       year = seq(study_period_start,study_period_end),
                       month = "09",
                       day = "23") %>% 
  mutate(date_str = paste(year,month,day,sep = "-"),.keep = "unused") %>% 
  mutate(start_date = ymd(date_str),.keep = "unused")



s_end <- expand.grid(year = seq(study_period_start,study_period_end),
                     month = "12",
                     day = "20") %>% 
  mutate(date_str = paste(year,month,day,sep = "-"),.keep = "unused") %>% 
  mutate(end_date = ymd(date_str),.keep = "unused") %>% pull()


fall_matrix <- s_start %>% mutate(end_date = s_end)



#           Season final                                                    ####

seasonal_reference <- bind_rows(fall_matrix,
                                winter_matrix,
                                spring_matrix,
                                summer_matrix) %>% 
  mutate(int = interval(start_date,end_date)) %>% 
  mutate(season_year = paste(season,year(start_date),sep = "_"),.after = season)


#        Creating NDVI Master Database                                      ####

# List of NDVI tiles
ndvi_list <- list.files("1.Data/data_clean/NDVI",
                        full.names = T)

# Extracting Dates 
ndvi_dates <- list.files("1.Data/data_clean/NDVI",
                         full.names = F) %>% 
  str_remove("ndvi_") %>% 
  str_remove(".tif") %>% 
  ymd()

# Creating Database
ndvi_database <- data.frame(filepath = ndvi_list,
                            date = ndvi_dates) %>% 
  mutate(year = year(date)) %>% 
  filter(year != 2006) %>% 
  mutate(season = NA) 

# Assigning Season_year value
for (i in 1:nrow(ndvi_database)) {
  d <- ndvi_database[i,2]
  ndvi_database[i,4] <- season_year_locator(d, ref_sheet = seasonal_reference)
  print(i)
}

#        Creating Raster Summaries                                          ####

# Indicating Export Directory
export_dir <- "1.Data/data_clean/NDVI_summaries/summaries_seasonal" 

# Create a list of unique seasons
seasons_unique <- ndvi_database$season %>% unique()

for (i in 1:length(seasons_unique)) {
  
  # Extracting a certain year
  target_season <- seasons_unique[i]
  
  # Subsetting Database for target ndvi files
  target_layers <- ndvi_database %>% 
    filter(season == target_season) %>% 
    .$filepath
  
  # Stacking NDVI tiles and summarizing across
  ndvi_summary <- rast(target_layers) %>% 
    app(fun=mean,na.rm = T)
  
  # Exporting NDVI summary raster
  writeRaster(ndvi_summary,
              filename = paste0(export_dir,
                                "/ndvi_avg_",
                                target_season,"_250m.tif"),
              overwrite = T)
  
  # Iteration Tracker
  print(paste0(i, " out of ", length(seasons_unique), " completed"))
}

#   Mean Summary Rasters - Overall Yearly and Seasonal (2008-2019)          ####
#      Overall: Yearly                                                      ####
# Export Directory 
export_dir <- "1.Data/data_clean/NDVI_summaries/summaries_yearly_overall"

# Making list of tiles
ndvi_stack <- list.files("1.Data/data_clean/NDVI_summaries/summaries_yearly",
                         full.names = T) %>% 
  str_subset('2006',negate = T) %>% 
  str_subset('2007',negate = T) %>% 
  str_subset('2020',negate = T) %>% 
  str_subset('2021',negate = T) %>% 
  str_subset('2022',negate = T) %>%
  str_subset('2023',negate = T) %>% rast()

# Summarizing
yearly_summary <- app(ndvi_stack,mean,na.rm = T)

# Export
writeRaster(yearly_summary,
            filename = paste0(export_dir,
                              "/ndvi_avg_yr_2008_2019_250m.tif"),
            overwrite = T)

#      Overall: Seasonal                                                    ####

# Export Directory 
export_dir <- "1.Data/data_clean/NDVI_summaries/summaries_seasonal_overall"

# Making list of tiles
ndvi_stack <- list.files("1.Data/data_clean/NDVI_summaries/summaries_seasonal",
                         full.names = T) %>% 
  str_subset('2006',negate = T) %>% 
  str_subset('2007',negate = T) %>% 
  str_subset('2020',negate = T) %>% 
  str_subset('2021',negate = T) %>% 
  str_subset('2022',negate = T) %>%
  str_subset('2023',negate = T) 

# Season list
season_list <- c("winter",
                 "spring",
                 "summer",
                 "fall")

# Summarizing
for (i in 1:length(season_list)) {
  
  # Subset Season and Stack 
  stack <- ndvi_stack %>% str_subset(pattern = season_list[i]) %>% 
    rast()
  
  # Summarizing
  seasonal_summary <- app(stack,mean,na.rm = T)
  
  # Export
  writeRaster(seasonal_summary,
              filename = paste0(export_dir,
                                "/ndvi_avg_",season_list[i],"_2008_2019_250m.tif"),
              overwrite = T)
  
  # Iteration Tracker
  print(paste0(i, " out of ", length(season_list), " completed"))
  
}

###############################################################################
#   Max Summary Rasters - Yearly and Seasonal                               ####
#      Yearly Summaries                                                     ####
#        Creating NDVI Master Database                                      ####

# List of NDVI tiles
ndvi_list <- list.files("1.Data/data_clean/NDVI",
                        full.names = T)

# Extracting Dates 
ndvi_dates <- list.files("1.Data/data_clean/NDVI",
                         full.names = F) %>% 
  str_remove("ndvi_") %>% 
  str_remove(".tif") %>% 
  ymd()

# Creating Database
ndvi_database <- data.frame(filepath = ndvi_list,
                            dates = ndvi_dates) %>% 
  mutate(year = year(dates)) %>% 
  filter(year != 2006)

#        Processing NDVI layers                                             ####

# Indicating Export Directory
export_dir <- "1.Data/data_clean/NDVI_summaries/summaries_yearly"

# Making list of unique years
years_unique <- unique(ndvi_database$year)

for (i in 1:length(years_unique)) {
  
  # Extracting a certain year
  target_year <- years_unique[i]
  
  # Subsetting Database for target ndvi files
  target_layers <- ndvi_database %>% 
    filter(year == target_year) %>% 
    .$filepath
  
  # Stacking NDVI tiles and summarizing across
  ndvi_summary <- rast(target_layers) %>% 
    app(fun=max,na.rm = T)
  
  # Exporting NDVI summary raster
  writeRaster(ndvi_summary,
              filename = paste0(export_dir,
                                "/ndvi_max_yr_",
                                target_year,"_250m.tif"),
              overwrite = T)
  
  # Iteration Tracker
  print(paste0(i, " out of ", length(years_unique), " completed"))
}

#      Seasonal Summaries                                                   ####
#        Creating Seasonal Reference                                        ####
#           Period Settings                                                 ####

period_buffer <- 3

study_period_start <- min(unique(ndvi_database$year))- period_buffer
study_period_end <- max(unique(ndvi_database$year))+ period_buffer

#           Season 1: Winter                                                ####

s_start <- expand.grid(season = "winter",
                       year = seq(study_period_start,study_period_end),
                       month = "12",
                       day = "21") %>% 
  mutate(date_str = paste(year,month,day,sep = "-"),.keep = "unused") %>% 
  mutate(start_date = ymd(date_str),.keep = "unused")



s_end <- expand.grid(year = seq(study_period_start,study_period_end)+1,
                     month = "03",
                     day = "19") %>% 
  mutate(date_str = paste(year,month,day,sep = "-"),.keep = "unused") %>% 
  mutate(end_date = ymd(date_str),.keep = "unused") %>% pull()


winter_matrix <- s_start %>% mutate(end_date = s_end)

#           Season 2: Spring                                                ####
s_start <- expand.grid(season = "spring",
                       year = seq(study_period_start,study_period_end),
                       month = "03",
                       day = "20") %>% 
  mutate(date_str = paste(year,month,day,sep = "-"),.keep = "unused") %>% 
  mutate(start_date = ymd(date_str),.keep = "unused")



s_end <- expand.grid(year = seq(study_period_start,study_period_end),
                     month = "06",
                     day = "20") %>% 
  mutate(date_str = paste(year,month,day,sep = "-"),.keep = "unused") %>% 
  mutate(end_date = ymd(date_str),.keep = "unused") %>% pull()


spring_matrix <- s_start %>% mutate(end_date = s_end)



#           Season 2: summer                                                ####
s_start <- expand.grid(season = "summer",
                       year = seq(study_period_start,study_period_end),
                       month = "06",
                       day = "21") %>% 
  mutate(date_str = paste(year,month,day,sep = "-"),.keep = "unused") %>% 
  mutate(start_date = ymd(date_str),.keep = "unused")



s_end <- expand.grid(year = seq(study_period_start,study_period_end),
                     month = "09",
                     day = "22") %>% 
  mutate(date_str = paste(year,month,day,sep = "-"),.keep = "unused") %>% 
  mutate(end_date = ymd(date_str),.keep = "unused") %>% pull()


summer_matrix <- s_start %>% mutate(end_date = s_end)



#           Season 4: fall                                                  ####
s_start <- expand.grid(season = "fall",
                       year = seq(study_period_start,study_period_end),
                       month = "09",
                       day = "23") %>% 
  mutate(date_str = paste(year,month,day,sep = "-"),.keep = "unused") %>% 
  mutate(start_date = ymd(date_str),.keep = "unused")



s_end <- expand.grid(year = seq(study_period_start,study_period_end),
                     month = "12",
                     day = "20") %>% 
  mutate(date_str = paste(year,month,day,sep = "-"),.keep = "unused") %>% 
  mutate(end_date = ymd(date_str),.keep = "unused") %>% pull()


fall_matrix <- s_start %>% mutate(end_date = s_end)



#           Season final                                                    ####

seasonal_reference <- bind_rows(fall_matrix,
                                winter_matrix,
                                spring_matrix,
                                summer_matrix) %>% 
  mutate(int = interval(start_date,end_date)) %>% 
  mutate(season_year = paste(season,year(start_date),sep = "_"),.after = season)


#        Creating NDVI Master Database                                      ####

# List of NDVI tiles
ndvi_list <- list.files("1.Data/data_clean/NDVI",
                        full.names = T)

# Extracting Dates 
ndvi_dates <- list.files("1.Data/data_clean/NDVI",
                         full.names = F) %>% 
  str_remove("ndvi_") %>% 
  str_remove(".tif") %>% 
  ymd()

# Creating Database
ndvi_database <- data.frame(filepath = ndvi_list,
                            date = ndvi_dates) %>% 
  mutate(year = year(date)) %>% 
  filter(year != 2006) %>% 
  mutate(season = NA) 

# Assigning Season_year value
for (i in 1:nrow(ndvi_database)) {
  d <- ndvi_database[i,2]
  ndvi_database[i,4] <- season_year_locator(d, ref_sheet = seasonal_reference)
  print(i)
}

#        Creating Raster Summaries                                          ####

# Indicating Export Directory
export_dir <- "1.Data/data_clean/NDVI_summaries/summaries_seasonal" 

# Create a list of unique seasons
seasons_unique <- ndvi_database$season %>% unique()

for (i in 1:length(seasons_unique)) {
  
  # Extracting a certain year
  target_season <- seasons_unique[i]
  
  # Subsetting Database for target ndvi files
  target_layers <- ndvi_database %>% 
    filter(season == target_season) %>% 
    .$filepath
  
  # Stacking NDVI tiles and summarizing across
  ndvi_summary <- rast(target_layers) %>% 
    app(fun=max,na.rm = T)
  
  # Exporting NDVI summary raster
  writeRaster(ndvi_summary,
              filename = paste0(export_dir,
                                "/ndvi_max_",
                                target_season,"_250m.tif"),
              overwrite = T)
  
  # Iteration Tracker
  print(paste0(i, " out of ", length(seasons_unique), " completed"))
}

#   Max Summary Rasters - Overall Yearly and Seasonal (2008-2019)           ####
#      Overall: Yearly                                                      ####
# Export Directory 
export_dir <- "1.Data/data_clean/NDVI_summaries/summaries_yearly_overall"

# Making list of tiles
ndvi_stack <- list.files("1.Data/data_clean/NDVI_summaries/summaries_yearly",
                         full.names = T) %>% 
  str_subset('2006',negate = T) %>% 
  str_subset('2007',negate = T) %>% 
  str_subset('2020',negate = T) %>% 
  str_subset('2021',negate = T) %>% 
  str_subset('2022',negate = T) %>%
  str_subset('2023',negate = T) %>% rast()

# Summarizing
yearly_summary <- app(ndvi_stack,max,na.rm = T)

# Export
writeRaster(yearly_summary,
            filename = paste0(export_dir,
                              "/ndvi_max_yr_2008_2019_250m.tif"),
            overwrite = T)

#      Overall: Seasonal                                                    ####

# Export Directory 
export_dir <- "1.Data/data_clean/NDVI_summaries/summaries_seasonal_overall"

# Making list of tiles
ndvi_stack <- list.files("1.Data/data_clean/NDVI_summaries/summaries_seasonal",
                         full.names = T) %>% 
  str_subset('2006',negate = T) %>% 
  str_subset('2007',negate = T) %>% 
  str_subset('2020',negate = T) %>% 
  str_subset('2021',negate = T) %>% 
  str_subset('2022',negate = T) %>%
  str_subset('2023',negate = T) 

# Season list
season_list <- c("winter",
                 "spring",
                 "summer",
                 "fall")

# Summarizing
for (i in 1:length(season_list)) {
  
  # Subset Season and Stack 
  stack <- ndvi_stack %>% str_subset(pattern = season_list[i]) %>% 
    rast()
  
  # Summarizing
  seasonal_summary <- app(stack,max,na.rm = T)
  
  # Export
  writeRaster(seasonal_summary,
              filename = paste0(export_dir,
                                "/ndvi_max_",season_list[i],"_2008_2019_250m.tif"),
              overwrite = T)
  
  # Iteration Tracker
  print(paste0(i, " out of ", length(season_list), " completed"))
  
}

###############################################################################
#   Min Summary Rasters - Yearly and Seasonal                               ####
#      Yearly Summaries                                                     ####
#        Creating NDVI Master Database                                      ####

# List of NDVI tiles
ndvi_list <- list.files("1.Data/data_clean/NDVI",
                        full.names = T)

# Extracting Dates 
ndvi_dates <- list.files("1.Data/data_clean/NDVI",
                         full.names = F) %>% 
  str_remove("ndvi_") %>% 
  str_remove(".tif") %>% 
  ymd()

# Creating Database
ndvi_database <- data.frame(filepath = ndvi_list,
                            dates = ndvi_dates) %>% 
  mutate(year = year(dates)) %>% 
  filter(year != 2006)

#        Processing NDVI layers                                             ####

# Indicating Export Directory
export_dir <- "1.Data/data_clean/NDVI_summaries/summaries_yearly"

# Making list of unique years
years_unique <- unique(ndvi_database$year)

for (i in 1:length(years_unique)) {
  
  # Extracting a certain year
  target_year <- years_unique[i]
  
  # Subsetting Database for target ndvi files
  target_layers <- ndvi_database %>% 
    filter(year == target_year) %>% 
    .$filepath
  
  # Stacking NDVI tiles and summarizing across
  ndvi_summary <- rast(target_layers) %>% 
    app(fun=min,na.rm = T)
  
  # Exporting NDVI summary raster
  writeRaster(ndvi_summary,
              filename = paste0(export_dir,
                                "/ndvi_min_yr_",
                                target_year,"_250m.tif"),
              overwrite = T)
  
  # Iteration Tracker
  print(paste0(i, " out of ", length(years_unique), " completed"))
}

#      Seasonal Summaries                                                   ####
#        Creating Seasonal Reference                                        ####
#           Period Settings                                                 ####

period_buffer <- 3

study_period_start <- min(unique(ndvi_database$year))- period_buffer
study_period_end <- max(unique(ndvi_database$year))+ period_buffer

#           Season 1: Winter                                                ####

s_start <- expand.grid(season = "winter",
                       year = seq(study_period_start,study_period_end),
                       month = "12",
                       day = "21") %>% 
  mutate(date_str = paste(year,month,day,sep = "-"),.keep = "unused") %>% 
  mutate(start_date = ymd(date_str),.keep = "unused")



s_end <- expand.grid(year = seq(study_period_start,study_period_end)+1,
                     month = "03",
                     day = "19") %>% 
  mutate(date_str = paste(year,month,day,sep = "-"),.keep = "unused") %>% 
  mutate(end_date = ymd(date_str),.keep = "unused") %>% pull()


winter_matrix <- s_start %>% mutate(end_date = s_end)

#           Season 2: Spring                                                ####
s_start <- expand.grid(season = "spring",
                       year = seq(study_period_start,study_period_end),
                       month = "03",
                       day = "20") %>% 
  mutate(date_str = paste(year,month,day,sep = "-"),.keep = "unused") %>% 
  mutate(start_date = ymd(date_str),.keep = "unused")



s_end <- expand.grid(year = seq(study_period_start,study_period_end),
                     month = "06",
                     day = "20") %>% 
  mutate(date_str = paste(year,month,day,sep = "-"),.keep = "unused") %>% 
  mutate(end_date = ymd(date_str),.keep = "unused") %>% pull()


spring_matrix <- s_start %>% mutate(end_date = s_end)



#           Season 2: summer                                                ####
s_start <- expand.grid(season = "summer",
                       year = seq(study_period_start,study_period_end),
                       month = "06",
                       day = "21") %>% 
  mutate(date_str = paste(year,month,day,sep = "-"),.keep = "unused") %>% 
  mutate(start_date = ymd(date_str),.keep = "unused")



s_end <- expand.grid(year = seq(study_period_start,study_period_end),
                     month = "09",
                     day = "22") %>% 
  mutate(date_str = paste(year,month,day,sep = "-"),.keep = "unused") %>% 
  mutate(end_date = ymd(date_str),.keep = "unused") %>% pull()


summer_matrix <- s_start %>% mutate(end_date = s_end)



#           Season 4: fall                                                  ####
s_start <- expand.grid(season = "fall",
                       year = seq(study_period_start,study_period_end),
                       month = "09",
                       day = "23") %>% 
  mutate(date_str = paste(year,month,day,sep = "-"),.keep = "unused") %>% 
  mutate(start_date = ymd(date_str),.keep = "unused")



s_end <- expand.grid(year = seq(study_period_start,study_period_end),
                     month = "12",
                     day = "20") %>% 
  mutate(date_str = paste(year,month,day,sep = "-"),.keep = "unused") %>% 
  mutate(end_date = ymd(date_str),.keep = "unused") %>% pull()


fall_matrix <- s_start %>% mutate(end_date = s_end)



#           Season final                                                    ####

seasonal_reference <- bind_rows(fall_matrix,
                                winter_matrix,
                                spring_matrix,
                                summer_matrix) %>% 
  mutate(int = interval(start_date,end_date)) %>% 
  mutate(season_year = paste(season,year(start_date),sep = "_"),.after = season)


#        Creating NDVI Master Database                                      ####

# List of NDVI tiles
ndvi_list <- list.files("1.Data/data_clean/NDVI",
                        full.names = T)

# Extracting Dates 
ndvi_dates <- list.files("1.Data/data_clean/NDVI",
                         full.names = F) %>% 
  str_remove("ndvi_") %>% 
  str_remove(".tif") %>% 
  ymd()

# Creating Database
ndvi_database <- data.frame(filepath = ndvi_list,
                            date = ndvi_dates) %>% 
  mutate(year = year(date)) %>% 
  filter(year != 2006) %>% 
  mutate(season = NA) 

# Assigning Season_year value
for (i in 1:nrow(ndvi_database)) {
  d <- ndvi_database[i,2]
  ndvi_database[i,4] <- season_year_locator(d, ref_sheet = seasonal_reference)
  print(i)
}

#        Creating Raster Summaries                                          ####

# Indicating Export Directory
export_dir <- "1.Data/data_clean/NDVI_summaries/summaries_seasonal" 

# Create a list of unique seasons
seasons_unique <- ndvi_database$season %>% unique()

for (i in 1:length(seasons_unique)) {
  
  # Extracting a certain year
  target_season <- seasons_unique[i]
  
  # Subsetting Database for target ndvi files
  target_layers <- ndvi_database %>% 
    filter(season == target_season) %>% 
    .$filepath
  
  # Stacking NDVI tiles and summarizing across
  ndvi_summary <- rast(target_layers) %>% 
    app(fun=min,na.rm = T)
  
  # Exporting NDVI summary raster
  writeRaster(ndvi_summary,
              filename = paste0(export_dir,
                                "/ndvi_min_",
                                target_season,"_250m.tif"),
              overwrite = T)
  
  # Iteration Tracker
  print(paste0(i, " out of ", length(seasons_unique), " completed"))
}

#   Min Summary Rasters - Overall Yearly and Seasonal (2008-2019)           ####
#      Overall: Yearly                                                      ####
# Export Directory 
export_dir <- "1.Data/data_clean/NDVI_summaries/summaries_yearly_overall"

# Making list of tiles
ndvi_stack <- list.files("1.Data/data_clean/NDVI_summaries/summaries_yearly",
                         full.names = T) %>% 
  str_subset('2006',negate = T) %>% 
  str_subset('2007',negate = T) %>% 
  str_subset('2020',negate = T) %>% 
  str_subset('2021',negate = T) %>% 
  str_subset('2022',negate = T) %>%
  str_subset('2023',negate = T) %>% rast()

# Summarizing
yearly_summary <- app(ndvi_stack,min,na.rm = T)

# Export
writeRaster(yearly_summary,
            filename = paste0(export_dir,
                              "/ndvi_min_yr_2008_2019_250m.tif"),
            overwrite = T)

#      Overall: Seasonal                                                    ####

# Export Directory 
export_dir <- "1.Data/data_clean/NDVI_summaries/summaries_seasonal_overall"

# Making list of tiles
ndvi_stack <- list.files("1.Data/data_clean/NDVI_summaries/summaries_seasonal",
                         full.names = T) %>% 
  str_subset('2006',negate = T) %>% 
  str_subset('2007',negate = T) %>% 
  str_subset('2020',negate = T) %>% 
  str_subset('2021',negate = T) %>% 
  str_subset('2022',negate = T) %>%
  str_subset('2023',negate = T) 

# Season list
season_list <- c("winter",
                 "spring",
                 "summer",
                 "fall")

# Summarizing
for (i in 1:length(season_list)) {
  
  # Subset Season and Stack 
  stack <- ndvi_stack %>% str_subset(pattern = season_list[i]) %>% 
    rast()
  
  # Summarizing
  seasonal_summary <- app(stack,min,na.rm = T)
  
  # Export
  writeRaster(seasonal_summary,
              filename = paste0(export_dir,
                                "/ndvi_min_",season_list[i],"_2008_2019_250m.tif"),
              overwrite = T)
  
  # Iteration Tracker
  print(paste0(i, " out of ", length(season_list), " completed"))
  
}

###############################################################################
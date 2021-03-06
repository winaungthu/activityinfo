# required packages:
#require("activityinfo")
#require("reshape2")

#####################################################
#  ActivityInfo Monitoring analysis script          #
#####################################################

#  This script retrieves a selection of information for all activities in a
#  database which have reporting frequency "once".

# authenticate
#activityInfoLogin()

#
source("code/0-activityinfo.R")
#
source("code/0-packages.R")

### JOR Monitoring Database Jordan db 1064
database.id <- 1064

values <- getIndicatorValueTable(database.id)
# this gives us almost all the information we need. Missing are the start and 
# end date of the reporting period as well as the value of the attributes for
# each site.



#################################################################################################
### Step 1: create a lookup table for single attributes (i.e. those attributes
### that are in the activities and which allow only a single selection)

# retrieve the database schema as a list:
schema <- getDatabaseSchema(database.id)

# convert list of activities to a data frame
activities.table <-asActivityDataFrame(schema)


# extract attributes from the current database:
include.multiple.selection <- TRUE
attributes <-
  do.call(rbind, lapply(schema$activities,
                        function(activity) {
                          extractAttributes(activity, include.multiple.selection)
                        }))

### Step 2: extract start/end date and attributes from all sites:

# select the identifiers of activities that have reporting frequency "monthly":
activities.reported.monthly <-
  activities.table$activityId[activities.table$reportingFrequency == 1]

# retrieve a data frame with all sites linked to all indicators in the database
# and which contains the information missing in the 'data' object:
sites <- do.call(rbind, lapply(activities.reported.monthly, function(id) {
  cat("Getting sites for activity", id, "\n")
  sites <- getSites(id)
  do.call(rbind, lapply(sites, function(site) {
    n <- length(site$attributes)
    if (n) {
      df <- data.frame(siteId = rep(site$id, n),
                       activityId = rep(site$activity, n),
                     #  startDate = rep(site$startDate, n),
                     #  endDate = rep(site$endDate, n),
                       comments = ifelse(is.null(site$comments), "", site$comments),
                       stringsAsFactors = FALSE)
      # site$attributes is a vector with attribute identifiers. Some of these
      # may be multiple-selection attributes, which we currently ignore.
      i <- match(site$attributes, attributes$id, nomatch = 0)
      df$attributeGroup <- attributes$group[i]
      df$attributeValue <- attributes$name[i]
      df$multipleAllowed <- attributes$multipleAllowed[i]
    } else {
      return(NULL)
    }
    return(df)
  }))
}))

# Now we have:
# - sites$attributeGroup contains the name of the attribute
# - sites$attributeValue contains the actual value (i.e. selection) of the 
#   attribute
# Create a wide-format data frame with a column for each attribute group:
if (!include.multiple.selection) {
  sites.wide <- dcast(sites,
                      siteId + activityId + startDate + endDate ~ attributeGroup)


#################################################################################################
###### Step 3: merge missing information into the 'values' data frame:
  values <- merge(values, sites.wide, by = c("siteId", "activityId"), all.x = TRUE)
} else {
  values <- merge(values, sites, by = c("siteId", "activityId"), all.x = TRUE)
  warning("attribute values are not stored in separate columns!")
}
# 'values' should now have a separate column for every single-selection
# attribute found in all indicators that exist in the given database.


#################################################################################################
### Step 4: add the full geographic tree to the data.
country.id <- schema$country$id

location.types <- getLocationTypes(country.id)
location.types.table <-
  do.call(rbind, lapply(location.types, function(type) {
    data.frame(id = type$id,
               name = type$name,
               stringsAsFactors = FALSE)
  }))

admin.levels <- getAdminLevels(country.id)
admin.levels.table <-
  do.call(rbind, lapply(admin.levels, function(level) {
    data.frame(id = level$id,
               name = level$name,
               parent.id = if(!is.null(level$parentId)) level$parentId else NA,
               stringsAsFactors = FALSE)
  }))

# add a column to 'values' for each administrative level in the country:
admin.levels.table$column <- sanitizeNames(admin.levels.table$name)
for (column.name in admin.levels.table$column) {
  values[[column.name]] <- NA_character_
}

# add location type identifier to the activities table as having only the name
# is not very useful:
activities.table$locationTypeId <-
  location.types.table$id[match(activities.table$locationTypeName,
                                location.types.table$name)]

# retrieve all locations for each type present in the activities table:
locations <- list()
for (type in unique(activities.table$locationTypeId)) {
  cat("Getting all location entities of type", type, "\n")
  locations <- c(locations, getLocations(type))
}

# store the names of administrative entities for each record (i.e. site) in the
# final result:
location.ids <- sapply(locations, function(loc) loc$id)
for (id in unique(values$locationId)) {
  rows <- which(values$locationId == id)
  j <- which(location.ids == id)
  if (length(j) == 1L) {
    admin.levels <- extractAdminLevelEntities(locations[[j]])
    for (col in names(admin.levels)) {
      values[[col]][rows] <- admin.levels[[col]]
    }
  } else {
    warning("found zero or more locations with identifier ",
            values$locationId[i], ". Skipping row(s) ", paste(rows, collapse = ", "), ".")
  }
}


#################################################################################################
### Step 5: Let's cast attributes and merge them back to unique indicators
# reformat attributes
## First unique values for sites;

#names(values)
values.unique <- unique(values[,c("siteId" , "activityId" , "locationId" , "locationName"  ,
                                  "partnerId"  , "partnerName" ,  "activityName" ,
                                  "activityCategory","indicatorId"  , "value", "indicatorName",
                                  "month" , "database",  "indicatorCategory","units" , 
                                  "month",
                                  #"startDate" , "endDate" , 
                                  #"attributeGroup" , "attributeValue" , "multipleAllowed"
                                  "governorate" ,  "region", "district" ,  "subdistrict", "refugee.camps", "camp.districts","comments"  )])

## Let's cast attributes
# We have single and multiple attributes -- multipleAllowed
#names(values)

sites.unique.attr <- unique(values[,c("siteId" , "attributeGroup" , "attributeValue" , "multipleAllowed" )])
sites.unique <- as.data.frame(values[,c("siteId"  )])
sites.unique <- unique(sites.unique)

sites.attribute.single <- sites.unique.attr[sites.unique.attr$multipleAllowed == "FALSE",c("siteId", "attributeGroup" , "attributeValue")]
sites.attribute.single.wide <- dcast(sites.attribute.single, siteId ~ attributeGroup, value.var="attributeValue")


sites.attribute.multiple <- sites.unique.attr[sites.unique.attr$multipleAllowed == "TRUE",c("siteId", "attributeGroup" , "attributeValue")]
sites.attribute.multiple.wide <- dcast(sites.attribute.multiple, siteId  ~ attributeValue)

## Merge back
#rm(values.unique.attribute)
values.unique.attribute <- merge (x=values.unique, y=sites.attribute.single.wide, by="siteId", all.x=TRUE)
values.unique.attribute <- merge (x=values.unique.attribute, y=sites.attribute.multiple.wide, by="siteId", all.x=TRUE)


values.unique.attribute$objective <- substr(values.unique.attribute$activityCategory , (regexpr("-", values.unique.attribute$activityCategory , ignore.case=FALSE, fixed=TRUE))+1,50)
values.unique.attribute$sector <- substr(values.unique.attribute$activityCategory ,1, (regexpr("-", values.unique.attribute$activityCategory , ignore.case=FALSE, fixed=TRUE))-1)



db.1064.monitor <- values.unique.attribute

#################################################################################################
###  merge with the right code for the map
regionactivityinfo <- read.csv("data/regionactivityinfocode.csv")


values.unique.attribute <- merge(x=values.unique.attribute, y=regionactivityinfo, by="governorate", all.x=TRUE)

# Distinguish camps
values.unique.attribute$gcode <- as.character(values.unique.attribute$gcode)
values.unique.attribute$rcode <- as.character(values.unique.attribute$rcode)
values.unique.attribute$gcode[!is.na(values.unique.attribute$Refugee.camps)] <- "2"
values.unique.attribute$rcode[!is.na(values.unique.attribute$Refugee.camps)] <- "5"

# Distinguish Country wide intervention
values.unique.attribute$rcode[values.unique.attribute$locationName=="Country Wide"] <- "3"
values.unique.attribute$gcode[values.unique.attribute$locationName=="Country Wide"] <- "1"


#################################################################################################
###  Convert month in full date format
values.unique.attribute$startDate <- as.Date(paste(values.unique.attribute$month,"-01",sep=""),"%Y-%m-%d" )
values.unique.attribute$startDate <- format(values.unique.attribute$startDate, "%d/%m/%Y")

#################################################################################################
###  Selection of indicators that have gender disaggregation


values.unique.attribute$indicatorName <- as.factor(values.unique.attribute$indicatorName)
levels(values.unique.attribute$indicatorName)

values.unique.attribute$men <- with(values.unique.attribute, 
                                    ifelse(
                                      grepl("men|Men", ignore.case = TRUE, fixed = FALSE, useBytes = FALSE, values.unique.attribute$indicatorName),
                                      paste0("Men"), "")
                                    )
values.unique.attribute$women <- with(values.unique.attribute,
                                      ifelse(grepl("women|Women", ignore.case = TRUE, fixed = FALSE, useBytes = FALSE, values.unique.attribute$indicatorName),
                                             paste0("Women"), "")
                                      )
values.unique.attribute$boy <- with(values.unique.attribute, 
                                    ifelse(grepl("boy|Boys|Boy", ignore.case = TRUE, fixed = FALSE, useBytes = FALSE, values.unique.attribute$indicatorName),
                                           paste0("Boys"), "")
                                    )
values.unique.attribute$girl <- with(values.unique.attribute,
                                     ifelse(grepl("girl|Girls|girls", ignore.case = TRUE, fixed = FALSE, useBytes = FALSE,  values.unique.attribute$indicatorName),
                                            paste0("Girls"), "")
                                     )

values.unique.attribute$gender <- paste0(values.unique.attribute$girl, values.unique.attribute$boy, 
                                           values.unique.attribute$women ,  values.unique.attribute$men, sep="")

#################################################################################################
### Merge site type into one through concatenation

values.unique.attribute <- rename (values.unique.attribute, c("Informal Tented Settlement" = "ITS" ,  "Urban areas"="Urban"))

## Replace NA with NULL -- df[is.na(df)] <- " "
values.unique.attribute$Camp[is.na(values.unique.attribute$Camp)] <- " "
values.unique.attribute$ITS[is.na(values.unique.attribute$ITS)] <- " " 
values.unique.attribute$Other[is.na(values.unique.attribute$Other)] <- " "
values.unique.attribute$Urban[is.na(values.unique.attribute$Urban)] <- " "

values.unique.attribute$sitetype <- paste0(values.unique.attribute$Camp, values.unique.attribute$ITS, 
                                           values.unique.attribute$Other ,  values.unique.attribute$Urban, sep=" - ")                
#names(values.unique.attribute)

 #                      "activityId"                     "locationId"                     "locationName"                   "partnerId"                     
# "partnerName"                    "activityName"                   "activityCategory"               "indicatorId"                    "value"                         
# "indicatorName"                  "month"                          "database"                       "indicatorCategory"              "units"                         
# "month.1"                        "governorate"                    "region"                         "district"                       "subdistrict"                   
# "refugee.camps"                  "camp.districts"                 "comments"                       "2-RRP6 Implementation Type"     "3-RRP6 appeal through"         
# "4-Allocation according to RRP6" "objective"                      "sector"  


output <- rename (values.unique.attribute, c(
 # "siteId"= "siteid" ,
  "startDate"= "StartDate" ,
 # ""=  "EndDate",
 # ""=  "Year",
 # ""=  "Month" ,
  "objective"= "Category",
  "activityName"=  "activity",
  "indicatorName"= "Indicator",
  "governorate"=  "Governorate" ,
  "gender"=  "Gender",
  "partnerName"=  "Partner" ,  
  "sitetype"=  "SiteType",
  "2-RRP6 Implementation Type"= "appeal",
  "3-RRP6 appeal through"=  "Fundedby",
  "4-Allocation according to RRP6"=  "allocation",
  "rcode"=  "rcode" ,
  "gcode"=  "gcode" ,
  "value"= "Value" ,
  "units"=  "Units"  ,
  "locationName"= "location",
  "region.y"= "region"))

names(output)
##################################################################################
######### Writing output for Dashbaord dataviz @ https://github.com/unhcr-jordan/sectors 

output.education <-  subset(output, output$sector == "EDUCATION")
write.csv(output.education, file = "out/monitor/education/data.csv",na="")

output.health <-  subset(output, output$sector == "HEALTH")
write.csv(output.health, file = "out/monitor/health/data.csv",na="")

output.food <-  subset(output, output$sector == "FOOD")
write.csv(output.food, file = "out/monitor/food/data.csv",na="")

output.cash <-  subset(output, output$sector == "CASH")
write.csv(output.cash, file = "out/monitor/cash/data.csv",na="")

output.nfi <-  subset(output, output$sector == "NFI")
write.csv(output.nfi, file = "out/monitor/nfi/data.csv",na="")

output.protection <-  subset(output, output$sector == "PROTECTION")
write.csv(output.protection, file = "out/monitor/protection/data.csv",na="")

output.shelter <-  subset(output, output$sector == "SHELTER")
write.csv(output.shelter, file = "out/monitor/shelter/data.csv",na="")

output.wash <-  subset(output, output$sector == "WASH")
write.csv(output.wash, file = "out/monitor/wash/data.csv",na="")

########################################################


db.1064.monitor <- values.unique.attribute

### Clean unused elements

rm(activities.table)
rm(admin.levels.table)
#rm(attributes.single)
rm(location.types.table)
rm(sites)
#rm(sites.wide)
rm(values)
# rm(activities.reported.once)
rm(activities.reported.monthly)
rm(admin.levels)
rm(col)
rm(column.name)
rm(country.id)
rm(database.id)
rm(id)
rm(j)
rm(location.ids)
rm(location.types)
rm(locations)
rm(rows)
rm(schema)
rm(type)

rm(attributes)
rm(include.multiple.selection)
rm(sites.attribute.multiple)
rm(sites.attribute.single)
rm(sites.attribute.single.dup)
rm(sites.attribute.single.wide)
rm(sites.unique)
rm(sites.unique.attr)
rm(values.unique)
rm(values.unique.attribute)
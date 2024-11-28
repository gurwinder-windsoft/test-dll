# Define MongoDB URIs
$preprodURI = $env:PREPRODURI
$prodURI = "mongodb://admin:adminYBXdGH123@68.219.243.214:27017/?authSource=admin"

# Define collections to export and import
$collections = @("Client", "User")

# Define export paths
$exportPath = "C:\exported_data\"

foreach ($collectionName in $collections) {
  # Set export path for current collection
  $collectionExportPath = $exportPath + $collectionName + ".json"

  # Step 4: Export collection data from preprod to a file
  Write-Host "Exporting $collectionName data from preprod"
  & 'C:\mongodb-tools\mongodb-database-tools-windows-x86_64-100.10.0\bin\mongoexport.exe' --uri=$preprodURI --db=SyncNotifyHubService --collection=$collectionName --out=$collectionExportPath --jsonArray
  Write-Host "Exported $collectionName data to $collectionExportPath"

  # Step 5: Import collection data into prod
  Write-Host "Importing $collectionName data into prod"
  & 'C:\mongodb-tools\mongodb-database-tools-windows-x86_64-100.10.0\bin\mongoimport.exe' --uri=$prodURI --db=SyncNotifyHubService --collection=$collectionName --file=$collectionExportPath --jsonArray --upsert --verbose 
  Write-Host "Imported $collectionName data into prod"
}

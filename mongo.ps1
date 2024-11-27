param (
    [string]$collectionName,
    [string]$exportPath
)

# Use environment variables for MongoDB URIs
$preprodUri = $env:PREPRODURI  # URI for preprod database
$prodUri = $env:PRODURI        # URI for prod database

# Function to export data from preprod
function Export-PreprodData {
    param (
        [string]$collectionName
    )

    try {
        $mongoExportCommand = "& 'C:\mongodb-tools\mongodb-database-tools-windows-x86_64-100.10.0\bin\mongoexport.exe' --uri=`"$preprodUri`" --db=SyncNotifyHubService --collection=$collectionName --out=`"$exportPath`" --jsonArray --authenticationDatabase=admin"
        Write-Host "Exporting $collectionName from preprod..."
        Write-Host "Running export command: $mongoExportCommand"
        Invoke-Expression $mongoExportCommand
        Write-Host "Exported $collectionName successfully to $exportPath"
        return $exportPath
    } catch {
        Write-Host "Error exporting data from preprod: $($_.Exception.Message)"
        Write-Host "StackTrace: $($_.Exception.StackTrace)"
        return $null
    }
}

# Function to import data into prod
function Import-ProdData {
    param (
        [string]$collectionName,
        [string]$exportFile
    )

    try {
        if (Test-Path $exportFile) {
            $importCommand = "mongoimport --uri=$prodUri --db=SyncNotifyHubService --collection=$collectionName --file=$exportFile --jsonArray --authenticationDatabase=admin --upsert"
            Write-Host "Importing data into prod from $exportFile..."
            Write-Host "Running import command: $importCommand"
            Invoke-Expression $importCommand
            Write-Host "Data imported into prod successfully."
        } else {
            Write-Host "Error: The file $exportFile was not found."
        }
    } catch {
        Write-Host "Error importing data into prod: $($_.Exception.Message)"
    }
}

# Main logic for exporting from preprod and importing to prod
$collections = @("Client", "User")  # List of collections to export/import

foreach ($collectionName in $collections) {
    # Step 1: Export data from preprod
    $exportFile = Export-PreprodData -collectionName $collectionName -exportPath "$env:GITHUB_WORKSPACE\$collectionName.json"
    if ($exportFile) {
        # Step 2: Import data into prod
        Import-ProdData -collectionName $collectionName -exportFile $exportFile
    } else {
        Write-Host "Data export for $collectionName failed. Cannot proceed with import."
    }
}

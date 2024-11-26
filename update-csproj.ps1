$githubToken = $env:TOKENGIT  # Replace with your GitHub token
$orgName = "windsoft-erp"
$packageType = "nuget"

# Logging configuration
$logLevel = "Info"

# Write-Log function to handle logging
function Write-Log {
    param ($Level, $Message)
    $logEntry = "$(Get-Date) - $Level - $Message"
    Write-Host $logEntry
}

# Start script execution log
Write-Log -Level Info -Message "Script execution started."

# Load the renamed packages map from JSON and convert it to a hashtable
$packageMapFilePath = "package_map.json"
$packageMap = @{}

if (Test-Path $packageMapFilePath) {
    # Convert JSON to hashtable
    $jsonContent = Get-Content -Path $packageMapFilePath | ConvertFrom-Json
    foreach ($key in $jsonContent.PSObject.Properties.Name) {
        $packageMap[$key] = $jsonContent.$key
    }
    Write-Log -Level Info -Message "Loaded package map: $($packageMap | ConvertTo-Json)"
} else {
    Write-Log -Level Error -Message "package_map.json file not found at '$packageMapFilePath'."
    exit
}

# Functions
function Get-GitHubPackageVersions {
    param ($packageName)
    if (-not $packageName) {
        Write-Log -Level Error -Message "Package name is empty, skipping GitHub version lookup."
        return @()
    }

    $url = "https://api.github.com/orgs/$orgName/packages/$packageType/$packageName/versions"
    $headers = @{
        "Authorization" = "Bearer $githubToken"
        "Accept" = "application/vnd.github+json"
    }

    try {
        $response = Invoke-WebRequest -Uri $url -Headers $headers -Method Get
        Write-Log -Level Info -Message "Response from GitHub for '$packageName': $($response.Content)"
        $versions = ($response.Content | ConvertFrom-Json).name
        return $versions
    } catch {
        Write-Log -Level Error -Message "Error retrieving package versions for '$packageName': $_"
        return @()
    }
}

function Clean-PackageName {
    param ($packageName)
    # Remove metadata like 'Version=', 'Culture=', etc.
    $cleanedPackageName = $packageName -replace ",\s*Version=.*$", "" -replace ",\s*Culture=.*$", "" `
                                                   -replace ",\s*PublicKeyToken=.*$", "" `
                                                   -replace ",\s*processorArchitecture=.*$", ""
    return $cleanedPackageName
}

function Extract-VersionFromHintPath {
    param ($hintPath)
    # Extract version from the HintPath, which follows the pattern 'Ver-<version>_'
    if ($hintPath -match "Ver-([\d\.]+)_") {
        return $matches[1]
    }
    return ""
}

function Update-ReferenceHintPath {
    param ($reference, $packageName, $version)
    $reference.HintPath = "..\packages\$packageName.$version\lib\net4.5.2\$packageName.dll"
}

function Update-CsProjFile {
    param ($filePath)
    $xml = [xml](Get-Content -Path $filePath)

    foreach ($reference in $xml.Project.ItemGroup.Reference) {
        $hintPath = $reference.HintPath
        $packageName = $reference.Include

        # Check if HintPath contains an IP address or network share path
        if ($hintPath -ne $null -and ($hintPath -like "*10.139.20.22*" -or $hintPath -like "*10.139.3.11*" -or $hintPath.StartsWith("\\server\"))) {     
            Write-Log -Level Info -Message "Found package with IP or network share: $packageName"

            # Clean the package name before matching
            $cleanedPackageName = Clean-PackageName -packageName $packageName
            Write-Log -Level Info -Message "Cleaned package name: '$cleanedPackageName'"

            # Extract version from HintPath if possible
            $version = ""
            if ($packageName -match "([a-zA-Z\.]+), Version=([0-9\.]+)") {
                $version = $matches[2].TrimEnd('0').TrimEnd('.')
            }

            # If version is not found in the Include element, extract from HintPath
            if (-not $version) {
                $version = Extract-VersionFromHintPath -hintPath $hintPath
                Write-Log -Level Info -Message "Version extracted from HintPath: '$version'"
            }

            # If still no version, skip this package
            if (-not $version) {
                Write-Log -Level Warning -Message "No version found for '$cleanedPackageName'. Skipping update."
                continue
            }

            # If cleaned package name is empty, use the original package name
            if ([string]::IsNullOrEmpty($cleanedPackageName)) {
                Write-Log -Level Info -Message "Cleaned package name is empty. Using original package name '$packageName'."
                $cleanedPackageName = $packageName
            }

            # Rename the package if it's in the map
            if ($packageMap.ContainsKey($cleanedPackageName)) {
                Write-Log -Level Info -Message "Package '$cleanedPackageName' is being renamed to '$($packageMap[$cleanedPackageName])'."
                $cleanedPackageName = $packageMap[$cleanedPackageName]
            }

            # Check if the renamed package is in GitHub packages
            $availableVersions = Get-GitHubPackageVersions -packageName $cleanedPackageName

            # If no matching version found, skip the update
            if (-not $availableVersions -or -not $availableVersions.Contains($version)) {
                Write-Log -Level Warning -Message "No matching version found for '$cleanedPackageName'. Skipping update."
                continue
            }

            # Update the HintPath with the new package version
            Write-Log -Level Info -Message "Updating reference for '$cleanedPackageName' to version '$version'."
            Update-ReferenceHintPath -reference $reference -packageName $cleanedPackageName -version $version

            # Now check for and remove SpecificVersion element
            $namespaceManager = New-Object System.Xml.XmlNamespaceManager($xml.NameTable)
            $namespaceManager.AddNamespace("msbuild", "http://schemas.microsoft.com/developer/msbuild/2003")

            $specificVersionElement = $reference.SelectSingleNode("msbuild:SpecificVersion", $namespaceManager)
            if ($specificVersionElement) {
                Write-Log -Level Info -Message "Removing SpecificVersion element for reference '$packageName'."
                $reference.RemoveChild($specificVersionElement)
            } else {
                Write-Log -Level Info -Message "No SpecificVersion element found for '$packageName', nothing to remove."
            }
        }
    }

    # Save the updated .csproj file
    $xml.Save((Get-Item -Path $filePath).FullName)
    Write-Log -Level Info -Message "Updated .csproj file '$filePath' successfully."
}

# Get all .csproj files (you can specify a folder path here)
$csProjFiles = Get-ChildItem -Path "Aigle.2017-main" -Recurse -Filter *.csproj

# Process each .csproj file
foreach ($csProjFile in $csProjFiles) {
    Write-Log -Level Info -Message "Processing .csproj file: $($csProjFile.FullName)"
    Update-CsProjFile -filePath $csProjFile.FullName
}

Write-Log -Level Info -Message "Script execution completed."

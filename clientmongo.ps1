# Function to login and retrieve the token from response headers
function Login {
    $url = "https://preprodapi.syncnotifyhub.windsoft.ro/api/User/login"
    $loginCredentials = @{
        email    = "test.admin@windsoft.ro"
        Password = "testpasswordadmin"
    }
    $jsonBody = $loginCredentials | ConvertTo-Json
    try {
        $response = Invoke-WebRequest -Uri $url -Method Post -Body $jsonBody -ContentType "application/json" -ErrorAction Stop
        $statusCode = $response.StatusCode
        Write-Host "Response status code: $statusCode"
        if ($response.Headers["Authorization"]) {
            $authToken = $response.Headers["Authorization"]
            Write-Host "Login successful! Authorization token: $authToken"
            return $authToken
        } else {
            Write-Host "Login failed: No Authorization header found."
            return $null
        }
    } catch {
        Write-Host "Login failed: $($_.Exception.Message)"
        return $null
    }
}

# Function to get or create the client
function GetOrCreate-Client {
    param (
        [string]$authToken,
        [string]$clientName,
        [string]$clientStatus
    )
    $url = "https://preprodapi.syncnotifyhub.windsoft.ro/api/Client"
    $headers = @{ "Authorization" = "Bearer $authToken" }
    try {
        $response = Invoke-WebRequest -Uri $url -Method Get -Headers $headers -ContentType "application/json" -ErrorAction Stop
        if ($response.StatusCode -eq 200) {
            $clients = $response.Content | ConvertFrom-Json
            $existingClient = $clients | Where-Object { $_.clientName -eq $clientName }
            if ($existingClient) {
                Write-Host "Client $clientName found."
                return $existingClient
            } else {
                Write-Host "Client $clientName not found. Creating the client..."
                $body = @{ clientName = $clientName; clientStatus = $clientStatus } | ConvertTo-Json
                $createResponse = Invoke-WebRequest -Uri $url -Method Post -Headers $headers -Body $body -ContentType "application/json" -ErrorAction Stop
                if ($createResponse.StatusCode -eq 201) {
                    Write-Host "Client $clientName created successfully."
                    return $createResponse.Content | ConvertFrom-Json
                } else {
                    Write-Host "Failed to create client. Status Code: $($createResponse.StatusCode)"
                    return $null
                }
            }
        } else {
            Write-Host "Failed to fetch client details. Status Code: $($response.StatusCode)"
            return $null
        }
    } catch {
        Write-Host "Error fetching or creating client: $($_.Exception.Message)"
        return $null
    }
}

# Function to list build files from FTP server using SSH
function List-FTPFiles {
    param (
        [string]$FTPUser,
        [string]$FTPPrivateKey,
        [string]$FTPServerHost,
        [string]$Directory
    )
    $sshDir = "$env:USERPROFILE\.ssh"
    if (-not (Test-Path $sshDir)) {
        New-Item -ItemType Directory -Path $sshDir
    }
    $privateKeyPath = "$sshDir\id_rsa"
    Set-Content -Path $privateKeyPath -Value $FTPPrivateKey -Force
    icacls $privateKeyPath /inheritance:r /grant:r "$($env:USERNAME):(R)"
    $knownHostsPath = "$sshDir\known_hosts"
    if (-not (Test-Path $knownHostsPath)) {
        New-Item -ItemType File -Path $knownHostsPath -Force
    }
    ssh-keyscan -H $FTPServerHost | Out-File -Append -FilePath $knownHostsPath
    $sshCommand = "ssh -i $privateKeyPath -o StrictHostKeyChecking=no $FTPUser@$FTPServerHost 'ls $Directory'"
    Write-Host "Running SSH command: $sshCommand"
    $result = Invoke-Expression $sshCommand
    if ($result) {
        Write-Host "SSH connection successful. Listing files in ${Directory}:"
        return $result.Split("`n") | Where-Object { $_ -ne "" }
    } else {
        Write-Host "Failed to connect to the FTP server or list files."
        return $null
    }
    Remove-Item $privateKeyPath -Force
}

# Function to get the latest build file from the list of files
function Get-LatestBuildFile {
    param (
        [array]$buildFiles
    )
    $regex = 'Hard_WindNet_(\d+\.\d+\.\d+(\.\d+)?)_\d{14}\.zip'
    $latestBuild = $buildFiles | Where-Object { $_ -match $regex }
    if ($latestBuild) {
        $version = ($latestBuild -replace 'Hard_WindNet_(\d+\.\d+\.\d+(\.\d+)?)_\d{14}\.zip', '$1')
        Write-Host "Found latest build: $latestBuild with version: $version"
        return $latestBuild, $version
    } else {
        Write-Host "No valid build files found."
        return $null, $null
    }
}

# Function to check if the product exists and create it if not
function GetOrCreate-Product {
    param (
        [string]$authToken,
        [string]$clientName,
        [string]$productName,
        [string]$latestZipFile,
        [string]$version
    )
    $url = "https://preprodapi.syncnotifyhub.windsoft.ro/api/Product"
    $headers = @{ "Authorization" = "Bearer $authToken" }
    try {
        $response = Invoke-WebRequest -Uri $url -Method Get -Headers $headers -ContentType "application/json" -ErrorAction Stop
        if ($response.StatusCode -eq 200) {
            $products = $response.Content | ConvertFrom-Json
            $existingProduct = $products | Where-Object { $_.productName -eq $productName }
            if ($existingProduct) {
                Write-Host "Product $productName found."
                return $existingProduct
            } else {
                Write-Host "Product $productName not found. Creating the product..."
                $body = @{
                    productName = $productName
                    clientName  = $clientName
                    version     = $version
                    latestVersion = $latestZipFile
                } | ConvertTo-Json -Depth 3
                $createResponse = Invoke-WebRequest -Uri $url -Method Post -Headers $headers -Body $body -ContentType "application/json" -ErrorAction Stop
                if ($createResponse.StatusCode -eq 201) {
                    Write-Host "Product $productName created successfully."
                    return $createResponse.Content | ConvertFrom-Json
                } else {
                    Write-Host "Failed to create product. Status Code: $($createResponse.StatusCode)"
                    return $null
                }
            }
        } else {
            Write-Host "Failed to fetch product details. Status Code: $($response.StatusCode)"
            return $null
        }
    } catch {
        Write-Host "Error fetching or creating product: $($_.Exception.Message)"
        return $null
    }
}

# Main script logic
$authToken = Login

if ($authToken) {
    $authToken = $authToken.Trim()
    if ($authToken.StartsWith("Bearer ")) {
        $authToken = $authToken.Substring(7) # Remove "Bearer " prefix
    }
    Write-Host "Cleaned Authorization token: $authToken"

    $clientName = "Aigleclient.2017"
    $clientStatus = "Active"
    $client = GetOrCreate-Client -authToken $authToken -clientName $clientName -clientStatus $clientStatus

    if ($client) {
        Write-Host "Client $clientName processed successfully."

        $FTPUser = $env:FTP_USER
        $FTPPrivateKey = $env:FTP_PRIVATE_KEY
        $FTPServerHost = "preprodftp.windsoft.ro"
        $Directory = "/mnt/ftpdata/$clientName"

        $buildFiles = List-FTPFiles -FTPUser $FTPUser -FTPPrivateKey $FTPPrivateKey -FTPServerHost $FTPServerHost -Directory $Directory
        if ($buildFiles.Count -gt 0) {
            Write-Host "Found build files: $($buildFiles -join ', ')"
            $latestBuild, $version = Get-LatestBuildFile -buildFiles $buildFiles
            if ($latestBuild) {
                $productName = "Aigle1"  # Hardcoded for now, can be dynamic
                $product = GetOrCreate-Product -authToken $authToken -clientName $clientName -productName $productName -latestZipFile $latestBuild -version $version
                Write-Host "Processed product: $product"
            } else {
                Write-Host "No valid build files found."
            }
        } else {
            Write-Host "No build files found on the FTP server."
        }
    } else {
        Write-Host "Failed to process client, exiting."
    }
} else {
    Write-Host "Login failed, exiting."
}

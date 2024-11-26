# Function to login and retrieve the token from response headers
function Login {
    $url = "https://preprodapi.syncnotifyhub.windsoft.ro/api/User/login"
    $loginCredentials = @{
        email    = "test.admin@windsoft.ro"
        Password = "testpasswordadmin"
    }
    # Convert the credentials to JSON format
    $jsonBody = $loginCredentials | ConvertTo-Json
    try {
        # Send the POST request and capture the entire response (including status code and headers)
        $response = Invoke-WebRequest -Uri $url -Method Post -Body $jsonBody -ContentType "application/json" -ErrorAction Stop

        # Capture the HTTP status code
        $statusCode = $response.StatusCode
        Write-Host "Response status code: $statusCode"

        # Check if the response contains headers
        if ($response.Headers["Authorization"]) {
            $authToken = $response.Headers["Authorization"]
            Write-Host "Login successful! Authorization token: $authToken"
            return $authToken
        } else {
            Write-Host "Login failed: No Authorization header found in response headers."
            return $null
        }
    } catch {
        Write-Host "Login failed: $($_.Exception.Message)"
        return $null
    }
}

# Function to check if the client exists and return the client object
function Get-Client {
    param (
        [string]$authToken,
        [string]$clientName
    )

    $url = "https://preprodapi.syncnotifyhub.windsoft.ro/api/Client"
    $headers = @{
        "Authorization" = "Bearer $authToken"
    }

    try {
        Write-Host "Sending request to fetch client details..."
        $response = Invoke-WebRequest -Uri $url -Method Get -Headers $headers -ContentType "application/json" -ErrorAction Stop
        Write-Host "Response status code: $($response.StatusCode)"
        Write-Host "Response body: $($response.Content)"

        # If the request is successful, check if the client exists
        if ($response.StatusCode -eq 200) {
            $clients = $response.Content | ConvertFrom-Json
            foreach ($client in $clients) {
                if ($client.clientName -eq $clientName) {
                    Write-Host "Client $clientName found."
                    return $client
                }
            }
            Write-Host "Client $clientName not found."
            return $null
        } else {
            Write-Host "Failed to fetch client details. Status Code: $($response.StatusCode)"
            return $null
        }
    } catch {
        Write-Host "Error fetching client details: $($_.Exception.Message)"
        return $null
    }
}

# Function to create a client if it doesn't exist
function Create-Client {
    param (
        [string]$authToken,
        [string]$clientName,
        [string]$clientStatus
    )

    $url = "https://preprodapi.syncnotifyhub.windsoft.ro/api/Client"
    $headers = @{
        "Authorization" = "Bearer $authToken"
    }

    $body = @{
        clientName = $clientName
        clientStatus = $clientStatus
    } | ConvertTo-Json

    try {
        Write-Host "Creating client: $clientName..."
        $response = Invoke-WebRequest -Uri $url -Method Post -Headers $headers -Body $body -ContentType "application/json" -ErrorAction Stop
        Write-Host "Response status code: $($response.StatusCode)"
        Write-Host "Response body: $($response.Content)"
        if ($response.StatusCode -eq 201) {
            Write-Host "Client $clientName created successfully."
            return $response.Content | ConvertFrom-Json
        } else {
            Write-Host "Failed to create client. Status Code: $($response.StatusCode)"
            Write-Host "Response body: $($response.Content)"
        }
    } catch {
        Write-Host "Error creating client: $($_.Exception.Message)"
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

    # Create SSH directory for storing the private key
    $sshDir = "$env:USERPROFILE\.ssh"
    if (-not (Test-Path $sshDir)) {
        New-Item -ItemType Directory -Path $sshDir
    }

    # Save the private key to a file
    $privateKeyPath = "$sshDir\id_rsa"
    Set-Content -Path $privateKeyPath -Value $FTPPrivateKey -Force
    # Set correct permissions for the private key file
    icacls $privateKeyPath /inheritance:r /grant:r "$($env:USERNAME):(R)"

    # Add the FTP server's SSH fingerprint to known_hosts
    $knownHostsPath = "$sshDir\known_hosts"
    if (-not (Test-Path $knownHostsPath)) {
        New-Item -ItemType File -Path $knownHostsPath -Force
    }

    # Fetch the SSH fingerprint of the FTP server and append it to known_hosts
    ssh-keyscan -H $FTPServerHost | Out-File -Append -FilePath $knownHostsPath
    # SSH command to list files in the directory
    $sshCommand = "ssh -i $privateKeyPath -o StrictHostKeyChecking=no $FTPUser@$FTPServerHost 'ls $Directory'"
    Write-Host "Running SSH command: $sshCommand"

    # Execute the SSH command and capture the output
    $result = Invoke-Expression $sshCommand

    if ($result) {
        Write-Host "SSH connection successful. Listing files in ${Directory}:"
        return $result.Split("`n") | Where-Object { $_ -ne "" }  # Split by line and remove empty lines
    } else {
        Write-Host "Failed to connect to the FTP server or list files."
        return $null
    }

    # Clean up by removing the private key file after use
    Remove-Item $privateKeyPath -Force
}

# Function to get the latest build file from the list of files
function Get-LatestBuildFile {
    param (
        [array]$buildFiles
    )

    # Updated regex to match both 3-part and 4-part versions (e.g., 2.0.0 or 2.0.0.1)
    $regex = 'Hard_WindNet_(\d+\.\d+\.\d+(\.\d+)?)_\d{14}\.zip'

    # Try to match the latest build file
    $latestBuild = $buildFiles | Where-Object { $_ -match $regex }
    if ($latestBuild) {
        # Extract version (3 or 4 parts)
        $version = ($latestBuild -replace 'Hard_WindNet_(\d+\.\d+\.\d+(\.\d+)?)_\d{14}\.zip', '$1')
        Write-Host "Found latest build: $latestBuild with version: $version"
        return $latestBuild, $version
    } else {
        Write-Host "No valid build files found."
        return $null, $null
    }
}

# Refactored function to check if the product exists or create it if it doesn't
function Get-ProductOrCreate {
    param (
        [string]$authToken,
        [object]$client,
        [string]$latestZipFile,
        [string]$version
    )

    $url = "https://preprodapi.syncnotifyhub.windsoft.ro/api/Product"
    $headers = @{
        "Authorization" = "Bearer $authToken"
    }

    # Ensure product name doesn't have spaces
    $productName = "Aigle1"  # Hardcoded for now, can be dynamic if required
    $clientName = $client.clientName -replace '\s', ''  # Remove spaces from client name

    $body = @{
        productName  = $productName
        client       = $client  # Pass the client object here
        version      = $version
        latestVersion = $latestZipFile
    } | ConvertTo-Json -Depth 3  # Increase depth for nested client object

    Write-Host "Checking if product $productName exists for client $clientName..."
    
    try {
        # Attempt to create or check the product
        $response = Invoke-WebRequest -Uri $url -Method Post -Headers $headers -Body $body -ContentType "application/json" -ErrorAction Stop

        # If the status code is 201, product is created successfully
        if ($response.StatusCode -eq 201) {
            Write-Host "Product $($body.productName) created successfully."
            return $response.Content | ConvertFrom-Json
        }
        # If status code is 200, it means the product already exists (common with duplicate errors)
        elseif ($response.StatusCode -eq 200) {
            Write-Host "Product $($body.productName) already exists."
            return $response.Content | ConvertFrom-Json
        }
        else {
            Write-Host "Unexpected response: $($response.StatusCode)"
            Write-Host "Response body: $($response.Content)"
            return $null
        }
    } catch {
        Write-Host "Error checking or creating product: $($_.Exception.Message)"
        return $null
    }
}

# Main execution block
$authToken = Login
if ($authToken) {
    # Get client or create if necessary
    $clientName = "ClientExample"
    $client = Get-Client -authToken $authToken -clientName $clientName
    if (-not $client) {
        $client = Create-Client -authToken $authToken -clientName $clientName -clientStatus "Active"
    }

    # Get build files from FTP
    $FTPServerHost = "preprodftp.windsoft.ro"
    $FTPUser = $env:FTP_USER
    $FTPPrivateKey = $env:FTP_PRIVATE_KEY
    $buildFiles = List-FTPFiles -FTPUser $FTPUser -FTPPrivateKey $FTPPrivateKey -FTPServerHost $FTPServerHost -Directory "/builds"

    # Get the latest build file
    $latestZipFile, $version = Get-LatestBuildFile -buildFiles $buildFiles
    if ($latestZipFile -and $version) {
        # Check or create the product
        $product = Get-ProductOrCreate -authToken $authToken -client $client -latestZipFile $latestZipFile -version $version
    }
}

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

# Function to get or create a client
function GetOrCreate-Client {
    param (
        [string]$authToken,
        [string]$clientName,
        [string]$clientStatus
    )
    $url = "https://preprodapi.syncnotifyhub.windsoft.ro/api/Client"
    $headers = @{
        "Authorization" = "Bearer $authToken"
    }
    try {
        # Send the GET request to check if the client exists
        $response = Invoke-WebRequest -Uri $url -Method Get -Headers $headers -ContentType "application/json" -ErrorAction Stop
        Write-Host "Response status code: $($response.StatusCode)"
        Write-Host "Response body: $($response.Content)"
        if ($response.StatusCode -eq 200) {
            # Parse the response to check if the client exists
            $clients = $response.Content | ConvertFrom-Json
            $client = $clients | Where-Object { $_.clientName -eq $clientName }

            if ($client) {
                Write-Host "Client $clientName found."
                return $client
            } else {
                Write-Host "Client $clientName not found. Creating the client..."
                # Client doesn't exist, create it
                $body = @{
                    clientName  = $clientName
                    clientStatus = $clientStatus
                } | ConvertTo-Json
                # Send POST request to create the client
                $createResponse = Invoke-WebRequest -Uri $url -Method Post -Headers $headers -Body $body -ContentType "application/json" -ErrorAction Stop
                Write-Host "Create response status code: $($createResponse.StatusCode)"
                Write-Host "Create response body: $($createResponse.Content)"
                if ($createResponse.StatusCode -eq 201) {
                    Write-Host "Client $clientName created successfully."
                    return $createResponse.Content | ConvertFrom-Json
                } else {
                    Write-Host "Failed to create client. Status Code: $($createResponse.StatusCode)"
                    Write-Host "Response body: $($createResponse.Content)"
                    return $null
                }
            }
        } else {
            Write-Host "Failed to fetch client details. Status Code: $($response.StatusCode)"
            return $null
        }
    } catch {
        Write-Host "Error fetching or creating client details: $($_.Exception.Message)"
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
    $sshCommand = "ssh -i $privateKeyPath -o StrictHostKeyChecking=no $FTPUser@$FTPServerHost 'ls -l $Directory'"
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
    # Regex to match the timestamps and filenames
    $regex = '(\w+\s\d+\s\d{2}:\d{2})\s+(.+\.zip)'  # Matches timestamp and filename
    # Initialize variables to track the latest file and timestamp
    $latestTimestamp = [datetime]::MinValue
    $latestFile = $null
    foreach ($file in $buildFiles) {
        if ($file -match $regex) {
            # Extract the timestamp and filename
            $timestampStr = $matches[1]  # e.g., "Nov 26 07:50"
            $filename = $matches[2]      # e.g., "Hard_WindNet_1.0.0810.1625.zip"
            # Parse the timestamp into a DateTime object
            try {
                $timestamp = [datetime]::ParseExact($timestampStr, 'MMM dd HH:mm', $null)
                Write-Host "Parsed timestamp: $timestamp for file: $filename"  # Debugging
            } catch {
                Write-Host "Error parsing timestamp: $timestampStr for file: $filename"
                continue
            }
            # Compare timestamps to find the latest file
            if ($timestamp -gt $latestTimestamp) {
                $latestTimestamp = $timestamp
                $latestFile = $filename
            }
        }
    }
    # Return the latest file and timestamp
    if ($latestFile) {
        Write-Host "Found latest build: $latestFile with timestamp: $latestTimestamp"
        return $latestFile
    } else {
        Write-Host "No valid build files found."
        return $null
    }
}

# Function to get or create the product
function Create-Product {
    param (
        [string]$authToken,
        [object]$client,
        [string]$latestZipFile,
        [string]$version,
        [string]$productName
    )
    $url = "https://preprodapi.syncnotifyhub.windsoft.ro/api/Product"
    $headers = @{
        "Authorization" = "Bearer $authToken"
    }
    # Ensure product name doesn't have spaces
    $productName = $productName -replace '\s', ''
    # If version is not provided, extract it from the latestZipFile (e.g., "Hard_WindNet_125.zip")
    if (-not $version) {
        $version = $latestZipFile -replace ".*_(\d+)\.zip", '$1'  # Extract the version number from the filename
    }
    # Debugging: Print the request body to check its structure
    Write-Host "Request Body: $body"
    $body = @{
        productName  = $productName
        client       = $client  # Pass the client object here
        version      = $version  # Ensure version is set
        latestVersion = $latestZipFile
    } | ConvertTo-Json
    try {
        # Check if the product exists
        $getResponse = Invoke-WebRequest -Uri $url -Method Get -Headers $headers -ContentType "application/json" -ErrorAction Stop
        if ($getResponse.StatusCode -eq 200) {
            # Parse the response to check if the product exists
            $products = $getResponse.Content | ConvertFrom-Json
            foreach ($product in $products) {
                if ($product.productName -eq $productName) {
                    Write-Host "Product $productName found."
                    return $product
                }
            }
        }
        # If the product doesn't exist, create it
        Write-Host "Product $productName not found. Creating the product..."
        $createResponse = Invoke-WebRequest -Uri $url -Method Post -Headers $headers -Body $body -ContentType "application/json" -ErrorAction Stop
        # Debugging: Print the response from the creation request
        Write-Host "Create Product Response Status Code: $($createResponse.StatusCode)"
        Write-Host "Create Product Response Body: $($createResponse.Content)"
        if ($createResponse.StatusCode -eq 201) {
            Write-Host "Product created successfully!"
            return $createResponse.Content | ConvertFrom-Json
        } else {
            Write-Host "Failed to create product. Status Code: $($createResponse.StatusCode)"
            Write-Host "Response Content: $($createResponse.Content)"
            return $null
        }
    } catch {
        Write-Host "Error creating product: $($_.Exception.Message)"
        Write-Host "Error details: $($_.Exception.Response)"
        return $null
    }
}

# Main script logic
$authToken = Login
if ($authToken) {
    $authToken = $authToken.Trim()
    if ($authToken.StartsWith("Bearer ")) {
        $authToken = $authToken.Substring(7)
    }

    Write-Host "Cleaned Authorization token: $authToken"
    $clientName = "Aigleclient.2017"
    $clientStatus = "Active"
    # Step 1: Get or create the client
    $client = GetOrCreate-Client -authToken $authToken -clientName $clientName -clientStatus $clientStatus
    if (-not $client) {
        Write-Host "Failed to get or create client, exiting."
        return  # Exit if client creation fails
    }
    # Step 2: List build files from the FTP server
    $FTPServerHost = "preprodftp.windsoft.ro"
    $FTPUser = $env:FTP_USER
    $FTPPrivateKey = $env:FTP_PRIVATE_KEY
    $Directory = "/mnt/ftpdata/$clientName"
    $buildFiles = List-FTPFiles -FTPUser $FTPUser -FTPPrivateKey $FTPPrivateKey -FTPServerHost $FTPServerHost -Directory $Directory
    if (-not $buildFiles) {
        Write-Host "No build files found, exiting."
        return
    }
    # Step 3: Get the latest build file
    $latestZipFile, $version = Get-LatestBuildFile -buildFiles $buildFiles
    if (-not $latestZipFile) {
        Write-Host "No valid build files found, exiting."
        return
    }
    # Step 4: Create the product if it doesn't exist
    $product = Create-Product -authToken $authToken -client $client -latestZipFile $latestZipFile -version $version -productName "Aigle1"
}

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

# Function to get or create the product
# Function to get or create the product
function GetOrCreate-Product {
    param (
        [string]$authToken,
        [string]$clientName,
        [string]$productName,
        [string]$latestZipFile,
        [string]$version
    )

    $url = "https://preprodapi.syncnotifyhub.windsoft.ro/api/Product"
    $headers = @{
        "Authorization" = "Bearer $authToken"
    }

    try {
        # Send the GET request to check if the product exists
        Write-Host "Sending request to fetch product details..."
        $response = Invoke-WebRequest -Uri $url -Method Get -Headers $headers -ContentType "application/json" -ErrorAction Stop

        Write-Host "Response status code: $($response.StatusCode)"
        Write-Host "Response body: $($response.Content)"

        if ($response.StatusCode -eq 200) {
            # Parse the response to check if the product exists
            $products = $response.Content | ConvertFrom-Json
            $product = $products | Where-Object { $_.productName -eq $productName }

            if ($product) {
                Write-Host "Product $productName found."
                return $product
            } else {
                Write-Host "Product $productName not found. Creating the product..."
            }
        }

        # If the product was not found, create the product
        # Prepare the product creation request body
        $body = @{
            productName  = $productName
            clientName   = $clientName  # Assuming we pass the client name in the product creation
            version      = $version
            latestVersion = $latestZipFile
        } | ConvertTo-Json

        Write-Host "Creating product with the following data:"
        Write-Host $body

        # Send the POST request to create the product
        $createResponse = Invoke-WebRequest -Uri $url -Method Post -Headers $headers -Body $body -ContentType "application/json" -ErrorAction Stop

        Write-Host "Create response status code: $($createResponse.StatusCode)"
        Write-Host "Create response body: $($createResponse.Content)"

        if ($createResponse.StatusCode -eq 201) {
            Write-Host "Product $productName created successfully."
            return $createResponse.Content | ConvertFrom-Json
        } else {
            Write-Host "Failed to create product. Status Code: $($createResponse.StatusCode)"
            Write-Host "Response body: $($createResponse.Content)"
            return $null
        }
    } catch {
        Write-Host "Error fetching or creating product: $($_.Exception.Message)"
        if ($_.Exception.Response) {
            $errorResponse = $_.Exception.Response.GetResponseStream()
            $reader = New-Object System.IO.StreamReader($errorResponse)
            $errorBody = $reader.ReadToEnd()
            Write-Host "Detailed error response: $errorBody"
        }
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

    # Step 4: Get or create the product
    $product = GetOrCreate-Product -authToken $authToken -clientName $clientName -productName "Aigle1" -latestZipFile $latestZipFile -version $version
    if ($product) {
        Write-Host "Product operation completed successfully."
    } else {
        Write-Host "Product creation or fetching failed."
    }
}

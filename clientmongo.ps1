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

# Function to get or create client
function Get-OrCreate-Client {
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
        Write-Host "Checking if client exists..."

        # First, try to fetch the client details
        $response = Invoke-WebRequest -Uri "$url?clientName=$clientName" -Method Get -Headers $headers -ContentType "application/json" -ErrorAction Stop
        Write-Host "Response status code: $($response.StatusCode)"
        $clients = $response.Content | ConvertFrom-Json

        # If the client exists
        foreach ($client in $clients) {
            if ($client.clientName -eq $clientName) {
                Write-Host "Client $clientName found."
                return $client
            }
        }

        Write-Host "Client $clientName not found. Creating the client..."
        
        # If the client is not found, create it
        $body = @{
            clientName  = $clientName
            clientStatus = $clientStatus
        } | ConvertTo-Json

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
        Write-Host "Error: $($_.Exception.Message)"
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

# Function to get the product details
function Get-Product {
    param (
        [string]$authToken,
        [string]$clientName,
        [string]$productName
    )

    $url = "https://preprodapi.syncnotifyhub.windsoft.ro/api/Product"
    $headers = @{
        "Authorization" = "Bearer $authToken"
    }

    try {
        Write-Host "Sending request to fetch product details..."

        $response = Invoke-WebRequest -Uri $url -Method Get -Headers $headers -ContentType "application/json" -ErrorAction Stop

        Write-Host "Response status code: $($response.StatusCode)"
        Write-Host "Response body: $($response.Content)"

        # If the request is successful, check if the product exists
        if ($response.StatusCode -eq 200) {
            $products = $response.Content | ConvertFrom-Json
            foreach ($product in $products) {
                if ($product.productName -eq $productName) {
                    Write-Host "Product $productName found."
                    return $product
                }
            }
            Write-Host "Product $productName not found."
            return $null
        } else {
            Write-Host "Failed to fetch product details. Status Code: $($response.StatusCode)"
            return $null
        }
    } catch {
        Write-Host "Error fetching product details: $($_.Exception.Message)"
        return $null
    }
}

# Function to create a product
function Create-Product {
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

    Write-Host "Creating product with the following details:"
    Write-Host "Product: $($body.productName)"
    Write-Host "Client: $($body.client.clientName)"
    Write-Host "Version: $($body.version)"
    Write-Host "Latest ZIP: $($body.latestVersion)"
    
    # Send POST request to create the product
    $response = Invoke-WebRequest -Uri $url -Method Post -Headers $headers -Body $body -ContentType "application/json" -ErrorAction Stop

    if ($response.StatusCode -eq 201) {
        Write-Host "Product created successfully!"
        return $response.Content | ConvertFrom-Json
    } else {
        Write-Host "Failed to create product. Status Code: $($response.StatusCode)"
        Write-Host "Response: $($response.Content)"
    }
}

# Main script logic
$authToken = Login

if ($authToken) {
    # Clean up any extra spaces or characters from the token
    $authToken = $authToken.Trim()

    # Ensure the token has no extra characters
    if ($authToken.StartsWith("Bearer ")) {
        $authToken = $authToken.Substring(7) # Remove "Bearer " prefix
    }

    Write-Host "Cleaned Authorization token: $authToken"

    $clientName = "Aigleclient.2017"
    $clientStatus = "Active"

    # Step 1: Get or Create the client
    $client = Get-OrCreate-Client -authToken $authToken -clientName $clientName -clientStatus $clientStatus

    if (-not $client) {
        Write-Host "Failed to get or create client, exiting."
        return  # Exit the script if client creation fails
    } else {
        Write-Host "Client $clientName found or created."
    }

    # Step 2: List build files from FTP
    $FTPUser = $env:FTP_USER
    $FTPPrivateKey = $env:FTP_PRIVATE_KEY
    $FTPServerHost = "preprodftp.windsoft.ro"
    $Directory = "/mnt/ftpdata/$clientName"

    $buildFiles = List-FTPFiles -FTPUser $FTPUser -FTPPrivateKey $FTPPrivateKey -FTPServerHost $FTPServerHost -Directory $Directory

    if ($buildFiles) {
        # Step 3: Get the latest build file
        $latestBuildFile, $latestVersion = Get-LatestBuildFile -buildFiles $buildFiles

        if ($latestBuildFile) {
            Write-Host "Latest build file: $latestBuildFile"
            Write-Host "Version: $latestVersion"

            # Step 4: Get product details
            $productName = "AigleProduct"  # Example product name
            $product = Get-Product -authToken $authToken -clientName $clientName -productName $productName

            if ($product) {
                # Step 5: Create a new product (or update it if needed)
                $newProduct = Create-Product -authToken $authToken -client $client -latestZipFile $latestBuildFile -version $latestVersion
            }
        }
    }
} else {
    Write-Host "Login failed, exiting."
}

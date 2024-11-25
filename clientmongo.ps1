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

# Helper Function to Create Client
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

    # Define the client details
    $clientBody = @{
        clientName  = $clientName
        clientStatus = $clientStatus
    } | ConvertTo-Json

    try {
        Write-Host "Creating client with the following details:"
        Write-Host "Client Name: $clientName"
        Write-Host "Client Status: $clientStatus"

        # Send the POST request to create the client
        $response = Invoke-WebRequest -Uri $url -Method Post -Headers $headers -Body $clientBody -ContentType "application/json" -ErrorAction Stop       

        Write-Host "Response status code: $($response.StatusCode)"
        Write-Host "Response body: $($response.Content)"

        if ($response.StatusCode -eq 201) {
            Write-Host "Client $clientName created successfully."
            return $response.Content | ConvertFrom-Json
        } else {
            Write-Host "Failed to create client. Status Code: $($response.StatusCode)"
            Write-Host "Response body: $($response.Content)"
            return $null
        }
    } catch {
        Write-Host "Error creating client: $($_.Exception.Message)"
        return $null
    }
}

# Function to check if the product exists and return the product object
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
        Write-Host "Sending request to fetch product details for $productName..."

        $response = Invoke-WebRequest -Uri $url -Method Get -Headers $headers -ContentType "application/json" -ErrorAction Stop

        Write-Host "Response status code: $($response.StatusCode)"
        Write-Host "Response body: $($response.Content)"

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

# Helper Function to Create Product
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
    Write-Host "Latest ZIP File: $($body.latestVersion)"

    try {
        # Send the POST request to create the product
        $response = Invoke-WebRequest -Uri $url -Method Post -Headers $headers -Body $body -ContentType "application/json" -ErrorAction Stop

        Write-Host "Response status code: $($response.StatusCode)"
        Write-Host "Response body: $($response.Content)"

        if ($response.StatusCode -eq 201) {
            Write-Host "Product $($body.productName) created successfully."
            return $response.Content | ConvertFrom-Json
        } else {
            Write-Host "Failed to create product. Status Code: $($response.StatusCode)"
            Write-Host "Response body: $($response.Content)"
        }
    } catch {
        Write-Host "Error creating product: $($_.Exception.Message)"
    }
}

# Function to get the latest build from FTP server using SSH
function Get-BuildFiles {
    $remoteDirectory = "/mnt/ftpdata/$clientName"
    $privateKeyPath = "pri.key"
    $sshUser = $env:FTP_USER
    $sshHost = "preprodftp.windsoft.ro"
    $buildFiles = @()

    try {
        # Fetch list of files from remote directory using SSH
        $command = "ssh -i $privateKeyPath -o StrictHostKeyChecking=no $sshUser@$sshHost 'ls $remoteDirectory'"
        $output = Invoke-Expression $command
        $buildFiles = $output -split "`n"

        # Return the list of build files
        Write-Host "Build files fetched from FTP server:"
        $buildFiles | ForEach-Object { Write-Host $_ }

        return $buildFiles
    } catch {
        Write-Host "Error fetching build files from FTP server: $($_.Exception.Message)"
        return @()
    }
}

# Function to get the latest build from the fetched files
function Get-LatestBuild {
    param (
        [array]$buildFiles
    )

    # Extract the latest build (in this case, the file with the most recent date)
    $latestBuild = $buildFiles | Sort-Object { [datetime]::ParseExact($_, 'yyyy-MM-dd_HH-mm-ss', $null) } -Descending | Select-Object -First 1
    Write-Host "Latest build: $latestBuild"

    return $latestBuild
}

# Main logic
$authToken = Login
if ($authToken) {
    $client = Get-Client -authToken $authToken -clientName "Aigle"
    if (-not $client) {
        $client = Create-Client -authToken $authToken -clientName "Aigle" -clientStatus "Active"
    }

    $product = Get-Product -authToken $authToken -clientName $client.clientName -productName "Aigle1"
    if (-not $product) {
        $product = Create-Product -authToken $authToken -client $client -latestZipFile "example.zip" -version "1.0.0"
    }

    $buildFiles = Get-BuildFiles
    if ($buildFiles.Count -gt 0) {
        $latestBuild = Get-LatestBuild -buildFiles $buildFiles
        Write-Host "Latest build: $latestBuild"
    }
}

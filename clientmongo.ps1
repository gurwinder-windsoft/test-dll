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

# Helper Function to fetch files from FTP using SSH/SFTP
function Get-BuildFilesFromFTP {
    param (
        [string]$hostName,
        [string]$userName,
        [string]$privateKeyPath,
        [string]$remoteDir
    )

    # Use the `ssh` command to list files from the FTP server
    Write-Host "Listing files from remote FTP directory $remoteDir..."

    try {
        # Run the ssh command to list files on the FTP server
        $command = "ssh -i $privateKeyPath -o StrictHostKeyChecking=no $userName@$hostName 'ls $remoteDir'"
        $result = Invoke-Expression $command

        Write-Host "Files found on the FTP server:"
        Write-Host $result
        return $result -split "`n" | Where-Object { $_ -match ".*\.zip$" }  # Return only zip files
    } catch {
        Write-Host "Error fetching files from FTP server: $($_.Exception.Message)"
        return $null
    }
}

# Helper function to get the latest build file from the list
function Get-LatestBuildFile {
    param (
        [array]$buildFiles
    )

    # Regex to match zip files (assuming zip files for build)
    $regex = 'Hard_WindNet_(\d+\.\d+\.\d+(\.\d+)?)_\d{14}\.zip'

    # Find the latest build
    $latestBuild = $buildFiles | Where-Object { $_ -match $regex } | Sort-Object { [version]$matches[1] } -Descending | Select-Object -First 1

    if ($latestBuild) {
        Write-Host "Found latest build: $latestBuild"
        return $latestBuild
    } else {
        Write-Host "No valid build files found."
        return $null
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

    # Step 1: Get the client details
    $client = Get-Client -authToken $authToken -clientName $clientName

    if (-not $client) {
        Write-Host "Client $clientName not found. Creating the client..."
        $client = Create-Client -authToken $authToken -clientName $clientName -clientStatus $clientStatus
        if (-not $client) {
            Write-Host "Failed to create client, exiting."
            return
        }
    }

    # Step 2: Fetch build files from FTP
    $hostName = "preprodftp.windsoft.ro"
    $userName = $env:FTP_USER
    $privateKeyPath = $env:FTP_PRIVATE_KEY
    $remoteDir = "/mnt/ftpdata/$clientName"

    $buildFiles = Get-BuildFilesFromFTP -hostName $hostName -userName $userName -privateKeyPath $privateKeyPath -remoteDir $remoteDir

    if ($buildFiles.Count -gt 0) {
        Write-Host "Found build files: $($buildFiles)"
        $latestBuild = Get-LatestBuildFile -buildFiles $buildFiles
        if ($latestBuild) {
            # Step 3: Get the product details
            $productName = "Aigle1"  # Hardcoded for now, can be dynamic
            $existingProduct = Get-Product -authToken $authToken -clientName $clientName -productName $productName

            if (-not $existingProduct) {
                Write-Host "Product $productName not found. Creating the product..."
                $product = Create-Product -authToken $authToken -client $client -latestZipFile $latestBuild -version "1.0.0"
                if ($product) {
                    Write-Host "Product $productName created successfully."
                } else {
                    Write-Host "Failed to create product. Exiting."
                    return
                }
            } else {
                Write-Host "Product $productName already exists for client $clientName."
            }
        } else {
            Write-Host "No valid build files found. Exiting."
        }
    } else {
        Write-Host "No files found on FTP server."
    }
} else {
    Write-Host "Authentication failed, exiting."
}

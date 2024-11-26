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

# Function to get the latest build from FTP server
function Get-LatestBuildFile {
    param (
        [array]$buildFiles
    )

    # Updated regex to match both 3-part and 4-part versions (e.g., 2.0.0 or 2.0.0.1)
    $regex = 'Hard_WindNet_(\d+\.\d+\.\d+(\.\d+)?)_\d{14}\.zip'

    # Try to match the latest build file
    $latestBuild = $buildFiles | Where-Object { $_.Name -match $regex }

    if ($latestBuild) {
        # Extract version (3 or 4 parts)
        $version = ($latestBuild.Name -replace 'Hard_WindNet_(\d+\.\d+\.\d+(\.\d+)?)_\d{14}\.zip', '$1')
        Write-Host "Found latest build: $($latestBuild.Name) with version: $version"
        return $latestBuild, $version
    } else {
        Write-Host "No valid build files found."
        return $null, $null
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

# Step 2: Connect to the FTP server using SSH (from GitHub Actions)
$ftpServer = "92.180.12.186"
$sshKeyPath = "$env:GITHUB_WORKSPACE\pri.key"
$ftpUser = $env:FTP_USER

# Ensure the SSH private key exists
if (-Not (Test-Path $sshKeyPath)) {
    Write-Host "SSH private key not found at: $sshKeyPath"
    exit 1
}

# Test SSH connection to FTP server
Write-Host "Testing SSH connection to FTP server..."

# Construct the ssh command and ensure $sshKeyPath is properly quoted
$sshCommand = "ssh -o StrictHostKeyChecking=no -i `"$sshKeyPath`" $ftpUser@$ftpServer ls"

# Debugging: Output the command to see how it is formed
Write-Host "SSH Command: $sshCommand"

# Run the SSH command
try {
    $result = Invoke-Expression $sshCommand

    # Check if the result contains any output
    if ($result) {
        Write-Host "SSH connection successful. Listing files on FTP server: $result"
    } else {
        Write-Host "SSH connection failed or no files returned."
    }
} catch {
    Write-Host "Failed to connect to FTP server. Error: $_"
}

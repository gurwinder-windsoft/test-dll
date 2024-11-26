# Function to login and retrieve the token from response headers
function Login {
    $url = "https://preprodapi.syncnotifyhub.windsoft.ro/api/User/login"
    $loginCredentials = @{
        email    = "test.admin@windsoft.ro"
        Password = "testpasswordadmin"
    }

    $jsonBody = $loginCredentials | ConvertTo-Json

    try {
        # Send the POST request and capture the entire response (including status code and headers)
        $response = Invoke-WebRequest -Uri $url -Method Post -Body $jsonBody -ContentType "application/json" -ErrorAction Stop

        $statusCode = $response.StatusCode
        Write-Host "Response status code: $statusCode"

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
            Write-Host "Response body: $($response.Content)"
            return $null
        }
    } catch {
        Write-Host "Error fetching client details: $($_.Exception.Message)"
        return $null
    }
}

# Function to create a new client
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

    $clientBody = @{
        clientName  = $clientName
        clientStatus = $clientStatus
    } | ConvertTo-Json

    try {
        Write-Host "Creating client with the following details:"
        Write-Host "Client Name: $clientName"
        Write-Host "Client Status: $clientStatus"

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

# Function to fetch build files from FTP server using SSH
# Load the SSH.NET library
Add-Type -Path "C:\Program Files\PackageManagement\NuGet\Packages\SSH.NET.2016.1.0\lib\net45\Renci.SshNet.dll"

# Function to create an SSH connection and execute a command
function Execute-SSHCommand {
    param (
        [string]$host,
        [string]$user,
        [string]$privateKeyPath,
        [string]$command
    )

    # Create a new SSH client
    $sshClient = New-Object Renci.SshNet.SshClient($host, $user, [Renci.SshNet.PrivateKeyFile]::new($privateKeyPath))
    
    try {
        # Connect to the SSH server
        $sshClient.Connect()
        
        # Execute the command
        $output = $sshClient.RunCommand($command)
        Write-Host "Output: $($output.Result)"
        
        # Disconnect the SSH session
        $sshClient.Disconnect()
    } catch {
        Write-Host "Error executing SSH command: $($_.Exception.Message)"
    }
}

# Parameters for SSH connection
$host = "92.180.12.186"
$user = $env:FTP_USER  # Ensure this environment variable is set in GitHub Actions
$privateKeyPath = "pri.key"  # Path to your private key
$command = "ls /mnt/ftpdata"  # Command to list files

# Execute the SSH command
Execute-SSHCommand -host $host -user $user -privateKeyPath $privateKeyPath -command $command

    $regex = 'Hard_WindNet_(\d+\.\d+\.\d+(\.\d+)?)_\d{14}\.zip'

    $latestBuild = $buildFiles | Where-Object { $_ -match $regex }

    if ($latestBuild) {
        $version = ($latestBuild -replace 'Hard_WindNet_(\d+\.\d+\.\d+(\.\d+)?)_\d{14}\.zip', '$1')
        Write-Host "Found latest build: $($latestBuild) with version: $version"
        return $latestBuild, $version
    } else {
        Write-Host "No valid build files found."
        return $null, $null
    }
}

# Main script execution
$authToken = Login

if ($authToken) {
    $authToken = $authToken.Trim()

    if ($authToken.StartsWith("Bearer ")) {
        $authToken = $authToken.Substring(7) # Remove "Bearer " prefix
    }

    Write-Host "Cleaned Authorization token: $authToken"

    $clientName = "Aigleclient.2017"
    $clientStatus = "Active"

    $client = Get-Client -authToken $authToken -clientName $clientName

    if (-not $client) {
        Write-Host "Client $clientName not found. Creating the client..."
        $client = Create-Client -authToken $authToken -clientName $clientName -clientStatus $clientStatus
        if (-not $client) {
            Write-Host "Failed to create client, exiting."
            return
        }
    }

    $buildFiles = Get-BuildFiles

    if ($buildFiles.Count -gt 0) {
        $latestBuild, $version = Get-LatestBuildFile -buildFiles $buildFiles
        if ($latestBuild) {
            Write-Host "Latest build: $latestBuild with version: $version"
        } else {
            Write-Host "No valid build files found."
        }
    } else {
        Write-Host "No files found on FTP server."
    }
} else {
    Write-Host "Authorization failed. Exiting."
}

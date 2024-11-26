param (
    [string]$FTPUser,
    [string]$FTPPrivateKey,
    [string]$FTPServerHost
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

# Ensure SSH is available (if you're on Windows)
$sshAvailable = Get-Command ssh -ErrorAction SilentlyContinue
if (-not $sshAvailable) {
    Write-Host "SSH is not installed on this machine."
    exit 1
}

# Add the FTP server's SSH fingerprint to known_hosts
$knownHostsPath = "$sshDir\known_hosts"
if (-not (Test-Path $knownHostsPath)) {
    New-Item -ItemType File -Path $knownHostsPath -Force
}

# Fetch the SSH fingerprint of the FTP server and append it to known_hosts
ssh-keyscan -H $FTPServerHost | Out-File -Append -FilePath $knownHostsPath

# Test SSH connection to the FTP server
Write-Host "Testing SSH connection to $FTPServerHost..."
$sshCommand = "ssh -i $privateKeyPath -o StrictHostKeyChecking=no $FTPUser@$FTPServerHost 'ls /mnt/ftpdata/Aigleclient.2017/'"
Write-Host "Running SSH command: $sshCommand"

# Execute the SSH command and capture the output
$result = Invoke-Expression $sshCommand

if ($result) {
    Write-Host "SSH connection successful. Listing files in /mnt/ftpdata/Aigleclient.2017/:"
    Write-Host $result
} else {
    Write-Host "Failed to connect to the FTP server or list files."
}

# Clean up by removing the private key file after use
Remove-Item $privateKeyPath -Force

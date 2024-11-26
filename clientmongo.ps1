param (
    [string]$FTPUser,
    [string]$FTPPrivateKey,
    [string]$FTPServerHost
)

# Ensure the .ssh directory exists
$sshDir = "$env:USERPROFILE\.ssh"
if (-not (Test-Path $sshDir)) {
    New-Item -ItemType Directory -Path $sshDir
}

# Set the private key path and save the private key
$privateKeyPath = "$sshDir\id_rsa"
$FTPPrivateKey | Set-Content -Path $privateKeyPath -Force

# Ensure SSH is available
if (-not (Get-Command ssh -ErrorAction SilentlyContinue)) {
    Write-Host "SSH is not installed."
    exit 1
}

# Add the FTP server's SSH fingerprint to known_hosts (if not already present)
$knownHostsPath = "$sshDir\known_hosts"
if (-not (Test-Path $knownHostsPath)) {
    New-Item -ItemType File -Path $knownHostsPath -Force
}
ssh-keyscan -H $FTPServerHost | Out-File -Append -FilePath $knownHostsPath

# Test SSH connection to the FTP server
Write-Host "Testing SSH connection to $FTPServerHost..."
$sshCommand = "ssh -i $privateKeyPath -o StrictHostKeyChecking=no $FTPUser@$FTPServerHost 'ls'"
$result = Invoke-Expression $sshCommand

if ($result) {
    Write-Host "SSH connection successful. Listing files on the FTP server:"
    Write-Host $result
} else {
    Write-Host "Failed to connect to the FTP server."
}

# Clean up by removing the private key file after use
Remove-Item $privateKeyPath -Force

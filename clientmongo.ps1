param (
    [string]$FTPUser,
    [string]$FTPPrivateKey,
    [string]$FTPServerHost
)

# Set the private key path and save it
$privateKeyPath = "$env:USERPROFILE\.ssh\id_rsa"
$FTPPrivateKey | Set-Content -Path $privateKeyPath -Force

# Ensure SSH is available
if (-not (Get-Command ssh -ErrorAction SilentlyContinue)) {
    Write-Host "SSH is not installed."
    exit 1
}

# Add the FTP server's SSH fingerprint to known_hosts (if not already present)
ssh-keyscan -H $FTPServerHost | Out-File -Append -FilePath "$env:USERPROFILE\.ssh\known_hosts"

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

# Define FTP credentials and connection details from GitHub secrets
$ftpUser = $env:FTP_USER
$ftpPrivateKeyPath = $env:PREPRODFTPKEY
$sshHostKeyFingerprint = $env:SSH_HOST_KEY_FINGERPRINT

# Define WinSCP assembly path and load it into PowerShell
$WinSCPAssemblyPath = "$env:TEMP\WinSCP\WinSCP.6.3.5\lib\netstandard2.0\WinSCPnet.dll"

# Ensure the assembly is loaded properly
if (Test-Path $WinSCPAssemblyPath) {
    Write-Host "Loading WinSCP .NET Assembly from: $WinSCPAssemblyPath"
    Add-Type -Path $WinSCPAssemblyPath
    Write-Host "WinSCP .NET Assembly loaded successfully."
} else {
    Write-Host "WinSCP .NET Assembly not found at the specified path."
    exit 1
}

# Define session options for FTP connection
essionOptions = New-Object WinSCP.SessionOptions
$sessionOptions.Protocol = [WinSCP.Protocol]::Sftp
$sessionOptions.HostName = "preprodftp.windsoft.ro"  # FTP Host Address
$sessionOptions.UserName = $env:FTP_USER  # FTP Username
$sessionOptions.SshPrivateKeyPath = $env:PREPRODFTPKEY  # Path to PEM Key
$sessionOptions.SshHostKeyFingerprint = $env:SSH_HOST_KEY_FINGERPRINT  # SSH Hos

# Check if the WinSCP executable exists
$WinSCPExecutablePath = "$env:TEMP\WinSCP\WinSCP.6.3.5\tools\WinSCP.exe"
if (Test-Path $WinSCPExecutablePath) {
    Write-Host "Found WinSCP executable at: $WinSCPExecutablePath"
} else {
    Write-Host "WinSCP executable not found at the expected location."
    exit 1
}

# Create an SFTP session object
$session = New-Object WinSCP.Session
$session.ExecutablePath = $WinSCPExecutablePath

# Open the session and interact with the FTP server
try {
    Write-Host "Opening SFTP session..."
    $session.Open($sessionOptions)
    Write-Host "Session opened successfully."

    # List the files in the directory
    $remoteFiles = $session.ListDirectory("/mnt/ftpdata/")
    Write-Host "Files found on FTP:"
    $remoteFiles.Files | ForEach-Object { Write-Host $_.Name }
} catch {
    Write-Host "Error: $($_.Exception.Message)"
} finally {
    $session.Dispose()
}

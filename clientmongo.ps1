# Define FTP credentials and connection details
$ftpUser = "your-ftp-username"  # FTP Username
$ftpPrivateKeyPath = "path-to-your-private-key.pem"  # Path to your private SSH key (PEM)
$sshHostKeyFingerprint = "your-ssh-host-key-fingerprint"  # SSH Host Key Fingerprint (replace with actual)

# Define WinSCP assembly path and load it into PowerShell
$WinSCPAssemblyPath = "path-to-WinSCPnet.dll"  # Update with the actual path of the WinSCPnet.dll file

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
$sessionOptions = New-Object WinSCP.SessionOptions
$sessionOptions.Protocol = [WinSCP.Protocol]::Sftp
$sessionOptions.HostName = "preprodftp.windsoft.ro"  # FTP Host Address
$sessionOptions.UserName = $ftpUser  # FTP Username
$sessionOptions.SshPrivateKeyPath = $ftpPrivateKeyPath  # Path to PEM Key
$sessionOptions.SshHostKeyFingerprint = $sshHostKeyFingerprint  # SSH Host Key Fingerprint

# Check if the WinSCP executable exists (this will be used for logging or other operations)
$WinSCPExecutablePath = "path-to-WinSCP.exe"  # Update with the actual path of WinSCP.exe
if (Test-Path $WinSCPExecutablePath) {
    Write-Host "Found WinSCP executable at: $WinSCPExecutablePath"
} else {
    Write-Host "WinSCP executable not found at the expected location."
    exit 1
}

# Create an SFTP session object
$session = New-Object WinSCP.Session
$session.ExecutablePath = $WinSCPExecutablePath

# Open the session and list the files in the directory
try {
    Write-Host "Opening SFTP session..."
    $session.Open($sessionOptions)
    Write-Host "Session opened successfully."

    # List the files in the remote directory
    $remoteFiles = $session.ListDirectory("/mnt/ftpdata/")  # Update with the correct remote directory
    Write-Host "Files found on FTP server:"
    
    # Display the file names
    $remoteFiles.Files | ForEach-Object { Write-Host $_.Name }
} catch {
    Write-Host "Error: $($_.Exception.Message)"
} finally {
    # Ensure to dispose of the session after the operation
    $session.Dispose()
}

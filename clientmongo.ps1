# Define FTP credentials and connection details
$ftpUser = $env:FTP_USER
$ftpPrivateKeyPath = $env:PREPRODFTPKEY
$sshHostKeyFingerprint = $env:SSH_HOST_KEY_FINGERPRINT  # SSH Host Key Fingerprint (replace with actual)

# Dynamically get the path of the WinSCP assembly (updated path from the latest log)
$WinSCPAssemblyPath = "C:\Users\runneradmin\AppData\Local\Temp\WinSCP\WinSCP.6.3.5\lib\net40\WinSCPnet.dll"  # Update with actual path

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

# Dynamically find the correct path for WinSCP.exe
$WinSCPExecutablePath = "C:\Users\runneradmin\AppData\Local\Temp\WinSCP\WinSCP.6.3.5\WinSCP.exe"  # Update with actual path
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

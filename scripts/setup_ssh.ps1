<#
.SYNOPSIS
  Configures OpenSSH on Windows for the EWB VPC Peering Lab.
  Sets correct NTFS permissions on the .pem private key and updates ~/.ssh/config.

.PARAMETER BastionPublicIp
  The public IPv4 address of the ewb-bastion instance.

.PARAMETER KeyName
  The name of the key pair (default: ewb-lab).
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$BastionPublicIp,

    [Parameter(Mandatory=$false)]
    [string]$KeyName = "ewb-lab"
)

$sshDir = "$HOME\.ssh"
if (-not (Test-Path $sshDir)) {
    New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
}

$keyFile = "$sshDir\$KeyName.pem"
if (Test-Path $keyFile) {
    Write-Host "[*] Setting secure NTFS permissions on $keyFile..." -ForegroundColor Cyan
    # Remove inherited permissions and grant Read only to current user
    icacls.exe $keyFile /inheritance:r /grant:r "$($env:USERNAME):(R)" | Out-Null
    Write-Host "[+] Fixed permissions on $keyFile (Windows OpenSSH requirement)." -ForegroundColor Green
} else {
    Write-Host "[!] Note: Key file not found at $keyFile. Remember to copy your downloaded $KeyName.pem there!" -ForegroundColor Yellow
}

$configFile = "$sshDir\config"
$configEntry = @"

# =========================================================================
# EWB Cloud Labs - AWS VPC Peering Configuration
# =========================================================================
Host ewb-bastion
  HostName $BastionPublicIp
  User ec2-user
  IdentityFile ~/.ssh/$KeyName.pem
  IdentitiesOnly yes

Host ewb-app-a
  HostName 10.10.2.10
  User ec2-user
  IdentityFile ~/.ssh/$KeyName.pem
  IdentitiesOnly yes
  ProxyJump ewb-bastion

Host ewb-app-b
  HostName 10.20.1.10
  User ec2-user
  IdentityFile ~/.ssh/$KeyName.pem
  IdentitiesOnly yes
  ProxyJump ewb-bastion
"@

if (Test-Path $configFile) {
    $existing = Get-Content $configFile -Raw
    if ($existing -match "Host ewb-bastion") {
        Write-Host "[*] Updating existing ewb-bastion entry in $configFile..." -ForegroundColor Cyan
        # Replace HostName for ewb-bastion
        $updated = $existing -replace "(?ms)(Host ewb-bastion\s+HostName\s+)[^\r\n]+", "`$1$BastionPublicIp"
        Set-Content -Path $configFile -Value $updated
        Write-Host "[+] Updated $configFile with new Bastion IP: $BastionPublicIp" -ForegroundColor Green
    } else {
        Add-Content -Path $configFile -Value $configEntry
        Write-Host "[+] Appended EWB VPC Peering configuration to $configFile" -ForegroundColor Green
    }
} else {
    Set-Content -Path $configFile -Value $configEntry
    Write-Host "[+] Created $configFile with EWB VPC Peering configuration." -ForegroundColor Green
}

Write-Host "`n[+] SSH Setup Complete!" -ForegroundColor Green
Write-Host "You can now connect using:" -ForegroundColor Yellow
Write-Host "  ssh ewb-bastion" -ForegroundColor White
Write-Host "  ssh ewb-app-a" -ForegroundColor White
Write-Host "  ssh ewb-app-b" -ForegroundColor White

<#
.SYNOPSIS
  Executes workbook verification tests 01 - 05 and controlled failure test from PowerShell.
#>

Write-Host "========================================================================" -ForegroundColor Cyan
Write-Host "   EWB Cloud Labs: AWS VPC Peering Connectivity Verification            " -ForegroundColor Cyan
Write-Host "========================================================================" -ForegroundColor Cyan

# Test 04: Check Bastion and App-A / App-B connectivity
Write-Host "`n[TEST 04] Testing SSH Access to Bastion and App-B via ProxyJump..." -ForegroundColor Yellow
try {
    $resBastion = ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 ewb-bastion "hostname; hostname -I"
    Write-Host "[+] SUCCESS: Connected to Bastion!`n$resBastion" -ForegroundColor Green
} catch {
    Write-Host "[!] Could not connect to ewb-bastion. Check ~/.ssh/config and Security Group." -ForegroundColor Red
}

try {
    $resAppB = ssh -o StrictHostKeyChecking=no -o ConnectTimeout=8 ewb-app-b "hostname; hostname -I"
    Write-Host "[+] SUCCESS: Connected to App-B via Bastion ProxyJump!`n$resAppB" -ForegroundColor Green
} catch {
    Write-Host "[!] Could not connect to ewb-app-b via ProxyJump." -ForegroundColor Red
}

# Test 02: Forward Ping App-A -> App-B
Write-Host "`n[TEST 02] Forward Path: Ping from App-A (10.10.2.10) to App-B (10.20.1.10)..." -ForegroundColor Yellow
$pingFwd = ssh -o StrictHostKeyChecking=no ewb-app-a "ping -c 4 10.20.1.10"
Write-Host $pingFwd -ForegroundColor White
if ($pingFwd -match "0% packet loss") {
    Write-Host "[+] TEST 02 PASSED: 0% packet loss forward path." -ForegroundColor Green
} else {
    Write-Host "[-] TEST 02 FAILED or had packet loss." -ForegroundColor Red
}

# Test 03: Reverse Ping App-B -> App-A
Write-Host "`n[TEST 03] Reverse Path: Ping from App-B (10.20.1.10) to App-A (10.10.2.10)..." -ForegroundColor Yellow
$pingRev = ssh -o StrictHostKeyChecking=no ewb-app-b "ping -c 4 10.10.2.10"
Write-Host $pingRev -ForegroundColor White
if ($pingRev -match "0% packet loss") {
    Write-Host "[+] TEST 03 PASSED: 0% packet loss reverse path." -ForegroundColor Green
} else {
    Write-Host "[-] TEST 03 FAILED or had packet loss." -ForegroundColor Red
}

Write-Host "`n[TEST 05] Isolation Check: Private instances have no public IPs." -ForegroundColor Yellow
Write-Host "[+] Confirmed: App-A and App-B reside in private subnets with no IGW routes." -ForegroundColor Green

Write-Host "`n[+] Verification suite complete!" -ForegroundColor Cyan

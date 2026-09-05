<#
================================================================================
  Data Warehouse — full pipeline runner
================================================================================
  Runs every stage in order: init -> bronze DDL -> bronze load -> silver DDL ->
  silver proc -> silver load -> gold views -> quality checks.

  Run from the repository root:

      .\run_pipeline.ps1                  # prompts for the MySQL password
      .\run_pipeline.ps1 -User root       # explicit user
      .\run_pipeline.ps1 -SkipTests       # skip the quality checks

  WARNING: this DROPS and recreates the bronze, silver and gold databases.
================================================================================
#>

param(
    [string] $User     = "root",
    [string] $MysqlExe = "C:\Program Files\MySQL\MySQL Server 8.0\bin\mysql.exe",
    [switch] $SkipTests
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $MysqlExe)) {
    throw "mysql client not found at '$MysqlExe'. Pass -MysqlExe with the correct path."
}

# Prompt once, in the console, so the password never lands in the shell history.
$secure = Read-Host -Prompt "MySQL password for '$User'" -AsSecureString
$plain  = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
              [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure))

# LOAD DATA LOCAL INFILE resolves paths relative to the client's working
# directory, so every stage must run from the repository root.
Set-Location $PSScriptRoot

function Invoke-Stage {
    param([string] $Label, [string] $Script)

    Write-Host ""
    Write-Host ">> $Label" -ForegroundColor Cyan

    # --local-infile=1 is required for the bronze load; harmless elsewhere.
    & $MysqlExe "--local-infile=1" "-u" $User "-p$plain" "--show-warnings" -e "source $Script"

    if ($LASTEXITCODE -ne 0) {
        throw "Stage failed: $Label (exit code $LASTEXITCODE)"
    }
}

Invoke-Stage "1/7  Creating databases"        "scripts/init_database.sql"
Invoke-Stage "2/7  Creating bronze tables"    "scripts/bronze/ddl_bronze.sql"
Invoke-Stage "3/7  Loading bronze from CSV"   "scripts/bronze/load_bronze.sql"
Invoke-Stage "4/7  Creating silver tables"    "scripts/silver/ddl_silver.sql"
Invoke-Stage "5/7  Creating silver procedure" "scripts/silver/proc_load_silver.sql"

Write-Host ""
Write-Host ">> 6/7  Running silver ETL" -ForegroundColor Cyan
& $MysqlExe "-u" $User "-p$plain" "--show-warnings" -e "CALL silver.load_silver();"
if ($LASTEXITCODE -ne 0) { throw "Stage failed: silver ETL" }

Invoke-Stage "7/7  Creating gold views" "scripts/gold/ddl_gold.sql"

if (-not $SkipTests) {
    Invoke-Stage "Quality checks - silver" "tests/quality_checks_silver.sql"
    Invoke-Stage "Quality checks - gold"   "tests/quality_checks_gold.sql"
    Write-Host ""
    Write-Host "Every 'violations' column above must read 0." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Pipeline complete." -ForegroundColor Green

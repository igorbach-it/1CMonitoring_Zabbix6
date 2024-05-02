# Проверка установки Git Bash
if (-not (Get-Command "git" -ErrorAction SilentlyContinue)) {
    Write-Host "Git Bash не установлен. Производится установка..."
    $gitBashInstallerUrl = "https://github.com/git-for-windows/git/releases/download/v2.34.1.windows.1/Git-2.34.1-64-bit.exe"
    $installerPath = "$env:TEMP\GitBashInstaller.exe"
    Invoke-WebRequest -Uri $gitBashInstallerUrl -OutFile $installerPath
    Start-Process -FilePath $installerPath -Args "/VERYSILENT" -Wait
}

# Проверка и удаление существующей службы
$serviceName = "1C:Enterprise 8.3 Remote Server"
$service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
if ($service) {
    Stop-Service -Name $serviceName -Force
    sc.exe delete $serviceName
    Write-Host "Ожидание удаления службы..."
    while ($true) {
        try {
            $service = Get-Service -Name $serviceName -ErrorAction Stop
            Start-Sleep -Seconds 2
        } catch {
            Write-Host "Служба удалена."
            break
        }
    }
}

# Проверка существования пользователя и запрос пароля
$userName = "USR1CV8_RAS"
if (-not (Get-LocalUser -Name $userName -ErrorAction SilentlyContinue)) {
    $password = Read-Host "Введите пароль для нового пользователя $userName" -AsSecureString
    New-LocalUser -Name $userName -Password $password -Description "Пользователь для запуска службы 1С"
} else {
    $password = Read-Host "Введите текущий пароль для пользователя $userName" -AsSecureString
}

$servicePath = (Get-CimInstance -ClassName Win32_Service -Filter "Name = '1C:Enterprise 8.3 Server Agent (x86-64)'").PathName
$version = [regex]::Match($servicePath, "\\1cv8\\(.+?)\\bin\\").Groups[1].Value
$binPath = [regex]::Match($servicePath, "^(.+)\\bin\\").Groups[1].Value
$rasPath = "$binPath\bin\ras.exe"

# Создание новой службы
$binPathArg =  $rasPath + '" cluster --service --port=1545 localhost:1540'
$cred = New-Object System.Management.Automation.PSCredential(".\$userName", $password)
if (-not (Get-Service -Name $serviceName -ErrorAction SilentlyContinue)) {
    New-Service -Name $serviceName -BinaryPathName $binPathArg -DisplayName $serviceName -StartupType Automatic -Credential $cred
    # Запуск службы
    Start-Service -Name $serviceName
} else {
    Write-Host "Служба все еще отмечена для удаления. Попробуйте перезагрузить сервер."
}

# Определение URL и пути сохранения
$url = "https://github.com/igorbach-it/1CMonitoring_Zabbix6/archive/refs/heads/main.zip"
$destinationPath = "C:\Temp\1CMonitoring_Zabbix6-main.zip"
$tempExtractPath = "C:\Temp\1CMonitoring_Zabbix6-main"
$finalExtractPath = "C:\Windows\zabbix-agent"

# Создание временной директории, если она не существует
if (-not (Test-Path "C:\Temp")) {
    New-Item -Path "C:\Temp" -ItemType Directory
}

# Загрузка файла
Invoke-WebRequest -Uri $url -OutFile $destinationPath

# Разархивирование файла
Expand-Archive -Path $destinationPath -DestinationPath $tempExtractPath -Force

# Путь к папке скриптов во временной директории
$sourceScriptsPath = Join-Path -Path $tempExtractPath -ChildPath "1CMonitoring_Zabbix6-main\scripts"
$destinationScriptsPath = Join-Path -Path $finalExtractPath -ChildPath "scripts"

# Создание целевой директории для скриптов, если она не существует
if (-not (Test-Path $destinationScriptsPath)) {
    New-Item -Path $destinationScriptsPath -ItemType Directory -Force
}

# Копирование скриптов
Get-ChildItem -Path $sourceScriptsPath -Recurse | ForEach-Object {
    $targetFilePath = $_.FullName.Replace($sourceScriptsPath, $destinationScriptsPath)
    if (-not (Test-Path (Split-Path -Path $targetFilePath -Parent))) {
        New-Item -Path (Split-Path -Path $targetFilePath -Parent) -ItemType Directory -Force
    }
    Copy-Item -Path $_.FullName -Destination $targetFilePath -Force
}

# Путь к файлам конфигурации во временной директории
$sourceConfFilesPath = Join-Path -Path $tempExtractPath -ChildPath "1CMonitoring_Zabbix6-main"

# Копирование файлов конфигурации .conf
Get-ChildItem -Path $sourceConfFilesPath -Filter *.conf -Recurse | ForEach-Object {
    $targetConfFilePath = Join-Path -Path $finalExtractPath -ChildPath $_.Name
    Copy-Item -Path $_.FullName -Destination $targetConfFilePath -Force
}

# Удаление временной директории и ZIP-файла
Remove-Item -Path $tempExtractPath -Recurse -Force
Remove-Item -Path $destinationPath

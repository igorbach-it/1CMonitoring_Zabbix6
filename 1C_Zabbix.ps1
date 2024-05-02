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

# Определение пути каталога скрипта
$scriptPath = Split-Path -Parent -Path $MyInvocation.MyCommand.Definition

# Путь назначения
$destinationPath = "C:\Windows\zabbix-agent\1C"

# Создание пути назначения, если он не существует
if (-not (Test-Path -Path $destinationPath)) {
    New-Item -ItemType Directory -Path $destinationPath -Force
}

# Копирование всех файлов и папок из каталога скрипта в путь назначения
Copy-Item -Path "$scriptPath\*" -Destination $destinationPath -Recurse -Force

Write-Host "Файлы и папки успешно скопированы в $destinationPath"



# Получение пути к службе Zabbix Agent
$zabbixService = Get-WmiObject win32_service | Where-Object { $_.Name -like '*zabbix*' } | Select-Object -ExpandProperty PathName

# Определение пути к каталогу Zabbix Agent
if ($zabbixService -ne $null) {
    # Удаление кавычек и аргументов из строки пути
    $agentPath = $zabbixService -replace '"', '' -replace ' .*', ''
    # Получение только пути к каталогу
    $agentDirectory = [System.IO.Path]::GetDirectoryName($agentPath)
} else {
    Write-Host "Служба Zabbix Agent не найдена."
    exit
}

# Поиск файла конфигурации в каталоге службы
$configFile = Get-ChildItem -Path $agentDirectory -Filter "*.conf" | Where-Object { $_.Name -like "zabbix_agentd*.conf" } | Select-Object -ExpandProperty FullName

# Проверка наличия файла конфигурации
if ($configFile -ne $null) {
    $configFilePath = $configFile
} else {
    Write-Host "Файл конфигурации Zabbix Agent не найден."
    exit
}

# Вывод используемых путей для проверки
Write-Host "Путь к Zabbix Agent: $agentDirectory"
Write-Host "Путь к файлу конфигурации: $configFilePath"

# Остановка Zabbix Agent
Stop-Service -Name "Zabbix Agent" -ErrorAction SilentlyContinue
Start-Sleep -Seconds 5

# Загрузка содержимого файла конфигурации, с проверкой на существование файла
if (Test-Path $configFilePath) {
    $content = Get-Content $configFilePath -Raw
} else {
    Write-Host "Файл конфигурации Zabbix Agent не найден: $configFilePath"
    exit
}

# Проверка и добавление новых строк в конец файла, если они отсутствуют
$scripts1C = "Include=.\1C\*.conf"
$newContent = $content

if ($content -and -not $content.Contains($scripts1C)) {
    $newContent += "`r`n" + $scripts1C
    $newContent | Set-Content $configFilePath
    Write-Host "Обновления файла конфигурации Zabbix Agent выполнены."
} else {
    Write-Host "Нет необходимости обновлять файл конфигурации Zabbix Agent."
}

# Запуск Zabbix Agent
Start-Service -Name "Zabbix Agent" -ErrorAction SilentlyContinue

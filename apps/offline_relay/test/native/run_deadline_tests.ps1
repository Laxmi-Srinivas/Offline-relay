param(
    [string]$KotlinCache = (Join-Path $env:USERPROFILE '.gradle/caches/modules-2/files-2.1'),
    [string]$OutputDirectory = (Join-Path $env:TEMP 'OfflineRelayDeadlineTests'),
    [string]$AndroidJar = '',
    [string]$FlutterEmbeddingJar = ''
)
$ErrorActionPreference = 'Stop'

function Find-CachedJar([string]$relative, [string]$name) {
    $jar = Get-ChildItem -LiteralPath (Join-Path $KotlinCache $relative) -Recurse -Filter $name |
        Select-Object -First 1
    if ($null -eq $jar) { throw "Missing cached jar: $relative/$name" }
    return $jar.FullName
}

$compiler = Find-CachedJar 'org.jetbrains.kotlin/kotlin-compiler-embeddable/2.1.20' 'kotlin-compiler-embeddable-2.1.20.jar'
$stdlib = Find-CachedJar 'org.jetbrains.kotlin/kotlin-stdlib/2.1.20' 'kotlin-stdlib-2.1.20.jar'
$reflect = Find-CachedJar 'org.jetbrains.kotlin/kotlin-reflect/2.1.20' 'kotlin-reflect-2.1.20.jar'
$scriptRuntime = Find-CachedJar 'org.jetbrains.kotlin/kotlin-script-runtime/2.1.20' 'kotlin-script-runtime-2.1.20.jar'
$coroutines = Find-CachedJar 'org.jetbrains.kotlinx/kotlinx-coroutines-core-jvm/1.8.0' 'kotlinx-coroutines-core-jvm-1.8.0.jar'
$annotations = Find-CachedJar 'org.jetbrains/annotations/13.0' 'annotations-13.0.jar'
$trove = Find-CachedJar 'org.jetbrains.intellij.deps/trove4j/1.0.20200330' 'trove4j-1.0.20200330.jar'
$compilerClasspath = @($compiler, $stdlib, $reflect, $scriptRuntime, $coroutines, $annotations, $trove) -join ';'
$appRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '../..')).Path
$source = Join-Path $appRoot 'android/app/src/main/kotlin/dev/offlinerelay/offline_relay/ble/BleDeadlines.kt'
$test = Join-Path $PSScriptRoot 'BleDeadlinesTest.kt'
$helperSource = Join-Path $appRoot 'android/app/src/main/kotlin/dev/offlinerelay/offline_relay/ble/HelperConversation.kt'
$helperTest = Join-Path $PSScriptRoot 'HelperConversationTest.kt'
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$java = (Get-Command java -ErrorAction Stop).Source
& $java -cp $compilerClasspath org.jetbrains.kotlin.cli.jvm.K2JVMCompiler `
    -no-stdlib -no-reflect -classpath "$stdlib;$annotations" -d $OutputDirectory $source $test $helperSource $helperTest
if ($LASTEXITCODE -ne 0) { throw "Kotlin compilation failed: $LASTEXITCODE" }
& $java -cp "$OutputDirectory;$stdlib" dev.offlinerelay.offline_relay.ble.BleDeadlinesTestKt
if ($LASTEXITCODE -ne 0) { throw "Deadline tests failed: $LASTEXITCODE" }
& $java -cp "$OutputDirectory;$stdlib" dev.offlinerelay.offline_relay.ble.HelperConversationTestKt
if ($LASTEXITCODE -ne 0) { throw "Helper conversation tests failed: $LASTEXITCODE" }

if ($AndroidJar -or $FlutterEmbeddingJar) {
    if (-not $AndroidJar -or -not $FlutterEmbeddingJar) {
        throw 'Supply both AndroidJar and FlutterEmbeddingJar for session compilation.'
    }
    $session = Join-Path $appRoot 'android/app/src/main/kotlin/dev/offlinerelay/offline_relay/ble/BleRelaySession.kt'
    $sessionOutput = Join-Path $OutputDirectory 'session'
    New-Item -ItemType Directory -Path $sessionOutput -Force | Out-Null
    & $java -cp $compilerClasspath org.jetbrains.kotlin.cli.jvm.K2JVMCompiler `
        -no-stdlib -no-reflect -jvm-target 17 `
        -classpath "$stdlib;$annotations;$AndroidJar;$FlutterEmbeddingJar" `
        -d $sessionOutput $source $session
    if ($LASTEXITCODE -ne 0) { throw "Android session compilation failed: $LASTEXITCODE" }
    Write-Output 'Android BLE session Kotlin compilation passed (not an APK build or device test).'

    # Compile actual Activity/service integration using cached LifecycleOwner API.
    # Only the generated R symbol is substituted; no Android behavior is simulated.
    $lifecycle = Find-CachedJar 'androidx.lifecycle/lifecycle-common-jvm/2.8.7' 'lifecycle-common-jvm-2.8.7.jar'
    $rSymbol = Join-Path $OutputDirectory 'R.kt'
    Set-Content -LiteralPath $rSymbol -Encoding utf8 -Value 'package dev.offlinerelay.offline_relay; object R { object mipmap { const val ic_launcher = 1 } }'
    $activity = Join-Path $appRoot 'android/app/src/main/kotlin/dev/offlinerelay/offline_relay/MainActivity.kt'
    $service = Join-Path $appRoot 'android/app/src/main/kotlin/dev/offlinerelay/offline_relay/ble/BleRelayForegroundService.kt'
    & $java -cp $compilerClasspath org.jetbrains.kotlin.cli.jvm.K2JVMCompiler `
        -no-stdlib -no-reflect -jvm-target 17 `
        -classpath "$stdlib;$annotations;$AndroidJar;$FlutterEmbeddingJar;$lifecycle" `
        -d $sessionOutput $source $session $helperSource $activity $service $rSymbol
    if ($LASTEXITCODE -ne 0) { throw "Android Activity/service source compilation failed: $LASTEXITCODE" }
    Write-Output 'Android Activity/service source compilation passed (R symbol placeholder; not an APK/device test).'
}


$targetFile = "lambda_codigo_completo.txt"
$files = Get-ChildItem -Path lib -Recurse -Filter *.dart
$output = ""

foreach ($file in $files) {
    $relativePath = $file.FullName.Replace("C:\Users\kus\OneDrive\Escritorio\Proyectos\Lambda\", "")
    $output += "`n// FILE: $relativePath`n"
    $output += Get-Content $file.FullName -Raw
    $output += "`n"
}

$pubspec = Get-Item "pubspec.yaml"
$output += "`n// FILE: pubspec.yaml`n"
$output += Get-Content $pubspec.FullName -Raw

$output | Out-File -FilePath $targetFile -Encoding utf8

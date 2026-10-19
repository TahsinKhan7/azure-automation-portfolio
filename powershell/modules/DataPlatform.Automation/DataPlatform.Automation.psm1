# DataPlatform.Automation
#
# Loader: dot-sources every function file under Private/ and Public/ and
# exports the public ones. Keeping one function per file makes each unit
# small enough to test in isolation (see ../../tests).

$privateFunctions = @(Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath 'Private') -Filter '*.ps1' -ErrorAction SilentlyContinue)
$publicFunctions = @(Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath 'Public') -Filter '*.ps1' -ErrorAction SilentlyContinue)

foreach ($file in @($privateFunctions + $publicFunctions)) {
    try {
        . $file.FullName
    } catch {
        throw "Failed to import function file '$($file.FullName)': $($_.Exception.Message)"
    }
}

Export-ModuleMember -Function $publicFunctions.BaseName

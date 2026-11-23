$ErrorActionPreference = 'Stop'

$cpp = 'windows/runner/flutter_window.cpp'
$cmake = 'windows/runner/CMakeLists.txt'

Copy-Item 'tool/windows/global_barcode_hook.h' 'windows/runner/global_barcode_hook.h' -Force
Copy-Item 'tool/windows/global_barcode_hook.cpp' 'windows/runner/global_barcode_hook.cpp' -Force

if (!(Test-Path $cpp) -or !(Test-Path $cmake)) {
  throw 'Generated Flutter Windows runner files were not found.'
}

$source = Get-Content $cpp -Raw

if ($source -notmatch 'global_barcode_hook.h') {
  if ($source -notmatch '#include "flutter_window.h"') {
    throw 'Could not locate flutter_window.h include in generated runner.'
  }

  $source = $source.Replace(
    '#include "flutter_window.h"',
    '#include "flutter_window.h"' + "`r`n" + '#include "global_barcode_hook.h"')
}

if ($source -notmatch 'g_global_barcode_hook') {
  if ($source -notmatch 'SetChildContent\(flutter_controller_->view\(\)->GetNativeWindow\(\)\);') {
    throw 'Could not locate Flutter child window setup point.'
  }

  if ($source -notmatch 'FlutterWindow::FlutterWindow\(') {
    throw 'Could not locate FlutterWindow constructor.'
  }

  $source = $source.Replace(
    'SetChildContent(flutter_controller_->view()->GetNativeWindow());',
    'g_global_barcode_hook = std::make_unique<GlobalBarcodeHook>(flutter_controller_->engine()->messenger());' + "`r`n  " + 'SetChildContent(flutter_controller_->view()->GetNativeWindow());')

  $source = $source.Replace(
    'FlutterWindow::FlutterWindow(',
    'static std::unique_ptr<GlobalBarcodeHook> g_global_barcode_hook;' + "`r`n`r`n" + 'FlutterWindow::FlutterWindow(')
}

Set-Content -Path $cpp -Value $source -Encoding utf8

$build = Get-Content $cmake -Raw

if ($build -notmatch 'global_barcode_hook.cpp') {
  if ($build -notmatch '"flutter_window.cpp"') {
    throw 'Could not locate flutter_window.cpp in generated runner CMakeLists.'
  }

  $build = $build.Replace(
    '"flutter_window.cpp"',
    '"flutter_window.cpp"' + "`r`n  " + '"global_barcode_hook.cpp"')
}

Set-Content -Path $cmake -Value $build -Encoding utf8

Write-Host 'Global barcode hook integrated into the generated Windows runner.'

param([Parameter(Mandatory=$true)][string]$Runtime)
$ErrorActionPreference='Stop'
if (!(Test-Path ($Runtime+'\synthetic-fixture.marker'))) { throw 'Synthetic fixture required' }
$launch=Get-Content ($Runtime+'\launch.json') -Raw | ConvertFrom-Json
$app=Get-Process -Id $launch.pid
if (!$launch.isolated -or !$app.Path.StartsWith((Split-Path $Runtime)+'\build\windows\')) { throw 'Wrong process' }
$command=Get-Content ($Runtime+'\driver-command.json') -Raw | ConvertFrom-Json
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -AssemblyName System.Windows.Forms
. "$PSScriptRoot\windows_accessibility.ps1"
Add-Type @'
using System;
using System.Runtime.InteropServices;
public class RecoveryInput {
 [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hwnd);
 [DllImport("user32.dll")] public static extern bool SetCursorPos(int x,int y);
 [DllImport("user32.dll")] public static extern void mouse_event(uint flags,uint x,uint y,uint data,UIntPtr extra);
}
'@
function Click-Control($control) {
 if (!$control -or $control.Current.IsOffscreen) {throw 'Observed picker control unavailable'}
 $rect=$control.Current.BoundingRectangle
 if ($rect.Width -le 0 -or $rect.Height -le 0) {throw 'Empty control rectangle'}
 [RecoveryInput]::SetCursorPos(($rect.X+$rect.Width/2),($rect.Y+$rect.Height/2)) | Out-Null
 [RecoveryInput]::mouse_event(2,0,0,0,[UIntPtr]::Zero)
 [RecoveryInput]::mouse_event(4,0,0,0,[UIntPtr]::Zero)
}
try {
 $processCondition=New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ProcessIdProperty,$app.Id)
 $windows=[System.Windows.Automation.AutomationElement]::RootElement.FindAll([System.Windows.Automation.TreeScope]::Children,$processCondition)
 $main=@($windows | Where-Object {$_.Current.ClassName -eq 'FLUTTER_RUNNER_WIN32_WINDOW'})[0]
 $window=[IntPtr]$main.Current.NativeWindowHandle
 $result=@{mode=$command.mode;pid=$app.Id}
 if ($command.mode -in @('accessibility','tap','longpress')) {
  [RecoveryInput]::SetForegroundWindow($window) | Out-Null
  if ($command.mode -eq 'accessibility') {
   $result.controls=@([FiFeAccessibility]::Dump($window) | Where-Object {$_.name})
  } elseif ($command.mode -eq 'tap') {
   if(![FiFeAccessibility]::Act($window,$command.name)) {throw 'Named accessibility action unavailable'}
  } else {
   $nodes=@([FiFeAccessibility]::Dump($window) | Where-Object {$_.name -eq $command.name})
   if ($nodes.Count -ne 1) {throw 'Expected one observed recovery row'}
   $node=$nodes[0]
   [RecoveryInput]::SetCursorPos(($node.left+$node.width/2),($node.top+$node.height/2)) | Out-Null
   [RecoveryInput]::mouse_event(2,0,0,0,[UIntPtr]::Zero)
   try { Start-Sleep -Milliseconds 800 } finally { [RecoveryInput]::mouse_event(4,0,0,0,[UIntPtr]::Zero) }
  }
 } else {
  $dialog=@($windows | Where-Object {$_.Current.ClassName -eq '#32770'})[0]
  if (!$dialog) {throw 'App-owned native folder dialog unavailable'}
  $nodes=$dialog.FindAll([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.Condition]::TrueCondition)
  if ($command.mode -eq 'dialog') {
   $result.controls=@($nodes | Where-Object {$_.Current.Name} | ForEach-Object {@{name=$_.Current.Name;id=$_.Current.AutomationId;type=$_.Current.ControlType.ProgrammaticName}})
  } elseif ($command.mode -eq 'dialog-cancel') {
   $button=@($nodes | Where-Object {$_.Current.Name -eq 'Cancel' -and $_.Current.AutomationId -eq '2'})[0]
   Click-Control $button
  } elseif ($command.mode -eq 'dialog-select') {
   if (!$command.path.StartsWith($Runtime+'\')) {throw 'Picker limited to this synthetic runtime'}
   [RecoveryInput]::SetForegroundWindow([IntPtr]$dialog.Current.NativeWindowHandle) | Out-Null
   if ($command.path -match '[+^%~{}()]') {throw 'Unsupported synthetic path characters'}
   [System.Windows.Forms.SendKeys]::SendWait('^l')
   [System.Windows.Forms.SendKeys]::SendWait($command.path)
   [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
   $deadline=[DateTime]::UtcNow.AddSeconds(8)
   do {
    $nodes=$dialog.FindAll([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.Condition]::TrueCondition)
    $address=@($nodes | Where-Object {$_.Current.Name -eq ('Address: '+$command.path)})
    if ($address.Count -gt 0) {break}
    Start-Sleep -Milliseconds 100
   } while ([DateTime]::UtcNow -lt $deadline)
   if ($address.Count -eq 0) {throw 'Picker did not navigate to the generated folder'}
   $button=@($nodes | Where-Object {$_.Current.Name -eq $command.button -and $_.Current.AutomationId -eq '1'})[0]
   Click-Control $button
  } else {throw 'Unknown mode'}
 }
 $result.success=$true
 $result | ConvertTo-Json -Depth 5 | Set-Content ($Runtime+'\driver-result.json')
} catch {
 @{success=$false;mode=$command.mode;error=$_.Exception.Message} | ConvertTo-Json | Set-Content ($Runtime+'\driver-result.json')
 exit 1
}

param([Parameter(Mandatory=$true)][string]$Runtime)
$ErrorActionPreference='Stop'
$ProgressPreference='SilentlyContinue'
if (!(Test-Path ($Runtime+'\synthetic-fixture.marker'))) { throw 'Synthetic fixture required' }
$launch=Get-Content ($Runtime+'\launch.json') -Raw | ConvertFrom-Json
$app=Get-Process -Id $launch.pid
if (!$launch.isolated -or !$app.Path.StartsWith((Split-Path $Runtime)+'\build\windows\')) { throw 'Wrong process' }
$command=Get-Content ($Runtime+'\driver-command.json') -Raw | ConvertFrom-Json
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public class FiFeDesktopDriver {
 public delegate bool EnumCallback(IntPtr hwnd, IntPtr state);
 [DllImport("user32.dll")] public static extern bool EnumWindows(EnumCallback callback, IntPtr state);
 [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint id);
 [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr hwnd, StringBuilder text, int size);
 [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hwnd);
 [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindow(string className, string title);
 [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hwnd);
 [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
 [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr window, out Rect rect);
 [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr hwnd, uint message, IntPtr wparam, IntPtr lparam);
 [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
 [DllImport("user32.dll")] public static extern void mouse_event(uint flags, uint x, uint y, uint data, UIntPtr extra);
 [DllImport("user32.dll")] public static extern void keybd_event(byte key, byte scan, uint flags, UIntPtr extra);
 [DllImport("user32.dll")] public static extern short GetAsyncKeyState(int key);
 [StructLayout(LayoutKind.Sequential)] public struct GuiState { public uint size,flags; public IntPtr active,focus,capture,menuOwner,moveSize,caret; public Rect caretRect; }
 [DllImport("user32.dll")] public static extern bool GetGUIThreadInfo(uint thread, ref GuiState state);
 public static bool MenuOwnedBy(IntPtr window) {
  uint process; uint thread=GetWindowThreadProcessId(window,out process);
  var state=new GuiState();state.size=(uint)Marshal.SizeOf(state);
  return GetGUIThreadInfo(thread,ref state) && (state.flags & 4)!=0 && state.menuOwner==window;
 }
 public static void Key(byte key) { keybd_event(key,0,0,UIntPtr.Zero);keybd_event(key,0,2,UIntPtr.Zero); }
 [StructLayout(LayoutKind.Sequential)] public struct IconId { public uint size; public IntPtr window; public uint id; public Guid guid; }
 [StructLayout(LayoutKind.Sequential)] public struct Rect { public int left,top,right,bottom; }
 [DllImport("shell32.dll")] public static extern int Shell_NotifyIconGetRect(ref IconId icon, out Rect rect);
 public static IntPtr Window(uint id) {
  IntPtr found=IntPtr.Zero;
  EnumWindows((hwnd,state)=>{uint owner; GetWindowThreadProcessId(hwnd,out owner); var name=new StringBuilder(256); GetClassName(hwnd,name,256);
   if(owner==id && name.ToString()=="FLUTTER_RUNNER_WIN32_WINDOW") {found=hwnd;return false;} return true;},IntPtr.Zero);
  return found;
 }
 public static IntPtr Popup(uint id) {
  IntPtr found=IntPtr.Zero;
  EnumWindows((hwnd,state)=>{uint owner; GetWindowThreadProcessId(hwnd,out owner);var name=new StringBuilder(256);GetClassName(hwnd,name,256);
   if(owner==id && name.ToString()=="#32768" && IsWindowVisible(hwnd)) {found=hwnd;return false;}return true;},IntPtr.Zero);
  return found;
 }
}
'@
try {
 $window=[FiFeDesktopDriver]::Window($app.Id)
 if($window -eq [IntPtr]::Zero) { throw 'App window not found in interactive desktop' }
 $result=@{mode=$command.mode; pid=$app.Id; window=$window.ToInt64(); beforeVisible=[FiFeDesktopDriver]::IsWindowVisible($window)}
 if ($command.mode -in @('accessibility','tap')) {
  . "$PSScriptRoot\windows_accessibility.ps1"
  [FiFeDesktopDriver]::SetForegroundWindow($window) | Out-Null
  if($command.mode -eq 'tap') {
   if(![FiFeAccessibility]::Act($window,$command.name)) { throw 'Named native accessibility action unavailable' }
   $result.action=$command.name
  } else {
   $result.controls=@([FiFeAccessibility]::Dump($window) | Where-Object { $_.name } | Select-Object -First 60)
  }
 } elseif ($command.mode -eq 'close') {
  [FiFeDesktopDriver]::PostMessage($window,0x112,[IntPtr]0xF060,[IntPtr]::Zero) | Out-Null
  $deadline=[DateTime]::UtcNow.AddSeconds(5)
  while([FiFeDesktopDriver]::IsWindowVisible($window) -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 50 }
 } elseif ($command.mode -eq 'inspect') {
  $element=[System.Windows.Automation.AutomationElement]::FromHandle($window)
  $elements=$element.FindAll([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.Condition]::TrueCondition)
  $result.controls=@($elements | ForEach-Object { if($_.Current.Name) { @{name=$_.Current.Name; type=$_.Current.ControlType.ProgrammaticName; enabled=$_.Current.IsEnabled} } } | Select-Object -First 60)
 } elseif ($command.mode -eq 'tray') {
  $taskbar=[System.Windows.Automation.AutomationElement]::FromHandle([FiFeDesktopDriver]::FindWindow('Shell_TrayWnd',$null))
  $items=$taskbar.FindAll([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.Condition]::TrueCondition)
  $result.tray=@($items | ForEach-Object { if($_.Current.Name) { @{name=$_.Current.Name; type=$_.Current.ControlType.ProgrammaticName; offscreen=$_.Current.IsOffscreen; rectangle=$_.Current.BoundingRectangle.ToString()} } } | Select-Object -Last 35)
 } elseif ($command.mode -in @('Open','Sync','Quit','menu')) {
  $iconCondition=New-Object System.Windows.Automation.AndCondition(
    (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty,'FiFe')),
    (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::Button)))
  $icons=[System.Windows.Automation.AutomationElement]::RootElement.FindAll([System.Windows.Automation.TreeScope]::Descendants,$iconCondition)
  $visibleIcon=@($icons | Where-Object { !$_.Current.IsOffscreen })
  if($visibleIcon.Count -eq 0) {
   $taskbar=[System.Windows.Automation.AutomationElement]::FromHandle([FiFeDesktopDriver]::FindWindow('Shell_TrayWnd',$null))
   $overflow=$taskbar.FindFirst([System.Windows.Automation.TreeScope]::Descendants,
      (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty,'Show Hidden Icons')))
   if($null -ne $overflow) {
    $box=$overflow.Current.BoundingRectangle
    [FiFeDesktopDriver]::SetCursorPos([int]($box.X+$box.Width/2),[int]($box.Y+$box.Height/2)) | Out-Null
    [FiFeDesktopDriver]::mouse_event(2,0,0,0,[UIntPtr]::Zero)
    [FiFeDesktopDriver]::mouse_event(4,0,0,0,[UIntPtr]::Zero)
    Start-Sleep -Milliseconds 350
   }
  }
  $icon=New-Object FiFeDesktopDriver+IconId
  $icon.size=[Runtime.InteropServices.Marshal]::SizeOf($icon); $icon.window=$window; $icon.id=1
  $rect=New-Object FiFeDesktopDriver+Rect
  $code=[FiFeDesktopDriver]::Shell_NotifyIconGetRect([ref]$icon,[ref]$rect)
  if($code -ne 0 -or $rect.right -le $rect.left) { throw ('Tray icon rectangle unavailable: '+$code) }
  $result.icon=@{left=$rect.left; top=$rect.top; right=$rect.right; bottom=$rect.bottom}
  [FiFeDesktopDriver]::SetCursorPos([int](($rect.left+$rect.right)/2),[int](($rect.top+$rect.bottom)/2)) | Out-Null
  [FiFeDesktopDriver]::mouse_event(8,0,0,0,[UIntPtr]::Zero)
  [FiFeDesktopDriver]::mouse_event(16,0,0,0,[UIntPtr]::Zero)
  $condition=New-Object System.Windows.Automation.AndCondition(
    (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ProcessIdProperty,$app.Id)),
    (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::MenuItem)))
  $deadline=[DateTime]::UtcNow.AddSeconds(5)
  do {
   $items=[System.Windows.Automation.AutomationElement]::RootElement.FindAll([System.Windows.Automation.TreeScope]::Descendants,$condition)
   if ($items.Count -ge 3) { break }
   Start-Sleep -Milliseconds 100
  } while ([DateTime]::UtcNow -lt $deadline)
  $result.menu=@($items | ForEach-Object { @{name=$_.Current.Name; enabled=$_.Current.IsEnabled} })
  $result.nativeMenuOwned=[FiFeDesktopDriver]::MenuOwnedBy($window)
  if($items.Count -lt 3 -and $result.nativeMenuOwned) {
   if($command.mode -ne 'menu') {
    [FiFeDesktopDriver]::SetForegroundWindow($window) | Out-Null
    if([FiFeDesktopDriver]::GetForegroundWindow() -ne $window) { throw 'Fixture does not own keyboard focus' }
    foreach($key in @(0x10,0x11,0x12,0x5B,0x5C)) { if([FiFeDesktopDriver]::GetAsyncKeyState($key) -lt 0) { throw 'Physical modifier is held; refusing keyboard action' } }
    $popup=[FiFeDesktopDriver]::Popup($app.Id)
    if($popup -eq [IntPtr]::Zero -or ![FiFeDesktopDriver]::MenuOwnedBy($window)) { throw 'Verified menu lost focus before selection' }
    $menuRect=New-Object FiFeDesktopDriver+Rect
    [FiFeDesktopDriver]::GetWindowRect($popup,[ref]$menuRect) | Out-Null
    # These are the three observed native rows, with a separator before Quit.
    $rowHeight=($menuRect.bottom-$menuRect.top-12)/3
    $y=switch($command.mode) { 'Open' {$menuRect.top+2+$rowHeight/2} 'Sync' {$menuRect.top+2+$rowHeight*1.5} 'Quit' {$menuRect.bottom-2-$rowHeight/2} }
    [FiFeDesktopDriver]::SetCursorPos([int](($menuRect.left+$menuRect.right)/2),[int]$y) | Out-Null
    [FiFeDesktopDriver]::mouse_event(2,0,0,0,[UIntPtr]::Zero)
    [FiFeDesktopDriver]::mouse_event(4,0,0,0,[UIntPtr]::Zero)
    Start-Sleep -Milliseconds 300
   }
   $result.nativePopupMouseAction=$true
  } elseif($items.Count -lt 3) {
   $menus=[System.Windows.Automation.AutomationElement]::RootElement.FindAll([System.Windows.Automation.TreeScope]::Descendants,
      (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::MenuItem)))
   $result.otherMenus=@($menus | ForEach-Object { @{name=$_.Current.Name; owner=$_.Current.ProcessId; offscreen=$_.Current.IsOffscreen} } | Select-Object -First 12)
   Add-Type -AssemblyName System.Drawing
   $bitmap=New-Object System.Drawing.Bitmap(480,500)
   $graphics=[System.Drawing.Graphics]::FromImage($bitmap)
   $graphics.CopyFromScreen(1440,580,0,0,$bitmap.Size)
   $bitmap.Save(($Runtime+'\tray-diagnostic.png'))
   $graphics.Dispose(); $bitmap.Dispose()
   throw 'Actual tray click did not expose its menu (icon may be in overflow)'
  }
  if($items.Count -ge 3 -and $command.mode -ne 'menu') {
   $item=@($items | Where-Object { $_.Current.Name -eq $command.mode })
   if($item.Count -ne 1 -or !$item[0].Current.IsEnabled) { throw 'Requested menu action unavailable' }
   $item[0].GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
   Start-Sleep -Milliseconds 300
  }
 }
 $deadline=[DateTime]::UtcNow.AddSeconds(5)
 if($command.mode -eq 'Quit') {
  while((Get-Process -Id $app.Id -ErrorAction SilentlyContinue) -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 100 }
 }
 if($command.mode -eq 'Open') {
  while(![FiFeDesktopDriver]::IsWindowVisible($window) -and [DateTime]::UtcNow -lt $deadline) { Start-Sleep -Milliseconds 100 }
 }
 $result.afterVisible=[FiFeDesktopDriver]::IsWindowVisible($window)
 $result.running=$null -ne (Get-Process -Id $app.Id -ErrorAction SilentlyContinue)
 if($command.mode -eq 'Quit' -and $result.running) { throw 'Quit did not terminate the fixture' }
 if($command.mode -eq 'Open' -and !$result.afterVisible) { throw 'Open did not show the fixture window' }
 if($command.mode -eq 'close' -and ($result.afterVisible -or !$result.running)) { throw 'Close must hide the window and retain the process' }
 $result.success=$true
 $result | ConvertTo-Json -Depth 6 | Set-Content ($Runtime+'\driver-result.json')
} catch {
 if(!$result) { $result=@{mode=$command.mode} }
 $result.success=$false; $result.error=$_.Exception.Message
 $result | ConvertTo-Json -Depth 6 | Set-Content ($Runtime+'\driver-result.json')
 exit 1
}

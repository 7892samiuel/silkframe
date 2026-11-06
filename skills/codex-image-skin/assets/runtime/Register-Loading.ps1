$ErrorActionPreference='Stop'
$service=New-Object -ComObject 'Schedule.Service';$service.Connect();$folder=$service.GetFolder('\')
$name='CodexImageSkinLoading';$helper=Join-Path $PSScriptRoot 'ImageSkinLoadingHost.exe'
$old=@($folder.GetTasks(1)|Where-Object Name -eq $name)|Select-Object -First 1
if($old -and ($old.Definition.Actions.Count -ne 1 -or $old.Definition.Actions.Item(1).Path -ine $helper)){throw 'Loading cover task name belongs to another action; preserved.'}
$definition=$service.NewTask(0);$definition.RegistrationInfo.Description='Current-user Codex startup cover; original app entry invokes it. No timer or login trigger.'
$definition.Principal.UserId=[Security.Principal.WindowsIdentity]::GetCurrent().Name;$definition.Principal.LogonType=3;$definition.Principal.RunLevel=0
$definition.Settings.Enabled=$true;$definition.Settings.Hidden=$true;$definition.Settings.ExecutionTimeLimit='PT1M';$definition.Settings.MultipleInstances=0
$definition.Settings.DisallowStartIfOnBatteries=$false;$definition.Settings.StopIfGoingOnBatteries=$false
$action=$definition.Actions.Create(0);$action.Path=$helper;$action.Arguments='$(Arg0) $(Arg1) $(Arg2)';$action.WorkingDirectory=$PSScriptRoot
$task=$folder.RegisterTaskDefinition($name,$definition,6,$null,$null,3,$null)
@{task=$task.Name;helper=$helper;arguments=$task.Definition.Actions.Item(1).Arguments;triggerCount=$task.Definition.Triggers.Count;runLevel=$task.Definition.Principal.RunLevel;enabled=$task.Enabled}|ConvertTo-Json

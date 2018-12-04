#requires -modules dbatools
function Get-MaintenancePlanDetails {
    <#
        .SYNOPSIS
            Returns details from SQL Server maintenance plans.
            
        .DESCRIPTION
            Queries for the SSIS data for the maintenance plan xml and returns the details from the xml information.
            
        .EXAMPLE
            PS C:\> Get-MaintenancePlanDetails -SqlInstance DBDEVSERVER01 -Name 'USER-DB-BACKUP-DAILY'

            Returns information on the maintenance plan 'USER-DB-BACKUP-DAILY' on the server 'DBDEVSERVER01' for backup information.
        
        .PARAMETER SqlInstance
            Name of the server to run the command against. Defauls to "localhost".

        .PARAMETER Name
            Name of the Maintenance Plan to filter down to.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType('MaintenancePlanDetails')]
    param (
        [Parameter(ValueFromPipelineByPropertyName)]
        [Alias('Server', 'ServerName', 'Instance', 'InstanceName')]
        [ValidateNotNullOrEmpty()]
        [String]$SqlInstance = 'localhost',

        [Parameter(ValueFromPipelineByPropertyName)]
        [ValidateNotNullOrEmpty()]
        [Alias('MaintenancePlan', 'PlanName', 'Plan')]
        [String]$Name
    )

    begin {
        Write-Verbose "[$((Get-Date).TimeOfDay) BEGIN  ]: Creating Enum class: [ BackupAction ]"
        Enum BackupAction {
            Database = 0
            Files = 1
            Logs = 2
        }
        Write-Verbose "[$((Get-Date).TimeOfDay) BEGIN  ]: Created Enum class: [ BackupAction ]"
        Write-Verbose "[$((Get-Date).TimeOfDay) BEGIN  ]: Creating Enum class: [ BackupDevice ]"
        Enum BackupDevice {
            LogicalDevice = 0
            Tape = 1
            File = 2
            Pipe = 3
            VirtualDevice = 4
        }
        Write-Verbose "[$((Get-Date).TimeOfDay) BEGIN  ]: Created Enum class: [ BackupDevice ]"
        Write-Verbose "[$((Get-Date).TimeOfDay) BEGIN  ]: Creating Enum class: [ BackupCompressionAction ]"
        Enum BackupCompressionAction {
            ServerDefault = 0
            Compressed = 1
            NotCompressed = 2
        }
        Write-Verbose "[$((Get-Date).TimeOfDay) BEGIN  ]: Created Enum class: [ BackupCompressionAction ]"

        Write-Verbose "[$((Get-Date).TimeOfDay) BEGIN  ]: Creating maintenance plan SQL query"
        $MaintenancePlanQry = "
SELECT CAST(CAST(sp.[packagedata] AS VARBINARY(MAX)) AS XML) AS [maintenance_plan_xml],
	   Frequency = REPLACE(x.FreqDescription, '##ActiveStartTime##', x.ActiveStartTime),
	   x.JobName,
	   x.ScheduleName,
	   x.IsEnabled 
FROM msdb.dbo.sysssispackages AS sp
CROSS APPLY (
	SELECT JobName = j.[name],
		   ScheduleName = ss.[name],
		   IsEnabled = ss.[enabled],
		   FreqDescription = f.FrequencyDescription + (CASE WHEN (freq_recurrence_factor = 1 
															  OR (freq_type = 4 AND freq_interval = 1 AND freq_subday_type = 1))
															THEN ': At ##ActiveStartTime##.' 
															ELSE '.'
													   END),
		   ActiveStartTime = STUFF(STUFF(RIGHT('000000' + CAST(ss.active_start_time AS varchar(6)), 6), 3, 0, ':'), 6, 0, ':')
	FROM msdb.dbo.sysjobs AS j
	JOIN msdb.dbo.sysjobschedules AS sj
	ON j.job_id = sj.job_id
	JOIN msdb.dbo.sysschedules AS ss
	ON sj.schedule_id = ss.schedule_id
	LEFT JOIN (
		SELECT d.FrequencyType, 
			   d.FrequencyInterval, 
			   d.FrequencySubdayType, 
			   d.FrequencySubdayInterval, 
			   d.FrequencyRelativeInterval, 
			   d.FrequencyDescription
		FROM (
			VALUES
			(64, 0, 0, 0, 0, 'Runs when computer is idle'),
			(4, 1, 4, 5, 0, 'Daily: Every 5 minutes'),
			(4, 1, 4, 10, 0, 'Daily: Every 10 minutes'),
			(4, 1, 4, 15, 0, 'Daily: Every 15 minutes'),
			(4, 1, 4, 30, 0, 'Daily: Every 30 minutes'),
			(4, 1, 4, 60, 0, 'Daily: Every 60 minutes'),
			(8, 1, 1, 0, 0, 'Weekly: Sunday'),
			(32, 1, 1, 0, 1, 'Monthy: Sunday: First'),
			(4, 1, 8, 6, 0, 'Daily: Every 6 hours'),
			(4, 1, 1, 0, 0, 'Daily'),
			(4, 1, 4, 1, 0, 'Daily: Every 1 minute'),
			(4, 1, 8, 3, 0, 'Daily: Every 3 hours'),
			(4, 1, 8, 12, 0, 'Daily: Every 12 hours'),
			(4, 1, 8, 1, 0, 'Daily: Every 1 hour')
		) AS d(FrequencyType, FrequencyInterval, FrequencySubdayType, FrequencySubdayInterval, FrequencyRelativeInterval, FrequencyDescription)) f
	ON ss.freq_type = f.FrequencyType
   AND ss.freq_interval = f.FrequencyInterval
   AND ss.freq_subday_type = f.FrequencySubdayType
   AND ss.freq_subday_interval = f.FrequencySubdayInterval
   AND ss.freq_relative_interval = f.FrequencyRelativeInterval
	WHERE j.[name] LIKE '' + sp.[name] + '%') AS x"
        Write-Verbose "[$((Get-Date).TimeOfDay) BEGIN  ]: Created maintenance plan SQL query"

        if ($PSBoundParameters.ContainsKey('Name')) {
            Write-Verbose "[$((Get-Date).TimeOfDay) BEGIN  ]: Appending filter for maintenance plan name: [ $Name ]"
            $MaintenancePlanQry = $MaintenancePlanQry += " WHERE [name] = '$Name'"
            Write-Verbose "[$((Get-Date).TimeOfDay) BEGIN  ]: Appended filter for maintenance plan name: [ $Name ]"
        }

        Write-Verbose "[$((Get-Date).TimeOfDay) BEGIN  ]: Creating XML XPath parameters"
        $Xpath = @{
            Namespace = @{
                DTS     = "www.microsoft.com/SqlServer/Dts"
                SQLTask = "www.microsoft.com/sqlserver/dts/tasks/sqltask"
            }
            XPath     = '//SQLTask:SqlTaskData'
        }
        Write-Verbose "[$((Get-Date).TimeOfDay) BEGIN  ]: Created XML XPath parameters"
    }

    process {
        Write-Verbose "[$((Get-Date).TimeOfDay) PROCESS]: Retrieving SQL results."
        if ($PSCmdlet.ShouldProcess($SqlInstance, 'Retrieving maintenance plan xml')) {
            $MaintenancePlanXml = Invoke-DbaQuery -SqlInstance $SqlInstance -Database msdb -Query $MaintenancePlanQry 
        }

        if ($PSCmdlet.ShouldProcess($SqlInstance, 'Querying for backup details')) {
            Write-Verbose "[$((Get-Date).TimeOfDay) PROCESS]: Looping over [ $($MaintenancePlanXml.Count) ] rows for processing"
            foreach ($Plan in $MaintenancePlanXml) {
                
                # If there's a DesignTimeProperties node, we can't turn the DataRow into an XML document.
                Write-Verbose "[$((Get-Date).TimeOfDay) PROCESS]: Removing <DTS:DesignTimeProperties> Node"
                $XmlString = ($Plan.maintenance_plan_xml -replace "`n", " ") -replace "<DTS:DesignTimeProperties>.*</DTS:DesignTimeProperties>"
                $XmlString | Format-Table | Out-String | Write-Debug
                Write-Verbose "[$((Get-Date).TimeOfDay) PROCESS]: Removed <DTS:DesignTimeProperties> Node"

                Write-Verbose "[$((Get-Date).TimeOfDay) PROCESS]: Querying XML for SqlTaskData"
                $SqlTaskData = Select-Xml @Xpath -Content $XmlString
                $SqlTaskData | Format-Table | Out-String | Write-Debug
                Write-Verbose "[$((Get-Date).TimeOfDay) PROCESS]: Queried XML for SqlTaskData"

                Write-Verbose "[$((Get-Date).TimeOfDay) PROCESS]: Looping on SqlTask results for [ $($Plan.ScheduleName) ]"
                foreach ($SqlTask in $SqlTaskData.Node) {
                    if ($SqlTask.HasAttribute('SQLTask:BackupAction')) {
                        if (($Plan.ScheduleName -like '*Full*' -and $SqlTask.BackupFileExtension -eq '') -or
                            ($Plan.ScheduleName -like '*Diff*' -and $SqlTask.BackupFileExtension -in ('dif', 'bak')) -or
                            ($Plan.ScheduleName -like '*Trans*' -and $SqlTask.BackupFileExtension -eq 'trn')
                        ) {
                            [PSCustomObject]@{
                                TaskName                 = if ($null -eq $SqlTask.TaskName -or $SqlTask.TaskName -eq '') { $Plan.JobName } else { $SqlTask.TaskName }
                                Frequency                = $Plan.Frequency
                                IgnoreNotOnlineDatabases = $SqlTask.IgnoreDatabasesInNotOnlineState
                                BackupAction             = [BackupAction]$SqlTask.BackupAction
                                BackupExtension          = $SqlTask.BackupFileExtension
                                BackupDevice             = [BackupDevice]$SqlTask.BackupDeviceType
                                Compression              = [BackupCompressionAction]$SqlTask.BackupCompressionAction
                                CopyOnly                 = $SqlTask.CopyOnlyBackup
                                IsEncrypted              = $SqlTask.IsBackupEncrypted
                                HasChecksum              = $SqlTask.Checksum
                                SelectedDatabases        = ($SqlTask.SelectedDatabases).DatabaseName
                                PSTypeName               = 'MaintenancePlanDetails'
                            }
                        }
                    }
                }
            }
        }
    }
}

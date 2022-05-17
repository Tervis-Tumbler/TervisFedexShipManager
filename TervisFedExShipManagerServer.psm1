function Install-TervisFedexSMSHealthCheck {
	param (
		[Parameter(Mandatory,ValueFromPipelineByPropertyName)]$ComputerName
	)
	begin {
		$ScheduledTasksCredential = Get-TervisPasswordstatePassword `
			-Guid "eed2bd81-fd47-4342-bd59-b396da75c7ed" -AsCredential
	}
	process {
		$PowerShellApplicationParameters = @{
			ComputerName = $ComputerName
			EnvironmentName = "Infrastructure"
			ModuleName = "TervisFedExShipManagerServer"
			TervisModuleDependencies = `
				"WebServicesPowerShellProxyBuilder",
				"TervisMicrosoft.PowerShell.Utility",
				"TervisMicrosoft.PowerShell.Security",
				"PasswordstatePowershell",
				"TervisPasswordstatePowershell",
				"TervisMailMessage",
				"TervisFedExShipManagerServer"
			ScheduledTaskName = "FedExSMSHealthCheck"
			RepetitionIntervalName = "EveryDayEvery15Minutes"
			CommandString = "Invoke-TervisFedExSMSHealthCheck"
			ScheduledTasksCredential = $ScheduledTasksCredential
		}

		Install-PowerShellApplication @PowerShellApplicationParameters
	}
}

function Invoke-TervisFedExSMSHealthCheck {
	$FedexSMSServers = Get-ADComputer -Filter {Name -like "inf-fedexsms*"}

	$FedexSMSServers | ForEach-Object {
		$Server = $_.Name
		try {
			$FedexServices = Get-Service -DisplayName FedEx* -ComputerName $Server
		} catch {
			Write-Warning "Could not connect to $Server"
			Send-TervisMailMessage `
				-To "technicalservices@tervis.com" `
				-Subject "FSMS Heath Check: Could not connect to $Server" `
				-Body "Could not connect to $Server"
			return
		}
		$DownedServices = $FedexServices | Where-Object Status -ne "Running"

		$RunningCount = $FedexServices | Where-Object Status -eq "Running" |
			Measure-Object |
			Select-Object -ExpandProperty Count 
		$OtherCount = $FedexServices.Count - $RunningCount
		Write-Host "$Server - Services up: $RunningCount, down: $OtherCount"

		if (-not $DownedServices) { return }

		$DownedServices | Start-Service

		Start-Sleep 120

		$DownedServices | ForEach-Object {
			if ($_.Status -ne "Running") {
				Write-Warning "$Server - Attempt to start services has timed out. Restarting..."
				Restart-Computer -ComputerName $Server -Force
				return
			}
		}
	}
}

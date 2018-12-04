$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sut = (Split-Path -Leaf $MyInvocation.MyCommand.Path) -replace '\.Tests\.', '.'
. "$here\$sut"

Describe 'Testing Get-MaintenancePlanDetails results' {
    $Ast = [System.Management.Automation.Language.Parser]::ParseFile(
        "$here\$sut",
        # Not looking for errors or tokens at the moment.
        [ref]$null, [ref]$null
    )

    Context 'Parameters' {
        BeforeAll {
            $ParameterAst = $Ast.FindAll({
                $args[0] -is [System.Management.Automation.Language.ParameterAst]
            }, $true)
        }

        $Parameters = 'SqlInstance', 'Name'
        foreach ($Parameter in $Parameters) {
            It "has the expected parameter: [ $Parameter ]" {
                ($ParameterAst.Name.VariablePath.UserPath) -contains $Parameter |
                    Should -Be $true
            }
        }
    }
    
    Context 'Backup Results' {
        BeforeAll {
            Mock Invoke-DbaQuery {
                [PSCustomObject]@{
                    maintenance_plan_xml = Get-Content -Path "$here\TestMaintenancePlanXml.xml" -Raw
                    Frequency = "Daily: At 00:00:00"
                    JobName = "KneatO-USERDB-EXTRA-MONTHLY.Full"
                    ScheduleName = "KneatO-USERDB-EXTRA-MONTHLY.Full"
                    IsEnabled = $true
                }
            }
        }

        It 'should call the mocked "Invoke-DbaQuery"' {
            $null = Get-MaintenancePlanDetails -ServerName localhost
            Assert-MockCalled -CommandName Invoke-DbaQuery -Times 1
        }

        It 'should return a result for default parameters' {
            Get-MaintenancePlanDetails | Should -Not -BeNullOrEmpty
        }

        $DatabaseNames = 1..6 | ForEach-Object { "Database-{0:d2}" -f $_ }
        $FunctionResults = Get-MaintenancePlanDetails
        
        foreach ($DB in $DatabaseNames) {
            It "should have a record for the database: [ $DB ]" {
                $FunctionResults.SelectedDatabases -contains $DB | Should -be $true
            }
        }
    }
}

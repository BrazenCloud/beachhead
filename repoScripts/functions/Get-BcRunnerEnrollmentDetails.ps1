Function Get-BcRunnerEnrollmentDetails {
    [cmdletbinding()]
    param (
        [Parameter(Mandatory)]
        [string]$UtilityPath,
        [string]$Server = 'staging.brazencloud.com',
        [Parameter(Mandatory)]
        [string]$Token
    )
    $regex = '\> Enrollment: (Using ?)?(?<name>[^ ]+) (?<value>.*)\.'
    #        > Enrollment: UsingDesiredRunnerName default.
    & $UtilityPath -N -S $Server node -t $Token -d 0.00:00:00 --new | Where-Object { $_ -like '> Enrollment:*' } | Tee-Object -Variable 'enrollment'
    $ht = @{}
    foreach ($line in $enrollment) {
        if ($line -match $regex) {
            $ht[$Matches.name] = $Matches.value
        }
    }
    $ht
}
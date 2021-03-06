# Copyright 2011-2013 Amazon.com, Inc. or its affiliates. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License"). You
# may not use this file except in compliance with the License. A copy of
# the License is located at
#
#     http://aws.amazon.com/apache2.0/
#
# or in the "license" file accompanying this file. This file is
# distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF
# ANY KIND, either express or implied. See the License for the specific
# language governing permissions and limitations under the License.

<# 
.SYNOPSIS
    NAME: Create-InteractiveHiveJob.ps1
    This script shows an example of how to create an interactive hive job using powershell.
        
.DESCRIPTION
    This script creates an interactive EMR job, and runs a step to initialize Hive on the cluster. It assumes that the AWS tools for Windows Powershell library have
    been installed to your system in the default location.  For more information see http://aws.amAvailabilityZoneon.com/powershell/.  You need to replace <YOUR-LOG-BUCKET> and <YOUR-KEY-PAIR>
    with an S3  bucket in your account, and a key pair associated with your account.

.PARAMETER LogFileBucket
    This parameter specifies an existing S3 bucket to write the log files for the job to.
    DEFAULT: N/A
    Example: Create-InteractiveHiveJob.ps1 -LogFileBucket MyBucketName

.PARAMETER KeyName
    This parameter specifies a key pair name to use.  This key pair name must exist in your account, and will be used to log into the master node.
    DEFAULT: N/A
    Example: Create-InteractiveHiveJob.ps1 -KeyName MyBucketName
                
.PARAMETER AvailabilityZone
    This parameter specifies the availability zone to launch the instance to.
    DEFAULT: us-east-1b
    Example: Create-InteractiveHiveJob.ps1 -AvailabilityZone us-east-1a
    
.EXAMPLE
     Create-InteractiveHiveJob.ps1 

.NOTES
               NAME: Create-InteractiveHiveJob.ps1
               AUTHOR: Chris Keyser   
               AUTHOR EMAIL: ckeyser@amazon.com
               CREATION DATE: 1/18/2013
               LAST MODIFIED DATE:  1/18/2013
               LAST MODIFIED BY: Chris Keyser
               RELEASE VERSION: 0.0.1
#>
param( 
    [string] $LogFileBucket,
    [string] $KeyName, 
    [string] $AvailabilityZone
    )

Import-Module AWSPowerShell

if($LogFileBucket.length -eq 0)
{
    $LogFileBucket = Read-Host -prompt "Enter Log File Bucket"
}

if($KeyName.length -eq 0)
{
    $KeyName = Read-Host -prompt "Enter Key Pair Name"
}

if($AvailabilityZone.length -eq 0)
{
    $AvailabilityZone="us-east-1b"
}

$logUri = "s3n://" + $LogFileBucket + "/"

#
# This helper function step creates a step config, which specifies a step being submitted to the hadoop cluster.
#
Function CreateStepConfig
{
    param([string]$name, 
            [Amazon.ElasticMapReduce.Model.HadoopJarStepConfig] $stepToAdd, 
            [string]$actionOnFailure="CANCEL_AND_WAIT"
    )
     
    $stepconfig=New-Object  Amazon.ElasticMapReduce.Model.StepConfig
    $stepconfig.HadoopJarStep=$stepToAdd
    $stepconfig.Name=$name
    $stepconfig.ActionOnFailure=$actionOnFailure

    return $stepconfig
}

#
# This helper function adds a java step to a job.
#
Function AddJavaStep
{
    param([string]$name, 
        [string]$jar, 
        [string]$jobid, 
        [string[]] $jarargs, 
        [string]$actionOnFailure="CANCEL_AND_WAIT"
    )

    $step = CreateJavaStep $jar $jarargs
    $stepconfig = CreateStepConfig $name $step $actionOnFailure
    Add-EMRJobFlowStep -JobFlowId $jobid -Steps $stepconfig
}


$jobid = Start-EMRJobFlow -Name "Hive Job Flow" `
                          -Instances_MasterInstanceType "m1.large" `
                          -Instances_SlaveInstanceType "m1.large" `
                          -Instances_KeepJobFlowAliveWhenNoSteps $true `
                          -Instances_Placement_AvailabilityZone $AvailabilityZone `
                          -Instances_InstanceCount 1 `
                          -LogUri $loguri `
                          -VisibleToAllUsers $true `
                          -AmiVersion "latest" `
                          -Instances_Ec2KeyName $KeyName

#
# Wait for the cluster to complete starting.
#
$waitcnt = 0

do {
    Start-Sleep 10
    $starting = Get-EMRJobFlow -JobFlowStates ("STARTING") -JobFlowId $jobid
    $waitcnt = $waitcnt + 10
    Write-Host "Starting..." $waitcnt
}while($starting.Count -eq 1)
   
   
#
# Now create and add the step to start hive.  The step factory helps simlify the creation of this step for us.
#
                          
Write-Host "adding interactive hive setup step"

## For setting up interactive hive environment - first flow
$stepFactory = New-Object  Amazon.ElasticMapReduce.Model.StepFactory
$hiveSetupStep = $stepFactory.NewInstallHiveStep([Amazon.ElasticMapReduce.Model.StepFactory+HiveVersion]::Hive_Latest)
$hiveStepConfig = CreateStepConfig "Test Interactive Hive" $hiveSetupStep
Add-EMRJobFlowStep -JobFlowId $jobid -Steps $hiveStepConfig

$waitcnt = 0

do {
    Start-Sleep 10
    $running = Get-EMRJobFlow -JobFlowStates ("RUNNING") -JobFlowId $jobid
    $waitcnt = $waitcnt + 10
    Write-Host "Setting up Hive..." $waitcnt
}while($running.Count -eq 1)

#
# Hive is installed.  Get the public dns and display it.  This can then be used to ssh into the master node.
#

$jobflow = Get-EMRJobFlow -JobFlowStates ("WAITING") -JobFlowId $jobid
$masterdns = $jobflow[0].Instances.MasterPublicDnsName
Write-Host "Ready for interactive session, master dns: " $masterdns
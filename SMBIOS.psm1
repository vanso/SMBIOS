<#

Get-SMBIOS

Copyright (C) 2020 Vincent Anso

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.

This program was inspired by DMI Decode.

Copyright (C) 2000-2002 Alan Cox <alan@redhat.com>
Copyright (C) 2002-2020 Jean Delvare <jdelvare@suse.de>

https://www.nongnu.org/dmidecode/

#>

using module ".\SMBIOSLib.psm1"

using namespace System.Collections
using namespace System.Collections.Generic
using namespace System.Collections.Specialized

function Get-SMBIOS
{
    <#

    .SYNOPSIS
    Gets the System Management BIOS (SMBIOS) informations.

    .DESCRIPTION
    The Get-SMBIOS function gets the SMBIOS table contents in the form of objects.

    .INPUTS
    None. You cannot pipe objects to Get-SMBIOS.

    .OUTPUTS
    System.Collections.Generic.List[Object] Get-SMBIOS returns a list of SMBIOS objects.

    .EXAMPLE
    # Get all properties of Type 0 (BIOS).
    C:\PS> Get-SMBIOS -Type 0

    _Type           : 0
    _Description    : BIOS                                                                                                           
    _Handle         : 26
    Vendor          : Apple Inc.   
    Version         : 259.0.0.0.0
    ReleaseDate     : jeudi 13 juin 2019    
    AddressSegment  : 0x00000                                                                                                           
    ROMSize         : 8 192 Kb
    ImageSize       : 1 024 Kb
    Characteristics : {PCI is supported, BIOS is upgradeable (Flash), BIOS shadowing is allowed, Boot from CD is supported}
    Release         : 0.1
    FirmwareRelease : Not available

    .EXAMPLE
    # Display all properties of Type 0 (BIOS) and Type 1 (System).
    Get-SMBIOS -Type 0,1

    .EXAMPLE
    # Get Vendor and Version properties of Type 0
    C:\PS> Get-SMBIOS -Type 0 -Property Vendor, Version

    _Type        : 0                                                                                                                    
    _Description : BIOS                                                                                                                 
    _Handle      : 26                                                                                                                   
    Vendor       : Apple Inc.                                                                                                           
    Version      : 259.0.0.0.0      

    .EXAMPLE
    # Get the value of the Vendor property of Type 0 (as SMBString type).
    C:\PS> (Get-SMBIOS -Type 0 -Property Vendor).Vendor
    Apple Inc.

    .EXAMPLE
    # Get the value of the ChassisType property of Type 3 (as StringValue type).
    C:\PS> (Get-SMBIOS -Type 3 -Property ChassisType).ChassisType

    Value DisplayValue                                                                                                                  
    ----- ------------                                                                                                                     
       10 Notebook 

    .EXAMPLE
    # Get the value of the Features property of Type 2 (as StringValue array type).
    C:\PS> (Get-SMBIOS -Type 2 -Property Features).Features

    Value DisplayValue     
    ----- ------------     
        0 is a hosted board
        3 is replacable

    .LINK
    https://github.com/vanso/SMBIOS

    .LINK
    https://www.dmtf.org/standards/smbios

    #>
    
    [CmdletBinding(DefaultParameterSetName = "Type")]

    param(
        
        [Parameter(ParameterSetName = "Type", Position=0)]
        # Display all properties of a specified SMBIOS type.
        [Byte[]]$Type = 0..[Byte]::MaxValue,

        [Parameter(ParameterSetName = "Type", Position=1)]
        # Display selected properties of a specified SMBIOS type (Defined by the Type parameter).
        [String[]]$Property = "*",

        [Parameter(ParameterSetName = "Handle")]
        # Display all properties of a specified SMBIOS handle.
        [UInt16[]]$Handle = 0..[UInt16]::MaxValue,

        [Parameter(ParameterSetName = "Type")]
        # Display all properties in a expanded form (Value DisplayValue).
        [Switch]$Expand = $false,

        [Parameter(ParameterSetName = "Type")]
        # Specifies the memory size unit used for displaying memory capacities (B, kB, MB, GB, TB, PB ,EB ,ZB ,YB, Auto).
        [MemorySizeUnit]$MemorySizeUnit = [MemorySizeUnit]::Auto,

        [Parameter(ParameterSetName = "ListTypes")]
        # List all SMBIOS types.
        [Switch]$ListTypes,

        [Parameter(ParameterSetName = "ListAvailableTypes")]
        # List availables SMBIOS types.
        [Switch]$ListAvailableTypes,

        [Parameter(ParameterSetName = "ExcludeOEMTypes")]
        # List availables SMBIOS types without thoses greater than type 127.
        [Switch]$ExcludeOEMTypes,

        [Parameter(ParameterSetName = "Raw")]
        # Gets the SMBIOS table contents in the form of a minimal hash table (Type, Handle, Length, Data, Strings).
        [Switch]$Raw,
        
        [Parameter(ParameterSetName = "Version")]
        # Display the SMBIOS version.
        [Switch]$Version,

        [Parameter(ParameterSetName = "Statistics")]
        # Display statistics about the SMBIOS.
        [Switch]$Statistics
    )

    [Settings]::MemorySizeUnit = $MemorySizeUnit
    [Settings]::Verbose = $PSBoundParameters['Verbose']
    [Settings]::Expand = $Expand
    [Settings]::TemperatureUnit = [TemperatureUnit]::Celsius

    $PSPlatformName = $null

    # When $IsWindows doesn't exist on PowerShell 5.x
    if ($PSVersionTable.Platform) 
    {
        if ($IsMacOS)
        {
            $PSPlatformName = "macOS"

            [OSPlatform]::IsMacOS = $true
        }
        elseif ($IsLinux)
        {
            $PSPlatformName = "Linux"

            [OSPlatform]::IsLinux = $true
        }
        elseif ($IsWindows)
        {
            $PSPlatformName = "Windows"

            [OSPlatform]::IsWindows = $true
        }
    }
    else 
    {
        $PSPlatformName = "Windows"
    
        [OSPlatform]::IsWindows = $true    
    }

    Write-Verbose "PSPlatformName : $PSPlatformName"

    switch ($PSPlatformName)
    {
        "macOS" {
            $entryPoint = [SMBIOS]::ReadAppleSMBIOSProperty("`"SMBIOS-EPS`"")

            $tableData = [SMBIOS]::ReadAppleSMBIOSProperty("`"SMBIOS`"")
        }
        "Linux" {
            if (Test-Path -Path "/sys/firmware/dmi/tables/smbios_entry_point")
            {
                 try 
                 {
                    $entryPoint = [System.IO.File]::ReadAllBytes("/sys/firmware/dmi/tables/smbios_entry_point")
                 }
                 catch
                 {
                    Write-Host "An error occurred with reading the SMBIOS entry point ($($error[0].Exception.InnerException.Message))"

                    break
                 }
            }
            if (Test-Path -Path "/sys/firmware/dmi/tables/DMI")
            {
                try 
                {
                    $tableData = [System.IO.File]::ReadAllBytes("/sys/firmware/dmi/tables/DMI")
                }
                catch
                 {
                    Write-Host "An error occurred with reading the SMBIOS table $($error[0].Exception.InnerException.Message)"

                    break
                 }
            }
        }
        "Windows" {
            $SMBIOSRaw = (Get-CimInstance -Namespace root/WMI -ClassName MSSmBios_RawSMBiosTables -Verbose:$false -ErrorVariable cmdletError -ErrorAction SilentlyContinue)
            
            if ($cmdletError)
            {
                Write-Host "SMBIOS data not found ($($cmdletError.Exception.Message))."

                break
            }

            $tableData = $SMBIOSRaw.SMBIOSData
            
            [SMBIOS]::TableDataSize = $SMBIOSRaw.Size
            
            [SMBIOS]::Version = [Version]::new($SMBIOSRaw.SmbiosMajorVersion, $SMBIOSRaw.SmbiosMinorVersion)
        }
    }

    if ( -Not ([OSPlatform]::IsWindows) )
    {
        if ($entryPoint)
        {
            [SMBIOS]::ParseEntryPoint($entryPoint)
        }
        else
        {
            Write-Host "SMBIOS entry point not found."

            break
        }
    }

    if ($PSCmdlet.ParameterSetName -eq "Version")
    {
        return [SMBIOS]::Version
    }

    if ($tableData)
    {
        [SMBIOS]::ParseTableData($tableData)
    }
    else
    {
        Write-Host "SMBIOS table data not found."

        break
    }

    Write-Verbose "SMBIOS version : $([SMBIOS]::Version)"

    Write-Verbose "$([SMBIOS]::Structures.Count) structures found in $([SMBIOS]::TableDataSize) bytes."


    [List[Hashtable]]$elements = $null

    switch ($PSCmdlet.ParameterSetName)
    {
        "Type" {
            $elements = [SMBIOS]::Structures.FindAll( { $Type -contains $args[0].Type } )
        } 
             
        "Handle" {
            $elements = [SMBIOS]::Structures.FindAll( { $Handle -contains $args[0].Handle } )
        } 
            
        "ListTypes" {
            
            $list = [ArrayList]::new()
 
            for ($SMBIOSType = 0; $SMBIOSType  -le 44; $SMBIOSType++) 
            {   
                $list.Add( [SMBIOS]::Types[$SMBIOSType] ) | Out-Null
            }
            
            for ($SMBIOSType = 126; $SMBIOSType -le 127; $SMBIOSType++) 
            {   
                $list.Add( [SMBIOS]::Types[$SMBIOSType] ) | Out-Null
            }

            $list.Add( [SMBIOSType]::new(128, [Localization]::LocalizedString("START_OEM_RANGE") , @() ) ) | Out-Null
            
            $list.Add( [SMBIOSType]::new(255, [Localization]::LocalizedString("END_OEM_RANGE"), @() ) ) | Out-Null
    
            return $list
        }
          
        "ListAvailableTypes" {
            
            $availableTypes = [SMBIOS]::Structures.Type | Select-Object -Unique
            
            $list = [ArrayList]::new()
    
            foreach ($SMBIOSType in $availableTypes)
            {   
                $list.Add( [SMBIOS]::Types[$SMBIOSType] ) | Out-Null
            }
                
            return $list
        }
            
        "ExcludeOEMTypes" {
            
            $excludeTypes = [SMBIOS]::Structures.Type | Where-Object { $_ -le 127 } | Select-Object -Unique
            
            $list = [ArrayList]::new()
    
            foreach ($SMBIOSType in $excludeTypes)
            {    
                $list.Add( [SMBIOS]::Types[$SMBIOSType] ) | Out-Null  
            }
    
            return $list
        }
        "Raw" {
            return [SMBIOS]::Structures
        }
        "Statistics" {
            $unit = [Localization]::LocalizedString([MemorySizeUnit]::B)
                
            return [Ordered]@{ NumberOfStructures = $([SMBIOS]::Structures.Count) ; TableDataLength = $([StringValue]::new([SMBIOS]::TableDataSize, "{0} $unit")) }
        }
    }

    $outputs = [List[Object]]::new()

    $counter = 0

    foreach ($element in $elements)
    {    
        $_type = $element.Type
        $_length = $element.Length
        $_handle = $element.Handle
        $_data = $element.Data
        $_strings = $element.Strings
    
        $counter = $counter + 1
        
        Write-Progress -Activity "Structures remaining to be readed : $($elements.count - $counter)" -Status "Reading structure : $counter - Type : $_type ($([SMBIOS]::Types[$_type].Name)), Handle : $_handle, Length : $_length bytes" -PercentComplete $($counter / $elements.count * 100)

        switch ($_type) {
            0 {
                $object = [BIOSInformation]::new($_type, [SMBIOS]::Descriptions[$_type].Description, @("bios", "information"), $_length, $_handle, $_data, $_strings)

                break
            }
            1 {
                $object = [SystemInformation]::new($_type, [SMBIOS]::Descriptions[$_type].Description, @("system", "information"), $_length, $_handle, $_data, $_strings)

                break
            }
            2 {
                $object = [BaseboardInformation]::new($_type, [SMBIOS]::Descriptions[$_type].Description, @("baseboard", "module", "information"), $_length, $_handle, $_data, $_strings)
 
                break
            }
            3 {
                $object = [SystemEnclosure]::new($_type, [SMBIOS]::Descriptions[$_type].Description, @("system", "enclosure", "chassis"), $_length, $_handle, $_data, $_strings)

                break
            }
            4 {
                $object = [ProcessorInformation]::new($_type, [SMBIOS]::Descriptions[$_type].Description, @("processor", "information"), $_length, $_handle, $_data, $_strings)
            
                break
            }
            5 {
                $object = [MemoryControllerInformation]::new($_type, [SMBIOS]::Descriptions[$_type].Description, @("memory", "controller", "information"), $_length, $_handle, $_data, $_strings)

                break
            }
            6 {
                $object = [MemoryModuleInformation]::new($_type, [SMBIOS]::Descriptions[$_type].Description, @("memory", "module", "information"), $_length, $_handle, $_data, $_strings)
 
                break
            }
            7 {
                $object = [CacheInformation]::new($_type, [SMBIOS]::Descriptions[$_type].Description, @("cache", "information"), $_length, $_handle, $_data, $_strings)

                break
            }
            8 {
                $object = [PortConnectorInformation]::new($_type, [SMBIOS]::Descriptions[$_type].Description, @("port", "connector", "information"), $_length, $_handle, $_data, $_strings)
            
                break
            }
            9 {
                $object = [SystemSlots]::new($_type, [SMBIOS]::Descriptions[$_type].Description, @("sytem", "slots"), $_length, $_handle, $_data, $_strings)
            
                break
            }
            10 {
                $object = [OnBoardDevicesInformation]::new($_type, [SMBIOS]::Descriptions[$_type].Description, @("onboard", "devices", "information"), $_length, $_handle, $_data, $_strings)
            
                break
            }
            11 {
                $object = [OEMStrings]::new($_type, [SMBIOS]::Descriptions[$_type].Description, @("oem", "strings"), $_length, $_handle, $_data, $_strings)
            
                break
            }
            12 {
                $object = [SystemConfigurationOptions]::new($_type, [SMBIOS]::Descriptions[$_type].Description, @("strings"), $_length, $_handle, $_data, $_strings)
            
                break
            }
            13 {
                $object = [BIOSLanguageInformation]::new($_type, [SMBIOS]::Descriptions[$_type].Description, @("bios", "language", "information"), $_length, $_handle, $_data, $_strings)
            
                break
            }
            14 {
                $object = [GroupAssociations]::new($_type, [SMBIOS]::Descriptions[$_type].Description, @("group", "associations"), $_length, $_handle, $_data, $_strings)

                break
            }
            15 {
                $object = [SystemEventLog]::new($_type, [SMBIOS]::Descriptions[$_type].Description, @("system", "event", "log"), $_length, $_handle, $_data, $_strings)

                break
            }
            16 {
                $object = [PhysicalMemoryArray]::new($_type, [SMBIOS]::Descriptions[$_type].Description, @("physical", "memory"), $_length, $_handle, $_data, $_strings)

                break
            }
            17 {
                $object = [MemoryDevice]::new($_type, [SMBIOS]::Descriptions[$_type].Description, @("memory", "device"), $_length, $_handle, $_data, $_strings)
 
                break
            }
            18 {
                $object = [_32BitMemoryErrorInformation]::new($_type, [SMBIOS]::Descriptions[$_type].Description, @(), $_length, $_handle, $_data, $_strings)
 
                break
            }
            19 {
                $object = [MemoryArrayMappedAddress]::new($_type, [SMBIOS]::Descriptions[$_type].Description, @(), $_length, $_handle, $_data, $_strings)
 
                break
            }
            20 {
                $object = [MemoryDeviceMappedAddress]::new($_type, [SMBIOS]::Descriptions[$_type].Description, @(), $_length, $_handle, $_data, $_strings)
 
                break
            }
            21 {
                $object = [BuiltInPointingDevice]::new($_type, [SMBIOS]::Descriptions[$_type].Description, @(), $_length, $_handle, $_data, $_strings)
  
                break
            }
            22 {
                $object = [PortableBattery]::new($_type, [SMBIOS]::Descriptions[$_type].Description, @(), $_length, $_handle, $_data, $_strings)
 
                break
            }
            23 {
                $object = [SystemReset]::new($_type, [SMBIOS]::Descriptions[$_type].Description, @(), $_length, $_handle, $_data, $_strings)
     
                break
            }
            24 {
                $object = [HardwareSecurity]::new($_type, [SMBIOS]::Descriptions[$_type].Description, @(), $_length, $_handle, $_data, $_strings)
   
                break
            }
            25 {
                $object = [SystemPowerControls]::new($_type, [SMBIOS]::Descriptions[$_type].Description, @(), $_length, $_handle, $_data, $_strings)
         
                break
            }
            26 {
                $object = [VoltageProbe]::new($_type, [SMBIOS]::Descriptions[$_type].Description, @(), $_length, $_handle, $_data, $_strings)
         
                break
            }
            27 {
                $object = [CoolingDevice]::new($_type, [SMBIOS]::Descriptions[$_type].Description, @(), $_length, $_handle, $_data, $_strings)
        
                break
            }
            28 {
                $object = [TemperatureProbe]::new($_type, [SMBIOS]::Descriptions[$_type].Description, @(), $_length, $_handle, $_data, $_strings)
           
                break
            }
            29 {
                $object = [ElectricalCurrentProbe]::new($_type, [SMBIOS]::Descriptions[$_type].Description, @(), $_length, $_handle, $_data, $_strings)
         
                break
            }
            30 {
                $object = [OutOfBandRemoteAccess]::new($_type, [SMBIOS]::Descriptions[$_type].Description, @(), $_length, $_handle, $_data, $_strings)
          
                break
            }
            31 {
                $object = [BootIntegrityServicesEntryPoint]::new($_type, [SMBIOS]::Descriptions[$_type].Description, @(), $_length, $_handle, $_data, $_strings)
         
                break
            }
            32 {
                $object = [SystemBootInformation]::new($_type, [SMBIOS]::Descriptions[$_type].Description, @(), $_length, $_handle, $_data, $_strings)
           
                break
            }
            33 {
                $object = [_64BitMemoryErrorInformation]::new($_type, [SMBIOS]::Descriptions[$_type].Description, @(), $_length, $_handle, $_data, $_strings)
            
                break
            }
            34 {
                $object = [ManagementDevice]::new($_type, [SMBIOS]::Descriptions[$_type].Description, @(), $_length, $_handle, $_data, $_strings)
            
                break
            }
            35 {
                $object = [ManagementDeviceComponent]::new($_type, [SMBIOS]::Descriptions[$_type].Description, @(), $_length, $_handle, $_data, $_strings)
            
                break
            }
            36 {
                $object = [ManagementDeviceThresholdData]::new($_type, [SMBIOS]::Descriptions[$_type].Description, @(), $_length, $_handle, $_data, $_strings)
 
                break
            }
            37 {
                $object = [MemoryChannel]::new($_type, [SMBIOS]::Descriptions[$_type].Description, @(), $_length, $_handle, $_data, $_strings)
 
                break
            }
            38 {
                $object = [IPMIDeviceInformation]::new($_type, [SMBIOS]::Descriptions[$_type].Description, @(), $_length, $_handle, $_data, $_strings)
 
                break
            }
            39 {
                $object = [SystemPowerSupply]::new($_type, [SMBIOS]::Descriptions[$_type].Description, @(), $_length, $_handle, $_data, $_strings)
 
                break
            }
            40 {
                $object = [AdditionalInformation]::new($_type, [SMBIOS]::Descriptions[$_type].Description, @(), $_length, $_handle, $_data, $_strings)
 
                break
            }
            41 {
                $object = [OnboardDevicesExtendedInformation]::new($_type, [SMBIOS]::Descriptions[$_type].Description, @(), $_length, $_handle, $_data, $_strings)
 
                break
            }
            42 {
                $object = [ManagementControllerHostInterface]::new($_type, [SMBIOS]::Descriptions[$_type].Description, @(), $_length, $_handle, $_data, $_strings)
  
            }
            43 {
                $object = [TPMDevice]::new($_type, [SMBIOS]::Descriptions[$_type].Description, @(), $_length, $_handle, $_data, $_strings)
 
            }
            44 {
                $object = [ProcessorAdditionalInformation]::new($_type, [SMBIOS]::Descriptions[$_type].Description, @(), $_length, $_handle, $_data, $_strings)
 
            }
            126 {
                $object = [Inactive]::new($_type, [SMBIOS]::Descriptions[$_type].Description, @(), $_length, $_handle, $_data, $_strings)
 
                break
            }
            127 {
                $object = [EndOfTable]::new($_type, [SMBIOS]::Descriptions[$_type].Description, @(), $_length, $_handle, $_data, $_strings)
 
                break
            }
            default {
                $object = [OEMSpecificInformation]::new($_type, [SMBIOS]::Descriptions[$_type].Description, @(), $_length, $_handle, $_data, $_strings)
            
                break
            }
        }
        
        $object.SetProperties($Property)
    
        $object.Properties.GetEnumerator() | ForEach-Object { 
               
            $object | Add-Member -MemberType NoteProperty -Name $($_.Key) -Value $($_.Value) -Force
        }

        $outputs.Add($object)
    }

    Write-Progress "Done" -Completed

    return $outputs
}

Export-ModuleMember -Function Get-SMBIOS

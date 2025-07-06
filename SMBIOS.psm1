<#

SMBIOS

Copyright (C) 2020-2025 Vincent Anso

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
Copyright (C) 2002-2024 Jean Delvare <jdelvare@suse.de>

https://www.nongnu.org/dmidecode/

#>

using module ".\SMBIOSLib.psm1"

using namespace System.Collections
using namespace System.Collections.Generic
using namespace System.Collections.Specialized
using namespace System.Text
using namespace System.IO


function Get-SMBIOSVersion
{
    <#

    .SYNOPSIS
    Gets the SMBIOS version.

    #>
    
    [OutputType([Void])]
    [OutputType([Version])]
    param (
        [String]$FilePath
    )

    if (Get-SMBIOSEntryPoint -FilePath $FilePath)
    {
        return [SMBIOS]::Version
    }
}

function Get-SMBIOSEntryPoint
{
    <#

    .SYNOPSIS
    Gets the SMBIOS entry point as an array of bytes.

    #>
    
    [OutputType([Void])]
    [OutputType([Byte[]])]
    param (
        [String]$FilePath
    )
    
    $PSPlatformName = LocalizedString "UNKNOWN"

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

    if (-Not ([String]::IsNullOrEmpty($FilePath)))
    {
        $PSPlatformName = "File"
    }

    Write-Verbose "PSPlatformName : $PSPlatformName"

    switch ($PSPlatformName)
    {
        "macOS" {
            $arch = /usr/bin/arch

            if ( $arch -eq "arm64" )
            {
                Write-Warning $( LocalizedString "SMBIOS_NOT_SUPPORTED_MAC_APPLE_SILICON" )

                exit
            }
            elseif ( $arch -eq "i386" )
            {
                $entryPoint = [SMBIOS]::ReadAppleSMBIOSProperty("`"SMBIOS-EPS`"")

                $tableData = [SMBIOS]::ReadAppleSMBIOSProperty("`"SMBIOS`"")
            }
        }
        "Linux" {
            if (Test-Path -Path "/sys/firmware/dmi/tables/smbios_entry_point")
            {
                 try 
                 {
                    $entryPoint = [File]::ReadAllBytes("/sys/firmware/dmi/tables/smbios_entry_point")
                 }
                 catch
                 {
                    Write-Warning $( [String]::Format( $(LocalizedString "SMBIOS_ENTRY_POINT_ERROR"), $($error[0].Exception.InnerException.Message) ) )

                    break
                 }
            }
            if (Test-Path -Path "/sys/firmware/dmi/tables/DMI")
            {
                try 
                {
                    $tableData = [File]::ReadAllBytes("/sys/firmware/dmi/tables/DMI")
                }
                catch
                 {
                    Write-Warning $( [String]::Format( $(LocalizedString "SMBIOS_TABLE_DATA_ERROR"), $($error[0].Exception.InnerException.Message) ) )
                    
                    break
                 }
            }
        }
        "Windows" {
            $SMBIOSRaw = (Get-CimInstance -Namespace root/WMI -ClassName MSSmBios_RawSMBiosTables -Verbose:$false -ErrorVariable cmdletError -ErrorAction SilentlyContinue)

            if ($cmdletError)
            {
                Write-Warning $( [String]::Format( $(LocalizedString "SMBIOS_TABLE_DATA_ERROR"), $($cmdletError.Exception.Message)) )

                break
            }

            $tableData = $SMBIOSRaw.SMBIOSData

            switch ($SMBIOSRaw.SmbiosMajorVersion) {
                2 { $tableData
                    [Byte[]]$anchor = 0x5F, 0x53, 0x4D, 0x5F

                    $entryPoint = $anchor +
                                  0x00 +
                                  0x1F +
                                  $SMBIOSRaw.SmbiosMajorVersion +
                                  $SMBIOSRaw.SmbiosMinorVersion +
                                  0x00, 0x00 +
                                  0x00 +
                                  0x00, 0x00, 0x00, 0x00, 0x00 +
                                  0x5F, 0x44, 0x4D, 0x49, 0x5F +
                                  0x00 +
                                  [BitConverter]::GetBytes([UInt16]$SMBIOSRaw.Size) +
                                  0x00, 0x00, 0x00, 0x00 +
                                  0x00, 0x00 +
                                  $SMBIOSRaw.DmiRevision
                }
                3 {
                    [Byte[]]$anchor = 0x5F, 0x53, 0x4D, 0x33, 0x5F

                    $entryPoint = $anchor +
                                  0x00 +
                                  0x18 +
                                  $SMBIOSRaw.SmbiosMajorVersion +
                                  $SMBIOSRaw.SmbiosMinorVersion +
                                  $SMBIOSRaw.DmiRevision +
                                  0x01 +
                                  0x00 +
                                  $([BitConverter]::GetBytes([UInt32]$SMBIOSRaw.Size)) +
                                  $([BitConverter]::GetBytes([UInt64]0x20))
                }
            }
        }
        "File" {
            
            try 
            {
                $entryPoint = [File]::ReadAllBytes($FilePath)
                
                $tableData = $entryPoint
            }
            catch 
            {
                Write-Warning $( [String]::Format( $(LocalizedString "SMBIOS_READ_FILE_ERROR"), $($error[0].Exception.InnerException.Message) ) )
            }
        }
    }

    if ($entryPoint)
    {   
        [SMBIOS]::ParseEntryPoint($entryPoint)

        if ($PSPlatformName -eq "File")
        {
            $structureTableAddress = [SMBIOS]::StructureTableAddress

            [SMBIOS]::TableData = [ArraySegment[Byte]]::new($tableData, $structureTableAddress, $tableData.Count - $structureTableAddress)
        }
        else 
        {
            [SMBIOS]::TableData = $tableData
        }
    }
    else
    {
        Write-Warning $( LocalizedString "SMBIOS_ENTRY_POINT_NOT_FOUND" )

        break # return $null
    }

    return $entryPoint
}

function Parse-SMBIOSTableData
{
    if ([SMBIOS]::Version -ge [Version]::new(3,5))
    {
        [SMBIOS]::Encoding = [Encoding]::UTF8
    }
    else
    {
        [SMBIOS]::Encoding = [Encoding]::ASCII
    }

    if ([SMBIOS]::TableData)
    {
        [SMBIOS]::ParseTableData()
    }
    else
    {
        Write-Warning $( LocalizedString "SMBIOS_TABLE_DATA_NOT_FOUND" )

        break
    }
}

function Add-SMBIOSStructure 
{
    param (
        [String]$FilePath,
        [ValidateNotNull()]
        [List[Hashtable]]$Value
    )

    if (Get-SMBIOSEntryPoint -FilePath $FilePath)
    {
        Parse-SMBIOSTableData

        if ($Value)
        {
            foreach ($SMBIOSData in $Value.GetEnumerator())
            {
                [SMBIOS]::Structures.Add($SMBIOSData)
            }
        }
    }
}

function Get-SMBIOSTableData
{
    <#

    .SYNOPSIS
    Gets the SMBIOS table data as an array of bytes.

    #>
    
    [OutputType([Void])]
    [OutputType([Byte[]])]
    param (
        [String]$FilePath
    )

    if (Get-SMBIOSEntryPoint -FilePath $FilePath)
    {
        if ([SMBIOS]::TableData)
        {
            return [SMBIOS]::TableData
        }
        else
        {
            Write-Warning $(LocalizedString "SMBIOS_TABLE_DATA_NOT_FOUND" )

            break
        }
    }
}

function Update-SMBIOSStructure 
{
    param (
        [String]$FilePath,
        [ValidateNotNull()]
        [List[Hashtable]]$Value
    )

    if (Get-SMBIOSEntryPoint -FilePath $FilePath)
    {
        Parse-SMBIOSTableData

        if ($Value)
        {
            foreach ($SMBIOSData in $Value.GetEnumerator())
            {                    
                $typesToUpdate = [SMBIOS]::Structures.FindAll( { $($SMBIOSData.Type) -contains $args[0].Type } )

                foreach ($typeToUpdate in $typesToUpdate)
                {
                    if ($SMBIOSData.Data)
                    {
                        if ($null -eq $SMBIOSData.Offset)
                        {
                            $SMBIOSData.Offset = 0
                        }

                        [Array]::Copy($SMBIOSData.Data, 0, $typeToUpdate.Data, $SMBIOSData.Offset, $SMBIOSData.Data.Count)
                    }

                    if ($SMBIOSData.Strings)
                    {                            
                        $typeToUpdate.Strings.AddRange($SMBIOSData.Strings)
                    }

                    if ($SMBIOSData.StringAtIndex)
                    {
                        foreach($item in ($SMBIOSData.StringAtIndex).GetEnumerator())
                        {
                            $typeToUpdate.Strings.RemoveAt( $($item.Key) )
                            $typeToUpdate.Strings.Insert( $($item.Key), $($item.Value) )
                        }
                    }
                }
            }
        }
    }
}

function Export-SMBIOS
{
    <#

    .SYNOPSIS
    Export a dump of the SMBIOS to a file that can be read with the Get-SMBIOS function.

    #>
    
    param (
        [Parameter(Mandatory=$true)]
        [String]$FilePath
    )

    Get-SMBIOSEntryPoint | Out-Null

    $SMBIOSMajorVersion = [SMBIOS]::Version.Major

    switch ($SMBIOSMajorVersion) {
        2 { 
            [Byte[]]$anchor = 0x5F, 0x53, 0x4D, 0x5F

            $entryPoint = $anchor +
                          0x00 +
                          0x1F +
                          [SMBIOS]::Version.Major +
                          [SMBIOS]::Version.Minor +
                          0x00, 0x00 +
                          0x00 +
                          0x00, 0x00, 0x00, 0x00, 0x00 +
                          0x5F, 0x44, 0x4D, 0x49, 0x5F +
                          0x00 +
                          [BitConverter]::GetBytes([UInt16][SMBIOS]::TableDataSize) +
                          $([BitConverter]::GetBytes([UInt64]0x20))
                          $([BitConverter]::GetBytes([UInt16][SMBIOS]::Structures.Count))
                          0x00
        }
        3 {
            [Byte[]]$anchor = 0x5F, 0x53, 0x4D, 0x33, 0x5F

            $entryPoint = $anchor +
                          0x00 +
                          0x18 +
                          $([SMBIOS]::Version.Major) +
                          $([SMBIOS]::Version.Minor) +
                          0x00 +
                          0x01 +
                          0x00 +
                          $([BitConverter]::GetBytes([UInt32][SMBIOS]::TableData.Count)) +
                          $([BitConverter]::GetBytes([UInt64]0x20)) +
                          $([BitConverter]::GetBytes([UInt64]0x00))
        }
    }

    try 
    {
        [File]::WriteAllBytes($FilePath, $entryPoint + [SMBIOS]::TableData )
    }
    catch 
    {
        Write-Warning $( [String]::Format( $(LocalizedString "SMBIOS_WRITE_FILE_ERROR"), $($error[0].Exception.InnerException.Message) ) )
    }
}

function Get-SMBIOSTypes
{
    <#

    .SYNOPSIS
    List the standard SMBIOS types.

    #>
    
    $list = [ArrayList]::new()
 
    for ($SMBIOSType = 0; $SMBIOSType -le 46; $SMBIOSType++) 
    {   
        $list.Add( [SMBIOS]::Types[$SMBIOSType] ) | Out-Null
    }
    
    for ($SMBIOSType = 126; $SMBIOSType -le 127; $SMBIOSType++) 
    {   
        $list.Add( [SMBIOS]::Types[$SMBIOSType] ) | Out-Null
    }

    $list.Add( [SMBIOSType]::new(128, $(LocalizedString "START_OEM_RANGE"), @() ) ) | Out-Null
    
    $list.Add( [SMBIOSType]::new(255, $(LocalizedString "END_OEM_RANGE"  ), @() ) ) | Out-Null
    
    return $list
}

function Get-SMBIOSAvailableTypes 
{
    <#

    .SYNOPSIS
    List the available SMBIOS types in a synthetic way.

    #>
    
    [CmdletBinding()]
    param (
        [String]$FilePath,
        [Switch]$ExcludeOEMTypes
    )

    $list = [ArrayList]::new()

    if (Get-SMBIOSEntryPoint -FilePath $FilePath)
    {
        Parse-SMBIOSTableData

        Write-Verbose $( [String]::Format( $(LocalizedString "SMBIOS_VERSION"), $([SMBIOS]::Version) ) )

        Write-Verbose $( [String]::Format( $(LocalizedString "SMBIOS_SIZE_INFO"), $([SMBIOS]::Structures.Count), $([SMBIOS]::TableDataSize) ) )

        if ($ExcludeOEMTypes)
        {
            $availableTypes = [SMBIOS]::Structures.Type | Where-Object { $_ -le 127 } | Group-Object
        }
        else 
        {
            $availableTypes = [SMBIOS]::Structures.Type | Group-Object
        }
    
        foreach ($availableType in $availableTypes)
        {                   
            $index = $availableType.Name
            
            $SMBIOSType = [SMBIOS]::Types[$index]

            $handle = ([SMBIOS]::Structures | Where-Object Type -eq $index).Handle

            $AvailableSMBIOSType = [SMBIOSAvailableType]::new( $availableType.Count, $SMBIOSType.Type, $SMBIOSType.Name, $handle )

            $list.Add( $AvailableSMBIOSType ) | Out-Null
        }
    }

    return $list
}

function Get-SMBIOSInfo
{
    <#

    .SYNOPSIS
    Gets general info about the SMBIOS.

    #>
    
    param (
        [String]$FilePath
    )

    if (Get-SMBIOSEntryPoint -FilePath $FilePath)
    {
        Parse-SMBIOSTableData

        $unit = [Localization]::LocalizedString([MemorySizeUnit]::B)

        return [PSCustomObject]@{
            Version            = [SMBIOS]::Version
            SupportedVersion   = [SMBIOS]::SupportedVersion
            NumberOfStructures = [SMBIOS]::Structures.Count
            TableDataSize      = [StringValue]::new([SMBIOS]::TableDataSize, "{0} $unit")
            Encoding           = [SMBIOS]::Encoding
        }
    }
}

function Get-SMBIOS
{
    <#

    .SYNOPSIS
    Gets the System Management BIOS (SMBIOS) information.

    .DESCRIPTION
    The Get-SMBIOS function gets the SMBIOS table contents in the form of objects.

    .INPUTS
    None. You cannot pipe objects to Get-SMBIOS.

    .OUTPUTS
    System.Collections.Generic.List[Object] Get-SMBIOS returns a list of SMBIOS objects.

    .EXAMPLE
    # Get all properties of Type 0 (BIOS).
    C:\PS> Get-SMBIOS -Type 0

    Header          : Handle 0x0000, DMI type 0 (BIOS Information), 26 bytes
    Vendor          : Dell Inc.
    Version         : 2.25.0
    ReleaseDate     : lundi 9 décembre 2024
    AddressSegment  : 0xF0000
    ROMSize         : 32 MB
    ImageSize       : 64 kB
    Characteristics : {PCI is supported, Plug and Play is supported, BIOS is upgradeable (Flash), BIOS shadowing is allowed...}
    Release         : 2.25
    FirmwareRelease : Not Available

    .EXAMPLE
    # Display all properties of Type 0 (BIOS) and Type 1 (System).
    Get-SMBIOS -Type 0,1

    .EXAMPLE
    # Get Vendor and Version properties of Type 0
    C:\PS> Get-SMBIOS -Type 0 -Property Vendor, Version

    Header  : Handle 0x0000, DMI type 0 (BIOS Information), 26 bytes
    Vendor  : Dell Inc.
    Version : 2.25.0

    .EXAMPLE
    # Get the value of the Vendor property of Type 0 (as SMBString type).
    C:\PS> (Get-SMBIOS -Type 0 -Property Vendor).Vendor
    Dell Inc.

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

    param (

        [Parameter(ParameterSetName = "Debug")]
        # For debugging purpose only.
        [Switch]$Debugging,

        [Parameter(ParameterSetName = "Raw")]
        # Gets the SMBIOS table contents in the form of a minimal hash table (Type, Handle, Length, Data, Strings).
        [Switch]$Raw,

        [Parameter(ParameterSetName = "Debug")]
        [Parameter(ParameterSetName = "Type", Position=0)]
        [Parameter(ParameterSetName = "Raw", Position=1)]
        # Display all properties of a specified SMBIOS type.
        [ValidateRange(0,[Byte]::MaxValue)]
        [Byte[]]$Type = 0..[Byte]::MaxValue,

        [Parameter(ParameterSetName = "Handle")]
        # Display all properties of a specified SMBIOS handle.
        [ValidateRange(0,[UInt16]::MaxValue)]
        [UInt16[]]$Handle = 0..[UInt16]::MaxValue,

        [Parameter(ParameterSetName = "Debug")]
        [Parameter(ParameterSetName = "Type", Position=1)]
        # Display selected properties of a specified SMBIOS type (Defined by the Type parameter).
        [String[]]$Property = "*",

        [Parameter(ParameterSetName = "Type")]
        # Hide the header of a specific Type (Type, Handle, Length).
        [Switch]$HideHeader = $false,

        [Parameter(ParameterSetName = "Debug")]
        [Parameter(ParameterSetName = "Type")]
        # Display all properties in a expanded form (Value DisplayValue).
        [Switch]$Expand = $false,

        [Parameter(ParameterSetName = "Debug")]
        [Parameter(ParameterSetName = "Type")]
        # Specifies the memory size unit used for displaying memory capacities (B, kB, MB, GB, TB, PB ,EB ,ZB ,YB, Auto).
        [ValidateSet("B", "kB", "MB", "GB", "TB", "PB", "EB", "ZB", "YB", "Auto")]
        [MemorySizeUnit]$MemorySizeUnit = [MemorySizeUnit]::Auto,

        [Parameter(ParameterSetName = "Debug")]
        [Parameter(ParameterSetName = "Type")]
        # Specifies the temperature unit used for displaying temperatures (Celsius, Fahrenheit, Auto).
        [ValidateSet("Celsius", "Fahrenheit", "Auto")]
        [TemperatureUnit]$TemperatureUnit = [TemperatureUnit]::Auto,

        [Parameter(ParameterSetName = "Debug")]
        [Parameter(ParameterSetName = "ListAvailableTypes")]
        [Parameter(ParameterSetName = "Type")]
        [Parameter(ParameterSetName = "Raw")]
        [Parameter(ParameterSetName = "Handle")]
        [ValidateNotNullOrEmpty()]
        # Specifies the file path to use. Can read a file exported with dmidecode.
        [String]$FilePath,

        [Parameter(ParameterSetName = "Debug")]
        [Parameter(ParameterSetName = "Type")]
        [ValidateNotNullOrEmpty()]
        [ValidateRange("2.0", "3.7")]
        # Specifies the maximum version of SMBIOS that will be interpreted.
        [Version]$MaximumVersion = [SMBIOS]::Version,

        [Parameter(ParameterSetName = "Debug")]
        [ValidateNotNullOrEmpty()]
        # Add a SMBIOS structure in a raw format (For debugging purpose only).
        [List[Hashtable]]$AddSMBIOSData,
        
        [Parameter(ParameterSetName = "Debug")]
        [ValidateNotNullOrEmpty()]
        # Update a SMBIOS structure in a raw format (For debugging purpose only).
        [List[Hashtable]]$UpdateSMBIOSData,

        [Parameter(ParameterSetName = "ListTypes")]
        # List all SMBIOS types.
        [Switch]$ListTypes,

        [Parameter(ParameterSetName = "ListAvailableTypes")]
        # List available SMBIOS types.
        [Switch]$ListAvailableTypes,

        [Parameter(ParameterSetName = "Debug")]
        [Parameter(ParameterSetName = "Type")]
        [Parameter(ParameterSetName = "ListAvailableTypes")]
        # List available SMBIOS types without thoses greater than type 127.
        [Switch]$ExcludeOEMTypes,

        [Parameter(ParameterSetName = "Debug")]
        [Parameter(ParameterSetName = "Type")]
        # Doesn't displayed properties of a specified SMBIOS type.
        [ValidateRange(0,[Byte]::MaxValue)]
        [Byte[]]$ExcludeType,

        [Parameter(ParameterSetName = "Type")]
        # Doesn't displayed the SMBIOS strings in bold.
        [Switch]$NoEmphasis = $false,

        [Parameter(DontShow, ParameterSetName = "Version")]
        # Display the SMBIOS version.
        [switch]$Version,

        [Parameter(DontShow, ParameterSetName = "Statistics")]
        # Display statistics about the SMBIOS.
        [Switch]$Statistics 
    )

    [Settings]::MemorySizeUnit = $MemorySizeUnit
    [Settings]::Verbose = $PSBoundParameters['Verbose']
    [Settings]::Expand = $Expand
    [Settings]::TemperatureUnit = [TemperatureUnit]::Celsius
    [Settings]::HideHeader = $HideHeader
    [Settings]::NoEmphasis = $NoEmphasis

    Get-SMBIOSEntryPoint -FilePath $FilePath | Out-Null
    
    if ([SMBIOS]::SupportedVersion -lt [SMBIOS]::Version)
    {
        Write-Warning $( [String]::Format( $(LocalizedString "SMBIOS_PRESENT"            ), [SMBIOS]::Version          ) )
        Write-Warning $( [String]::Format( $(LocalizedString "SMBIOS_NOT_FULLY_SUPPORTED"), [SMBIOS]::SupportedVersion ) )
    }

    if ($PSCmdlet.ParameterSetName -eq "Version")
    {
        Write-Warning $(LocalizedString "DEPRECATED_VERSION_PARAMETER")
        
        return [SMBIOS]::Version
    }

    Parse-SMBIOSTableData

    Write-Verbose $( [String]::Format( $(LocalizedString "SMBIOS_VERSION"), $([SMBIOS]::Version) ) )

    if ($PSBoundParameters['MaximumVersion'])
    {
        if ($MaximumVersion -gt [SMBIOS]::Version)
        {
            Write-Warning $( [String]::Format( $(LocalizedString "SMBIOS_MAXIMUM_VERSION_GREATER_SMBIOS_VERSION" ), $MaximumVersion, [SMBIOS]::Version ) )
        }
        else 
        {
            [SMBIOS]::Version = $MaximumVersion
        }
    }

    if ($PSBoundParameters['MaximumVersion'])
    {
        Write-Verbose $( [String]::Format( $(LocalizedString "SMBIOS_MAXIMUM_VERSION"), $([SMBIOS]::Version) ) )
    }

    Write-Verbose $( [String]::Format( $(LocalizedString "SMBIOS_SIZE_INFO"), $([SMBIOS]::Structures.Count), $([SMBIOS]::TableDataSize) ) )

    $elements = [List[Hashtable]]::new()

    switch ($PSCmdlet.ParameterSetName)
    {
        "Type" 
        {
            if ($PSBoundParameters['AddSMBIOSData'])
            {
                foreach ($SMBIOSData in $AddSMBIOSData.GetEnumerator())
                {
                    [SMBIOS]::Structures.Add($SMBIOSData)
                }
            }
            
            if ($PSBoundParameters['UpdateSMBIOSData'])
            {
                foreach ($SMBIOSData in $UpdateSMBIOSData.GetEnumerator())
                {                    
                    $typesToUpdate = [SMBIOS]::Structures.FindAll( { $($SMBIOSData.Type) -contains $args[0].Type } )

                    foreach ($typeToUpdate in $typesToUpdate)
                    {
                        if ($SMBIOSData.Data)
                        {
                            if ($null -eq $SMBIOSData.Offset)
                            {
                                $SMBIOSData.Offset = 0
                            }

                            [Array]::Copy($SMBIOSData.Data, 0, $typeToUpdate.Data, $SMBIOSData.Offset, $SMBIOSData.Data.Count)
                        }

                        if ($SMBIOSData.Strings)
                        {                            
                            $typeToUpdate.Strings.AddRange($SMBIOSData.Strings)
                        }

                        if ($SMBIOSData.StringAtIndex)
                        {
                            foreach($item in ($SMBIOSData.StringAtIndex).GetEnumerator())
                            {
                                $typeToUpdate.Strings.RemoveAt( $($item.Key) )
                                $typeToUpdate.Strings.Insert( $($item.Key), $($item.Value) )
                            }
                        }
                    }
                }
            }
            
            $elements = [SMBIOS]::Structures.FindAll( { $Type -contains $args[0].Type } )

            if ($PSBoundParameters['ExcludeType'])
            {
                $elements.RemoveAll( { $ExcludeType -contains $args[0].Type } ) | Out-Null
            }

            if ($PSBoundParameters['ExcludeOEMTypes'])
            {
                $elements.RemoveAll( {  @(128..256) -contains $args[0].Type } ) | Out-Null
            }
        } 
             
        "Handle" 
        {
            $elements = [SMBIOS]::Structures.FindAll( { $Handle -contains $args[0].Handle } )
        }
        
        "ListTypes" 
        {    
            $list = [ArrayList]::new()
 
            for ($SMBIOSType = 0; $SMBIOSType -le 46; $SMBIOSType++) 
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
          
        "ListAvailableTypes"
        {
            if ($PSBoundParameters['ExcludeOEMTypes'])
            {                
                $availableTypes = [SMBIOS]::Structures.Type | Where-Object { $_ -le 127 } | Group-Object
            }
            else 
            {
                $availableTypes = [SMBIOS]::Structures.Type | Group-Object
            }

            $list = [ArrayList]::new()
    
            foreach ($availableType in $availableTypes)
            {                   
                $index = $availableType.Name
                
                $SMBIOSType = [SMBIOS]::Types[$index]

                $handle = ([SMBIOS]::Structures | Where-Object Type -eq $index).Handle
   
                $AvailableSMBIOSType = [SMBIOSAvailableType]::new( $availableType.Count, $SMBIOSType.Type, $SMBIOSType.Name, $handle )

                $list.Add( $AvailableSMBIOSType ) | Out-Null
            }
            
            return $list
        }

        "Raw"
        {            
            return [SMBIOS]::Structures.FindAll( { $Type -contains $args[0].Type } )
        }
        
        "Version"
        {
            Write-Warning $(LocalizedString "DEPRECATED_VERSION_PARAMETER")
            return Get-SMBIOSVersion
        }

        "Statistics"
        {
            Write-Warning $(LocalizedString "DEPRECATED_STATISTICS_PARAMETER")
            return Get-SMBIOSInfo
        }
    }

    $counter = 0

    foreach ($element in $elements)
    {
        $_type = $element.Type
        $_length = $element.Length
        $_handle = $element.Handle
        $_data = $element.Data
        $_strings = $element.Strings

        $counter++

        $object = $null

        Write-Progress -Activity $([String]::Format($(LocalizedString SMBIOS_PROGRESS_ACTIVITY), $($elements.count - $counter))) -Status $([String]::Format($(LocalizedString SMBIOS_PROGRESS_STATUS), $counter, $_type, $([SMBIOS]::Types[$_type].Name), $_handle, $_length)) -PercentComplete $($counter / $elements.count * 100)

        if ( [SMBIOS]::Version -ge [Version]::new(2, 0) )
        {
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
            }
        }

        if ( [SMBIOS]::Version -ge [Version]::new(2, 1) )
        {
            switch ($_type) {
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
            }
        }

        if ( [SMBIOS]::Version -ge [Version]::new(2, 2) )
        {
            switch ($_type) {
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
            }
        }

        if ( [SMBIOS]::Version -ge [Version]::new(2, 3) )
        {
            switch ($_type) {
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
                37 {
                    $object = [ManagementDeviceThresholdData]::new($_type, [SMBIOS]::Descriptions[$_type].Description, @(), $_length, $_handle, $_data, $_strings)
    
                    break
                }
            }
        }

        if ( [SMBIOS]::Version -ge [Version]::new(2, 3, 1) )
        {
            switch ($_type) {
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
            }
        }

        if ( [SMBIOS]::Version -ge [Version]::new(2, 6) )
        {
            switch ($_type) {
                40 {
                    $object = [AdditionalInformation]::new($_type, [SMBIOS]::Descriptions[$_type].Description, @(), $_length, $_handle, $_data, $_strings)

                    break
                }
                41 {
                    $object = [OnboardDevicesExtendedInformation]::new($_type, [SMBIOS]::Descriptions[$_type].Description, @(), $_length, $_handle, $_data, $_strings)

                    break
                }
            }
        }

        if ( [SMBIOS]::Version -ge [Version]::new(2, 7) )
        {
            switch ($_type) {
                42 {
                    $object = [ManagementControllerHostInterface]::new($_type, [SMBIOS]::Descriptions[$_type].Description, @(), $_length, $_handle, $_data, $_strings)
            
                    break
                }
            }
        }

        if ( [SMBIOS]::Version -ge [Version]::new(3, 1) )
        {
            switch ($_type) {
                43 {
                    $object = [TPMDevice]::new($_type, [SMBIOS]::Descriptions[$_type].Description, @(), $_length, $_handle, $_data, $_strings)
            
                    break
                }
            }
        }

        if ( [SMBIOS]::Version -ge [Version]::new(3, 3) )
        {
            switch ($_type) {
                44 {
                    $object = [ProcessorAdditionalInformation]::new($_type, [SMBIOS]::Descriptions[$_type].Description, @(), $_length, $_handle, $_data, $_strings)

                    break
                }
            }
        }

        if ( [SMBIOS]::Version -ge [Version]::new(3, 5) )
        {
            switch ($_type) {
                45 {
                    $object = [FirmwareInventoryInformation]::new($_type, [SMBIOS]::Descriptions[$_type].Description, @(), $_length, $_handle, $_data, $_strings)
                
                    break
                }
                46 {
                    $object = [StringProperty]::new($_type, [SMBIOS]::Descriptions[$_type].Description, @(), $_length, $_handle, $_data, $_strings)
                
                    break
                }
            }
        }

        if ( [SMBIOS]::Version -ge [Version]::new(2, 0) )
        {
            switch ($_type) {
                { ($_ -ge 47) -and ($_ -le 125) } {

                    $object = [Reserved]::new($_type, [SMBIOS]::Descriptions[$_type].Description, @(), $_length, $_handle, $_data, $_strings)

                    break
                }
                { ($_ -ge 128) -and ($_ -le 255) } {
                    $object = [OEMSpecificInformation]::new($_type, [SMBIOS]::Descriptions[$_type].Description, @(), $_length, $_handle, $_data, $_strings)
                
                    break
                }
            }
        }
    
        if ( [SMBIOS]::Version -ge [Version]::new(2, 2) )
        {
            switch ($_type) {
                126 {
                    $object = [Inactive]::new($_type, [SMBIOS]::Descriptions[$_type].Description, @(), $_length, $_handle, $_data, $_strings)

                    break
                }
                127 {
                    $object = [EndOfTable]::new($_type, [SMBIOS]::Descriptions[$_type].Description, @(), $_length, $_handle, $_data, $_strings)

                    break
                }
            }
        }

        if ($object)
        {
            $object.SetProperties($Property)
        
            $object.Properties.GetEnumerator() | ForEach-Object { 
                
                $object | Add-Member -MemberType NoteProperty -Name $($_.Key) -Value $($_.Value) -Force
            }

            $object
        }
        
    }

    Write-Progress $(LocalizedString "DONE") -Completed

}

Export-ModuleMember -Function @(
    'Get-SMBIOS',
    'Get-SMBIOSVersion',
    'Get-SMBIOSInfo',
    'Export-SMBIOS',
    'Get-SMBIOSTypes',
    'Get-SMBIOSAvailableTypes',
    'Get-SMBIOSTableData',
    'Get-SMBIOSEntryPoint'
    )

Update-FormatData -PrependPath $PSScriptRoot\Formats.ps1xml

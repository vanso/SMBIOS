<#

SMBIOSLib

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

using namespace System.Collections
using namespace System.Collections.Generic
using namespace System.Collections.Specialized
using namespace System.Globalization

#
# Used for compatibility with Windows PowerShell 5.x 
#
class OSPlatform
{
    static [string]$PSPlatformName
    static [bool]$IsLinux = $false
    static [bool]$IsWindows = $false
    static [bool]$IsMacOS = $false
}

#
# Global settings defined by the function parameters
#
class Settings
{
    static [MemorySizeUnit]$MemorySizeUnit
    static [TemperatureUnit]$TemperatureUnit
    static [Boolean]$Verbose
    static [Boolean]$Expand
}

#
# Utility class for localization.
#
class Localization
{
    hidden static [HashTable]$LocalisedStrings
    
    static Localization()
    {
        $localizableFilePath = "$PSScriptRoot/en-US/Strings.txt"
        
        if (Test-Path -Path $localizableFilePath)
        {
            [Localization]::LocalisedStrings = ConvertFrom-StringData -StringData (Get-Content -Path $localizableFilePath -Raw)
        }
    }
    
    static [String]LocalizedString([String]$string)
    {
        if ([Localization]::LocalisedStrings.$string)
        {
            return [Localization]::LocalisedStrings.$string
        }
        else
        {
            return "Localized string not found"
        }
    }
}

#
# Utility class to simplify the manipulation of bit fields.
#
class BitField
{
    static [int]Get([Object]$bitField, [int]$offset)
    {
        return [BitField]::Extract([Object]$bitField, [int]$offset, 1)
    }
    
    static [int]Extract([Object]$bitField, [int]$offset, [int]$length)
    {
        return (($bitField -shr $offset) -band (1 -shl ($length)) -1)
    }

    static [UInt32]LowUInt64([UInt64]$int)
    {
        return $int -band 0x000000007FFFFFFF
    }

    static [UInt32]HighUInt64([UInt64]$int)
    {
        return ($int -shr 32) -band 0xFFFFFFFF
    }
}

#
# Utility class for converting a bit field into other types.
#
class BitFieldConverter
{
    static [int]Length([Object]$bitField)
    {
        [int]$length = 0

        switch ($bitField) {
            { $bitField -is [Byte] } {
                $length = 8
            }
            { $bitField -is [UInt16] } {
                $length = 16
            }
            { $bitField -is [UInt32] } {
                $length = 32
            }
            { $bitField -is [UInt64] } {
                $length = 64
            }
        }

        return $length
    }

    #
    # ToStringArray
    #
    static [Array]ToStringArray([Object]$bitField, [Array]$names)
    {
        return [BitFieldConverter]::ToStringArray($bitField, [BitFieldConverter]::Length($bitField), $names)
    }

    static [Array]ToStringArray([Object]$bitField, [int]$length, [Array]$names)
    {
        $list = [ArrayList]::new()

        for ($i = 0; $i -le $length - 1 ; $i++)
        {
            if ($bitField -band (1 -shl $i))
            {         
                $list.Add($names[$i]) | Out-Null
            }
            else
            {
                $list.Add($null) | Out-Null
            }
        }

        return $list.ToArray()
    }

    static [StringValue]ToStringValue([Object]$bitField, [String]$dictionaryName, [ref]$classRef)
    {
        return [BitFieldConverter]::ToStringValue($bitField, [BitFieldConverter]::Length($bitField), $dictionaryName, $classRef)
    }

    static [StringValue]ToStringValue([Object]$bitField, [int]$length, [String]$dictionaryName, [ref]$classRef)
    {
        $class = $classRef.Value

        $names = $class::StringArrays[$dictionaryName]

        return [BitFieldConverter]::ToStringValue($bitField, $length, $names)
    }

    static [StringValue]ToStringValue([Object]$bitField, [Array]$names)
    {
        return [BitFieldConverter]::ToStringValue($bitField, [BitFieldConverter]::Length($bitField), $names)
    }

    static [StringValue]ToStringValue([Object]$bitField, [int]$length, [Array]$names)
    {
        for ($i = 0; $i -le $length - 1 ; $i++)
        {
            if ($bitField -band (1 -shl $i))
            {         
                return [StringValue]::new($i, $names[$i])
            }
        }

        return $null
    }

    #
    # ToStringValueArray
    #
    static [Array]ToStringValueArray([Object]$bitField, [String]$dictionaryName, [ref]$classRef)
    {    
        return [BitFieldConverter]::ToStringValueArray($bitField, [BitFieldConverter]::Length($bitField), $dictionaryName, 0, $classRef)
    }

    static [Array]ToStringValueArray([Object]$bitField, [int]$length, [String]$dictionaryName, [ref]$classRef)
    {
        return [BitFieldConverter]::ToStringValueArray($bitField, $length, $dictionaryName, 0, $classRef)
    }

    static [Array]ToStringValueArray([Object]$bitField, [int]$length, [String]$dictionaryName, [int]$offset, [ref]$classRef)
    {     
        $class = $classRef.Value

        $names = $class::StringArrays[$dictionaryName]

        return [BitFieldConverter]::ToStringValueArray($bitField, $length, $names, $offset)
    }

    static [Array]ToStringValueArray([Object]$bitField, [Array]$names)
    {
        return [BitFieldConverter]::ToStringValueArray($bitField, [BitFieldConverter]::Length($bitField), $names, 0)
    }

    static [Array]ToStringValueArray([Object]$bitField, [int]$length, [Array]$names)
    {
        return [BitFieldConverter]::ToStringValueArray($bitField, $length, $names, 0)
    }

    static [Array]ToStringValueArray([Object]$bitField, [int]$length, [Array]$names, [int]$offset)
    {
        $list = [ArrayList]::new()
        
        for ($i = 0; $i -le $length - 1 ; $i++)
        {
            if ($bitField -band (1 -shl $i))
            {         
                $list.Add( [StringValue]::new($i + $offset, $names[$i]) ) | Out-Null
            }
        }

        return $list.ToArray()
    }
  
    #
    # ToBitArray
    #
    static [Collections.BitArray]ToBitArray([Object]$bitField)
    {
        return [BitFieldConverter]::ToBitArray($bitField, [BitFieldConverter]::Length($bitField))
    }

    static [BitArray]ToBitArray([Object]$bitField, [int]$length)
    {   
        $list = [List[Boolean]]::new()

        for ($i = 0; $i -le $length - 1 ; $i++)
        {
            if ($bitField -band (1 -shl $i))
            {
                $list.Add($true) | Out-Null
            }
            else
            {
                $list.Add($false) | Out-Null
            }
        }

        return [BitArray]::new($list.ToArray())
    }

    #
    # ToInt
    #
    static [int]ToInt([Byte]$bitField, [int]$offset, [int]$count)
    {
        return [BitFieldConverter]::ToInt([UInt32]$bitField, [int]$offset, [int]$count)
    }

    static [int]ToInt([UInt16]$bitField, [int]$offset, [int]$count)
    {
        return [BitFieldConverter]::ToInt([UInt32]$bitField, [int]$offset, [int]$count)
    }

    static [int]ToInt([UInt32]$bitField, [int]$offset, [int]$count)
    {       
        $bitArray = [BitFieldConverter]::ToBitArray($bitField)

        [Boolean[]]$segment = [ArraySegment[Boolean]]::new($bitArray, $offset, $count) 

        $bitArray = [BitArray]::new($segment)

        [int[]]$int = [Array]::CreateInstance([int], 1) 

        $bitArray.CopyTo($int, 0)

        return $int[0]
    }

    static [int]ToInt([BitArray]$bitArray, [int]$offset, [int]$count)
    {       
        [Boolean[]]$segment = [ArraySegment[Boolean]]::new($bitArray, $offset, $count) 

        $bitArray = [BitArray]::new($segment)

        [int[]]$result = [Array]::CreateInstance([int], 1) 

        $bitArray.CopyTo($result, 0)

        return $result[0]
    }
}


class SMBString : PSObject
{ 
    SMBString([Object]$value, [Byte]$index) : base($value)
    {
        if ( [String]::IsNullOrEmpty($value) )
        {
            $this | Add-Member Value $null

            $this | Add-Member DisplayValue $([Localization]::LocalizedString("NOT_SPECIFIED"))
        }
        else
        {
            $this | Add-Member Value $value.ToString()

            $this | Add-Member DisplayValue $value.ToString()
        }

        $this | Add-Member Index $index
    }

    [String]ToString()
    {
        if ([Settings]::Expand)
        {                       
            return [String]::Format("Strings[{0}] ({1})", $this.Index, $this.DisplayValue)
        }
        else
        {       
            return $this.DisplayValue
        }
    }
}

#
# Class allowing to store each result in a uniform format.
#
class StringValue : IFormattable
{
    [Object]$Value
    [String]$DisplayValue
    hidden [Boolean]$Resolved

    StringValue()
    {
        $this.DisplayValue = [Localization]::LocalizedString("NOT_AVAILABLE")
    }
    
    StringValue([Object]$value)
    {   
        if ($value -eq $null)
        {
            $this.DisplayValue = [Localization]::LocalizedString("NOT_AVAILABLE")
        }
        else
        {
            $this.Value = $value

            $this.DisplayValue = $value
        }
    }

    StringValue([Object]$value, [String]$format)
    {
        if ($value -eq $null)
        {
            $this.DisplayValue = [Localization]::LocalizedString("NOT_AVAILABLE")
        }
        else
        {
            $this.Value = $value

            $this.DisplayValue = [String]::Format($format, $this.Value)

            $this.Resolved = $true
        }
    }

    StringValue([Object]$value, [Object]$exceptionValue, [String]$format, [String]$exceptionString)
    {
        $this.Value = $value
        
        $exception = $false
        
        if ($value -eq $exceptionValue)
        {
            $exception = $true
        }

        if ($exception)
        {
            $this.Displayvalue = [Localization]::LocalizedString($exceptionString)
        }
        else
        {
            if ( [String]::IsNullOrEmpty($format) )
            {
                $this.DisplayValue = $value
            }
            else
            {
                $this.DisplayValue = [String]::Format($format, $value)
            }
        }
    }

    StringValue([Object]$value, [Object]$exceptionValue, [String]$format, [Object]$effectiveValue, [String]$exceptionString)
    {
        $this.Value = $effectiveValue
        
        $exception = $false
        
        if ($value -eq $exceptionValue)
        {
            $exception = $true
        }

        if ($exception)
        {
            $this.Displayvalue = [Localization]::LocalizedString($exceptionString)
        }
        else
        {
            if ( [String]::IsNullOrEmpty($format) )
            {
                $this.DisplayValue = $effectiveValue
            }
            else
            {
                $this.DisplayValue = [String]::Format($format, $effectiveValue)
            }
        }
    }

    StringValue([Object]$value, [Object]$exceptionValue, [String]$format, [String]$exceptionString, [Object]$extendedValue, [Object]$effectiveValue)
    {
        if ($value -eq $extendedValue)
        {
            $this.Value = $effectiveValue
        }
        else
        {
            $this.Value = $value
        }

        $exception = $false
        
        if ($value -eq $exceptionValue)
        {
            $exception = $true
        }

        if ($exception)
        {
            $this.Displayvalue = [Localization]::LocalizedString($exceptionString)
        }
        else
        {
            if ( [String]::IsNullOrEmpty($format) )
            {
                $this.DisplayValue = $value
            }
            else
            {
                $this.DisplayValue = [String]::Format($format, $value)
            }
        }
    }

    StringValue([Object]$value, [OrderedDictionary]$names)
    {   
        $this.Value = $value
        
        $result = $names.[int]$Value
        
        if ($result)
        {
            $this.Resolved = $true

            $this.DisplayValue = $result

        }
        else 
        {                
            $outOfSpecification = [Localization]::LocalizedString("OUT_OF_SPEC")
                
            $this.DisplayValue = [String]::Format("{0} ($outOfSpecification)", $value)
        }
    }

    StringValue([Object]$value, [String]$dictionaryName, [ref]$classRef)
    {        
        $this.Value = $value
        
        $class = $classRef.Value

        $names = $class::StringArrays["$dictionaryName"]
        
        $result = $names.[int]$value
        
        if ($result)
        {
            $this.Resolved = $true

            $this.DisplayValue = $result
        }
        else 
        {                
            $outOfSpecification = [Localization]::LocalizedString("OUT_OF_SPEC")
                
            $this.DisplayValue = [String]::Format("{0} ($outOfSpecification)", $value)
        }
    }

    [String]ToString([String]$format, [IFormatProvider]$formatProvider)
    {   
        if (-Not ($formatProvider))
        {
            $formatProvider = [CultureInfo]::CurrentCulture
        }

        if (($format -eq "0") -or ($format -eq [String]::Empty))
        {
            if ([Settings]::Expand)
            {
                $formattedValue = $this.Value
                
                if ($this.Value -eq $null)
                {
                    $formattedValue = "`$null"
                }

                return [String]::Format("{0} ({1})", $formattedValue, $this.DisplayValue)
            }
            else
            {    
                return $this.DisplayValue
            }
        }
        else
        {
            return [String]::Format($formatProvider, $format, $this.Value)
        }
    }

    [OrderedDictionary]Expand()
    {
        return [Ordered]@{ Value = $this.Value ; DisplayValue = $this.DisplayValue }
    }

    static [int]op_Implicit([StringValue]$stringValue)
    {
        return $stringValue.Value
    }
}

#
# Data storage size units.
#
enum MemorySizeUnit
{
    B
    kB
    MB
    GB
    TB
    PB
    EB
    ZB
    YB
    Auto
}

class StringValueMemorySize : StringValue
{
    [Object]$Value
    [String]$DisplayValue
    [Object]$SizeInBytes
    [MemorySizeUnit]$Unit

    StringValueMemorySize([Object]$sizeInBytes, [MemorySizeUnit]$Unit) : base()
    { 
        $dataSizes = @(1, 1kb, 1mb, 1gb, 1tb, 1pb, 1.15292150460685E+18, 1.18059162071741E+21, 1.20892581961463E+24)
        
        if ([Settings]::MemorySizeUnit -eq [MemorySizeUnit]::Auto)
        {
            $_Unit = $unit
            
            $localizedUnit = [Localization]::LocalizedString($unit)
            
            $dataSize = $dataSizes[[int]$unit]
        }
        else
        {
            $customUnit = [Settings]::MemorySizeUnit

            $_Unit = $customUnit
            
            $localizedUnit = [Localization]::LocalizedString($customUnit)
            
            $dataSize = $dataSizes[[int]$customUnit]   
        }

        $this.Value = $sizeInBytes / $dataSize

        $this.SizeInBytes = $sizeInBytes

        $this.DisplayValue = [String]::Format("{0:N0} $localizedUnit", $this.Value)

        $this.Unit = $_Unit
    }
}

#
# Temperature units.
#
enum TemperatureUnit
{
   Celsius
   Fahrenheit
}

class StringValueTemperature
{
    [Object]$Value
    [String]$DisplayValue
    [TemperatureUnit]$Unit
    hidden [Sbyte]$Precision
    
    StringValueTemperature([Object]$temperatureInCelsius, [TemperatureUnit]$unit, [Sbyte]$precision) : base()
    {
        if ([Settings]::TemperatureUnit -eq [TemperatureUnit]::Celsiuselsius)
        {
            $_Unit = [TemperatureUnit]::Celsiuselsius
            
            $localizedUnit = [Localization]::LocalizedString("Celsius")
            
            $temperature = $temperatureInCelsius
        }
        else
        {
            $_Unit = [TemperatureUnit]::Fahrenheit
            
            $localizedUnit = [Localization]::LocalizedString("Fahrenheit")
            
            $temperature = ($temperatureInCelsius * 9/5) + 32 

            
        }
        
        $this.Value = $temperature

        $this.DisplayValue = [String]::Format("{0:F$($precision)} $localizedUnit", $this.Value)

        $this.Unit = $_Unit

        $this.Precision = $precision
    }

    [StringValue]ToFahrenheit()
    {
        $temperature = ($this.Value * 9/5) + 32 

        $localizedUnit = [Localization]::LocalizedString("Fahrenheit")

        $string = [String]::Format("{0:F$($this.Precision)} $localizedUnit", $this.Value)

        return [StringValue]::new($temperature, $string)
    }
}

class StringValueDateTime : StringValue
{
    [string]$Format
    
    StringValueDateTime([Object]$value) : base($value)
    {
    }
    
    StringValueDateTime([Object]$value, [String]$format) : base($value, $format)
    {
        $this.Format = $format
    }

    [String]ToString([String]$format, [IFormatProvider]$formatProvider)
    {   
        if (-Not ($formatProvider))
        {
            $formatProvider = [CultureInfo]::CurrentCulture
        }

        if (($format -eq "0") -or ($format -eq [String]::Empty))
        {           
            if ($this.Format)
            {
                $longDateString = $this.Format
            }
            else
            {
                $longDateString = $this.Value.ToLongDateString()
            }

            if ([Settings]::Expand)
            {
                 return [String]::Format("{0} ({1})", $this.Value, $longDateString)
            }
            else
            {
                return $longDateString
            }
        }
        else
        {
            return [String]::Format($formatProvider, $format, $this.Value)
        }        
    }

    static [DateTime]op_Implicit([StringValueDateTime]$stringValueDateTime)
    {
        return $stringValueDateTime.Value
    }
}

class StringValueVersion : StringValue
{
    StringValueVersion([Object]$value, [String]$format) : base($value, $format)
    {
    }

    StringValueVersion([Object]$value, [Object]$exceptionValue, [String]$format, [String]$exceptionString) : base($value, $exceptionValue, $format, $exceptionString)
    {
    }

    static [Version]op_Implicit([StringValueVersion]$stringValueVersion)
    {
        return $stringValueVersion.Value
    }
}

class StringValueOrderedDictionary : StringValue
{
    StringValueOrderedDictionary([Object]$value) : base($value)
    {
    }
    
    StringValueOrderedDictionary([Object]$value, [String]$format) : base($value, $format)
    {
    }

    static [OrderedDictionary]op_Implicit([StringValueOrderedDictionary]$stringValueOrderedDictionary)
    {
        return $stringValueOrderedDictionary.Value
    }

    [String]ToString([String]$format, [IFormatProvider]$formatProvider)
    {   
        if (-Not ($formatProvider))
        {
            $formatProvider = [CultureInfo]::CurrentCulture
        }

        if (($format -eq "0") -or ($format -eq [String]::Empty))
        {
            $ExpandedString = ( $this.Value.GetEnumerator() | ForEach-Object { "$($_.Key) = $($_.Value)" } ) -Join "; "

            $string = ( $this.Value.GetEnumerator() | ForEach-Object { "$($_.Key) $($_.Value)" } ) -Join " "

            if ([Settings]::Expand)
            {
                return [String]::Format("{0} ({1})", "{$ExpandedString}", $string)  
            }
            else
            {
                return $string
            }
        }
        else
        {
            return [String]::Format($formatProvider, $format, $this.Value)
        }
    }
}

#
# Defines a SMBIOSType
#
class SMBIOSType
{
    [int]$Type
    [string]$Name
    hidden [string[]]$Keywords

    SMBIOSType([int]$type, [string]$name, [string[]]$keywords)
    {
        $this.Type = $type
        $this.Name = $name
        $this.Keywords = $keywords
    }

    [String]ToString()
    {
        return $this.Name
    }
}

#
# Defines a SMBIOSTypeDescription
#
class SMBIOSTypeDescription
{
    [int]$Type
    [string]$Description

    SMBIOSTypeDescription([int]$type, [string]$description)
    {
        $this.Type = $type
        $this.Description = $description
    }

    [String]ToString()
    {
        return $this.Description
    }
}

#
# Reads, analyzes SMBIOS structures and stores them in a form of Hashtable.
#
class SMBIOS
{
    static [Version]$Version
    static [Array]$Types
    static [Array]$Descriptions
    static [Array]$AvailableTypes
    static [List[Hashtable]]$Structures
    static [Byte[]]$TableData
    static [int]$TableDataSize
    static [Byte[]]$EntryPoint

    static SMBIOS()
    {
        # Generates SMBIOS types list
        $typesList = [ArrayList]::new()

        $SMBIOSTypes = [SMBIOSStructure]::StringArrays["SMBIOSType"]

        foreach ( $type in $SMBIOSTypes.GetEnumerator() )
        {
            $typesList.Add( [SMBIOSType]::new( $type.Key, $type.Value, @() ) )
        }

        [SMBIOS]::Types = $typesList

        # Generates SMBIOS descriptions list
        $descriptionsList = [ArrayList]::new()

        $SMBIOSTypeDescriptions = [SMBIOSStructure]::StringArrays["SMBIOSTypeDescription"]

        foreach ( $description in $SMBIOSTypeDescriptions.GetEnumerator() )
        {
            $descriptionsList.Add( [SMBIOSTypeDescription]::new( $description.Key, $description.Value ) )
        }

        [SMBIOS]::Descriptions = $descriptionsList
    }

    # Read SMBIOS on a Macintosh using the ioreg tool instead of an interop class due to the notarization requirements on macOS.
    # The SMBIOS-EPS property contains the entry point of the SMBIOS.
    # The SMBIOS property contains the SMBIOS table.
    static [Byte[]] ReadAppleSMBIOSProperty([String]$property)
    {    
        $AppleSMBIOSProperty = /usr/sbin/ioreg -c AppleSMBIOS -r | Select-String $property
    
        $SMBIOSProperty = ($AppleSMBIOSProperty -Split "= ")[1].TrimStart("<").TrimEnd(">")

        $tableDataList = [List[Byte]]::new()

        $length = $SMBIOSProperty.Length / 2

        for ($i = 0; $i -lt $length ; $i++) 
        {
            $hex = $SMBIOSProperty.SubString($i * 2, 2)
            $byte = [Convert]::ToByte($hex, 16)
            $tableDataList.Add($byte)
        }
    
        return $tableDataList.ToArray()
    }

    # Parse the entry point of the SMBIOS
    static [void]ParseEntryPoint([Byte[]]$entryPoint)
    {
        [SMBIOS]::EntryPoint = $entryPoint
        
        $anchor = [ArraySegment[Byte]]::new($entryPoint, 0, 4)
        [Byte[]]$_SM_ = 0x5F, 0x53, 0x4D, 0x5F

        $SMBIOSVersion = 0

        $majorVersion = 0
        $minorVersion = 0

        if ([Linq.Enumerable]::SequenceEqual($anchor, $_SM_))
        {
            $SMBIOSVersion = 2
        }

        $anchor = [ArraySegment[Byte]]::new($entryPoint, 0, 5)
        [Byte[]]$_SM3_ = 0x5F, 0x53, 0x4D, 0x33, 0x5F
  
        if ([Linq.Enumerable]::SequenceEqual($anchor, $_SM3_))
        {
            $SMBIOSVersion = 3
        }

        switch ($SMBIOSVersion) {
            2 {  
                [SMBIOS]::TableDataSize = [BitConverter]::ToUInt16($entryPoint, 0x16)
                $majorVersion = $entryPoint[0x06]
                $minorVersion = $entryPoint[0x07]

                [SMBIOS]::Version = [Version]::new($majorVersion, $minorVersion)
            }
            3 {  
                [SMBIOS]::TableDataSize = [BitConverter]::ToUInt32($entryPoint, 0x0C)
                $majorVersion = $entryPoint[0x07]
                $minorVersion = $entryPoint[0x08]

                [SMBIOS]::Version = [Version]::new($majorVersion,  $minorVersion)
            }
        }
    }

    # Parse the SMBIOS table
    static [Void]ParseTableData([Byte[]]$tableData)
    {
        [SMBIOS]::TableData = $tableData
        
        $structuresList = [List[Hashtable]]::new()

        $tableDataLength = [SMBIOS]::TableDataSize

        $offset = 0

        do
        {    
            # Read the header (fixed size)
            $type = $tableData[$offset] 
            $length = $tableData[$offset + 1]
            $handle = [BitConverter]::ToUInt16($tableData, $offset + 2)
            $data = [ArraySegment[Byte]]::new($tableData, $offset, $length) 
    
            $variableLengthBegin = $offset + $length
            $location = $variableLengthBegin
            $variableLength = 0
            
            # Read the strings (variable size)     
            while ($location -lt $tableDataLength) 
            {
                if (($tableData[$location] -eq 0x00) -and ($tableData[$location + 1] -eq 0x00))
                {
                    $variableData = [ArraySegment[Byte]]::new($tableData, $variableLengthBegin, $variableLength)
                    $strings = [System.Text.Encoding]::ASCII.GetString($variableData) -Split ("`0")
    
                    $structure = @{ "Type" = $type; "Length" = $length; "Handle" = $handle; "Data" = $data; "Strings" = $strings }
                    $structuresList.Add($structure) | Out-Null

                    $offset = $location + 2
                    break
                }
                else 
                {
                    $location = $location + 1
                    $variableLength = $variableLength + 1
                }
            }   
        }
        while ($offset -lt $tableDataLength)

        [SMBIOS]::Structures = $structuresList
    }
}

###################################################################################################################################
# class SMBIOSStructure                                                                                                           #
###################################################################################################################################
class SMBIOSStructure
{ 
    static [Hashtable]$StringArrays
    static [Hashtable]$StringArrayNameAlias
    
    static [Array]$PropertyNames

    static SMBIOSStructure()
    {
        $stringTables = [SMBIOSStructure]::GetStringTables("Types")

        [SMBIOSStructure]::StringArrays = $stringTables.StringArrays
             
        [SMBIOSStructure]::StringArrayNameAlias = $stringTables.StringArrayNameAlias
    }

    hidden [Byte]$SMBType
    hidden [String]$SMBDescription
    hidden [Byte]$Length
    hidden [UInt16]$Handle
    hidden [OrderedDictionary]$Properties
    hidden [String[]]$Keywords
    hidden [Byte[]]$Data
    hidden [String[]]$Strings
    hidden [Boolean]$Obsolete

    SMBIOSStructure([Byte]$type, [String]$description, [String[]]$keywords, [Byte]$length, [UInt16]$handle, [Byte[]]$data, [String[]]$strings)
    {
        $this.SMBType = $type
        $this.SMBDescription = $description
        $this.Length = $length
        $this.Keywords = $keywords
        $this.Handle = $handle
        $this.Data = $data
        $this.Strings = $strings
        $this.Properties = [Ordered]@{}
    }

    hidden [Byte]Get_Type()
    {
        return $this.SMBType
    }

    hidden [String]Get_Description()
    {
        return $this.SMBDescription
    }

    hidden [UInt16]Get_Handle()
    {
        return $this.Handle
    }

    hidden [ArraySegment[Byte]]Get_Data()
    {
        return $this.Data
    }

    hidden [String[]]Get_Strings()
    {
        return $this.Strings
    }

    hidden [Array]GetPropertyNames()
    {
        $class = $this.GetType()
        
        return $class::PropertyNames
    }

    hidden [Byte]GetByteAtOffset([int]$offset)
    {
        try {
            return $this.data[$offset]
        }
        catch {
            return 0
        }
    }

    hidden [UInt16]GetWordAtOffset([int]$offset)
    {
        try {
            return [BitConverter]::ToUInt16($this.data, $offset)
        }
        catch {
            return 0
        }
    }
    
    hidden [UInt32]GetDoubleWordAtOffset([int]$offset)
    {
        try {
            return [BitConverter]::ToUInt32($this.data, $offset)
        }
        catch {
            return 0
        }
    }

    hidden [UInt64]GetQuadWordAtOffset([int]$offset)
    {
        try {
            return [BitConverter]::ToUInt64($this.data, $offset)
        }
        catch {
            return 0
        }
    }

    hidden [String]GetStringAtOffset1([int]$offset)
    {
        $index = $this.data[$offset] - 1
        
        if ($index -ge 0)
        {
            return $this.strings[$index]
        }
        else 
        {
            return $null
        }
    }

    hidden [SMBString]GetStringAtOffset([Byte]$offset)
    {
        $index = $this.data[$offset] - 1
        
        if ($index -ge 0)
        {
            return [SMBString]::new($this.strings[$index], $index)
        }
        else 
        {
            return [SMBString]::new([String]::Empty, 255)
        }
    }

    hidden [SMBString]GetStringAtOffset2([int]$offset)
    {
        $index = $this.data[$offset] - 1
        
        if ($index -ge 0)
        {
            return [SMBString]::new($this.strings[$index], $index)
        }
        else 
        {
            return [SMBString]::new($null, 255)
        }
    }

    hidden [ArraySegment[Byte]]GetData()
    {
        return $this.data
    }

    hidden [String[]]GetStrings()
    {
        return $this.Strings
    }

    hidden [Byte]GetDMIType()
    {
        return $this.SMBType
    }

    hidden [int]GetLength()
    {
        return $this.Length
    }
    
    hidden [UInt16]GetHandle()
    {
        return $this.Handle
    }

    [Boolean]isObsolete()
    {
        return $this.Obsolete
    }

    hidden static [Hashtable]GetStringTables([String]$type)
    {  
        $xml = [xml](Get-Content -Path "$PSScriptRoot/en-US/$type.xml")
        
        $_stringArrays = @{}

        $_stringArrayNameAlias = @{}
   
        $collection = $null

        foreach ( $table in $xml.strings.table )
        {
            if ( $table.kind -eq "Ordered" )
            {
                $collection = [OrderedDictionary]::new()

                foreach( $entry in $table.entry )
                {
                    $collection.Add( [int]$entry.key, $entry.value )
                }
            }
            elseif ( $table.kind -eq "Array" )
            {  
                $collection = [Collections.ArrayList]::new()   

                foreach( $entry in $table.entry )
                {  
                    $collection.Add( $entry.value )
                }  
            }

            $_stringArrays.Add( $($table.name), $collection )

            $aliases = $($table.alias).Split(",")

            foreach( $alias in $aliases )
            {
                $_stringArrayNameAlias.Add( $alias, $table.name )
            }
        }

        return @{"StringArrays" = $_stringArrays ; "StringArrayNameAlias" = $_stringArrayNameAlias }
    }

    hidden [void]SetProperties([array]$propertiesList)
    {        
        $runtimeType = $this.GetType() 

        if ($propertiesList -eq "*")
        {
            $propertiesList = $runtimeType::PropertyNames
        }

        $propertiesList = @("_Type", "_Description", "_Handle") + $propertiesList 

        foreach ($property in $propertiesList)
        {
            try
            {
                $methodInfo = $runtimeType.GetMethod("Get$property")

                try
                {
                    $object = $methodInfo.Invoke($this, $null)

                    $this.Properties.Add($property, $object) | Out-Null      
                }
                catch
                {
                    Write-Warning "Property `"$property`" Not Found For Type $($this.SMBType) ($( $this.SMBDescription ))"
                }
            }
            catch
            {
                Write-Warning ($error[0].Exception)
            }  
        }
    }

    hidden [OrderedDictionary]GetProperties()
    {        
       return $this.Properties
    }
}


###################################################################################################################################
# Type 0                                                                                                                          #
###################################################################################################################################
class BIOSInformation : SMBIOSStructure 
{   
    hidden static [Hashtable]$StringArrays
    hidden static [Hashtable]$StringArrayNameAlias
    
    hidden static [Array]$PropertyNames
    
    static BIOSInformation()
    {
        $stringTables = [BIOSInformation]::GetStringTables("Type_0")
        
        [BIOSInformation]::StringArrays = $stringTables.StringArrays
                                            
        [BIOSInformation]::StringArrayNameAlias = $stringTables.StringArrayNameAlias

        $labels = [Collections.ArrayList]::new()

        if ( [SMBIOS]::Version -ge [Version]::new(2, 0) )
        {
            $labels.Add( "Vendor"          )
            $labels.Add( "Version"         ) 
            $labels.Add( "ReleaseDate"     ) 
            $labels.Add( "AddressSegment"  )  
            $labels.Add( "ROMSize"         )
            $labels.Add( "ImageSize"       )   
            $labels.Add( "Characteristics" )
        }

        if ( [SMBIOS]::Version -ge [Version]::new(2, 4) )
        {
            $labels.Add( "Release"         ) 
            $labels.Add( "FirmwareRelease" )
        }

        [BIOSInformation]::PropertyNames = $labels
    }

    BIOSInformation([Byte]$type, [String]$description, [String[]]$keywords, [Byte]$length, [UInt16]$handle, [Byte[]]$data, [String[]]$strings) : base ($type, $description, $keywords, $length, $handle, $data, $strings) 
    {
    }

    # Get Vendor
    hidden [SMBString]GetVendor() 
    {
        return $this.GetStringAtOffset(0x04)
    }

    # Get Version
    hidden [SMBString]GetVersion() 
    {
        return $this.GetStringAtOffset(0x05)
    }

    # Get AddressSegment
    hidden [StringValue]GetAddressSegment() 
    {
        $address = $this.GetWordAtOffset(0x06)

        return [StringValue]::new($address, "0x{0:X4}0")
    }

    # Get ReleaseDate
    hidden [StringValueDateTime]GetReleaseDate() 
    {      
        $releaseDate = $this.GetStringAtOffset(0x08)

        $culture = [CultureInfo]::CreateSpecificCulture("en-US")
        
        try
        {
            $date = [DateTime]::Parse($releaseDate, $culture)

            return [StringValueDateTime]::new($date)
        }
        catch
        {   
            $notAvailable = [Localization]::LocalizedString("NOT_AVAILABLE")
            
            return [StringValueDateTime]::new([DateTime]::new(1), $notAvailable)
        }
    }

    # Get ROMSize
    hidden [StringValueMemorySize]GetROMSize()
    {
        $size = 0
        
        $ROMSize = $this.GetByteAtOffset(0x09)

        $sizeInBytes = $ROMSize * 1kb

        $unit = [MemorySizeUnit]::kB

        if ( $ROMSize -eq 0xFF ) 
        {
            if ( [SMBIOS]::Version -ge [Version]::new(3, 1) ) 
            {    
                $extendedSize = $this.GetExtendedROMSize()

                if ($extendedSize) 
                {
                    if ($extendedSize -shr 14)
                    {  
                        $unit = [MemorySizeUnit]::GB
                        
                        $size = $extendedSize -band 0x3FFF

                        $sizeInBytes = $size * 1gb
                    }
                    else
                    {
                        $unit = [MemorySizeUnit]::MB

                        $size = $extendedSize -band 0x3FFF

                        $sizeInBytes = $size * 1mb
                    }
                }
            }
            else 
            {
                $size = 64 * ($ROMSize + 1)

                $sizeInBytes = $size * 1kb
            }
        }
        else 
        {
            $size = 64 * ($ROMSize + 1)

            $sizeInBytes = $size * 1kb
        }
        
        return [StringValueMemorySize]::new($sizeInBytes, $unit)
    }

    # Get ImageSize
    hidden [StringValueMemorySize]GetImageSize() 
    {   
        $address = $this.GetAddressSegment()
        
        $size = (0x10000 - $address) * 16

        $sizeInBytes = $size

        if ($size % 1024)
        {
            $unit = [MemorySizeUnit]::B
        }
        else
        {
            $unit = [MemorySizeUnit]::kB
        }

        return [StringValueMemorySize]::new($sizeInBytes, $unit)
    }

    # Get Characteristics
    hidden [StringValue[]]GetCharacteristics() 
    {                 
        $featuresList = [Collections.ArrayList]::new()

        $BIOSCharacteristics = $this.GetQuadWordAtOffset(0x0A)

        $characteristics = [BitField]::LowUInt64($BIOSCharacteristics)

        $reservedCharacteristics = [BitField]::HighUInt64($BIOSCharacteristics)

        $offset = 0

        $featuresList = $featuresList + [BitFieldConverter]::ToStringValueArray($characteristics, 32, "Characteristics", [ref]$this)

        $offset = $offset + 32

        if ( [SMBIOS]::Version -ge [Version]::new(2, 1) )
        {
            $characteristicsByte1 = $this.GetByteAtOffset(0x12)

            $featuresList = $featuresList + [BitFieldConverter]::ToStringValueArray($characteristicsByte1, 8, "CharacteristicsByte1", $offset, [ref]$this)

            $offset = $offset + 8
        }

        if ( [SMBIOS]::Version -ge [Version]::new(2, 3) )
        {    
            $characteristicsByte2 = $this.GetByteAtOffset(0x13)

            $featuresList = $featuresList + [BitFieldConverter]::ToStringValueArray($characteristicsByte2, 8, "CharacteristicsByte2", $offset, [ref]$this)

            $offset = $offset + 8
        }

        $featuresList = $featuresList + [BitFieldConverter]::ToStringValueArray($reservedCharacteristics, 32, "ReservedCharacteristics", $offset, [ref]$this)

        return $featuresList
    }
    
    # Get Release
    hidden [StringValueVersion]GetRelease() 
    {
        $majorRelease = $this.GetByteAtOffset(0x14) 

        $minorRelease = $this.GetByteAtOffset(0x15)
        
        $version = [Version]::new($majorRelease, $minorRelease)

        return [StringValueVersion]::new($version, [Version]::new(255.255), "{0}", "NOT_AVAILABLE")
    }

    # Get FirmwareRelease
    hidden [StringValueVersion]GetFirmwareRelease() 
    {   
        $majorRelease = $this.GetByteAtOffset(0x16)

        $minorRelease = $this.GetByteAtOffset(0x17)
        
        $version = [Version]::new($majorRelease, $minorRelease)

        return [StringValueVersion]::new($version, [Version]::new(255.255), "{0}", "NOT_AVAILABLE")
    }

    # Get ExtendedROMSize
    hidden [UInt16]GetExtendedROMSize()
    {
        return $this.GetWordAtOffset(0x18)
    }
}


###################################################################################################################################
# Type 1                                                                                                                          #
###################################################################################################################################
class SystemInformation : SMBIOSStructure 
{   
    static [Hashtable]$StringArrays
    static [Hashtable]$StringArrayNameAlias
    static [Hashtable]$LocalizedStrings

    static [Array]$PropertyNames

    static SystemInformation()
    {   
        $stringTables = [SystemInformation]::GetStringTables("Type_1")
        
        [SystemInformation]::StringArrays = $stringTables.StringArrays
                               
        [SystemInformation]::StringArrayNameAlias = $stringTables.StringArrayNameAlias

        $labels = [Collections.ArrayList]::new() 

        if ( [SMBIOS]::Version -ge [Version]::new(2, 0) )
        {
            $labels.Add( "Manufacturer" )
            $labels.Add( "ProductName"  ) 
            $labels.Add( "Version"      ) 
            $labels.Add( "SerialNumber" )
        }

        if ( [SMBIOS]::Version -ge [Version]::new(2, 1) )
        {
            $labels.Add( "UUID"         )    
            $labels.Add( "WakeUpType"   ) 
        }

        if ( [SMBIOS]::Version -ge [Version]::new(2, 4) )
        {
            $labels.Add( "SKUNumber"    ) 
            $labels.Add( "Family"       ) 
        }

        [SystemInformation]::PropertyNames = $labels
    }

    SystemInformation([Byte]$type, [String]$description, [String[]]$keywords, [Byte]$length, [UInt16]$handle, [Byte[]]$data, [String[]]$strings) : base($type, $description, $keywords, $length, $handle, $data, $strings) 
    {
    }

    # Get Manufacturer
    hidden [SMBString]GetManufacturer()
    {
        return $this.GetStringAtOffset(0x04)
    }

    # Get ProductName
    hidden [SMBString]GetProductName()
    {
        return $this.GetStringAtOffset(0x05)
    }
        
    # Get Version
    hidden [SMBString]GetVersion()
    {
        return $this.GetStringAtOffset(0x06)
    }
        
    # Get SerialNumber
    hidden [SMBString]GetSerialNumber()
    {
        return $this.GetStringAtOffset(0x07)
    }

    # Get UUID
    hidden [String]GetUUID()
    {
        $UUID = $null
        
        $bytes = [ArraySegment[Byte]]::new($this.data, 0x08, 16)
        
        [Byte[]]$a = [System.Linq.Enumerable]::ToArray($bytes)

        $only0x00 = [Array]::FindAll($a, [Predicate[Byte]] { $args[0] -eq 0x00 } )
        
        $only0xFF = [Array]::FindAll($a, [Predicate[Byte]] { $args[0] -eq 0xFF } )

        if ($only0x00.Count -eq 16)
        {
            $UUID = [Localization]::LocalizedString("NOT_SETTABLE")
        }
        elseif ($only0xFF.Count -eq 16)
        { 
            $UUID = [Localization]::LocalizedString("NOT_PRESENT")
        } 
        else
        {
            $UUID = [String]::Format( "{0:X02}{1:X02}{2:X02}{3:X02}-{4:X02}{5:X02}-{6:X02}{7:X02}-{8:X02}{9:X02}-{10:X02}{11:X02}{12:X02}{13:X02}{14:X02}{15:X02}",
                                         $a[3], $a[2], $a[1], $a[0],  $a[5], $a[4],  $a[7], $a[6],  $a[8], $a[9],  $a[10], $a[11], $a[12], $a[13], $a[14], $a[15] )
        }

        return $UUID
    }

    # Get WakeUpType
    hidden [StringValue]GetWakeUpType()
    {
        $wakeUpType = $this.GetByteAtOffset(0x18)

        return [StringValue]::new($wakeUpType, "WakeUpType", [ref]$this)
    }    

    # Get SKUNumber
    hidden [SMBString]GetSKUNumber()
    {
        return $this.GetStringAtOffset(0x19)
    }
        
    # Get Family
    hidden [SMBString]GetFamily()
    {
        return $this.GetStringAtOffset(0x1A)
    }
}


###################################################################################################################################
# Type 2                                                                                                                          #
###################################################################################################################################
class BaseboardInformation : SMBIOSStructure 
{    
    hidden static [Hashtable]$StringArrays
    hidden static [Hashtable]$StringArrayNameAlias
    
    static [Array]$PropertyNames

    static BaseboardInformation()
    {
        $stringTables = [BaseboardInformation]::GetStringTables("Type_2")

        [BaseboardInformation]::StringArrays = $stringTables.StringArrays             
                                
        [BaseboardInformation]::StringArrayNameAlias = $stringTables.StringArrayNameAlias

        $labels = [Collections.ArrayList]::new() 

        if ( [SMBIOS]::Version -ge [Version]::new(2, 0) )
        {
            $labels.Add( "Manufacturer"            )
            $labels.Add( "Product"                 ) 
            $labels.Add( "Version"                 ) 
            $labels.Add( "SerialNumber"            )
            $labels.Add( "AssetTag"                )    
            $labels.Add( "Features"                ) 
            $labels.Add( "LocationInChassis"       ) 
            $labels.Add( "ChassisHandle"           ) 
            $labels.Add( "BoardType"               ) 
            $labels.Add( "ContainedObjectsHandles" ) 
        }

        [BaseboardInformation]::PropertyNames = $labels
    }

    BaseboardInformation([Byte]$type, [String]$description, [String[]]$keywords, [Byte]$length, [UInt16]$handle, [Byte[]]$data, [String[]]$strings) : base($type, $description, $keywords, $length, $handle, $data, $strings) 
    {     
    }
    
    # Get Manufacturer
    hidden [SMBString]GetManufacturer()
    {
        return $this.GetStringAtOffset(0x04)
    }
       
    # Get Product
    hidden [SMBString]GetProduct()
    {
        return $this.GetStringAtOffset(0x05)
    }
       
    # Get Version
    hidden [SMBString]GetVersion()
    {
        return $this.GetStringAtOffset(0x06)
    }
        
    # Get SerialNumber
    hidden [SMBString]GetSerialNumber()
    {
        return $this.GetStringAtOffset(0x07)
    }
       
    # Get AssetTag
    hidden [SMBString]GetAssetTag()
    {
        return $this.GetStringAtOffset(0x08)
    }
        
    # Get Features
    hidden [StringValue[]]GetFeatures()    
    {    
        $features = $this.GetByteAtOffset(0x09)

        return [BitFieldConverter]::ToStringValueArray($features, "Features", [ref]$this)
    }
        
    # Get LocationInChassis
    hidden [SMBString]GetLocationInChassis()
    {
        return $this.GetStringAtOffset(0x0A)
    }
        
    # Get ChassisHandle
    hidden [UInt16]GetChassisHandle()
    {
        return $this.GetWordAtOffset(0x0B)
    }
    
    # Get BoardType    
    hidden [StringValue]GetBoardType()
    {
        $boardType = $this.GetByteAtOffset(0x0D)

        return [StringValue]::new($boardType, "BoardType", [ref]$this)
    }
    
    # Get ContainedObjectsHandles
    hidden [Array]GetContainedObjectsHandles()
    {
        $numberOfContainedObjectsHandles = $this.GetByteAtOffset(0x0E)

        $objectsHandles = [Collections.ArrayList]::new()

        for ($objectHandle = 0 ; $objectHandle -lt $numberOfContainedObjectsHandles ; $objectHandle++) 
        {
            $handle = $this.GetWordAtOffset(0x0F + ($objectHandle * 2))

            $objectsHandles.Add( $handle )
        }

        return $objectsHandles
    }
}


###################################################################################################################################
# Type 3                                                                                                                          #
###################################################################################################################################
class SystemEnclosure : SMBIOSStructure 
{
    hidden static [Hashtable]$StringArrays
    hidden static [Hashtable]$StringArrayNameAlias
    
    hidden static [Array]$PropertyNames

    static SystemEnclosure()
    {
        $stringTables = [SystemEnclosure]::GetStringTables("Type_3")

        [SystemEnclosure]::StringArrays = $stringTables.StringArrays
                                
        [SystemEnclosure]::StringArrayNameAlias = $stringTables.StringArrayNameAlias

        $labels = [Collections.ArrayList]::new() 

        if ( [SMBIOS]::Version -ge [Version]::new(2, 0) )
        {
            $labels.Add( "Manufacturer"       )
            $labels.Add( "ChassisType"        ) 
            $labels.Add( "Lock"               ) 
            $labels.Add( "Version"            )
            $labels.Add( "SerialNumber"       )    
            $labels.Add( "AssetTag"           )
        }
            
        if ( [SMBIOS]::Version -ge [Version]::new(2, 1) )
        {
            $labels.Add( "BootUpState"        ) 
            $labels.Add( "PowerSupplyState"   ) 
            $labels.Add( "ThermalState"       ) 
            $labels.Add( "SecurityStatus"     ) 
        }

        if ( [SMBIOS]::Version -ge [Version]::new(2, 3) )
        {
            $labels.Add( "OEMDefined"         ) 
            $labels.Add( "Heigth"             ) 
            $labels.Add( "NumberOfPowerCords" ) 
            $labels.Add( "ContainedElements"  ) 
        }

        if ( [SMBIOS]::Version -ge [Version]::new(2, 7) )
        {
            $labels.Add( "SKUNumber"          )     
        }
        
        [SystemEnclosure]::PropertyNames = $labels
    }

    SystemEnclosure([Byte]$type, [String]$description, [String[]]$keywords, [Byte]$length, [UInt16]$handle, [Byte[]]$data, [String[]]$strings) : base($type, $description, $keywords, $length, $handle, $data, $strings) 
    { 
    }

    # Get Manufacturer
    hidden [SMBString]GetManufacturer()
    {
        return $this.GetStringAtOffset(0x4)
    }
     
    # Get ChassisType
    hidden [StringValue]GetChassisType()
    {
        $type = $this.GetByteAtOffset(0x05)

        $chassisType = [BitField]::Extract($type, 0, 7)

        return [StringValue]::new($chassisType, "ChassisType", [ref]$this)
    }
      
    # Get Lockable
    hidden [StringValue]GetLock()
    {
        $type = $this.GetByteAtOffset(0x05)
        
        $lock = [BitField]::Get($type, 7)

        return [StringValue]::new($lock, "Lock", [ref]$this)
    }
    
    # Get Version
    hidden [SMBString]GetVersion()
    {
        return $this.GetStringAtOffset(0x06)
    }
        
    # Get SerialNumber
    hidden [SMBString]GetSerialNumber()
    {
        return $this.GetStringAtOffset(0x07)
    }
          
    # Get AssetTag
    hidden [SMBString]GetAssetTag()
    {
        return $this.GetStringAtOffset(0x08)
    }
    
    # Get _State
    hidden [StringValue]_State([Byte]$state)
    {
        return [StringValue]::new($state, "_State", [ref]$this)
    }
     
    # Get BootUpState
    hidden [StringValue]GetBootUpState()
    {
        $bootUpState = $this.GetByteAtOffset(0x09)

        return $this._State($bootUpState)
    }

    # Get PowerSupplyState
    hidden [StringValue]GetPowerSupplyState()
    {
        $powerSupplyState = $this.GetByteAtOffset(0x0A)

        return $this._State($powerSupplyState)
    }

    # Get ThermalState
    hidden [StringValue]GetThermalState()
    {
        $thermalState = $this.GetByteAtOffset(0x0B)

        return $this._State($thermalState)
    }
        
    # Get SecurityStatus   
    hidden [StringValue]GetSecurityStatus()
    {
        $securityStatus = $this.GetByteAtOffset(0x0C)

        return [StringValue]::new($securityStatus, "SecurityStatus", [ref]$this)
    }

    # Get OEMDefined
    hidden [UInt16]GetOEMDefined()
    {
        return $this.GetWordAtOffset(0x0D)
    }

    # Get Heigth
    hidden [StringValue]GetHeigth()
    {        
        $heigth = $this.GetByteAtOffset(0x11)

        return [StringValue]::new($heigth, 0x00, "{0} U", "UNSPECIFIED")
    }

    # Get NumberOfPowerCords
    hidden [StringValue]GetNumberOfPowerCords()
    {
        $powerCords = $this.GetByteAtOffset(0x12)

        return [StringValue]::new($powerCords, 0x00, $null, "UNSPECIFIED")
    }

    # Get ContainedElements
    hidden [StringValue[]]GetContainedElements()
    {
        $containedElementCount = $this.GetByteAtOffset(0x13)

        $containedElementRecordLength = $this.GetByteAtOffset(0x14)

        $containedElements = [ArraySegment[Byte]]::new($this.data, 0x15, $containedElementCount * $containedElementRecordLength)

        $containedElementsList = [Collections.ArrayList]::new()

        for ($containedElement = 0 ; $containedElement -lt $containedElementCount * $containedElementRecordLength ; $containedElement = $containedElement + $containedElementRecordLength)
        {
            $containedElementType = $containedElements.Array[$containedElement]
            
            $type = [BitField]::Extract($containedElementType, 0, 7)

            $minValue = $containedElements.Array[$containedElement + 1]

            $maxValue =  $containedElements.Array[$containedElement + 2]

            if ([BitField]::Get($containedElementType, 7))
            {
                $element = [Ordered]@{ TypeSelect = 1 ; Type = $type ; NumberOfElements = @($minValue..$maxValue) }

                $containedElementsList.Add([StringValue]::new($element, "$([SMBIOS]::Types[$type].Name) ($minValue..$maxValue)"))
            }
            else
            {
                $boardTypes = [BaseboardInformation]::StringArrays["BoardType"]

                $element = [Ordered]@{ TypeSelect = 0 ; Type = $type ; NumberOfElements = @($minValue..$maxValue) }

                $containedElementsList.Add([StringValue]::new($element, "$($boardTypes.$type) ($minValue..$maxValue)"))
            }
        }

        return $containedElementsList
    }

    # Get SKUNumber
    hidden [SMBString]GetSKUNumber()
    {
        $containedElementCount = $this.GetByteAtOffset(0x13)

        $containedElementRecordLength = $this.GetByteAtOffset(0x14)
        
        return $this.GetStringAtOffset(0x15 + $containedElementCount * $containedElementRecordLength)
    }
}


###################################################################################################################################
# Type 4                                                                                                                          #
###################################################################################################################################

# Used for compatibility with .NET Framework versions prior to 4.7.2.
enum ProcessorArchitecture
{
    X86     = 1  
    X64     = 2  
    IA64    = 3 
    ARM     = 4 
    ARM64   = 5
    UNKNOWN = [UInt16]::MaxValue
}

class ProcessorInformation : SMBIOSStructure 
{
    hidden static [Hashtable]$StringArrays
    hidden static [Hashtable]$StringArrayNameAlias

    hidden static [Array]$PropertyNames

    static ProcessorInformation()
    {
        $stringTables = [ProcessorInformation]::GetStringTables("Type_4")

        [ProcessorInformation]::StringArrays = $stringTables.StringArrays
                                
        [ProcessorInformation]::StringArrayNameAlias = $stringTables.StringArrayNameAlias

        $labels = [Collections.ArrayList]::new() 

        if ( [SMBIOS]::Version -ge [Version]::new(2, 0) )
        {
            $labels.Add( "SocketDesignation" )
            $labels.Add( "ProcessorType"     ) 
            $labels.Add( "Architecture"      )
            $labels.Add( "Family"            ) 
            $labels.Add( "Manufacturer"      )
            $labels.Add( "ID"                )  
            $labels.Add( "Signature"         )
            $labels.Add( "Features"          )    
            $labels.Add( "Version"           )
            $labels.Add( "Voltage"           )
            $labels.Add( "ExternalClock"     )
            $labels.Add( "MaxSpeed"          )
            $labels.Add( "CurrentSpeed"      )
            $labels.Add( "SocketPopulated"   )
            $labels.Add( "ProcessorStatus"   )
            $labels.Add( "Upgrade"           )
        }    
        if ( [SMBIOS]::Version -ge [Version]::new(2, 1) )
        {
            $labels.Add( "L1CacheHandle"     )
            $labels.Add( "L2CacheHandle"     )
            $labels.Add( "L3CacheHandle"     )
        }    
        if ( [SMBIOS]::Version -ge [Version]::new(2, 3) )
        { 
            $labels.Add( "SerialNumber"      )
            $labels.Add( "AssetTag"          )
            $labels.Add( "PartNumber"        )
        }
        if ( [SMBIOS]::Version -ge [Version]::new(2, 5) )
        {    
            $labels.Add( "CoreCount"         )
            $labels.Add( "CoreEnabled"       )
            $labels.Add( "ThreadCount"       )
            $labels.Add( "Characteristics"   )
        }
  
        [ProcessorInformation]::PropertyNames = $labels
    }

    ProcessorInformation([Byte]$type, [String]$description, [String[]]$keywords, [Byte]$length, [UInt16]$handle, [Byte[]]$data, [String[]]$strings) : base($type, $description, $keywords, $length, $handle, $data, $strings) 
    {   
    }
    
    # Get Architecture
    hidden [ProcessorArchitecture]GetArchitecture()
    {   
        $architecture = [ProcessorArchitecture]::UNKNOWN

        if ([OSPlatform]::IsWindows)
        {
            $processorArchitecture = (Get-CimInstance -ClassName Win32_Processor | Select-Object Architecture).Architecture

            switch ($processorArchitecture)
            {
                0       { $architecture = [ProcessorArchitecture]::X86   }
                5       { $architecture = [ProcessorArchitecture]::ARM   }
                9       { $architecture = [ProcessorArchitecture]::X64   }
                12      { $architecture = [ProcessorArchitecture]::ARM64 }
            }
        }
        else
        {
            $runtimeInformation = [System.Runtime.InteropServices.RuntimeInformation]
                
            $OSArchitecture = $runtimeInformation::OSArchitecture

            if ($OSArchitecture)
            {
                switch ("$OSArchitecture")
                {
                    "X86"   { $architecture = [ProcessorArchitecture]::X86   }
                    "X64"   { $architecture = [ProcessorArchitecture]::X64   }
                    "Arm"   { $architecture = [ProcessorArchitecture]::ARM   }
                    "Arm64" { $architecture = [ProcessorArchitecture]::ARM64 }
                } 
            }
        }
   
        return $architecture
    }

    # Get VendorID
    hidden [String]GetVendorID()
    {        
        $vendorID = $null

        if ([OSPlatform]::IsWindows)
        {
            $vendorID = (Get-CimInstance -ClassName Win32_Processor).Manufacturer
        }
        elseif ([OSPlatform]::IsLinux) 
        {
            $vendorID = ((Select-String -Path "/proc/cpuinfo" -Pattern "vendor_id") -Split ": ")[1]
        }
        elseif ([OSPlatform]::IsMacOS)
        {
            $vendorID = (sysctl -n machdep.cpu.vendor)
        }

        return $vendorID
    }
       
    # Get SocketDesignation
    hidden [SMBString]GetSocketDesignation()
    {
        return $this.GetStringAtOffset(0x04)
    }

    # Get ProcessorType
    hidden [StringValue]GetProcessorType()
    {
        $processorType = $this.GetByteAtOffset(0x05)

        return [StringValue]::new($processorType, "ProcessorType", [ref]$this)
    }
    
    # Get Family
    hidden [StringValue]GetFamily()
    {
        $family = $this.GetByteAtOffset(0x06)
        
        if ( ( $family -eq 0xFE) -and ( [SMBIOS]::Version -ge [Version]::new(2, 6) ) )
        {
            $family = $this.GetFamily2()
        }

        return [StringValue]::new($family, "Family", [ref]$this)
    }

    # Get Menufacturer
    hidden [SMBString]GetManufacturer()
    {
        return $this.GetStringAtOffset(0x07)
    }
    
    # Get ID
    hidden [StringValue]GetID()
    {
        $id = $this.GetQuadWordAtOffset(0x08)
        
        $bytes = [ArraySegment[Byte]]::new($this.data, 0x08, 8)

        [Byte[]]$a = [System.Linq.Enumerable]::ToArray($bytes)
        
        $processorId = [String]::Format( "{0:X02}{1:X02}{2:X02}{3:X02}{4:X02}{5:X02}{6:X02}{7:X02}",
                                            $a[7], $a[6], $a[5], $a[4], $a[3], $a[2], $a[1], $a[0] )

        return [StringValue]::new($id, $processorId)
    }
    
    hidden [StringValueOrderedDictionary]GetSignatureGenuineIntel([UInt32]$signature)
    {
        $type = [BitField]::Extract($signature, 12, 2)

        $familyId = [BitField]::Extract($signature, 8, 4)
        
        if ($familyId -eq 0xF)
        {
            $familyIdExt = [BitField]::Extract($signature, 20, 8)
        
            $family = $familyId + $familyIdExt
        }
        else 
        {
            $family = $familyId
        }
        
        $modelId = [BitField]::Extract($signature, 4, 4)
        
        if (($familyId -eq 0x6) -or ($familyId -eq 0xF))
        {
            $modelIdExt = [BitField]::Extract($signature, 16, 4) -shl 4
        
            $model = $modelId + $modelIdExt
        }
        else 
        {
            $model = $modelId
        }
        
        $stepping = [BitField]::Extract($signature, 0, 4)
                
        $orderedSignature = [Ordered]@{ Type = $type ; Family = $family ; Model = $model ; Stepping = $stepping }

        return [StringValueOrderedDictionary]::new($orderedSignature)
    }

    hidden [StringValueOrderedDictionary]GetSignatureAuthenticAMD([UInt32]$signature)
    {       
        $extFamily = [BitField]::Extract($signature, 20, 8)

        $extModel = [BitField]::Extract($signature, 16, 4) -shl 4

        $baseFamily = [BitField]::Extract($signature, 8, 4)
                    
        $baseModel = [BitField]::Extract($signature, 4, 4)
                    
        $stepping = [BitField]::Extract($signature, 0, 4)
                    
        if ($baseFamily -lt 0xF)
        {
            $family = $baseFamily
        }
        else
        {
            $family = $baseFamily + $extFamily
        }

        if ($baseModel -lt 0xF)
        {
            $model = $baseModel
        }
        else
        {
            $model = $baseModel + $extModel
        }

        $orderedSignature = [Ordered]@{ Family = $family ; Model = $model ; Stepping = $stepping }

        return [StringValueOrderedDictionary]::new($orderedSignature)
    }

    hidden [StringValueOrderedDictionary]GetSignatureArm([UInt32]$signature)
    {
        $implementer = [BitField]::Extract($signature, 24, 8)
                
        $variant = [BitField]::Extract($signature, 20, 4)
                
        $arch = [BitField]::Extract($signature, 16, 4)
                
        $partNum = [BitField]::Extract($signature, 4, 12)

        $revision = [BitField]::Extract($signature, 0, 4)

        $orderedSignature = [Ordered]@{ Implementer = $implementer ; Variant = $variant ; Architecture = $arch ; PartNum = $partNum ; Revision = $revision}

        return [StringValueOrderedDictionary]::new($orderedSignature)
    }

    # Get Signature
    hidden [StringValueOrderedDictionary]GetSignature()
    {  
        $id = $this.GetQuadWordAtOffset(0x08)

        $signature = [BitField]::LowUInt64($id)

        $architecture = $this.GetArchitecture()

        $vendorID = $this.GetVendorID()

        switch ($architecture)
        {
            ( { [ProcessorArchitecture]::X86, [ProcessorArchitecture]::X64 -contains $_ } )
            {
                if ( $vendorID -eq "GenuineIntel" )
                {
                    return $this.GetSignatureGenuineIntel($signature) 
                }
                elseif ( $vendorID -eq "AuthenticAMD" )
                {
                    return $this.GetSignatureAuthenticAMD($signature)
                }
            }

            ( { [ProcessorArchitecture]::Arm, [ProcessorArchitecture]::Arm64 -contains $_ } ) 
            {
                return $this.GetSignatureArm($signature)
            }
        }

        return [StringValueOrderedDictionary]::new()
    }

    # Get Features
    hidden [StringValue[]]GetFeatures()
    {     
        $id = $this.GetQuadWordAtOffset(0x08)

        $flags = [BitField]::HighUInt64($id)
        
        $vendorID = $this.GetVendorID()

        if ( ($vendorID -eq "GenuineIntel") -or ($vendorID -eq "AuthenticAMD") )
        {
            if (($id -and 0xBFEFFBFF) -ne 0)
            {
                return [BitFieldConverter]::ToStringValueArray($flags, $vendorID + "Features", [ref]$this)
            }
        }
        
        return @()
    }
    
    # Get Version
    hidden [SMBString]GetVersion()
    {
        return $this.GetStringAtOffset(0x10)
    }
    
    # Get Voltage
    hidden [StringValue[]]GetVoltage()
    {
        $value = $this.GetByteAtOffset(0x11)
        
        $voltagesList = [Collections.ArrayList]::new()

        # Legacy voltage mode
        if ($value -and 0x80) 
        {
            [Float]$voltage = ($value -band 0x7F) / 10

            $voltagesList.Add( [StringValue]::new($voltage, "{0:F01} V") )
        }
        else 
        { 
            $voltageCapability = @(
                [Float]5.0,
                [Float]3.3,
                [Float]2.9
            )

            $voltages = [BitFieldConverter]::ToArray($value, 2, $voltageCapability)

            foreach($voltage in $voltages)
            {
                if ($voltage)
                {
                    $voltagesList.Add([StringValue]::new($voltage, "{0:F01} V"))
                }
            }  
        }

        return $voltagesList
    }
    
    # Get ExternalClock
    hidden [StringValue]GetExternalClock()
    {
        $externalClock = $this.GetWordAtOffset(0x12)
        
        return  [StringValue]::new($externalClock, "{0} MHz")
    }
    
    # Get MaxSpeed
    hidden [StringValue]GetMaxSpeed()
    {
        $maxSpeed = $this.GetWordAtOffset(0x14)
        
        return  [StringValue]::new($maxSpeed, "{0} MHz")
    }
    
    # Get CurrentSpeed
    hidden [StringValue]GetCurrentSpeed()
    {
        $currentSpeed = $this.GetWordAtOffset(0x16)
        
        return  [StringValue]::new($currentSpeed, "{0} MHz")
    }
    
    # Get SocketPopulated
    hidden [bool]GetSocketPopulated()
    {
        return [bool]$this.GetByteAtOffset(0x18) -and 0x40
    }
    
    # Get ProcessorStatus
    hidden [StringValue]GetProcessorStatus()
    {
        [Byte]$status = $this.GetByteAtOffset(0x18) -and 0x07

        return [StringValue]::new($status, "Status", [ref]$this)
    }
    
    # Get Upgradable
    hidden [StringValue]GetUpgrade()
    {
        $upgradable = $this.GetByteAtOffset(0x19)

        return [StringValue]::new($upgradable, "Upgrade", [ref]$this)
    }
   
    # Get CacheHandle
    hidden [StringValue]GetCacheHandle([int]$offset, [int]$level)
    {            
        $handle = $this.GetWordAtOffset($offset)

        if ($handle -eq 0xFFFF)
        {
            if ([SMBIOS]::Version -lt [Version]::new(2, 3))
            {
                $format = [Localization]::LocalizedString("NOT_LN_CACHE")
                
                $notLnCache = [String]::Format($format, $level)

                return [StringValue]::new($handle, $notLnCache)
            }
            else
            {
                $notProvided = [Localization]::LocalizedString("NOT_PROVIDED")
                
                return [StringValue]::new($handle, $notProvided)
            }
        }
        else
        {
            return [StringValue]::new($handle)
        }
    }
   
    # Get L1CacheHandle
    hidden [StringValue]GetL1CacheHandle()
    {
        return $this.GetCacheHandle(0x1A, 1)
    }
    
    # Get L2CacheHandle
    hidden [StringValue]GetL2CacheHandle()
    {
        return $this.GetCacheHandle(0x1C, 2)
    }
    
    # Get L3CacheHandle
    hidden [StringValue]GetL3CacheHandle()
    {
        return $this.GetCacheHandle(0x1E, 3)
    }
    
    # Get SerialNumber
    hidden [SMBString]GetSerialNumber()
    {
        return $this.GetStringAtOffset(0x20)
    }
    
    # Get AssetTag
    hidden [SMBString]GetAssetTag()
    {
        return $this.GetStringAtOffset(0x21)
    }
    
    # Get PartNumber
    hidden [SMBString]GetPartNumber()
    {
        return $this.GetStringAtOffset(0x22)
    }
    
    # Get CoreCount
    hidden [UInt16]GetCoreCount()
    {
        $coreCount = $this.GetByteAtOffset(0x23)

        if ( ( $coreCount -eq 0xFF) -and ( [SMBIOS]::Version -ge [Version]::new(3, 0) ) )
        {
            $coreCount = $this.GetCoreCount2()
        }

        return $coreCount
    }
    
    # Get CoreEnabled
    hidden [UInt16]GetCoreEnabled()
    {
         $coreEnabled = $this.GetByteAtOffset(0x24)

        if ( ( $coreEnabled -eq 0xFF) -and ( [SMBIOS]::Version -ge [Version]::new(3, 0) ) )
        {
            $coreEnabled = $this.GetCoreEnabled2()
        }

        return $coreEnabled
    }
   
    # Get ThreadCount
    hidden [UInt16]GetThreadCount()
    {
        $threadCount = $this.GetByteAtOffset(0x25)
        
        if ( ( $threadCount -eq 0xFF) -and ( [SMBIOS]::Version -ge [Version]::new(3, 0) ) )
        {
            $threadCount = $this.GetThreadCount2()
        }

        return $threadCount
    }

    # Get Characteristics
    hidden [StringValue[]]GetCharacteristics()
    {
        $characteristics = $this.GetWordAtOffset(0x26)

        return [BitFieldConverter]::ToStringValueArray($characteristics, "Characteristics", [ref]$this)
    }
    
    # Get ProcessorFamily2
    hidden [UInt16]GetProcessorFamily2()
    {
        return $this.GetWordAtOffset(0x28)
    }

    # Get GetCoreCount2
    hidden [UInt16]GetCoreCount2()
    {
        return $this.GetWordAtOffset(0x2A)
    }

    # Get GetCoreCount2
    hidden [UInt16]GetCoreEnabled2()
    {
        return $this.GetWordAtOffset(0x2C)
    }

     # Get GetCoreCount2
    hidden [UInt16]GetThreadCount2()
    {
        return $this.GetWordAtOffset(0x2E)
    }  
}


###################################################################################################################################
# Type 5                                                                                                                          #
###################################################################################################################################
class MemoryControllerInformation : SMBIOSStructure 
{    
    hidden static [Hashtable]$StringArrays
    hidden static [Hashtable]$StringArrayNameAlias

    hidden static [Array]$PropertyNames

    static MemoryControllerInformation()
    {
        $stringTables = [MemoryControllerInformation]::GetStringTables("Type_5")

        [MemoryControllerInformation]::StringArrays = $stringTables.StringArrays
                                
        [MemoryControllerInformation]::StringArrayNameAlias = $stringTables.StringArrayNameAlias

        $labels = [Collections.ArrayList]::new() 

        if ( [SMBIOS]::Version -ge [Version]::new(2, 0) )
        {
            $labels.Add( "ErrorDetectingMethod"               )
            $labels.Add( "ErrorCorrectingCapabilities"        )
            $labels.Add( "SupportedInterleave"                )
            $labels.Add( "CurrentInterleave"                  )
            $labels.Add( "MaximumMemoryModuleSize"            )
            $labels.Add( "MaximumTotalMemorySize"             )
            $labels.Add( "SupportedSpeeds"                    )
            $labels.Add( "SupportedMemoryTypes"               )
            $labels.Add( "MemoryModuleVoltage"                )   
            $labels.Add( "AssociatedMemorySlots"              )
            $labels.Add( "MemoryModuleConfigurationHandles"   )
        }
        if ( [SMBIOS]::Version -ge [Version]::new(2, 1) )
        {
            $labels.Add( "EnabledErrorCorrectingCapabilities" )
        }

        [MemoryControllerInformation]::PropertyNames = $labels
    }

    MemoryControllerInformation([Byte]$type, [String]$description, [String[]]$keywords, [Byte]$length, [UInt16]$handle, [Byte[]]$data, [String[]]$strings) : base($type, $description, $keywords, $length, $handle, $data, $strings)
    {
        $this.Obsolete = $true
    }

    # Get ErrorDetectingMethod
    hidden [StringValue]GetErrorDetectingMethod()
    {
        $errorDetectingMethod = $this.GetByteAtOffset(0x4)

        return [StringValue]::new($errorDetectingMethod, "ErrorDetectingMethod", [ref]$this)
    }

    # Get ErrorCorrectingCapabilities
    hidden [StringValue[]]GetErrorCorrectingCapabilities()
    {
        $errorCorrectingCapabilities = $this.GetByteAtOffset(0x5)

        return [BitFieldConverter]::ToStringValueArray($errorCorrectingCapabilities, 6, "ErrorCorrectingCapabilities", [ref]$this)
    }

    # Get SupportedInterleave
    hidden [StringValue]GetSupportedInterleave()
    {
        $supportedInterleave = $this.GetByteAtOffset(0x6)

        return [StringValue]::new($supportedInterleave, "_Interleave", [ref]$this)
    }

    # Get CurrentInterleave
    hidden [StringValue]GetCurrentInterleave()
    {
        $currentInterleave = $this.GetByteAtOffset(0x7)
        
        return [StringValue]::new($currentInterleave, "_Interleave", [ref]$this)
    }

    # Get MaximumMemoryModuleSize
    hidden [StringValueMemorySize]GetMaximumMemoryModuleSize()
    {
        $size = $this.GetByteAtOffset(0x08)

        $maximumSizePerSlot = [Math]::Pow(2, $size)

        $unit = [MemorySizeUnit]::MB

        $sizeInBytes = $maximumSizePerSlot * 1mb

        return [StringValueMemorySize]::new($sizeInBytes, $unit)
    }

    # Get MaximumTotalMemorySize
    hidden [StringValueMemorySize]GetMaximumTotalMemorySize()
    {
        $maximumMemoryModuleSize = $this.GetMaximumMemoryModuleSize().Value
        
        $associatedMemorySlots = $this.GetAssociatedMemorySlots()

        $maximumTotalMemorySize = $maximumMemoryModuleSize * $associatedMemorySlots

        $unit = [MemorySizeUnit]::MB

        $sizeInBytes = $maximumTotalMemorySize * 1mb

        return [StringValueMemorySize]::new($sizeInBytes, $unit)
    }

    # Get SupportedSpeeds
    hidden [StringValue[]]GetSupportedSpeeds()
    {
        $supportedSpeeds = $this.GetWordAtOffset(0x09)

        return [BitFieldConverter]::ToStringValueArray($supportedSpeeds, 5, "SupportedSpeeds", [ref]$this)
    }

    # Get SupportedMemoryTypes
    hidden [StringValue[]]GetSupportedMemoryTypes()
    {
        $supportedTypes = $this.GetWordAtOffset(0x0B)

        return [BitFieldConverter]::ToStringValueArray($supportedTypes, 11, "SupportedMemoryTypes", [ref]$this)
    }

    # Get MemoryModuleVoltage
    hidden [StringValue[]]GetMemoryModuleVoltage()
    {
        $memoryModuleVoltage = $this.GetByteAtOffset(0x5)

        return [BitFieldConverter]::ToStringValueArray($memoryModuleVoltage, 3, "MemoryModuleVoltage", [ref]$this)
    }

    # Get AssociatedMemorySlots
    hidden [Byte]GetAssociatedMemorySlots()
    {
        return $this.GetByteAtOffset(0x0E)
    }

    # Get MemoryModuleConfigurationHandles
    hidden [Array]GetMemoryModuleConfigurationHandles()
    {
        $slots = $this.GetAssociatedMemorySlots()
        
        $handles = [Collections.ArrayList]::new()

        for ($offset = 0; $offset -lt $slots ; $offset++)
        {
            $handles.Add($this.GetWordAtOffset(0x0F + ( 2 * $offset )))
        }

        return $handles
    }

    # Get EnabledErrorCorrectingCapabilities
    hidden [StringValue[]]GetEnabledErrorCorrectingCapabilities()
    {
        $slots = $this.GetAssociatedMemorySlots()

        $capabilities = $this.GetByteAtOffset(0x0F + ( 2 * $slots ))

        return [BitFieldConverter]::ToStringValueArray($capabilities, 6, "ErrorCorrectingCapabilities", [ref]$this)
    } 
}


###################################################################################################################################
# Type 6                                                                                                                          #
###################################################################################################################################
class MemoryModuleInformation : SMBIOSStructure 
{ 
    hidden static [Hashtable]$StringArrays
    hidden static [Hashtable]$StringArrayNameAlias

    hidden static [Array]$PropertyNames

    static MemoryModuleInformation()
    {
        $stringTables = [MemoryModuleInformation]::GetStringTables("Type_6")

        [MemoryModuleInformation]::StringArrays = $stringTables.StringArrays
                                
        [MemoryModuleInformation]::StringArrayNameAlias = $stringTables.StringArrayNameAlias

        $labels = [Collections.ArrayList]::new() 

        if ( [SMBIOS]::Version -ge [Version]::new(2, 0) )
        {
            $labels.Add( "SocketDesignation" )
            $labels.Add( "BankConnections"   )
            $labels.Add( "CurrentSpeed"      )
            $labels.Add( "CurrentMemoryType" )
            $labels.Add( "InstalledSize"     )
            $labels.Add( "EnabledSize"       )
            $labels.Add( "ErrorStatus"       )
        }
      
        [MemoryModuleInformation]::PropertyNames = $labels 
    }

    MemoryModuleInformation([Byte]$type, [String]$description, [String[]]$keywords, [Byte]$length, [UInt16]$handle, [Byte[]]$data, [String[]]$strings) : base($type, $description, $keywords, $length, $handle, $data, $strings)
    { 
        $this.Obsolete = $true
    }

    # Get SocketDesignation
    hidden [SMBString]GetSocketDesignation()
    {
        return $this.GetStringAtOffset(0x04)  
    }

    # Get BankConnections
    hidden [StringValue[]]GetBankConnections()
    {
        $bankConnections = $this.GetByteAtOffset(0x05)

        $connections = [Collections.ArrayList]::new()

        if ($bankConnections -eq 0xFF)
        {
            $none = [Localization]::LocalizedString("NONE")
            
            $connections.Add( [StringValue]::new($bankConnections, $none) )
        }

        $bank = $bankConnections -shr 4
        
        if ($bank -ne 0xF)
        {
            $connections.Add([StringValue]::new($bank, "RAS $bank"))
        }

        $bank = $bankConnections -band 0x0F

        if ($bank -ne 0xF)
        {
            $connections.Add([StringValue]::new($bank, "RAS $bank"))
        }

        return $connections
    }

    # Get CurrentSpeed
    hidden [StringValue]GetCurrentSpeed()
    {
        $currentSpeed = $this.GetByteAtOffset(0x06)
        
        return [StringValue]::new($currentSpeed, 0x00, "{0} ns", "UNKNOWN")
    }

    # Get CurrentMemoryType
    hidden [StringValue[]]GetCurrentMemoryType()
    {
        $currentMemoryType = $this.GetWordAtOffset(0x07)

        return [BitFieldConverter]::ToStringValueArray($currentMemoryType, "CurrentMemoryType", [ref]$this)
    }

    hidden [StringValueMemorySize]_Size($size)
    {
        $memorySize = [BitField]::Extract($size, 0, 7)

        if (@(0x7D, 0x7E, 0x7F) -contains $memorySize)
        {             
             $none = [Localization]::LocalizedString("NONE")
             
             return [StringValue]::new($memorySize, $none)
        }
        else
        {
            $effectiveSize = [Math]::Pow(2, $memorySize)

            $unit = [MemorySizeUnit]::MB

            $sizeInBytes = $effectiveSize * 1mb

            return [StringValueMemorySize]::new($sizeInBytes, $unit)
        }
    }

    # Get InstalledSize
    hidden [StringValueMemorySize]GetInstalledSize()
    {
        $installedSize =  $this.GetByteAtOffset(0x09)

        return $this._Size($installedSize)
    }

    # Get EnabledSize
    hidden [StringValueMemorySize]GetEnabledSize()
    {
        $enabledSize =  $this.GetByteAtOffset(0x0A)

        return $this._Size($enabledSize)
    }

    # Get ErrorStatus
    hidden [StringValue]GetErrorStatus()
    {
        $errorStatus = $this.GetByteAtOffset(0x0B)
    
        return [BitFieldConverter]::ToStringValue($errorStatus, "ErrorStatus", [ref]$this)
    }
}


###################################################################################################################################
# Type 7                                                                                                                          #
###################################################################################################################################
class CacheInformation : SMBIOSStructure 
{        
    hidden static [Hashtable]$StringArrays
    hidden static [Hashtable]$StringArrayNameAlias
    
    hidden static [Array]$PropertyNames

    static CacheInformation()
    {
        $stringTables = [CacheInformation]::GetStringTables("Type_7")

        [CacheInformation]::StringArrays = $stringTables.StringArrays
                                
        [CacheInformation]::StringArrayNameAlias = $stringTables.StringArrayNameAlias

        $labels = [Collections.ArrayList]::new() 

        if ( [SMBIOS]::Version -ge [Version]::new(2, 0) )
        {
            $labels.Add( "SocketDesignation"   )
            $labels.Add( "Enabled"             )
            $labels.Add( "Socketed"            )
            $labels.Add( "Level"               )
            $labels.Add( "OperationalMode"     )
            $labels.Add( "Location"            )
            $labels.Add( "MaximumCacheSize"    )
            $labels.Add( "InstalledSize"       )
            $labels.Add( "SupportedSRAMType"   )
            $labels.Add( "CurrentSRAMType"     )
        }
        if ( [SMBIOS]::Version -ge [Version]::new(2, 1) )
        {
            $labels.Add( "CacheSpeed"          )
            $labels.Add( "ErrorCorrectionType" )
            $labels.Add( "SystemCacheType"     )
            $labels.Add( "Associativity"       )
        }

        [CacheInformation]::PropertyNames = $labels
    }

    CacheInformation([Byte]$type, [String]$description, [String[]]$keywords, [Byte]$length, [UInt16]$handle, [Byte[]]$data, [String[]]$strings) : base($type, $description, $keywords, $length, $handle, $data, $strings) 
    {
    }

    # Get SocketDesignation
    hidden [SMBString]GetSocketDesignation()
    {
        return $this.GetStringAtOffset(0x04)
    }
    
    # Get Enabled
    hidden [bool]GetEnabled()
    {
        $cacheConfiguration = $this.GetWordAtOffset(0x05)

        return [BitField]::Get($cacheConfiguration, 7) 
    }

    # Get OperationalMode
    hidden [StringValue]GetOperationalMode()
    {
        $cacheConfiguration = $this.GetWordAtOffset(0x5)

        $operationalMode = [BitField]::Extract($cacheConfiguration, 8, 2)

        return [StringValue]::new($operationalMode, "OperationalMode", [ref]$this)
    }

    # Get Location
    hidden [StringValue]GetLocation()
    {
        $cacheConfiguration = $this.GetWordAtOffset(0x05)

        $location = [BitField]::Extract($cacheConfiguration, 5, 2)

        return [StringValue]::new($location,"Location", [ref]$this)
    }

    # Get Socketed
    hidden [bool]GetSocketed()
    {
        $cacheConfiguration = $this.GetWordAtOffset(0x05)

        return [BitField]::Get($cacheConfiguration, 3) 
    }

    # Get Level
    hidden [Byte]GetLevel()
    {
        $cacheConfiguration = $this.GetWordAtOffset(0x05)

        return [BitField]::Extract($cacheConfiguration, 0, 3) + 1
    }
    
    # Utility method for MaximumCacheSize, InstalledSize
    hidden [StringValueMemorySize]_GetSize($maximumSize, $maximumSize2)
    {
        if ($maximumSize -eq 0x00)
        {
            $none = [Localization]::LocalizedString("NONE")

            return [StringValue]::new($maximumSize, $none)
        }
        
        $granularity = [BitField]::Get($maximumSize, 16)

        $maxSize = [BitField]::Extract($maximumSize, 0, 15)

        if ($maximumSize -eq 0xFFFF)
        {
            $granularity = [BitField]::Get($maximumSize2, 32)

            $maxSize = [BitField]::Extract($maximumSize, 0, 31)
        }

        $unit = [MemorySizeUnit]::kB

        if ($granularity)
        {
            $sizeInBytes = $maxSize * 64 * 1kb
            
            return [StringValueMemorySize]::new($sizeInBytes, $unit)
        }
        else
        {
            $sizeInBytes = $maxSize * 1kb
            
            return [StringValueMemorySize]::new($sizeInBytes, $unit)
        }
    }

    # Get MaximumCacheSize
    hidden [StringValueMemorySize]GetMaximumCacheSize()
    {
        $maximumCacheSize = $this.GetWordAtOffset(0x07)

        $maximumCacheSize2 = $this.GetWordAtOffset(0x13)

        return $this._GetSize($maximumCacheSize, $maximumCacheSize2)
    }

    # Get InstalledSize
    hidden [StringValueMemorySize]GetInstalledSize()
    {
        $installedSize = $this.GetWordAtOffset(0x09)

        $installedSize2 = $this.GetWordAtOffset(0x17)

        return $this._GetSize($installedSize, $installedSize2)
    }

    # Get SupportedSRAMType
    hidden [StringValue[]]GetSupportedSRAMType()
    {
        $supportedSRAMType = $this.GetWordAtOffset(0x0B)

        return [BitFieldConverter]::ToStringValueArray($supportedSRAMType, "_SRAMType", [ref]$this)
    }

    # Get CurrentSRAMType
    hidden [StringValue]GetCurrentSRAMType()
    {
        $currentSRAMType = $this.GetWordAtOffset(0x0D)

        return [BitFieldConverter]::ToStringValue($currentSRAMType, "_SRAMType", [ref]$this)
    }

    # Get CacheSpeed
    hidden [StringValue]GetCacheSpeed()
    {
        $cacheSpeed = $this.GetByteAtOffset(0x0F)

        return [StringValue]::new($cacheSpeed, 0x00, "{0} ns", "UNKNOWN")
    }

    # Get ErrorCorrectionType
    hidden [StringValue]GetErrorCorrectionType()
    {
         $errorCorrectionType = $this.GetByteAtOffset(0x10)

         return [StringValue]::new($errorCorrectionType, "ErrorCorrectionType", [ref]$this)
    }

    # Get SystemCacheType
    hidden [StringValue]GetSystemCacheType()
    {
        $systemCacheType = $this.GetByteAtOffset(0x11)

        return [StringValue]::new($systemCacheType, "SystemCacheType", [ref]$this)
    }

    # Get Associativity
    hidden [StringValue]GetAssociativity()
    {
        $associativity = $this.GetByteAtOffset(0x12)

        return [StringValue]::new($associativity, "Associativity", [ref]$this)
    }
}


###################################################################################################################################
# Type 8                                                                                                                          #
###################################################################################################################################
class PortConnectorInformation : SMBIOSStructure 
{    
    hidden static [Hashtable]$StringArrays
    hidden static [Hashtable]$StringArrayNameAlias

    hidden static [Array]$PropertyNames

    static PortConnectorInformation()
    {
        $stringTables = [PortConnectorInformation]::GetStringTables("Type_8")

        [PortConnectorInformation]::StringArrays = $stringTables.StringArrays
                                
        [PortConnectorInformation]::StringArrayNameAlias = $stringTables.StringArrayNameAlias

        $labels = [Collections.ArrayList]::new() 

        if ( [SMBIOS]::Version -ge [Version]::new(2, 0) )
        {
            $labels.Add( "InternalReferenceDesignator" )
            $labels.Add( "InternalConnectorType"       )
            $labels.Add( "ExternalReferenceDesignator" )
            $labels.Add( "ExternalConnectorType"       )
            $labels.Add( "PortType"                    )
        }

        [PortConnectorInformation]::PropertyNames = $labels
    }

    PortConnectorInformation([Byte]$type, [String]$description, [String[]]$keywords, [Byte]$length, [UInt16]$handle, [Byte[]]$data, [String[]]$strings) : base($type, $description, $keywords, $length, $handle, $data, $strings)
    {   
    }

    # Get InternalReferenceDesignator
    hidden [SMBString]GetInternalReferenceDesignator()
    {
        return $this.GetStringAtOffset(0x04)
    }
    
    # Get InternalConnectorType
    hidden [StringValue]GetInternalConnectorType()
    {
        $internalConnectorType = $this.GetByteAtOffset(0x05)
        
        return [StringValue]::new($internalConnectorType, "_ConnectorType", [ref]$this)
    }
     
    # Get ExternalReferenceDesignator
    hidden [SMBString]GetExternalReferenceDesignator()
    {
        return $this.GetStringAtOffset(0x06)
    }

    # Get ExternalConnectorType
    hidden [StringValue]GetExternalConnectorType()
    {
        $externalConnectorType = $this.GetByteAtOffset(0x07)

        return [StringValue]::new($externalConnectorType, "_ConnectorType", [ref]$this)
    }

    # Get PortType
    hidden [StringValue]GetPortType()
    {
        $portType = $this.GetByteAtOffset(0x08)

        return [StringValue]::new($portType, "PortType", [ref]$this)
    }
}


###################################################################################################################################
# Type 9                                                                                                                          #
###################################################################################################################################
class SystemSlots : SMBIOSStructure 
{   
    hidden static [Hashtable]$StringArrays
    hidden static [Hashtable]$StringArrayNameAlias

    hidden static [Array]$PropertyNames

    static SystemSlots()
    {
        $stringTables = [SystemSlots]::GetStringTables("Type_9")

        [SystemSlots]::StringArrays = $stringTables.StringArrays
                                
        [SystemSlots]::StringArrayNameAlias = $stringTables.StringArrayNameAlias

        $labels = [Collections.ArrayList]::new() 
  
        if ( [SMBIOS]::Version -ge [Version]::new(2, 0) )
        {
            $labels.Add( "Designation"          )
            $labels.Add( "SlotType"             )
            $labels.Add( "SlotDataBusWidth"     )
            $labels.Add( "CurrentUsage"         )
            $labels.Add( "SlotLength"           )
            $labels.Add( "ID"                   )
            $labels.Add( "Characteristics"      )
        }
        if ( [SMBIOS]::Version -ge [Version]::new(2, 6) )
        {
            $labels.Add( "SegmentGroupNumber"   )
            $labels.Add( "BusNumber"            )
            $labels.Add( "DeviceFunctionNumber" )
        }
        if ( [SMBIOS]::Version -ge [Version]::new(3, 2) )
        {
            $labels.Add( "DataBusWidth"         )
            $labels.Add( "PeerDevices"          )
        }

        [SystemSlots]::PropertyNames = $labels
    }
    
    SystemSlots([Byte]$type, [String]$description, [String[]]$keywords, [Byte]$length, [UInt16]$handle, [Byte[]]$data, [String[]]$strings) : base($type, $description, $keywords, $length, $handle, $data, $strings)
    {
    }
    
    # Get Designation
    hidden [SMBString]GetDesignation()
    {
        return $this.GetStringAtOffset(0x04)
    }

     # Get SlotType
    hidden [StringValue]GetSlotType()
    {
        $slotType = $this.GetByteAtOffset(0x05)

        return [StringValue]::new($slotType, "SlotType", [ref]$this)
    }

     # Get SlotDataBusWidth
    hidden [StringValue]GetSlotDataBusWidth()
    {
        $slotDataBusWidth = $this.GetByteAtOffset(0x06)

        return [StringValue]::new($slotDataBusWidth, "SlotDataBusWidth", [ref]$this)
    }

     # Get CurrentUsage
    hidden [StringValue]GetCurrentUsage()
    {
        $currentUsage = $this.GetByteAtOffset(0x07)

        return [StringValue]::new($currentUsage, "CurrentUsage", [ref]$this)
    }

     # Get SlotLength
    hidden [StringValue]GetSlotLength()
    {
       $length = $this.GetByteAtOffset(0x08)

       return [StringValue]::new($length, "SlotLength", [ref]$this)
    }

    # Get ID
    hidden [UInt16]GetID()
    {
        return $this.GetWordAtOffset(0x09)
    }

    # Get Characteristics
    hidden [StringValue[]]GetCharacteristics()
    {
        $characteristics = [Collections.ArrayList]::new()

        $characteristics1 = $this.GetByteAtOffset(0x0B)

        $characteristics =  $characteristics + [BitFieldConverter]::ToStringValueArray($characteristics1, 8, "SlotCharacteristics1", [ref]$this)

        if ( [SMBIOS]::Version -ge [Version]::new(2, 1) )
        {   
            $characteristics2 = $this.GetByteAtOffset(0x0C)
            
            $characteristics = $characteristics + [BitFieldConverter]::ToStringValueArray($characteristics2, 4, "SlotCharacteristics2", 8, [ref]$this)
        }

        return $characteristics
    }

    # Get SegmentGroupNumber
    hidden [UInt16]GetSegmentGroupNumber()
    {
        return $this.GetWordAtOffset(0x0D)
    }

    # Get BusNumber
    hidden [Byte]GetBusNumber()
    {
        return $this.GetByteAtOffset(0x0F)
    }

    # Get DeviceFunctionNumber
    hidden [Byte]GetDeviceFunctionNumber()
    {
        return $this.GetByteAtOffset(0x10)
    }

    # Get DataBusWidth
    hidden [Byte]GetDataBusWidth()
    {
        return $this.GetByteAtOffset(0x11)
    }   
    
    # Get PeerDevices
    hidden [Byte]GetPeerDevices()
    {
        return $this.GetByteAtOffset(0x12)
    }   
}


###################################################################################################################################
# Type 10                                                                                                                         #
###################################################################################################################################
class OnBoardDevice {
    [StringValue]$DeviceType
    [StringValue]$Status
    [String]$Description

    OnBoardDevice([StringValue]$DeviceType, [StringValue]$Status, [String]$Description) 
    {
        $this.DeviceType = $DeviceType
        $this.Status = $Status
        $this.Description = $Description
    }
    
    [String]ToString() {
        return $this.Description
    }
}

class OnBoardDevicesInformation : SMBIOSStructure 
{        
    hidden static [Hashtable]$StringArrays
    hidden static [Hashtable]$StringArrayNameAlias
    
    hidden static [Array]$PropertyNames
    
    static OnBoardDevicesInformation()
    {
        $stringTables = [OnBoardDevicesInformation]::GetStringTables("Type_10")

        [OnBoardDevicesInformation]::StringArrays = $stringTables.StringArrays
                                
        [OnBoardDevicesInformation]::StringArrayNameAlias = $stringTables.StringArrayNameAlias

        $labels = [Collections.ArrayList]::new() 
  
        if ( [SMBIOS]::Version -ge [Version]::new(2, 0) )
        {
            $labels.Add( "Devices" )
        }

        [OnBoardDevicesInformation]::PropertyNames = $labels
    }

    OnBoardDevicesInformation([Byte]$type, [String]$description, [String[]]$keywords, [Byte]$length, [UInt16]$handle, [Byte[]]$data, [String[]]$strings) : base($type, $description, $keywords, $length, $handle, $data, $strings)
    { 
        $this.Obsolete = $true
    }

    # Get Devices
    hidden [OnBoardDevice[]]GetDevices()
    {
        $numberOfDevices = ($this.Length - 4) / 2

        $deviceList = [System.Collections.ArrayList]::new()

        $types = [OnBoardDevicesInformation]::StringArrays["DeviceTypes"]

        $status = [OnBoardDevicesInformation]::StringArrays["DeviceStatus"]

        for ($i = 1; $i -le $numberOfDevices ; $i++) 
        {
            [Byte]$deviceInformations = $this.data[4 + 2 * ($i - 1)]
            
            $deviceType = $([StringValue]::new($deviceInformations -band 127,  $types))

            $deviceStatus = $([StringValue]::new(($deviceInformations -shr 7), $status))

            $description = $this.strings[$this.data[5 + 2 * ($i - 1)] - 1]
            
            $deviceList.Add([OnBoardDevice]::new($deviceType, $deviceStatus, $description)) | Out-Null
        }

        return $deviceList.ToArray()
    }
}


###################################################################################################################################
# Type 11                                                                                                                         #
###################################################################################################################################
class OEMStrings : SMBIOSStructure 
{       
    hidden static [Hashtable]$StringArrays
    hidden static [Hashtable]$StringArrayNameAlias
    
    hidden static [Array]$PropertyNames

    static OEMStrings()
    {    
        [OEMStrings]::StringArrays = @{}

        [OEMStrings]::StringArrayNameAlias = @{}

        $labels = [Collections.ArrayList]::new() 

        if ( [SMBIOS]::Version -ge [Version]::new(2, 0) )
        {
            $labels.Add( "OEMStrings" )
        }

        [OEMStrings]::PropertyNames = $labels
    }

    OEMStrings([Byte]$type, [String]$description, [String[]]$keywords, [Byte]$length, [UInt16]$handle, [Byte[]]$data, [String[]]$strings) : base($type, $description, $keywords, $length, $handle, $data, $strings)
    {  
    }

    # Get Count
    hidden [Byte]GetCount()
    {
        return $this.GetByteAtOffset(0x04)
    } 

    # Get OEMStrings
    hidden [String[]]GetOEMStrings()
    {
        return ([SMBIOSStructure]$this).Strings
    } 
}


###################################################################################################################################
# Type 12                                                                                                                         #
###################################################################################################################################
class SystemConfigurationOptions : SMBIOSStructure 
{        
    hidden static [Hashtable]$StringArrays
    hidden static [Hashtable]$StringArrayNameAlias
    
    static [Array]$PropertyNames

    static SystemConfigurationOptions()
    {        
        [SystemConfigurationOptions]::StringArrays = @{}

        [SystemConfigurationOptions]::StringArrayNameAlias = @{}

        $labels = [Collections.ArrayList]::new() 

        if ( [SMBIOS]::Version -ge [Version]::new(2, 0) )
        {
            $labels.Add( "Options" )
        }

        [SystemConfigurationOptions]::PropertyNames = $labels
    }

    SystemConfigurationOptions([Byte]$type, [String]$description, [String[]]$keywords, [Byte]$length, [UInt16]$handle, [Byte[]]$data, [String[]]$strings) : base($type, $description, $keywords, $length, $handle, $data, $strings)
    {
    }

    # Get Count
    hidden [Byte]GetCount()
    {
        return $this.GetByteAtOffset(0x04)
    } 

    # Get Options
    hidden [String[]]GetOptions()
    {
        return ([SMBIOSStructure]$this).Strings
    } 
}


###################################################################################################################################
# Type 13                                                                                                                         #
###################################################################################################################################
class BIOSLanguageInformation : SMBIOSStructure 
{        
    hidden static [Hashtable]$StringArrays
    hidden static [Hashtable]$StringArrayNameAlias

    static [Array]$PropertyNames

    static BIOSLanguageInformation()
    {
        $stringTables = [BIOSLanguageInformation]::GetStringTables("Type_13")

        [BIOSLanguageInformation]::StringArrays = $stringTables.StringArrays
                                
        [BIOSLanguageInformation]::StringArrayNameAlias = $stringTables.StringArrayNameAlias

        $labels = [Collections.ArrayList]::new() 
  
        if ( [SMBIOS]::Version -ge [Version]::new(2, 0) )
        {
            $labels.Add( "InstallableLanguages" )
            $labels.Add( "CurrentLanguage"      )
            $labels.Add( "Format"               )
        }

        [BIOSLanguageInformation]::PropertyNames = $labels
    }

    BIOSLanguageInformation([Byte]$type, [String]$description, [String[]]$keywords, [Byte]$length, [UInt16]$handle, [Byte[]]$data, [String[]]$strings) : base($type, $description, $keywords, $length, $handle, $data, $strings)
    {
    }

    # Get InstallableLanguages
    hidden [String[]]GetInstallableLanguages()
    {
        $numberOfInstallableLanguages = $this.GetByteAtOffset(0x04)

        $installableLanguages = [ArrayList]::new()

        if ($this.Strings)
        {
            for ($i=0; $i -le $numberOfInstallableLanguages - 1; $i++)
            {
                $installableLanguages.Add( $this.strings[$i] )
            }
        }
        
        return $installableLanguages
    } 

    # Get CurrentLanguage
    hidden [SMBString]GetCurrentLanguage()
    {
        return $this.GetStringAtOffset(0x15)
    } 

    # Get Format
    hidden [StringValue]GetFormat()
    {
        [Byte]$format = $this.GetByteAtOffset(0x05) -band 0x01

        return [StringValue]::new($format, "Format", [ref]$this)
    }
}


###################################################################################################################################
# Type 14                                                                                                                         #
###################################################################################################################################
class GroupAssociationsItem
{
    [SMBIOSType]$Type
    [UInt16]$Handle

    GroupAssociationsItem([SMBIOSType]$type, [UInt16]$handle)
    {
        $this.Type = $type
        $this.Handle = $handle
    }

    [String]ToString()
    {
        return "$($this.Type)"
    }
}

class GroupAssociations : SMBIOSStructure 
{
    hidden static [Hashtable]$StringArrays
    hidden static [Hashtable]$StringArrayNameAlias

    static [Array]$PropertyNames

    static GroupAssociations()
    {
        [GroupAssociations]::StringArrays = @{}

        [GroupAssociations]::StringArrayNameAlias = @{}

        $labels = [Collections.ArrayList]::new() 
        
        if ( [SMBIOS]::Version -ge [Version]::new(2, 0) )
        {
            $labels.Add( "Name"  )
            $labels.Add( "Items" )
        }

       [GroupAssociations]::PropertyNames = $labels
    }

    GroupAssociations([Byte]$type, [String]$description, [String[]]$keywords, [Byte]$length, [UInt16]$handle, [Byte[]]$data, [String[]]$strings) : base($type, $description, $keywords, $length, $handle, $data, $strings)
    {
    }

    # Get Name
    hidden [SMBString]GetName()
    { 
        return $this.GetStringAtOffset(0x04)
    }

    # Get NumberOfItems
    hidden [Byte]GetNumberOfItems()
    { 
        return ($this.data.length - 5) / 3
    }

    # Get Items
    hidden [Array]GetItems()
    {
        $items = [Collections.ArrayList]::new()

        $length = $this.GetNumberOfItems()

        for ($i = 0; $i -lt $length ; $i++) 
        {            
            $type = $this.GetByteAtOffset(0x05 + 3 * $i)

            $SMBIOSType = [SMBIOS]::Types[$type]
           
            $handle = [BitConverter]::ToUInt16($this.data, 0x05 + 3 * $i + 1)   

            $item = [GroupAssociationsItem]::new($SMBIOSType, $handle)

            $items.Add( $item ) | Out-Null
        }

        return $items.ToArray()
    }
}


###################################################################################################################################
# Type 15                                                                                                                        #
###################################################################################################################################
class SystemEventLog : SMBIOSStructure 
{  
    hidden static [Hashtable]$StringArrays
    hidden static [Hashtable]$StringArrayNameAlias

    static [Array]$PropertyNames

    static SystemEventLog()
    {
        $stringTables = [SystemEventLog]::GetStringTables("Type_15")

        [SystemEventLog]::StringArrays = $stringTables.StringArrays
                                
        [SystemEventLog]::StringArrayNameAlias = $stringTables.StringArrayNameAlias

        $labels = [Collections.ArrayList]::new() 
        
        if ( [SMBIOS]::Version -ge [Version]::new(2, 0) )
        {
            $labels.Add( "AreaLength"                       )
            $labels.Add( "HeaderStartOffset"                )
            $labels.Add( "HeaderLength"                     )
            $labels.Add( "DataStartOffset"                  )
            $labels.Add( "AccessMethod"                     )
            $labels.Add( "Status"                           )
            $labels.Add( "ChangeToken"                      )
            $labels.Add( "AccessMethodAddress"              )
            $labels.Add( "HeaderFormat"                     )
            $labels.Add( "SupportedEventLogTypeDescriptors" )
        }

        [SystemEventLog]::PropertyNames = $labels
    }

    SystemEventLog([Byte]$type, [String]$description, [String[]]$keywords, [Byte]$length, [UInt16]$handle, [Byte[]]$data, [String[]]$strings) : base($type, $description, $keywords, $length, $handle, $data, $strings)
    {
    }

    # Get AreaLength
    hidden [StringValueMemorySize]GetAreaLength()
    { 
        $areaLength = $this.GetWordAtOffset(0x04)

        $unit = [MemorySizeUnit]::B

        return [StringValueMemorySize]::new($areaLength, $unit)
    }

    # Get HeaderStartOffset
    hidden [UInt16]GetHeaderStartOffset()
    { 
        return $this.GetWordAtOffset(0x06)
    }

    # Get HeaderLength
    hidden [StringValueMemorySize]GetHeaderLength()
    { 
        $headerLength = $this.GetDataStartOffset() - $this.GetHeaderStartOffset()

        $unit = [MemorySizeUnit]::B

        return [StringValueMemorySize]::new($headerLength, $unit)
    }

    # Get DataStartOffset
    hidden [UInt16]GetDataStartOffset()
    { 
        return $this.GetWordAtOffset(0x08)
    }

    # Get AccessMethod
    hidden [StringValue]GetAccessMethod()
    { 
        $accessMethod = $this.GetByteAtOffset(0x0A)

        return [StringValue]::new($accessMethod, "AccessMethod", [ref]$this)
    }

    # Get Status
    hidden [StringVAlue[]]GetStatus()
    { 
        $status = $this.GetByteAtOffset(0x0B)

        $logStatus = [Collections.ArrayList]::new()

        $statusValid = [BitField]::Get($status, 0)

        $logStatus.Add([StringValue]::new($statusValid, "StatusValid", [ref]$this)) | Out-Null

        $statusFull = [BitField]::Get($status, 1)

        $logStatus.Add([StringValue]::new($statusFull, "StatusFull", [ref]$this)) | Out-Null

        return $logStatus
    }

    # Get ChangeToken
    hidden [UInt16]GetChangeToken()
    { 
        return $this.GetWordAtOffset(0x0C)
    }

    # Get AccessMethodAddress
    hidden [UInt16]GetAccessMethodAddress()
    {
        return $this.GetWordAtOffset(0x10)
    }

    # Get HeaderFormat
    hidden [StringValue]GetHeaderFormat()
    { 
        $headerFormat = $this.GetByteAtOffset(0x14)

        return [StringValue]::new($headerFormat, "HeaderFormat", [ref]$this)
    }

    # Get NumberOfSupportedLogTypeDescriptors
    hidden [Byte]GetNumberOfSupportedLogTypeDescriptors()
    { 
        return $this.GetByteAtOffset(0x15)
    }

    # Get LengthOfEeachLogTypeDescriptor
    hidden [Byte]GetLengthOfEeachLogTypeDescriptor()
    { 
        return $this.GetByteAtOffset(0x16)
    }

    # Get SupportedEventLogTypeDescriptors
    hidden [Array]GetSupportedEventLogTypeDescriptors()
    { 
        $numberOfDescriptors = $this.GetNumberOfSupportedLogTypeDescriptors()
        
        $lengthOfDescriptor = $this.GetLengthOfEeachLogTypeDescriptor()

        $descriptors = [Collections.ArrayList]::new()

        for ($i = 0; $i -lt $numberOfDescriptors ; $i++) 
        { 
            $descriptorSegment = ([ArraySegment[Byte]]::new($this.data, 0x17 + ($i * $lengthOfDescriptor), $lengthOfDescriptor))
            
            [Byte[]]$descriptor = [System.Linq.Enumerable]::ToArray($descriptorSegment)

            $eventLogType = $descriptor[0]

            $type = [StringValue]::new($eventLogType, "EventLogType", [ref]$this)

            $dataFormatType = $descriptor[1]

            $format = [StringValue]::new($dataFormatType, "EventLogVariableDataFormatType", [ref]$this)

            $orderedDescriptor = [Ordered]@{ EventLogType = $type ; DataFormatType = $format }

            $descriptors.Add([StringValue]::new($orderedDescriptor, "$type")) | Out-Null
        }
       
        return $descriptors
    }
}


###################################################################################################################################
# Type 16                                                                                                                         #
###################################################################################################################################
class PhysicalMemoryArray : SMBIOSStructure 
{
    hidden static [Hashtable]$StringArrays
    hidden static [Hashtable]$StringArrayNameAlias

    static [Array]$PropertyNames

    static PhysicalMemoryArray()
    {
        $stringTables = [PhysicalMemoryArray]::GetStringTables("Type_16")

        [PhysicalMemoryArray]::StringArrays = $stringTables.StringArrays
                                
        [PhysicalMemoryArray]::StringArrayNameAlias = $stringTables.StringArrayNameAlias

        $labels = [Collections.ArrayList]::new() 
        
        if ( [SMBIOS]::Version -ge [Version]::new(2, 0) )
        {
            $labels.Add( "Location"                     )
            $labels.Add( "Use"                          )
            $labels.Add( "MemoryErrorCorrection"        )
            $labels.Add( "MaximumCapacity"              )
            $labels.Add( "MemoryErrorInformationHandle" )
            $labels.Add( "NumberOfMemoryDevices"        )
        }

        [PhysicalMemoryArray]::PropertyNames = $labels 
    }

    PhysicalMemoryArray([Byte]$type, [String]$description, [String[]]$keywords, [Byte]$length, [UInt16]$handle, [Byte[]]$data, [String[]]$strings) : base($type, $description, $keywords, $length, $handle, $data, $strings)
    {      
    }

    # Get Location
    hidden [StringValue]GetLocation()
    { 
        $location = $this.GetByteAtOffset(0x04)

        $stringArray = [PhysicalMemoryArray]::StringArrays["Location"]

        return [StringValue]::new($location, $stringArray)
    }

    # Get Use
    hidden [StringValue]GetUse()
    { 
        $use = $this.GetByteAtOffset(0x05)

        $stringArray = [PhysicalMemoryArray]::StringArrays["Use"]

        return [StringValue]::new($use, $stringArray)
    }

    # Get MemoryErrorCorrection
    hidden [StringValue]GetMemoryErrorCorrection()
    { 
        $correction = $this.GetByteAtOffset(0x06)

        return [StringValue]::new($correction, "MemoryErrorCorrection", [ref]$this)
    }

    # Get MaximumCapacity
    hidden [StringValueMemorySize]GetMaximumCapacity()
    { 
        $maximumCapacity = $this.GetDoubleWordAtOffset(0x07)
        
        $sizeInBytes = $maximumCapacity * 1kb
        
        if ($maximumCapacity -eq 0x80000000)
        {
            $sizeInBytes = $this.GetDoubleWordAtOffset(0x0F)    
        }

        $unit = [MemorySizeUnit]::GB

        return [StringValueMemorySize]::new($sizeInBytes, $unit)
    }

    # Get MemoryErrorInformationHandle
    hidden [StringValue]GetMemoryErrorInformationHandle()
    { 
        $handle = $this.GetWordAtOffset(0x0B)

        if ( @(0xFFFE, 0xFFFF) -contains $handle )
        {
            return [StringValue]::new($handle, "MemoryErrorInformationHandle", [ref]$this)
        }

        return [StringValue]::new($handle)
    }

    # Get NumberOfMemoryDevices
    hidden [UInt16]GetNumberOfMemoryDevices()
    {
        return $this.GetWordAtOffset(0x0D)
    }
}


###################################################################################################################################
# Type 17                                                                                                                         #
###################################################################################################################################
class MemoryDevice : SMBIOSStructure 
{    
    hidden static [Hashtable]$StringArrays
    hidden static [Hashtable]$StringArrayNameAlias

    static [Array]$PropertyNames

    static MemoryDevice()
    {
        $stringTables = [MemoryDevice]::GetStringTables("Type_17")

        [MemoryDevice]::StringArrays = $stringTables.StringArrays
                                
        [MemoryDevice]::StringArrayNameAlias = $stringTables.StringArrayNameAlias

        $labels = [Collections.ArrayList]::new() 
        
        if ( [SMBIOS]::Version -ge [Version]::new(2, 1) )
        {
            $labels.Add( "PhysicalMemoryArrayHandle"               )
            $labels.Add( "MemoryErrorInformationHandle"            )
            $labels.Add( "TotalWidth"                              )
            $labels.Add( "DataWidth"                               )
            $labels.Add( "Size"                                    )
            $labels.Add( "FormFactor"                              )
            $labels.Add( "DeviceSet"                               )
            $labels.Add( "DeviceLocator"                           )
            $labels.Add( "BankLocator"                             )
            $labels.Add( "MemoryType"                              )
            $labels.Add( "TypeDetail"                              )
        }
        if ( [SMBIOS]::Version -ge [Version]::new(2, 3) )
        {
            $labels.Add( "Speed"                                   )
            $labels.Add( "Manufacturer"                            )
            $labels.Add( "SerialNumber"                            )
            $labels.Add( "AssetTag"                                )
            $labels.Add( "PartNumber"                              )
        }
        if ( [SMBIOS]::Version -ge [Version]::new(2, 6) )
        {
            $labels.Add( "Attributes"                              )
        }
        if ( [SMBIOS]::Version -ge [Version]::new(2, 7) )
        {
            $labels.Add( "ConfiguredMemorySpeed"                   )
        }
        if ( [SMBIOS]::Version -ge [Version]::new(2, 8) )
        {   
            $labels.Add( "MinimumVoltage"                          )
            $labels.Add( "MaximumVoltage"                          )
            $labels.Add( "ConfiguredVoltage"                       )
        }
        if ( [SMBIOS]::Version -ge [Version]::new(3, 2) )
        {
            $labels.Add( "MemoryTechnology"                        )
            $labels.Add( "MemoryOperatingModeCapability"           )
            $labels.Add( "FirmwareVersion"                         )
            $labels.Add( "ModuleManufacturerID"                    )
            $labels.Add( "ModuleProductID"                         )
            $labels.Add( "MemorySubsystemControllerManufacturerID" )
            $labels.Add( "MemorySubsystemControllerProductID"      )
            $labels.Add( "NonVolatileSize"                         )
            $labels.Add( "VolatileSize"                            )
            $labels.Add( "CacheSize"                               )
            $labels.Add( "LogicalSize"                             )
        }

        [MemoryDevice]::PropertyNames = $labels   
    }

    MemoryDevice([Byte]$type, [String]$description, [String[]]$keywords, [Byte]$length, [UInt16]$handle, [Byte[]]$data, [String[]]$strings) : base($type, $description, $keywords, $length, $handle, $data, $strings)
    {   
    }

    # Get PhysicalMemoryArrayHandle
    hidden [UInt16]GetPhysicalMemoryArrayHandle()
    {
        return $this.GetWordAtOffset(0x04)
    }

    # Get MemoryErrorInformationHandle
    hidden [StringValue]GetMemoryErrorInformationHandle()
    {
        $handle = $this.GetWordAtOffset(0x06)

        if ( @(0xFFFE, 0xFFFF) -contains $handle )
        {
            return [StringValue]::new($handle, "MemoryErrorInformationHandle", [ref]$this)
        }

        return [StringValue]::new($handle)  
    }

    # Get TotalWidth
    hidden [StringValue]GetTotalWidth()
    {
        $totalWidth = $this.GetWordAtOffset(0x08)  

        return [StringValue]::new($totalWidth, 0x0000, "{0} bits", "UNKNOWN")
    }

    # Get DataWidth
    hidden [StringValue]GetDataWidth()
    {
        $dataWidth = $this.GetWordAtOffset(0x0A)  

        return [StringValue]::new($dataWidth, 0x0000, "{0} bits", "UNKNOWN")
    }

    # Get Size
    hidden [StringValueMemorySize]GetSize()
    {
        $size = $this.GetWordAtOffset(0x0C) 

        $sizeInBytes = 0

        $unit = [MemorySizeUnit]::B

        if ( @(0xFFFE, 0x0000) -contains $size )
        {
            return [StringValue]::new($size, "Size", [ref]$this)
        }

        if ($size -eq 0x7FFF)
        {
            $size = $this.ExtendedSize()

            $effectiveSize = [BitFieldConverter]::ToInt($size, 0, 30)

            $sizeInBytes = $effectiveSize * 1mb

            $unit = [MemorySizeUnit]::GB
        }
        else 
        {
            $effectiveSize = $size -band 0x7FFF

            if ($size -band (1 -shl 15))
            {
                $unit = [MemorySizeUnit]::kB
                
                $sizeInBytes = $effectiveSize * 1kb
            }
            else
            {
                $unit = [MemorySizeUnit]::MB

                $sizeInBytes = $effectiveSize * 1mb
            }
        }
        
        return [StringValueMemorySize]::new($sizeInBytes, $unit)
    }

    # Get FormFactor
    hidden [StringValue]GetFormFactor()
    {
        $formFactor = $this.GetByteAtOffset(0x0E)

        return [StringValue]::new($formFactor, "FormFactor", [ref]$this)
    }

    # Get DeviceSet
    hidden [StringValue]GetDeviceSet()
    {
        $deviceSet = $this.GetByteAtOffset(0x0F)
        
        if ( @(0xFF, 0x00) -contains $deviceSet )
        {
            return [StringValue]::new($deviceSet, "DeviceSet", [ref]$this)
        }

        return [StringValue]::new($deviceSet, "{0}")
    }

    # Get DeviceLocator
    hidden [SMBString]GetDeviceLocator()
    {
        return $this.GetStringAtOffset(0x10)
    }

    # Get BankLocator
    hidden [SMBString]GetBankLocator()
    {
        return $this.GetStringAtOffset(0x11)
    }

    # Get MemoryType
    hidden [StringValue]GetMemoryType()
    {
        $memoryType = $this.GetByteAtOffset(0x12)

        return [StringValue]::new($memoryType, "MemoryType", [ref]$this) 
    }

    # Get TypeDetail
    hidden [StringValue[]]GetTypeDetail()
    {
        $typeDetail = $this.GetWordAtOffset(0x13)

        return [BitFieldConverter]::ToStringValueArray($typeDetail, "TypeDetail", [ref]$this)    
    }

    # Get Speed
    hidden [StringValue]GetSpeed()
    {
        $speed = $this.GetWordAtOffset(0x15)

        $extendedSpeed = 0

        if ($speed -eq 0xFFFF)
        { 
            $extendedSpeed = $this.ExtendedSpeed()
        }
        
        return [StringValue]::new($speed, 0x00, "{0} MT/s", "UNKNOWN", 0xFFFF, $extendedSpeed)
    }

    # Get Manufacturer
    hidden [SMBString]GetManufacturer()
    {
        return $this.GetStringAtOffset(0x17) 
    }

    # Get SerialNumber
    hidden [SMBString]GetSerialNumber()
    {
        return $this.GetStringAtOffset(0x18)  
    }

    # Get AssetTag
    hidden [SMBString]GetAssetTag()
    {
        return $this.GetStringAtOffset(0x19)  
    }

    # Get PartNumber
    hidden [SMBString]GetPartNumber()
    {
        return $this.GetStringAtOffset(0x1A)
    }

    # Get Attributes
    hidden [StringValue]GetAttributes()
    {
        $attributes = $this.GetByteAtOffset(0x1A)

        $rank = [BitField]::Extract($attributes, 0, 4)

        return [StringValue]::new($rank, 0x00, $null, "UNKNOWN")
    }

    hidden [UInt32]ExtendedSize()
    {
        return $this.GetDoubleWordAtOffset(0x1C) 
    }

    # Get ConfiguredMemorySpeed
    hidden [StringValue]GetConfiguredMemorySpeed()
    {
        $configuredMemorySpeed = $this.GetWordAtOffset(0x20)

        $extendedConfiguredMemorySpeed = 0

        if ($configuredMemorySpeed -eq 0xFFFF)
        {  
            $extendedConfiguredMemorySpeed = $this.ExtendedConfiguredMemorySpeed()
        }

        return [StringValue]::new($configuredMemorySpeed, 0x00, "{0} MT/s", "UNKNOWN", 0xFFFF, $extendedConfiguredMemorySpeed)
    }

     # Get MinimumVoltage
    hidden [StringValue]GetMinimumVoltage()
    {
        $minimumVoltage = $this.GetWordAtOffset(0x22)  

        return [StringValue]::new($minimumVoltage, 0x00, "{0} mV", "UNKNOWN")
    }

    # Get MaximumVolatge
    hidden [StringValue]GetMaximumVoltage()
    {
        $maximumVoltage = $this.GetWordAtOffset(0x24)  

        return [StringValue]::new($maximumVoltage, 0x00, "{0} mV", "UNKNOWN")
    }

    # Get ConfiguredVoltage
    hidden [StringValue]GetConfiguredVoltage()
    {
        $configuredVoltage = $this.GetWordAtOffset(0x26)  

        return [StringValue]::new($configuredVoltage, 0x00, "{0} mV", "UNKNOWN")
    }

    # Get MemoryTechnology
    hidden [StringValue]GetMemoryTechnology()
    {
        $memoryTechnology = $this.GetByteAtOffset(0x28) 

        return [StringValue]::new($memoryTechnology, "MemoryTechnology", [ref]$this)
    }

    # Get MemoryOperatingModeCapability
    hidden [StringValue[]]GetMemoryOperatingModeCapability()
    {
        $memoryOperatingModeCapability = $this.GetByteAtOffset(0x29)
       
        return [BitFieldConverter]::ToStringValueArray($memoryOperatingModeCapability, 6, "MemoryOperatingModeCapability", [ref]$this)
    }

    # Get FirmwareVersion
    hidden [SMBString]GetFirmwareVersion()
    {
        return $this.GetStringAtOffset(0x2B) 
    }

    # Get ModuleManufacturerID
    hidden [StringValue]GetModuleManufacturerID()
    {
        $moduleManufacturerID = $this.GetWordAtOffset(0x2C)
       
        return [StringValue]::new($moduleManufacturerID, 0x00, $null, "UNKNOWN")
    }

    # Get ModuleProductID
    hidden [StringValue]GetModuleProductID()
    {
        $moduleProductID = $this.GetWordAtOffset(0x2E)

        return [StringValue]::new($moduleProductID, 0x00, $null, "UNKNOWN")
    }

    # Get MemorySubsystemControllerManufacturerID
    hidden [StringValue]GetMemorySubsystemControllerManufacturerID()
    {
        $memorySubsystemControllerManufacturerID = $this.GetWordAtOffset(0x30)

        return [StringValue]::new($memorySubsystemControllerManufacturerID, 0x00, $null, "UNKNOWN")     
    }

    # Get MemorySubsystemControllerProductID
    hidden [StringValue]GetMemorySubsystemControllerProductID()
    {
        $memorySubsystemControllerProductID = $this.GetWordAtOffset(0x32)

        return [StringValue]::new($memorySubsystemControllerProductID, 0x00, $null, "UNKNOWN")     
    }

    # Utility method for NonVolatileSize, VolatileSize, CacheSize, LogicalSize methods
    hidden [StringValueMemorySize]_GetSize($size)
    {        
        if (([BitField]::LowUInt64($size) -eq 0xFFFFFFFF) -and ([BitField]::HighUInt64($size) -eq 0xFFFFFFFF))
        {
            $unknown = [Localization]::LocalizedString("UNKNOWN")
            
            return [StringValue]::new($size, $unknown) 
        }
        elseif (([BitField]::LowUInt64($size) -eq 0x00) -and ([BitField]::HighUInt64($size) -eq 0x00))
        {
            $none = [Localization]::LocalizedString("NONE")
            
            return [StringValue]::new($size, $none)
        }
        else
        {
            $unit = [MemorySizeUnit]::B
            
            return [StringValueMemorySize]::new($size, $unit)
        }
    }

    # Get NonVolatileSize
    hidden [StringValueMemorySize]GetNonVolatileSize()
    {
        $nonVolatileSize = $this.GetQuadWordAtOffset(0x34)
        
        return $this._GetSize($nonVolatileSize)
    }

    # Get VolatileSize
    hidden [StringValueMemorySize]GetVolatileSize()
    {
        $volatileSize = $this.GetQuadWordAtOffset(0x3C)
        
        return $this._GetSize($volatileSize) 
    }

    # Get CacheSize
    hidden [StringValueMemorySize]GetCacheSize()
    {
        $cacheSize = $this.GetQuadWordAtOffset(0x44)
        
        return $this._GetSize($cacheSize)   
    }

    # Get LogicalSize
    hidden [StringValueMemorySize]GetLogicalSize()
    {
        $logicalSize = $this.GetQuadWordAtOffset(0x4C)
        
        return $this._GetSize($logicalSize)   
    }

    hidden [UInt32]ExtendedSpeed()
    {
        return $this.GetDoubleWordAtOffset(0x54)
    }

    hidden [UInt32]ExtendedConfiguredMemorySpeed()
    {
        return $this.GetDoubleWordAtOffset(0x58)
    }
}


###################################################################################################################################
# Type 18                                                                                                                         #
###################################################################################################################################
class _32BitMemoryErrorInformation : SMBIOSStructure 
{    
    hidden static [Hashtable]$StringArrays
    hidden static [Hashtable]$StringArrayNameAlias

    static [Array]$PropertyNames

    static _32BitMemoryErrorInformation()
    {
        $stringTables = [_32BitMemoryErrorInformation]::GetStringTables("Type_18")

        [_32BitMemoryErrorInformation]::StringArrays = $stringTables.StringArrays
                                
        [_32BitMemoryErrorInformation]::StringArrayNameAlias = $stringTables.StringArrayNameAlias

        $labels = [Collections.ArrayList]::new() 
        
        if ( [SMBIOS]::Version -ge [Version]::new(2, 1) )
        {
            $labels.Add( "ErrorType"               )
            $labels.Add( "ErrorGranularity"        )
            $labels.Add( "ErrorOperation"          )
            $labels.Add( "VendorSyndrome"          )
            $labels.Add( "MemoryArrayErrorAddress" )
            $labels.Add( "DeviceErrorAddress"      )
            $labels.Add( "ErrorResolution"         )
        }

        [_32BitMemoryErrorInformation]::PropertyNames = $labels 
    }

    _32BitMemoryErrorInformation([Byte]$type, [String]$description, [String[]]$keywords, [Byte]$length, [UInt16]$handle, [Byte[]]$data, [String[]]$strings) : base($type, $description, $keywords, $length, $handle, $data, $strings)
    {     
    }

    # Get ErrorType
    hidden [StringValue]GetErrorType()
    {
        $errorType = $this.GetByteAtOffset(0x04)

        return [StringValue]::new($errorType, "ErrorType", [ref]$this) 
    }

    # Get ErrorGranularity
    hidden [StringValue]GetErrorGranularity()
    {
        $errorGranularity = $this.GetByteAtOffset(0x05)

        return [StringValue]::new($errorGranularity, "ErrorGranularity", [ref]$this)  
    }

    # Get ErrorOperation
    hidden [StringValue]GetErrorOperation()
    {
        $errorOperation = $this.GetByteAtOffset(0x06)

        return [StringValue]::new($errorOperation, "ErrorOperation", [ref]$this)
    }

    # GetVendorSyndrome
    hidden [StringValue]GetVendorSyndrome()
    {
        $vendorSyndrome = $this.GetDoubleWordAtOffset(0x07)
        
        return [StringValue]::new($vendorSyndrome, 0x00, "0x{0:X8}", "UNKNOWN")
    }

    # Get MemoryArrayErrorAddress
    hidden [StringValue]GetMemoryArrayErrorAddress()
    { 
        $memoryArrayErrorAddress = $this.GetDoubleWordAtOffset(0x0B)

        return [StringValue]::new($memoryArrayErrorAddress, 0x00, "0x{0:X8}", "UNKNOWN")
    }

    # Get DeviceErrorAddress
    hidden [StringValue]GetDeviceErrorAddress()
    {
        $deviceErrorAddress = $this.GetDoubleWordAtOffset(0x0F) 

        return [StringValue]::new($deviceErrorAddress, -0x80000000, "0x{0:X8}", "UNKNOWN")
    }

    # Get ErrorResolution
    hidden [StringValue]GetErrorResolution()
    {
        $errorResolution = $this.GetDoubleWordAtOffset(0x13)

        return [StringValue]::new($errorResolution, -0x80000000, "0x{0:X8}", "UNKNOWN")
    }
}


###################################################################################################################################
# Type 19                                                                                                                         #
###################################################################################################################################
class MemoryArrayMappedAddress : SMBIOSStructure 
{    
    hidden static [Hashtable]$StringArrays
    hidden static [Hashtable]$StringArrayNameAlias
    
    static [Array]$PropertyNames

    static MemoryArrayMappedAddress()
    {
        $labels = [Collections.ArrayList]::new() 
        
        if ( [SMBIOS]::Version -ge [Version]::new(2, 1) )
        {
            $labels.Add( "StartingAddress"   )
            $labels.Add( "EndingAddress"     )
            $labels.Add( "RangeSize"         )
            $labels.Add( "MemoryArrayHandle" )
            $labels.Add( "PartitionWidth"    )
        }

        [MemoryArrayMappedAddress]::PropertyNames = $labels 
    }

    MemoryArrayMappedAddress([Byte]$type, [String]$description, [String[]]$keywords, [Byte]$length, [UInt16]$handle, [Byte[]]$data, [String[]]$strings) : base($type, $description, $keywords, $length, $handle, $data, $strings)
    {
    }

    # Get StartingAddress
    hidden [StringValue]GetStartingAddress()
    {
        $startingAddress = $this.GetDoubleWordAtOffset(0x04)

        if ($startingAddress -eq 0xFFFFFFFF)
        {
            $extendedStartingAddress = $this.GetExtendedStartingAddress()

            return [StringValue]::new($extendedStartingAddress, "0x{0:X16}")  
        }

        return [StringValue]::new($startingAddress, "0x{0:X8}")  
    }

    # Get EndingAddress
    hidden [StringValue]GetEndingAddress()
    {
        $endingAddress = $this.GetDoubleWordAtOffset(0x08)

        if ($endingAddress -eq 0xFFFFFFFF)
        {
            $extendedEndingAddress = $this.GetExtendedEndingAddress()

            return [StringValue]::new($extendedEndingAddress, "0x{0:X16}")  
        }

        return [StringValue]::new($endingAddress, "0x{0:X8}")  
    }

    # Get RangeSize
    hidden [StringValueMemorySize]GetRangeSize()
    {
        $start = $this.GetStartingAddress()

        $end = $this.GetEndingAddress()

        $size = $end.Value - $start.Value

        $unit = [MemorySizeUnit]::B

        return [StringValueMemorySize]::new($size, $unit)
    }

    # Get MemoryArrayHandle
    hidden [UInt16]GetMemoryArrayHandle()
    {
        return $this.GetWordAtOffset(0x0C)
    }

    # Get PartitionWidth
    hidden [Byte]GetPartitionWidth()
    {
        return $this.GetByteAtOffset(0x0E)  
    }

    # Get ExtendedStartingAddress
    hidden [UInt64]GetExtendedStartingAddress()
    {
         return $this.GetQuadWordAtOffset(0x0F)  
    }

    # Get ExtendedEndingAddress
    hidden [UInt64]GetExtendedEndingAddress()
    {
        return $this.GetQuadWordAtOffset(0x17)
    }
}


###################################################################################################################################
# Type 20                                                                                                                         #
###################################################################################################################################
class MemoryDeviceMappedAddress : SMBIOSStructure 
{    
    hidden static [Hashtable]$StringArrays
    hidden static [Hashtable]$StringArrayNameAlias
    
    static [Array]$PropertyNames

    static MemoryDeviceMappedAddress()
    {        
        $labels = [Collections.ArrayList]::new() 
        
        if ( [SMBIOS]::Version -ge [Version]::new(2, 1) )
        {
            $labels.Add( "StartingAddress"                )
            $labels.Add( "EndingAddress"                  )
            $labels.Add( "RangeSize"                      )
            $labels.Add( "MemoryDeviceHandle"             )
            $labels.Add( "MemoryArrayMappedAddressHandle" )
            $labels.Add( "PartitionRowPosition"           )
            $labels.Add( "InterleavePosition"             )
            $labels.Add( "InterleavedDataDepth"           )
        }

        [MemoryDeviceMappedAddress]::PropertyNames = $labels 
    }

    MemoryDeviceMappedAddress([Byte]$type, [String]$description, [String[]]$keywords, [Byte]$length, [UInt16]$handle, [Byte[]]$data, [String[]]$strings) : base($type, $description, $keywords, $length, $handle, $data, $strings)
    {
    }

    # Get StartingAddress
    hidden [StringValue]GetStartingAddress()
    {
        $startingAddress = $this.GetDoubleWordAtOffset(0x04)

        if ($startingAddress -eq 0xFFFFFFFF)
        {
            $extendedStartingAddress = $this.GetExtendedStartingAddress()

            return [StringValue]::new($extendedStartingAddress, "0x{0:X16}")  
        }

        return [StringValue]::new($startingAddress, "0x{0:X8}")    
    }

    # Get EndingAddress
    hidden [StringValue]GetEndingAddress()
    {
        $endingAddress = $this.GetDoubleWordAtOffset(0x08)

        if ($endingAddress -eq 0xFFFFFFFF)
        {
            $extendedEndingAddress = $this.GetExtendedEndingAddress()

            return [StringValue]::new($extendedEndingAddress, "0x{0:X16}")  
        }

        return [StringValue]::new($endingAddress, "0x{0:X8}")    
    }

    # Get RangeSize
    hidden [StringValueMemorySize]GetRangeSize()
    {
        $start = $this.GetStartingAddress()

        $end = $this.GetEndingAddress()

        $size = $end.Value - $start.Value

        $unit = [MemorySizeUnit]::B

        return [StringValueMemorySize]::new($size, $unit)
    }

    # Get MemoryDeviceHandle
    hidden [UInt16]GetMemoryDeviceHandle()
    {
        return $this.GetWordAtOffset(0x0C)  
    }

    # Get MemoryArrayMappedAddressHandle
    hidden [UInt16]GetMemoryArrayMappedAddressHandle()
    {
         return $this.GetWordAtOffset(0x0E)  
    }

    # Get PartitionRowPosition
    hidden [StringValue]GetPartitionRowPosition()
    {
       $partitionRowPosition = $this.GetByteAtOffset(0x10)

       return [StringValue]::new($partitionRowPosition, 0xFF, $null, "UNKNOWN")
    }

    # Get InterleavePosition
    hidden [StringValue]GetInterleavePosition()
    {
        $interleavePosition = $this.GetByteAtOffset(0x11) 

        return [StringValue]::new($interleavePosition, 0xFF, $null, "UNKNOWN")
    }

    # Get InterleavedDataDepth
    hidden [StringValue]GetInterleavedDataDepth()
    {
        $interleavedDataDepth = $this.GetByteAtOffset(0x12)  

        return [StringValue]::new($interleavedDataDepth, 0xFF, $null, "UNKNOWN")
    }

    # Get ExtendedStartingAddress
    hidden [UInt64]GetExtendedStartingAddress()
    {
         return $this.GetQuadWordAtOffset(0x13)  
    }

    # Get ExtendedEndingAddress
    hidden [UInt64]GetExtendedEndingAddress()
    {
        return $this.GetQuadWordAtOffset(0x1B)
    }
}


###################################################################################################################################
# Type 21                                                                                                                         #
###################################################################################################################################
class BuiltInPointingDevice : SMBIOSStructure 
{    
    hidden static [Hashtable]$StringArrays
    hidden static [Hashtable]$StringArrayNameAlias
    
    static [Array]$PropertyNames

    static BuiltInPointingDevice()
    {
        $stringTables = [BuiltInPointingDevice]::GetStringTables("Type_21")

        [BuiltInPointingDevice]::StringArrays = $stringTables.StringArrays
                                
        [BuiltInPointingDevice]::StringArrayNameAlias = $stringTables.StringArrayNameAlias
    
        $labels = [Collections.ArrayList]::new() 
        
        if ( [SMBIOS]::Version -ge [Version]::new(2, 1) )
        {
            $labels.Add( "PointingDeviceType" )
            $labels.Add( "Interface"          )
            $labels.Add( "NumberOfButtons"    )
        }

        [BuiltInPointingDevice]::PropertyNames = $labels 
    }

    BuiltInPointingDevice([Byte]$type, [String]$description, [String[]]$keywords, [Byte]$length, [UInt16]$handle, [Byte[]]$data, [String[]]$strings) : base($type, $description, $keywords, $length, $handle, $data, $strings)
    {
    }

    # Get PointingDeviceType
    hidden [StringValue]GetPointingDeviceType()
    {
        $type = $this.GetByteAtOffset(0x04) 

        return [StringValue]::new($type, "Type", [ref]$this)
    }

    # Get Interface
    hidden [StringValue]GetInterface()
    {
        $interface = $this.GetByteAtOffset(0x05)

        return [StringValue]::new($interface, "Interface", [ref]$this)  
    }

    # Get NumberOfButtons
    hidden [Byte]GetNumberOfButtons()
    {
        return $this.GetByteAtOffset(0x06)
    }
}


###################################################################################################################################
# Type 22                                                                                                                         #
###################################################################################################################################
class PortableBattery : SMBIOSStructure 
{    
    hidden static [Hashtable]$StringArrays
    hidden static [Hashtable]$StringArrayNameAlias

    static [Array]$PropertyNames

    static PortableBattery()
    {
        $stringTables = [PortableBattery]::GetStringTables("Type_22")

        [PortableBattery]::StringArrays = $stringTables.StringArrays
                                
        [PortableBattery]::StringArrayNameAlias = $stringTables.StringArrayNameAlias

        $labels = [Collections.ArrayList]::new() 
        
        if ( [SMBIOS]::Version -ge [Version]::new(2, 1) )
        {
            $labels.Add( "Location"                  )
            $labels.Add( "Manufacturer"              )   
        }
        if ( ( [SMBIOS]::Version -ge [Version]::new(2, 1) ) -and ( [SMBIOS]::Version -lt [Version]::new(2, 2) ) )
        {
            $labels.Add( "ManufactureDate"           )
            $labels.Add( "SerialNumber"              )
        }
         if ( [SMBIOS]::Version -ge [Version]::new(2, 1) )
        {
            $labels.Add( "DeviceName"                )
        }
        if ( ( [SMBIOS]::Version -ge [Version]::new(2, 1) ) -and ( [SMBIOS]::Version -lt [Version]::new(2, 2) ) )
        {    
            $labels.Add( "DeviceChemistry"           )
        }
        if ( [SMBIOS]::Version -ge [Version]::new(2, 1) )
        {
            $labels.Add( "DesignCapacity"            )
            $labels.Add( "DesignVoltage"             )
            $labels.Add( "SBDSVersionNumber"         )
            $labels.Add( "MaximumErrorInBatteryData" )
        }
        if ( [SMBIOS]::Version -ge [Version]::new(2, 2) )
        {
            $labels.Add( "SBDSSerialNumber"          )
            $labels.Add( "SBDSManufactureDate"       )
            $labels.Add( "SBDSDeviceChemistry"       )
            $labels.Add( "OEMSpecificInformation"    )
        }

        [PortableBattery]::PropertyNames = $labels 
    }

    PortableBattery([Byte]$type, [String]$description, [String[]]$keywords, [Byte]$length, [UInt16]$handle, [Byte[]]$data, [String[]]$strings) : base($type, $description, $keywords, $length, $handle, $data, $strings)
    {
    }

    # Get Location
    hidden [SMBString]GetLocation()
    {
         return $this.GetStringAtOffset(0x04)   
    }

    # Get Manufacturer
    hidden [SMBString]GetManufacturer()
    {
         return $this.GetStringAtOffset(0x05)   
    }

    # Get ManufactureDate
    hidden [SMBString]GetManufactureDate()
    {
         return $this.GetStringAtOffset(0x06)   
    }

    # Get SerialNumber
    hidden [SMBString]GetSerialNumber()
    {
         return $this.GetStringAtOffset(0x07)   
    }

    # Get DeviceName
    hidden [SMBString]GetDeviceName()
    {
         return $this.GetStringAtOffset(0x08)   
    }

    # Get DeviceChemistry
    hidden [StringValue]GetDeviceChemistry()
    {
        $chemistry = $this.GetByteAtOffset(0x09) 

        return [StringValue]::new($chemistry, "DeviceChemistry", [ref]$this)    
    }

    # Get DesignCapacity
    hidden [StringValue]GetDesignCapacity()
    {
        $designCapacity = $this.GetWordAtOffset(0x0A) 

        $capacity = $designCapacity

        if ( [SMBIOS]::Version -ge [Version]::new(2, 2) )
        {
            $multiplier = $this.GetDesignCapacityMultiplier()

            $capacity = $designCapacity * $multiplier
        }

        return [StringValue]::new($capacity, 0x00, "{0} mWh", "UNKNOWN")
    }

    # Get DesignVoltage
    hidden [StringValue]GetDesignVoltage()
    {
        $designVoltage = $this.GetWordAtOffset(0x0C)  

        return [StringValue]::new($designVoltage, 0x00, "{0} mV", "UNKNOWN")
    }

    # Get SBDSVersionNumber
    hidden [SMBString]GetSBDSVersionNumber()
    {
        return $this.GetStringAtOffset(0x0E)    
    }

    # Get MaximumErrorInBatteryData
    hidden [StringValue]GetMaximumErrorInBatteryData()
    {
        $maximumErrorInBatteryData = $this.GetByteAtOffset(0x0F)
        
        return [StringValue]::new($maximumErrorInBatteryData, 0xFF, "{0:P}", $maximumErrorInBatteryData / 100, "UNKNOWN")
    }
    
    # Get SBDSSerialNumber
    hidden [StringValue]GetSBDSSerialNumber()
    {
        $SBDSSerialNumber = $this.GetWordAtOffset(0x10)

        return [StringValue]::new($SBDSSerialNumber, 0x00, "{0}", "UNKNOWN")
    }

    # Get SBDSManufactureDate
    hidden [StringValueDateTime]GetSBDSManufactureDate()
    {
        $BDSManufactureDate = $this.GetWordAtOffset(0x12)

        if ($BDSManufactureDate -eq 0x00)
        {
            $unknown = [Localization]::LocalizedString("UNKNOWN")
            
            return [StringValueDateTime]::new([DateTime]::new(1), "$unknown")
        }
        
        $year = 1980 + [BitField]::Extract($BDSManufactureDate, 9, 7)

        $month = [BitField]::Extract($BDSManufactureDate, 5, 4)

        $day = [BitField]::Extract($BDSManufactureDate, 0, 5) 

        $date = [DateTime]::new($year, $month, $day)

        return [StringValueDateTime]::new($date)   
    }

    # Get SBDSDeviceChemistry
    hidden [SMBString]GetSBDSDeviceChemistry()
    {
        return $this.GetStringAtOffset(0x14)   
    }

    # Get DesignCapacityMultiplier
    hidden [Byte]GetDesignCapacityMultiplier()
    {
        return $this.GetByteAtOffset(0x15) 
    }

    # Get OEMSpecificInformation
    hidden [UInt32]GetOEMSpecificInformation()
    {
        return $this.GetDoubleWordAtOffset(0x16)  
    }
}


###################################################################################################################################
# Type 23                                                                                                                         #
###################################################################################################################################
class SystemReset : SMBIOSStructure 
{    
    hidden static [Hashtable]$StringArrays
    hidden static [Hashtable]$StringArrayNameAlias

    static [Array]$PropertyNames

    static SystemReset()
    {
        $stringTables = [SystemReset]::GetStringTables("Type_23")

        [SystemReset]::StringArrays = $stringTables.StringArrays
                                
        [SystemReset]::StringArrayNameAlias = $stringTables.StringArrayNameAlias

        $labels = [Collections.ArrayList]::new() 

        if ( [SMBIOS]::Version -ge [Version]::new(2, 1) )
        {
            $labels.Add( "Status"            )
            $labels.Add( "WatchdogTimer"     )
            $labels.Add( "BootOption"        )
            $labels.Add( "BootOptionOnLimit" )
            $labels.Add( "ResetCount"        ) 
            $labels.Add( "ResetLimit"        )
            $labels.Add( "TimerInterval"     )
            $labels.Add( "Timeout"           )
        }

        [SystemReset]::PropertyNames = $labels 
    }

    SystemReset([Byte]$type, [String]$description, [String[]]$keywords, [Byte]$length, [UInt16]$handle, [Byte[]]$data, [String[]]$strings) : base($type, $description, $keywords, $length, $handle, $data, $strings)
    {
    }

    # Get Status
    hidden [StringValue]GetStatus()
    {
        $capabilities = $this.GetByteAtOffset(0x04)

        $status = [BitField]::Get($capabilities, 0)

        return [StringValue]::new($status, "Status", [ref]$this)  
    }

    # Get WatchdogTimer
    hidden [StringValue]GetWatchdogTimer()
    {
        $capabilities = $this.GetByteAtOffset(0x04)

        $watchdogTimer = [BitField]::Get($capabilities, 5)

        return [StringValue]::new($watchdogTimer, "WatchdogTimer", [ref]$this)  
    }

    # Get BootOption
    hidden [StringValue]GetBootOption()
    {
        $capabilities = $this.GetByteAtOffset(0x04)

        $bootOption = [BitField]::Extract($capabilities, 1, 2)

        return [StringValue]::new($bootOption, "BootOption", [ref]$this)  
    }

    # Get BootOptionOnLimit
    hidden [StringValue]GetBootOptionOnLimit()
    {
        $capabilities = $this.GetByteAtOffset(0x04)

        $bootOptionOnLimit = [BitField]::Extract($capabilities, 3, 2)

        return [StringValue]::new($bootOptionOnLimit, "BootOption", [ref]$this)    
    }

    # Get ResetCount
    hidden [StringValue]GetResetCount()
    {
        $resetCount = $this.GetWordAtOffset(0x05)

        return [StringValue]::new($resetCount, 0xFFFF, $null, "UNKNOWN")
    }

    # Get ResetLimit
    hidden [StringValue]GetResetLimit()
    {
        $resetLimit = $this.GetWordAtOffset(0x07)

        return [StringValue]::new($resetLimit, 0xFFFF, $null, "UNKNOWN")
    }

    # Get TimerInterval
    hidden [StringValue]GetTimerInterval()
    {
        $timerInterval = $this.GetWordAtOffset(0x09)

        return [StringValue]::new($timerInterval, 0xFFFF, "{0} minutes", "UNKNOWN")
    }

    # Get Timeout
    hidden [StringValue]GetTimeout()
    {
        $timeout = $this.GetWordAtOffset(0x09)

        return [StringValue]::new($timeout, 0xFFFF, "{0} minutes", "UNKNOWN")
    }
}


###################################################################################################################################
# Type 24                                                                                                                         #
###################################################################################################################################
class HardwareSecurity : SMBIOSStructure 
{    
    hidden static [Hashtable]$StringArrays
    hidden static [Hashtable]$StringArrayNameAlias

    static [Array]$PropertyNames

    static HardwareSecurity()
    {
        $stringTables = [HardwareSecurity]::GetStringTables("Type_24")

        [HardwareSecurity]::StringArrays = $stringTables.StringArrays
                                
        [HardwareSecurity]::StringArrayNameAlias = $stringTables.StringArrayNameAlias

        $labels = [Collections.ArrayList]::new() 
        
        if ( [SMBIOS]::Version -ge [Version]::new(2, 2) )
        {
            $labels.Add( "PowerOnPasswordStatus"       )
            $labels.Add( "KeyboardPasswordStatus"      )
            $labels.Add( "AdministratorPasswordStatus" )
            $labels.Add( "FrontPanelResetStatus"       )
        }

        [HardwareSecurity]::PropertyNames = $labels 
    }

    HardwareSecurity([Byte]$type, [String]$description, [String[]]$keywords, [Byte]$length, [UInt16]$handle, [Byte[]]$data, [String[]]$strings) : base($type, $description, $keywords, $length, $handle, $data, $strings)
    { 
    }

    # Utility method for PowerOnPasswordStatus, KeyboardPasswordStatus, AdministratorPasswordStatus, FrontPanelResetStatus
    hidden [StringValue]_GetStatus([int]$offset, [int]$length)
    {
        $settings = $this.GetByteAtOffset(0x04)
  
        $status = [BitField]::Extract($settings, $offset, $length)
        
        return [StringValue]::new($status, "Status", [ref]$this) 
    }
    
    # Get PowerOnPasswordStatus
    hidden [StringValue]GetPowerOnPasswordStatus()
    {
        return $this._GetStatus(0, 2)
    }

    # Get KeyboardPasswordStatus
    hidden [StringValue]GetKeyboardPasswordStatus()
    {
        return $this._GetStatus(2, 2) 
    }

    # Get AdministratorPasswordStatus
    hidden [StringValue]GetAdministratorPasswordStatus()
    {
        return $this._GetStatus(4, 2)
    }

    # Get FrontPanelResetStatus
    hidden [StringValue]GetFrontPanelResetStatus()
    {
        return $this._GetStatus(6, 2)  
    }
}


###################################################################################################################################
# Type 25                                                                                                                         #
###################################################################################################################################
class SystemPowerControls : SMBIOSStructure 
{    
    hidden static [Hashtable]$StringArrays
    hidden static [Hashtable]$StringArrayNameAlias

    static [Array]$PropertyNames

    static SystemPowerControls()
    {
        $labels = [Collections.ArrayList]::new() 
        
        if ( [SMBIOS]::Version -ge [Version]::new(2, 2) )
        {
            $labels.Add( "Data"    )
            $labels.Add( "Strings" )
        }

        [SystemPowerControls]::PropertyNames = $labels 
    }

    SystemPowerControls([Byte]$type, [String]$description, [String[]]$keywords, [Byte]$length, [UInt16]$handle, [Byte[]]$data, [String[]]$strings) : base($type, $description, $keywords, $length, $handle, $data, $strings)
    {
    }

    hidden [Byte[]]GetData()
    {
        return $this.Data
    }

    hidden [String[]]GetStrings()
    {
        return $this.Strings
    }
}


###################################################################################################################################
# Type 26                                                                                                                         #
###################################################################################################################################
class VoltageProbe : SMBIOSStructure 
{    
    hidden static [Hashtable]$StringArrays
    hidden static [Hashtable]$StringArrayNameAlias
    
    static [Array]$PropertyNames

    static VoltageProbe()
    {
        $stringTables = [VoltageProbe]::GetStringTables("Type_26")

        [VoltageProbe]::StringArrays = $stringTables.StringArrays
                                
        [VoltageProbe]::StringArrayNameAlias = $stringTables.StringArrayNameAlias
        
        $labels = [Collections.ArrayList]::new() 
        
        if ( [SMBIOS]::Version -ge [Version]::new(2, 2) )
        {
            $labels.Add( "Description"           )
            $labels.Add( "Location"              )
            $labels.Add( "Status"                )
            $labels.Add( "MaximumValue"          )
            $labels.Add( "MinimumValue"          )
            $labels.Add( "Resolution"            )
            $labels.Add( "Tolerance"             )
            $labels.Add( "Accuracy"              )
            $labels.Add( "OEMDefinedInformation" )
            $labels.Add( "NominalValue"          )
        }

        [VoltageProbe]::PropertyNames = $labels 
    }

    VoltageProbe([Byte]$type, [String]$description, [String[]]$keywords, [Byte]$length, [UInt16]$handle, [Byte[]]$data, [String[]]$strings) : base($type, $description, $keywords, $length, $handle, $data, $strings)
    {
    }

    # Get Description
    hidden [SMBString]GetDescription()
    {
        return $this.GetStringAtOffset(0x04) 
    }

    # Get Location
    hidden [StringValue]GetLocation()
    {
        $locationAndStatus = $this.GetByteAtOffset(0x05)  

        $location = [BitField]::Extract($locationAndStatus, 0, 5)

        return [StringValue]::new($location, "Location", [ref]$this)
    }

    # Get Status
    hidden [StringValue]GetStatus()
    {
        $locationAndStatus = $this.GetByteAtOffset(0x05)  

        $status = [BitField]::Extract($locationAndStatus, 5, 3)

        return [StringValue]::new($status, "Status", [ref]$this)
    }

    # Get VoltageValue
     hidden [StringValue]GetVoltageValue($voltage)
    {
        return [StringValue]::new($voltage, 0x8000, "{0:F03} V", $voltage / 1000, "UNKNOWN")
    }
    
    # Get MaximumValue
    hidden [StringValue]GetMaximumValue()
    {
        $maximumValue = $this.GetWordAtOffset(0x06)
        
        return $this.GetVoltageValue($maximumValue) 
    }

    # Get MinimumValue
    hidden [StringValue]GetMinimumValue()
    {
        $minimumValue = $this.GetWordAtOffset(0x08)
        
        return $this.GetVoltageValue($minimumValue)   
    }

    # Get Resolution
    hidden [StringValue]GetResolution()
    {
        $resolution = $this.GetWordAtOffset(0x0A)

        return [StringValue]::new($resolution, 0x8000, "{0:F01} mV", $resolution / 10, "UNKNOWN")
    }

    # Get Tolerance
    hidden [StringValue]GetTolerance()
    {
        $tolerance = $this.GetWordAtOffset(0x0C)
        
        return $this.GetVoltageValue($tolerance)     
    }

    # Get Accuracy
    hidden [StringValue]GetAccuracy()
    {
        $accuracy = $this.GetWordAtOffset(0x0E)

        return [StringValue]::new($accuracy, 0x8000, "{0:F02}", $accuracy / 100, "UNKNOWN")
    }

    # Get OEMDefinedInformation
    hidden [UInt32]GetOEMDefinedInformation()
    {
        return $this.GetDoubleWordAtOffset(0x10)  
    }

    # Get NominalValue
    hidden [StringValue]GetNominalValue()
    {
        $nominalValue = $this.GetWordAtOffset(0x14)

        return $this.GetVoltageValue($nominalValue)    
    }
}


###################################################################################################################################
# Type 27                                                                                                                         #
###################################################################################################################################
class CoolingDevice : SMBIOSStructure 
{    
    hidden static [Hashtable]$StringArrays
    hidden static [Hashtable]$StringArrayNameAlias

    static [Array]$PropertyNames

    static CoolingDevice()
    {
        $stringTables = [CoolingDevice]::GetStringTables("Type_27")

        [CoolingDevice]::StringArrays = $stringTables.StringArrays
                                
        [CoolingDevice]::StringArrayNameAlias = $stringTables.StringArrayNameAlias
        
        $labels = [Collections.ArrayList]::new() 
        
        if ( [SMBIOS]::Version -ge [Version]::new(2, 2) )
        {
            $labels.Add( "TemperatureProbeHandle" )
            $labels.Add( "DeviceType"             )
            $labels.Add( "Status"                 )
            $labels.Add( "CoolingUnitGroup"       )
            $labels.Add( "OEMDefinedInformation"  )
            $labels.Add( "NominalSpeed"           )
        }
        
        if ( [SMBIOS]::Version -ge [Version]::new(2, 7) )
        {
            $labels.Add( "Description"            )
        }

        [CoolingDevice]::PropertyNames = $labels 
    }

    CoolingDevice([Byte]$type, [String]$description, [String[]]$keywords, [Byte]$length, [UInt16]$handle, [Byte[]]$data, [String[]]$strings) : base($type, $description, $keywords, $length, $handle, $data, $strings)
    {
    }

    # Get TemperatureProbeHandle
    hidden [UInt16]GetTemperatureProbeHandle()
    {
        return $this.GetWordAtOffset(0x04)  
    }

    # Get DeviceType
    hidden [StringValue]GetDeviceType()
    {
        $deviceTypeAndStatus = $this.GetByteAtOffset(0x06)
        
        $deviceType = [BitField]::Extract($deviceTypeAndStatus, 0, 5)

        return [StringValue]::new($deviceType, "DeviceType", [ref]$this)     
    }

    # Get Status
    hidden [StringValue]GetStatus()
    {
        $deviceTypeAndStatus = $this.GetByteAtOffset(0x06)
        
        $status = [BitField]::Extract($deviceTypeAndStatus, 5, 3)

        return [StringValue]::new($status, "Status", [ref]$this)      
    }

    # Get CoolingUnitGroup
    hidden [Byte]GetCoolingUnitGroup()
    {
        return $this.GetByteAtOffset(0x07)
    }

    # Get OEMDefinedInformation
    hidden [UInt32]GetOEMDefinedInformation()
    {
        return $this.GetDoubleWordAtOffset(0x08)    
    }

    # Get NominalSpeed
    hidden [StringValue]GetNominalSpeed()
    {
        $nominalSpeed = $this.GetWordAtOffset(0x0C)
        
        return [StringValue]::new($nominalSpeed, 0x8000, "{0} rpm", "UNKNOWN")
    }

    # Get Description
    hidden [SMBString]GetDescription()
    {
        return $this.GetStringAtOffset(0x0E)  
    }
}


###################################################################################################################################
# Type 28                                                                                                                         #
###################################################################################################################################
class TemperatureProbe : SMBIOSStructure 
{    
    hidden static [Hashtable]$StringArrays
    hidden static [Hashtable]$StringArrayNameAlias

    static [Array]$PropertyNames

    static TemperatureProbe()
    {
        $stringTables = [TemperatureProbe]::GetStringTables("Type_28")

        [TemperatureProbe]::StringArrays = $stringTables.StringArrays
                                
        [TemperatureProbe]::StringArrayNameAlias = $stringTables.StringArrayNameAlias

        $labels = [Collections.ArrayList]::new() 
        
        if ( [SMBIOS]::Version -ge [Version]::new(2, 2) )
        {
            $labels.Add( "Description"           )
            $labels.Add( "Location"              )
            $labels.Add( "Status"                )
            $labels.Add( "MaximumValue"          )
            $labels.Add( "MinimumValue"          )
            $labels.Add( "Resolution"            )
            $labels.Add( "Tolerance"             )
            $labels.Add( "Accuracy"              )
            $labels.Add( "OEMDefinedInformation" )
            $labels.Add( "NominalValue"          )
        }

        [TemperatureProbe]::PropertyNames = $labels 
    }

    TemperatureProbe([Byte]$type, [String]$description, [String[]]$keywords, [Byte]$length, [UInt16]$handle, [Byte[]]$data, [String[]]$strings) : base($type, $description, $keywords, $length, $handle, $data, $strings)
    {
    }

    # Get Description
    hidden [SMBString]GetDescription()
    {
        return $this.GetStringAtOffset(0x04)  
    }

    # Get Location
    hidden [StringValue]GetLocation()
    {
        $locationAndStatus = $this.GetByteAtOffset(0x05)  

        $location = [BitField]::Extract($locationAndStatus, 0, 5)

        return [StringValue]::new($location, "Location", [ref]$this)  
    }

     # Get Status
    hidden [StringValue]GetStatus()
    {
        $locationAndStatus = $this.GetByteAtOffset(0x05)  

        $status = [BitField]::Extract($locationAndStatus, 5, 3)

        return [StringValue]::new($status, "Status", [ref]$this)  
    }

    # Get TemperatureValue
    hidden [StringValueTemperature]GetTemperatureValue($temperature)
    {
        if ($temperature -eq 0x8000)
        {
            $unknown = [Localization]::LocalizedString("UNKNOWN")
            
            return [StringValue]::new($temperature, $unknown) 
        }
        else
        {
            return  [StringValueTemperature]::new($temperature / 10, [TemperatureUnit]::Celsius, 1)
        }  
    }

    # Get MaximumValue
    hidden [StringValueTemperature]GetMaximumValue()
    {
        $maximumValue = $this.GetWordAtOffset(0x06)
        
        return $this.GetTemperatureValue($maximumValue)   
    }

    # Get MinimumValue
    hidden [StringValueTemperature]GetMinimumValue()
    {
        $minimumValue = $this.GetWordAtOffset(0x08)
        
        return $this.GetTemperatureValue($minimumValue)   
    }

    # Get Resolution
    hidden [StringValueTemperature]GetResolution()
    {
        $resolution = $this.GetWordAtOffset(0x0A)

        if ($resolution -eq 0x8000)
        {
            $unknown = [Localization]::LocalizedString("UNKNOWN")
            
            return [StringValue]::new($resolution, $unknown) 
        }
        else
        {
            return [StringValueTemperature]::new($resolution / 1000, [TemperatureUnit]::Celsius, 3)
        } 
    }

    # Get Tolerance
    hidden [StringValueTemperature]GetTolerance()
    {
        $tolerance = $this.GetWordAtOffset(0x0C)
        
        return $this.GetTemperatureValue($tolerance) 
    }

    # Get Accuracy
    hidden [StringValue]GetAccuracy()
    {
        $accuracy = $this.GetWordAtOffset(0x0E)
        
        return [StringValue]::new($accuracy, 0x8000, "{0:F02}", $accuracy / 100, "UNKNOWN")
    }

    # Get OEMDefinedInformation
    hidden [UInt32]GetOEMDefinedInformation()
    {
        return $this.GetDoubleWordAtOffset(0x10)
    }

    # Get NominalValue
    hidden [StringValueTemperature]GetNominalValue()
    {
        $nominalValue = $this.GetWordAtOffset(0x14)
        
        return $this.GetTemperatureValue($nominalValue)
    }
}


###################################################################################################################################
# Type 29                                                                                                                         #
###################################################################################################################################
class ElectricalCurrentProbe : SMBIOSStructure 
{    
    hidden static [Hashtable]$StringArrays
    hidden static [Hashtable]$StringArrayNameAlias

    static [Array]$PropertyNames

    static ElectricalCurrentProbe()
    {
        $stringTables = [ElectricalCurrentProbe]::GetStringTables("Type_29")

        [ElectricalCurrentProbe]::StringArrays = $stringTables.StringArrays
                                
        [ElectricalCurrentProbe]::StringArrayNameAlias = $stringTables.StringArrayNameAlias
        
        $labels = [Collections.ArrayList]::new() 
        
        if ( [SMBIOS]::Version -ge [Version]::new(2, 1) )
        {
            $labels.Add( "Description"           )
            $labels.Add( "Location"              )
            $labels.Add( "Status"                )
            $labels.Add( "MaximumValue"          )
            $labels.Add( "MinimumValue"          )
            $labels.Add( "Resolution"            )
            $labels.Add( "Tolerance"             )
            $labels.Add( "Accuracy"              )
            $labels.Add( "OEMDefinedInformation" )
            $labels.Add( "NominalValue"          )
        }

        [ElectricalCurrentProbe]::PropertyNames = $labels 
    }

    ElectricalCurrentProbe([Byte]$type, [String]$description, [String[]]$keywords, [Byte]$length, [UInt16]$handle, [Byte[]]$data, [String[]]$strings) : base($type, $description, $keywords, $length, $handle, $data, $strings)
    {
    }

    # Get Description
    hidden [SMBString]GetDescription()
    {
        return $this.GetStringAtOffset(0x04)    
    }

    # Get Location
    hidden [StringValue]GetLocation()
    {
        $locationAndStatus = $this.GetByteAtOffset(0x05)  

        $location = [BitField]::Extract($locationAndStatus, 0, 5)

        return [StringValue]::new($location, "Location", [ref]$this)    
    }

    # Get Status
    hidden [StringValue]GetStatus()
    {
        $locationAndStatus = $this.GetByteAtOffset(0x05)  

        $status = [BitField]::Extract($locationAndStatus, 5, 3)

        return [StringValue]::new($status, "Status", [ref]$this)    
    }

    # Get ElectricalCurrentValue
    hidden [StringValue]GetElectricalCurrentValue($electricalValue)
    {
        return [StringValue]::new($electricalValue, 0x8000, "{0:F03} A", $electricalValue / 1000, "UNKNOWN")
    }

    # Get MaximumValue
    hidden [StringValue]GetMaximumValue()
    {
        $maximumValue = $this.GetWordAtOffset(0x06)
        
        return $this.GetElectricalCurrentValue($maximumValue)    
    }

    # Get MinimumValue
    hidden [StringValue]GetMinimumValue()
    {
        $minimumValue = $this.GetWordAtOffset(0x08)
        
        return $this.GetElectricalCurrentValue($minimumValue)     
    }

    # Get Resolution
    hidden [StringValue]GetResolution()
    {
        $resolution = $this.GetWordAtOffset(0x0A)

        return [StringValue]::new($resolution, 0x8000, "{0:F01} mA", $resolution / 10, "UNKNOWN")
    }

    # Get Tolerance
    hidden [StringValue]GetTolerance()
    {
        $tolerance = $this.GetWordAtOffset(0x0C)
        
        return $this.GetElectricalCurrentValue($tolerance)  
    }

    # Get Accuracy
    hidden [StringValue]GetAccuracy()
    {
        $accuracy = $this.GetWordAtOffset(0x0E)

        return [StringValue]::new($accuracy, 0x8000, "{0:F02}", $accuracy / 100, "UNKNOWN")
    }

    # Get OEMDefinedInformation
    hidden [UInt32]GetOEMDefinedInformation()
    {
        return $this.GetDoubleWordAtOffset(0x10)  
    }

    # Get NominalValue
    hidden [StringValue]GetNominalValue()
    {
        $nominalValue = $this.GetWordAtOffset(0x14)
        
        return $this.GetElectricalCurrentValue($nominalValue)    
    }
}


###################################################################################################################################
# Type 30                                                                                                                         #
###################################################################################################################################
class OutOfBandRemoteAccess : SMBIOSStructure 
{    
    hidden static [Hashtable]$StringArrays
    hidden static [Hashtable]$StringArrayNameAlias

    static [Array]$PropertyNames

    static OutOfBandRemoteAccess()
    {
        $stringTables = [OutOfBandRemoteAccess]::GetStringTables("Type_30")

        [OutOfBandRemoteAccess]::StringArrays = $stringTables.StringArrays
                                
        [OutOfBandRemoteAccess]::StringArrayNameAlias = $stringTables.StringArrayNameAlias
        
        $labels = [Collections.ArrayList]::new() 
        
        if ( [SMBIOS]::Version -ge [Version]::new(2, 1) )
        {
            $labels.Add( "ManufacturerName"          )
            $labels.Add( "InboundConnectionEnabled"  )
            $labels.Add( "OutboundConnectionEnabled" )
        }

        [OutOfBandRemoteAccess]::PropertyNames = $labels 
    }

    OutOfBandRemoteAccess([Byte]$type, [String]$description, [String[]]$keywords, [Byte]$length, [UInt16]$handle, [Byte[]]$data, [String[]]$strings) : base($type, $description, $keywords, $length, $handle, $data, $strings)
    {   
    }

    # Get ManufacturerName
    hidden [SMBString]GetManufacturerName()
    {
        return $this.GetStringAtOffset(0x04)  
    }

    # Get InboundConnectionEnabled
    hidden [Boolean]GetInboundConnectionEnabled()
    {
        $connections = $this.GetByteAtOffset(0x05)

        return [BitField]::Get($connections, 0)
    }

    # Get OutboundConnectionEnabled
    hidden [Boolean]GetOutboundConnectionEnabled()
    {
        $connections = $this.GetByteAtOffset(0x05)

        return [BitField]::Get($connections, 1)
    }
}


###################################################################################################################################
# Type 31                                                                                                                         #
###################################################################################################################################
class BootIntegrityServicesEntryPoint : SMBIOSStructure 
{    
    hidden static [Hashtable]$StringArrays
    hidden static [Hashtable]$StringArrayNameAlias

    static [Array]$PropertyNames

    static BootIntegrityServicesEntryPoint()
    {
        $labels = [Collections.ArrayList]::new() 
        
        if ( [SMBIOS]::Version -ge [Version]::new(2, 3) )
        {
            $labels.Add( "Data"    )
            $labels.Add( "Strings" )
        }

        [BootIntegrityServicesEntryPoint]::PropertyNames = $labels 
    }

    BootIntegrityServicesEntryPoint([Byte]$type, [String]$description, [String[]]$keywords, [Byte]$length, [UInt16]$handle, [Byte[]]$data, [String[]]$strings) : base($type, $description, $keywords, $length, $handle, $data, $strings)
    {
    }

    hidden [Byte[]]GetData()
    {
        return $this.Data
    }

    hidden [String[]]GetStrings()
    {
        return $this.Strings
    }
}


###################################################################################################################################
# Type 32                                                                                                                         #
###################################################################################################################################
class SystemBootInformation : SMBIOSStructure 
{   
    static [Array]$PropertyNames 
    
    static SystemBootInformation()
    {
        $stringTables = [SystemBootInformation]::GetStringTables("Type_32")

        [SystemBootInformation]::StringArrays = $stringTables.StringArrays
                                
        [SystemBootInformation]::StringArrayNameAlias = $stringTables.StringArrayNameAlias

        $labels = [Collections.ArrayList]::new() 
        
        if ( [SMBIOS]::Version -ge [Version]::new(2, 3) )
        {
            $labels.Add( "BootStatus" )
        }

        [SystemBootInformation]::PropertyNames = $labels 
    }

    SystemBootInformation([Byte]$type, [String]$description, [String[]]$keywords, [Byte]$length, [UInt16]$handle, [Byte[]]$data, [String[]]$strings) : base($type, $description, $keywords, $length, $handle, $data, $strings)
    {
    }

    # Get BootStatus
    hidden [StringValue]GetBootStatus()
    {
        $bootStatus = $this.GetByteAtOffset(0x0A)

        $status = [SystemBootInformation]::StringArrays["Status"]

        if ($bootStatus -lt 0x08)
        {
            return [StringValue]::new($bootStatus, $status)
        }
        elseif ($bootStatus -ge 0x80 -and $bootStatus -lt 0xC0)
        {
            return [StringValue]::new($bootStatus, $status.0x80)
        }
        else
        {
            return [StringValue]::new($bootStatus, $status.0xC0)
        }
    }
}


###################################################################################################################################
# Type 33                                                                                                                         #
###################################################################################################################################
class _64BitMemoryErrorInformation : SMBIOSStructure 
{    
    hidden static [Hashtable]$StringArrays
    hidden static [Hashtable]$StringArrayNameAlias

    static [Array]$PropertyNames

    static _64BitMemoryErrorInformation()
    {
        # _32BitMemoryErrorInformation and _64BitMemoryErrorInformation strings are the same.
        $stringTables = [_64BitMemoryErrorInformation]::GetStringTables("Type_18")

        [_64BitMemoryErrorInformation]::StringArrays = $stringTables.StringArrays
                                
        [_64BitMemoryErrorInformation]::StringArrayNameAlias = $stringTables.StringArrayNameAlias

        $labels = [Collections.ArrayList]::new() 
        
        if ( [SMBIOS]::Version -ge [Version]::new(2, 3) )
        {
            $labels.Add( "ErrorType"               )
            $labels.Add( "ErrorGranularity"        )
            $labels.Add( "ErrorOperation"          )
            $labels.Add( "VendorSyndrome"          )
            $labels.Add( "MemoryArrayErrorAddress" )
            $labels.Add( "DeviceErrorAddress"      )
            $labels.Add( "ErrorResolution"         )
        }

        [_64BitMemoryErrorInformation]::PropertyNames = $labels 
    }

    _64BitMemoryErrorInformation([Byte]$type, [String]$description, [String[]]$keywords, [Byte]$length, [UInt16]$handle, [Byte[]]$data, [String[]]$strings) : base($type, $description, $keywords, $length, $handle, $data, $strings)
    {   
    }

    # Get ErrorType
    hidden [StringValue]GetErrorType()
    {
        $errorType = $this.GetByteAtOffset(0x04)

        return [StringValue]::new($errorType, "ErrorType", [ref]$this) 
    }

    # Get ErrorGranularity
    hidden [StringValue]GetErrorGranularity()
    {
        $errorGranularity = $this.GetByteAtOffset(0x05)

        return [StringValue]::new($errorGranularity, "ErrorGranularity", [ref]$this)  
    }

    # Get ErrorOperation
    hidden [StringValue]GetErrorOperation()
    {
        $errorOperation = $this.GetByteAtOffset(0x06)

        return [StringValue]::new($errorOperation, "ErrorOperation", [ref]$this)
    }

    # GetVendorSyndrome
    hidden [StringValue]GetVendorSyndrome()
    {
        $vendorSyndrome = $this.GetDoubleWordAtOffset(0x07)

        return [StringValue]::new($vendorSyndrome, 0x00000000, "0x{0:X8}", "UNKNOWN")
    }

    # Get MemoryArrayErrorAddress
    hidden [StringValue]GetMemoryArrayErrorAddress()
    {
        $memoryArrayErrorAddress = $this.GetQuadWordAtOffset(0x0B)
        
        if (([BitField]::HighUInt64($memoryArrayErrorAddress) -eq -0x80000000) -and ([BitField]::LowUInt64($memoryArrayErrorAddress) -eq 0x00))
        {
            $unknown = [Localization]::LocalizedString("UNKNOWN")
            
            return [StringValue]::new($memoryArrayErrorAddress, $unknown) 
        }

        return [StringValue]::new($memoryArrayErrorAddress, "0x{0:X16}")
    }

    # Get DeviceErrorAddress
    hidden [StringValue]GetDeviceErrorAddress()
    {
        $deviceErrorAddress = $this.GetQuadWordAtOffset(0x13)

        if (([BitField]::HighUInt64($deviceErrorAddress) -eq -0x80000000) -and ([BitField]::LowUInt64($deviceErrorAddress) -eq 0x00))
        {
            $unknown = [Localization]::LocalizedString("UNKNOWN")
            
            return [StringValue]::new($deviceErrorAddress, $unknown) 
        }

        return [StringValue]::new($deviceErrorAddress, "0x{0:X16}")  
    }

    # Get ErrorResolution
    hidden [StringValue]GetErrorResolution()
    {
        $errorResolution = $this.GetDoubleWordAtOffset(0x1B)

        return [StringValue]::new($errorResolution, -0x80000000, "0x{0:X16}", "UNKNOWN")
    }
}


###################################################################################################################################
# Type 34                                                                                                                         #
###################################################################################################################################
class ManagementDevice : SMBIOSStructure 
{    
    hidden static [Hashtable]$StringArrays
    hidden static [Hashtable]$StringArrayNameAlias

    static [Array]$PropertyNames

    static ManagementDevice()
    {
         $stringTables = [ManagementDevice]::GetStringTables("Type_34")

        [ManagementDevice]::StringArrays = $stringTables.StringArrays
                                
        [ManagementDevice]::StringArrayNameAlias = $stringTables.StringArrayNameAlias
        
        $labels = [Collections.ArrayList]::new() 
        
        if ( [SMBIOS]::Version -ge [Version]::new(2, 3) )
        {
            $labels.Add( "Description" )
            $labels.Add( "DeviceType"  )
            $labels.Add( "Address"     )
            $labels.Add( "AddressType" )
        }

        [ManagementDevice]::PropertyNames = $labels 
    }

    ManagementDevice([Byte]$type, [String]$description, [String[]]$keywords, [Byte]$length, [UInt16]$handle, [Byte[]]$data, [String[]]$strings) : base($type, $description, $keywords, $length, $handle, $data, $strings)
    {
    }

    # Get Description
    hidden [SMBString]GetDescription()
    {
        return $this.GetStringAtOffset(0x04)
    }

    # Get DeviceType
    hidden [StringValue]GetDeviceType()
    {
        $deviceType = $this.GetByteAtOffset(0x05)

        return [StringValue]::new($deviceType, "DeviceType", [ref]$this)
    }

    # Get Address
    hidden [StringValue]GetAddress()
    {
        $address = $this.GetDoubleWordAtOffset(0x06)

        return [StringValue]::new($address, "0x{0:X8}")
    }

    # Get AddressType
    hidden [StringValue]GetAddressType()
    {
        $addressType = $this.GetByteAtOffset(0x0A)

        return [StringValue]::new($addressType, "AddressType", [ref]$this)
    }
}


###################################################################################################################################
# Type 35                                                                                                                         #
###################################################################################################################################
class ManagementDeviceComponent : SMBIOSStructure 
{    
    hidden static [Hashtable]$StringArrays
    hidden static [Hashtable]$StringArrayNameAlias

    static [Array]$PropertyNames

    static ManagementDeviceComponent()
    {
        $labels = [Collections.ArrayList]::new() 
        
        if ( [SMBIOS]::Version -ge [Version]::new(2, 3) )
        {
            $labels.Add( "Description"            )
            $labels.Add( "ManagementDeviceHandle" )
            $labels.Add( "ComponentHandle"        )
            $labels.Add( "ThresholdHandle"        )
        }

        [ManagementDeviceComponent]::PropertyNames = $labels 
    }

    ManagementDeviceComponent([Byte]$type, [String]$description, [String[]]$keywords, [Byte]$length, [UInt16]$handle, [Byte[]]$data, [String[]]$strings) : base($type, $description, $keywords, $length, $handle, $data, $strings)
    {
    }

    # Get Description
    hidden [SMBString]GetDescription()
    {
        return $this.GetStringAtOffset(0x04)  
    }

    # Get ManagementDeviceHandle
    hidden [UInt16]GetManagementDeviceHandle()
    {
        return $this.GetWordAtOffset(0x05)  
    }

    # Get ComponentHandle
    hidden [UInt16]GetComponentHandle()
    {
         return $this.GetWordAtOffset(0x07)  
    }

    # Get ThresholdHandle
    hidden [UInt16]GetThresholdHandle()
    {
        return $this.GetWordAtOffset(0x09)
    }
}


###################################################################################################################################
# Type 36                                                                                                                         #
###################################################################################################################################
class ManagementDeviceThresholdData : SMBIOSStructure 
{    
    hidden static [Hashtable]$StringArrays
    hidden static [Hashtable]$StringArrayNameAlias

    static [Array]$PropertyNames

    static ManagementDeviceThresholdData()
    {
        $labels = [Collections.ArrayList]::new() 
        
        if ( [SMBIOS]::Version -ge [Version]::new(2, 3) )
        {
            $labels.Add( "LowerThresholdNonCritical"    )
            $labels.Add( "UpperThresholdNonCritical"    )
            $labels.Add( "LowerThresholdCritical"       )
            $labels.Add( "UpperThresholdCritical"       )
            $labels.Add( "LowerThresholdNonRecoverable" )
            $labels.Add( "UpperThresholdNonRecoverable" )
        }

        [ManagementDeviceThresholdData]::PropertyNames = $labels 
    }

    ManagementDeviceThresholdData([Byte]$type, [String]$description, [String[]]$keywords, [Byte]$length, [UInt16]$handle, [Byte[]]$data, [String[]]$strings) : base($type, $description, $keywords, $length, $handle, $data, $strings)
    {
    }

    # Get ThresholdData
    hidden [StringValue]GetThresholdData($value)
    {
        return [StringValue]::new($value, 0x8000, $null, "NOT_AVAILABLE")
    }

    # Get LowerThresholdNonCritical
    hidden [StringValue]GetLowerThresholdNonCritical()
    {
        $lowerThresholdNonCritical = $this.GetWordAtOffset(0x04)
        
        return $this.GetThresholdData($lowerThresholdNonCritical)
    }

    # Get UpperThresholdNonCritical
    hidden [StringValue]GetUpperThresholdNonCritical()
    {
        $upperThresholdNonCritical = $this.GetWordAtOffset(0x06)
        
        return $this.GetThresholdData($upperThresholdNonCritical)  
    }

    # Get LowerThresholdCritical
    hidden [StringValue]GetLowerThresholdCritical()
    {
        $lowerThresholdCritical = $this.GetWordAtOffset(0x08)
        
        return $this.GetThresholdData($lowerThresholdCritical)    
    }

    # Get UpperThresholdCritical
    hidden [StringValue]GetUpperThresholdCritical()
    {
        $upperThresholdCritical = $this.GetWordAtOffset(0x0A)
        
        return $this.GetThresholdData($upperThresholdCritical)   
    }

    # Get LowerThresholdNonRecoverable
    hidden [StringValue]GetLowerThresholdNonRecoverable()
    {
        $lowerThresholdNonRecoverable = $this.GetWordAtOffset(0x0C)
        
        return $this.GetThresholdData($lowerThresholdNonRecoverable)   
    }

    # Get UpperThresholdNonRecoverable
    hidden [StringValue]GetUpperThresholdNonRecoverable()
    {
        $upperThresholdNonRecoverable = $this.GetWordAtOffset(0x0D)
        
        return $this.GetThresholdData($upperThresholdNonRecoverable)     
    }
}


###################################################################################################################################
# Type 37                                                                                                                         #
###################################################################################################################################
class MemoryChannel : SMBIOSStructure 
{    
    hidden static [Hashtable]$StringArrays
    hidden static [Hashtable]$StringArrayNameAlias

    static [Array]$PropertyNames

    static MemoryChannel()
    {
        $labels = [Collections.ArrayList]::new() 
        
        if ( [SMBIOS]::Version -ge [Version]::new(2, 3) )
        {
            $labels.Add( "Data"    )
            $labels.Add( "Strings" )
        }

        [MemoryChannel]::PropertyNames = $labels 
    }

    MemoryChannel([Byte]$type, [String]$description, [String[]]$keywords, [Byte]$length, [UInt16]$handle, [Byte[]]$data, [String[]]$strings) : base($type, $description, $keywords, $length, $handle, $data, $strings)
    {    
    }

    hidden [Byte[]]GetData()
    {
        return $this.Data
    }

    hidden [String[]]GetStrings()
    {
        return $this.Strings
    }
}


###################################################################################################################################
# Type 38                                                                                                                         #
###################################################################################################################################
class IPMIDeviceInformation : SMBIOSStructure 
{    
    hidden static [Hashtable]$StringArrays
    hidden static [Hashtable]$StringArrayNameAlias

    static [Array]$PropertyNames

    static IPMIDeviceInformation()
    {
        $labels = [Collections.ArrayList]::new() 
        
        if ( [SMBIOS]::Version -ge [Version]::new(2, 3) )
        {
            $labels.Add( "Data"    )
            $labels.Add( "Strings" )
        }

        [IPMIDeviceInformation]::PropertyNames = $labels 
    }

    IPMIDeviceInformation([Byte]$type, [String]$description, [String[]]$keywords, [Byte]$length, [UInt16]$handle, [Byte[]]$data, [String[]]$strings) : base($type, $description, $keywords, $length, $handle, $data, $strings)
    {
    }

    hidden [Byte[]]GetData()
    {
        return $this.Data
    }

    hidden [String[]]GetStrings()
    {
        return $this.Strings
    }
}


###################################################################################################################################
# Type 39                                                                                                                         #
###################################################################################################################################
class SystemPowerSupply : SMBIOSStructure 
{    
    hidden static [Hashtable]$StringArrays
    hidden static [Hashtable]$StringArrayNameAlias

    static [Array]$PropertyNames

    static SystemPowerSupply()
    {
        $stringTables = [SystemPowerSupply]::GetStringTables("Type_39")
        
        [SystemPowerSupply]::StringArrays = $stringTables.StringArrays
                                
        [SystemPowerSupply]::StringArrayNameAlias = $stringTables.StringArrayNameAlias

        $labels = [Collections.ArrayList]::new() 
        
        if ( [SMBIOS]::Version -ge [Version]::new(2, 31) )
        {
            $labels.Add( "PowerUnitGroup"             )
            $labels.Add( "Location"                   )
            $labels.Add( "DeviceName"                 )
            $labels.Add( "Manufacturer"               )
            $labels.Add( "SerialNumber"               )
            $labels.Add( "AssetTagNumber"             )
            $labels.Add( "ModelPartNumber"            )
            $labels.Add( "RevisionLevel"              )
            $labels.Add( "MaxPowerCapacity"           )
            $labels.Add( "PowerSupplyType"            )
            $labels.Add( "PowerSupplyStatus"          )
            $labels.Add( "InputVoltageRangeSwitching" )
            $labels.Add( "Characteristics"            )
            $labels.Add( "InputVoltageProbeHandle"    )
            $labels.Add( "CoolingDeviceHandle"        )
            $labels.Add( "InputCurrentProbeHandle"    )
        }

        [SystemPowerSupply]::PropertyNames = $labels 
    }

    SystemPowerSupply([Byte]$type, [String]$description, [String[]]$keywords, [Byte]$length, [UInt16]$handle, [Byte[]]$data, [String[]]$strings) : base($type, $description, $keywords, $length, $handle, $data, $strings)
    {
    }

    # Get PowerUnitGroup
    hidden [Byte]GetPowerUnitGroup()
    {
        return $this.GetByteAtOffset(0x04)  
    }

    # Get Location
    hidden [SMBString]GetLocation()
    {
        return $this.GetStringAtOffset(0x05)   
    }

    # Get DeviceName
    hidden [SMBString]GetDeviceName()
    {
        return $this.GetStringAtOffset(0x06)
    }

    # Get Manufacturer
    hidden [SMBString]GetManufacturer()
    {
        return $this.GetStringAtOffset(0x07)
    }

    # Get SerialNumber
    hidden [SMBString]GetSerialNumber()
    {
        return $this.GetStringAtOffset(0x08)  
    }

    # Get AssetTagNumber
    hidden [SMBString]GetAssetTagNumber()
    {
       return $this.GetStringAtOffset(0x09)  
    }

    # Get ModelPartNumber
    hidden [SMBString]GetModelPartNumber()
    {
        return $this.GetStringAtOffset(0x0A)
    }

    # Get RevisionLevel
    hidden [SMBString]GetRevisionLevel()
    {
        return $this.GetStringAtOffset(0x0B)
    }

    # Get MaxPowerCapacity
    hidden [StringValue]GetMaxPowerCapacity()
    {
        $maxPowerCapacity = $this.GetWordAtOffset(0x0C)
        
        return [StringValue]::new($maxPowerCapacity, 0x8000, "{0} W", "UNKNOWN")
    }

    # Get PowerSupplyType
    hidden [StringValue]GetPowerSupplyType()
    {
        $characteristics = $this.GetWordAtOffset(0x0E) 
        
        $type = [BitField]::Extract($characteristics, 0 , 4)

        return [StringValue]::new($type, "PowerSupplyType", [ref]$this)
    }

    # Get PowerSupplyStatus
    hidden [StringValue]GetPowerSupplyStatus()
    {
        $characteristics = $this.GetWordAtOffset(0x0E) 
        
        $status = [BitField]::Extract($characteristics, 7 , 3)

        return [StringValue]::new($status, "PowerSupplyStatus", [ref]$this)
    }

    # Get InputVoltageRangeSwitching
    hidden [StringValue]GetInputVoltageRangeSwitching()
    {
        $characteristics = $this.GetWordAtOffset(0x0E)
        
        $IVRS = [BitField]::Extract($characteristics, 3 , 4)

        return [StringValue]::new($IVRS, "InputVoltageRangeSwitching", [ref]$this)
    }

    # Get Characteristics
    hidden [StringValue[]]GetCharacteristics()
    {
        $characteristics = $this.GetWordAtOffset(0x0E)
        
        $powerSupply = [BitField]::Extract($characteristics, 0 , 3)

        return [BitFieldConverter]::ToStringValueArray($powerSupply, 3, "Characteristics", [ref]$this)
    }

     # Get ProbeHandle
     hidden [StringValue]GetProbeHandle($handle)
     {
        return [StringValue]::new($handle, 0xFFFF, $null, "NOT_PROVIDED")
     } 
    
    # Get InputVoltageProbeHandle
    hidden [StringValue]GetInputVoltageProbeHandle()
    {
        $handle = $this.GetWordAtOffset(0x10) 
        
        return $this.GetProbeHandle($handle)
    }

    # Get CoolingDeviceHandle
    hidden [StringValue]GetCoolingDeviceHandle()
    {
        $handle = $this.GetWordAtOffset(0x12)   

        return $this.GetProbeHandle($handle)
    }

    # Get InputCurrentProbeHandle
    hidden [StringValue]GetInputCurrentProbeHandle()
    {
        $handle = $this.GetWordAtOffset(0x14) 
        
        return $this.GetProbeHandle($handle)
    }
}


###################################################################################################################################
# Type 40                                                                                                                         #
###################################################################################################################################
class AdditionalInformationEntry
{
    [UInt16]$ReferencedHandle
    [Byte]$ReferencedOffset
    [SMBString]$String
    [ArraySegment[Byte]]$Value

    AdditionalInformationEntry([UInt16]$referencedHandle, [Byte]$referencedOffset, [SMBString]$string, [ArraySegment[Byte]]$value)
    {
        $this.ReferencedHandle = $referencedHandle
        $this.ReferencedOffset = $referencedOffset
        $this.String = $string
        $this.Value = $value
    }

    [String]ToString()
    {
        return $this.String
    }
}

class AdditionalInformation : SMBIOSStructure 
{    
    hidden static [Hashtable]$StringArrays
    hidden static [Hashtable]$StringArrayNameAlias

    static [Array]$PropertyNames

    static AdditionalInformation()
    {
        $labels = [Collections.ArrayList]::new() 
        
        if ( [SMBIOS]::Version -ge [Version]::new(2, 6) )
        {
            $labels.Add( "AdditionalInformations" )
        }

        [AdditionalInformation]::PropertyNames = $labels 
    }

    AdditionalInformation([Byte]$type, [String]$description, [String[]]$keywords, [Byte]$length, [UInt16]$handle, [Byte[]]$data, [String[]]$strings) : base($type, $description, $keywords, $length, $handle, $data, $strings)
    {
    }

    # Get NumberOfAdditionalInformationEntries
    hidden [Byte]GetNumberOfAdditionalInformationEntries()
    {
        return $this.GetByteAtOffset(0x04) 
    }

    # Get AdditionalInformationEntries
    hidden [Array]GetAdditionalInformations()
    {  
        $entries = $this.GetNumberOfAdditionalInformationEntries()

        $additionalInformations = [ArrayList]::new()

        $offset = 0x05
        
        $length = 0

        for ($i = 0; $i -lt $entries; $i++)
        {
            $offset = $offset + $length
            
            $length = $this.GetByteAtOffset($offset)

            $refHandle = $this.GetWordAtOffset($offset + 0x01)
            
            $refOffset = $this.GetByteAtOffset($offset + 0x03)

            $string = $this.GetStringAtOffset($offset + 0x04)

            $value = [ArraySegment[Byte]]::new($this.data, $offset + 0x05, $length - 0x05)

            $entry = [AdditionalInformationEntry]::new($refHandle, $refOffset,  $string, $value)    
            
            $additionalInformations.Add($entry)
        }
        
        return $additionalInformations
    }
}


###################################################################################################################################
# Type 41                                                                                                                         #
###################################################################################################################################
class OnboardDevicesExtendedInformation : SMBIOSStructure 
{    
    hidden static [Hashtable]$StringArrays
    hidden static [Hashtable]$StringArrayNameAlias

    static [Array]$PropertyNames

    static OnboardDevicesExtendedInformation()
    {
         $stringTables = [OnboardDevicesExtendedInformation]::GetStringTables("Type_41")
        
        [OnboardDevicesExtendedInformation]::StringArrays = $stringTables.StringArrays
                                
        [OnboardDevicesExtendedInformation]::StringArrayNameAlias = $stringTables.StringArrayNameAlias
        
        $labels = [Collections.ArrayList]::new() 
        
        if ( [SMBIOS]::Version -ge [Version]::new(2, 6) )
        {
            $labels.Add( "ReferenceDesignation" )
            $labels.Add( "DeviceType"           )
            $labels.Add( "DeviceStatus"         )
            $labels.Add( "DeviceTypeInstance"   )
            $labels.Add( "SegmentGroupNumber"   )
            $labels.Add( "BusNumber"            )
            $labels.Add( "DeviceFunctionNumber" )
        }

        [OnboardDevicesExtendedInformation]::PropertyNames = $labels 
    }

    OnboardDevicesExtendedInformation([Byte]$type, [String]$description, [String[]]$keywords, [Byte]$length, [UInt16]$handle, [Byte[]]$data, [String[]]$strings) : base($type, $description, $keywords, $length, $handle, $data, $strings)
    {
    }

    # Get ReferenceDesignation
    hidden [SMBString]GetReferenceDesignation()
    {
        return $this.GetStringAtOffset(0x4)
    }

    # Get DeviceType
    hidden [StringValue]GetDeviceType()
    {
        $deviceType = $this.GetWordAtOffset(0x05)
        
        $type = [BitField]::Extract($deviceType, 0, 7)

        return [StringValue]::new($type, "DeviceType", [ref]$this)  
    }

    # Get DeviceStatus
    hidden [StringValue]GetDeviceStatus()
    {
        $deviceType = $this.GetWordAtOffset(0x05)
        
        $status = [BitField]::Get($deviceType, 7)

        return [StringValue]::new($status, "DeviceStatus", [ref]$this)   
    }

    # Get DeviceTypeInstance
    hidden [Byte]GetDeviceTypeInstance()
    {
        return $this.GetByteAtOffset(0x06) 
    }

    # Get SegmentGroupNumber
    hidden [UInt16]GetSegmentGroupNumber()
    {
        return $this.GetWordAtOffset(0x07) 
    }

    # Get BusNumber
    hidden [Byte]GetBusNumber()
    {
        return $this.GetByteAtOffset(0x09)  
    }

    # Get DeviceFunctionNumber
    hidden [Byte]GetDeviceFunctionNumber()
    {
        return $this.GetByteAtOffset(0x0A)   
    }
}


###################################################################################################################################
# Type 42                                                                                                                         #
###################################################################################################################################
class ProtocolRecordDataFormat
{
    $ProtocolType
    $ProtocolTypeSpecificDataLength
    $ProtocolTypeSpecificData
}

class ManagementControllerHostInterface : SMBIOSStructure 
{    
    hidden static [Hashtable]$StringArrays
    hidden static [Hashtable]$StringArrayNameAlias

    static [Array]$PropertyNames

    static ManagementControllerHostInterface()
    {
        $labels = [Collections.ArrayList]::new() 
        
        if ( [SMBIOS]::Version -ge [Version]::new(2, 6) )
        {
            $labels.Add( "Data"    )
            $labels.Add( "Strings" )
        }

        [ManagementControllerHostInterface]::PropertyNames = $labels 
    }

    ManagementControllerHostInterface([Byte]$type, [String]$description, [String[]]$keywords, [Byte]$length, [UInt16]$handle, [Byte[]]$data, [String[]]$strings) : base($type, $description, $keywords, $length, $handle, $data, $strings)
    {
    }

    hidden [Byte[]]GetData()
    {
        return $this.Data
    }

    hidden [String[]]GetStrings()
    {
        return $this.Strings
    }
}


###################################################################################################################################
# Type 43                                                                                                                         #
###################################################################################################################################
class TPMDevice : SMBIOSStructure 
{    
    hidden static [Hashtable]$StringArrays
    hidden static [Hashtable]$StringArrayNameAlias

    static [Array]$PropertyNames

    static TPMDevice()
    {
        $stringTables = [TPMDevice]::GetStringTables("Type_43")

        [TPMDevice]::StringArrays = $stringTables.StringArrays
                                
        [TPMDevice]::StringArrayNameAlias = $stringTables.StringArrayNameAlias

        $labels = [Collections.ArrayList]::new() 
        
        if ( [SMBIOS]::Version -ge [Version]::new(3, 1) )
        {
            $labels.Add( "VendorID"              )
            $labels.Add( "SpecVersion"           )
            $labels.Add( "FirmwareVersion"       )
            $labels.Add( "Description"           )
            $labels.Add( "Characteristics"       )
            $labels.Add( "OEMDefinedInformation" )
            
        }

        [TPMDevice]::PropertyNames = $labels 
    }

    TPMDevice([Byte]$type, [String]$description, [String[]]$keywords, [Byte]$length, [UInt16]$handle, [Byte[]]$data, [String[]]$strings) : base($type, $description, $keywords, $length, $handle, $data, $strings)
    {
    }

    # Get VendorID
    hidden [StringValue]GetVendorID()
    {
        $id = [ArraySegment[Byte]]::new($this.data, 0x04, 4)

        [Byte[]]$array = [System.Linq.Enumerable]::ToArray($id)
        
        [Byte[]]$reverseArray = [System.Linq.Enumerable]::Reverse($array)

        $vendorID = [Text.Encoding]::ASCII.GetString($reverseArray)

        return [StringValue]::new($id, $vendorID)
    }

    # Get SpecVersion
    hidden [Version]GetSpecVersion()
    {
        $majorSpecVersion = $this.GetByteAtOffset(0x08) 

        $minorSpecVersion = $this.GetByteAtOffset(0x09)  

        return [Version]::new($majorSpecVersion, $minorSpecVersion)
    }

    # Get FirmwareVersion
    hidden [UInt32]GetFirmwareVersion()
    {
        # TMP 1.X
        return $this.GetDoubleWordAtOffset(0x0A)
    }

    
    # Get FirmwareVersion2
    hidden [UInt32]GetFirmwareVersion2()
    {
        # TMP 2.X
        return $this.GetDoubleWordAtOffset(0x0E)
    }

    # Get Description
    hidden [SMBString]GetDescription()
    {
        return $this.GetStringAtOffset(0x12)  
    }

    # Get Characteristics
    hidden [StringValue[]]GetCharacteristics()
    {
        $characteristics = $this.GetQuadWordAtOffset(0x13)

        return [BitFieldConverter]::ToStringValueArray($characteristics, 5, "Characteristics", [ref]$this)
    }

    # Get OEMDefinedInformation
    hidden [UInt32]GetOEMDefinedInformation()
    {
        return $this.GetDoubleWordAtOffset(0x1B)
    }
}


###################################################################################################################################
# Type 44                                                                                                                         #
###################################################################################################################################
class ProcessorAdditionalInformation : SMBIOSStructure 
{    
    hidden static [Hashtable]$StringArrays
    hidden static [Hashtable]$StringArrayNameAlias

    static [Array]$PropertyNames

    static ProcessorAdditionalInformation()
    {
        $labels = [Collections.ArrayList]::new() 
        
        if ( [SMBIOS]::Version -ge [Version]::new(3, 3) )
        {
            $labels.Add( "Data"    )
            $labels.Add( "Strings" )
        }

        [ProcessorAdditionalInformation]::PropertyNames = $labels 
    }

    ProcessorAdditionalInformation([Byte]$type, [String]$description, [String[]]$keywords, [Byte]$length, [UInt16]$handle, [Byte[]]$data, [String[]]$strings) : base($type, $description, $keywords, $length, $handle, $data, $strings)
    {
    }

    hidden [Byte[]]GetData()
    {
        return $this.Data
    }

    hidden [String[]]GetStrings()
    {
        return $this.Strings
    }
 }


###################################################################################################################################
# Type 126                                                                                                                        #
###################################################################################################################################
class Inactive : SMBIOSStructure 
{    
    hidden static [Hashtable]$StringArrays
    hidden static [Hashtable]$StringArrayNameAlias

    static [Array]$PropertyNames

    static Inactive()
    {
        $labels = [Collections.ArrayList]::new() 
        
        [Inactive]::PropertyNames = $labels 
    }

    Inactive([Byte]$type, [String]$description, [String[]]$keywords, [Byte]$length, [UInt16]$handle, [Byte[]]$data, [String[]]$strings) : base($type, $description, $keywords, $length, $handle, $data, $strings)
    {
    }
}


###################################################################################################################################
# Type 127                                                                                                                        #
###################################################################################################################################
class EndOfTable : SMBIOSStructure 
{ 
    hidden static [Hashtable]$StringArrays
    hidden static [Hashtable]$StringArrayNameAlias

    static [Array]$PropertyNames

    static EndOfTable()
    {
        $labels = [Collections.ArrayList]::new() 
        
        [EndOfTable]::PropertyNames = $labels 
    }

    EndOfTable([Byte]$type, [String]$description, [String[]]$keywords, [Byte]$length, [UInt16]$handle, [Byte[]]$data, [String[]]$strings) : base($type, $description, $keywords, $length, $handle, $data, $strings)
    {
    }
}


###################################################################################################################################
# Type 128..255                                                                                                                   #
###################################################################################################################################
class OEMSpecificInformation : SMBIOSStructure
{ 
    static [Array]$PropertyNames

    static OEMSpecificInformation()
    {
        $labels = [Collections.ArrayList]::new() 
    
        $labels.Add( "Data"    )
        $labels.Add( "Strings" )

        [OEMSpecificInformation]::PropertyNames = $labels 
    }
    
    OEMSpecificInformation([Byte]$type, [String]$description, [String[]]$keywords, [Byte]$length, [UInt16]$handle, [Byte[]]$data, [String[]]$strings) : base($type, $description, $keywords, $length, $handle, $data, $strings)
    {   
    }

    hidden [Byte[]]GetData()
    {
        return $this.Data
    }

    hidden [String[]]GetStrings()
    {
        return $this.Strings
    }
}

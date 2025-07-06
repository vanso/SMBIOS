<#

SMBIOSLib

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

using namespace System.Collections
using namespace System.Collections.Generic
using namespace System.Collections.Specialized
using namespace System.Globalization
using namespace System.Text
using namespace System.Net
using namespace System.Net.NetworkInformation

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
    static [Boolean]$HideHeader
    static [Boolean]$NoEmphasis
}

#
# Utility class for localization.
#
class Localization
{
    hidden static [HashTable]$LocalisedStrings
    
    static Localization()
    {
        $cultureName = (Get-Culture).Name

        if ( Test-Path -Path $(Join-Path -Path $PSScriptRoot -ChildPath $cultureName) )
        {
            [Localization]::LocalisedStrings = Import-LocalizedData -UICulture $cultureName
        }
        else
        {
            [Localization]::LocalisedStrings = Import-LocalizedData -UICulture "en-US"
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
            return "Localized string not found for $string."
        }
    }
}

function Get-LocalizedString
{
    param(
        [String]$String
    )

    [Localization]::LocalizedString($String)
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
        $bytes = [BitConverter]::GetBytes($int)

        return [BitConverter]::ToUInt32($bytes, 0)
    }                               

    static [UInt32]HighUInt64([UInt64]$int)
    {  
        $bytes = [BitConverter]::GetBytes($int)
        
        return [BitConverter]::ToUInt32($bytes, 2)
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
    # ToArray
    #
    static [Array]ToArray([Object]$bitField, [Array]$names)
    {
        return [BitFieldConverter]::ToArray($bitField, [BitFieldConverter]::Length($bitField), $names)
    }

    static [Array]ToArray([Object]$bitField, [int]$length, [Array]$names)
    {        
        $list = [ArrayList]::new()

        for ($i = 0; $i -le $length - 1 ; $i++)
        {
            if ($bitField -band (1 -shl $i))
            {                         
                $list.Add($names[$i]) | Out-Null
            }
        }

        return $list
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
        if ($bitField -eq 0)
        {          
            return [StringValue]::new(-1, $(Get-LocalizedString "NONE"))
        }
        
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
    static [StringValue[]]ToStringValueArray([Object]$bitField, [String]$dictionaryName, [ref]$classRef)
    {    
        return [BitFieldConverter]::ToStringValueArray($bitField, [BitFieldConverter]::Length($bitField), $dictionaryName, 0, $classRef)
    }

    static [StringValue[]]ToStringValueArray([Object]$bitField, [int]$length, [String]$dictionaryName, [ref]$classRef)
    {
        return [BitFieldConverter]::ToStringValueArray($bitField, $length, $dictionaryName, 0, $classRef)
    }

    static [StringValue[]]ToStringValueArray([Object]$bitField, [int]$length, [String]$dictionaryName, [int]$offset, [ref]$classRef)
    {     
        $class = $classRef.Value

        $names = $class::StringArrays[$dictionaryName]

        return [BitFieldConverter]::ToStringValueArray($bitField, $length, $names, $offset)
    }

    static [StringValue[]]ToStringValueArray([Object]$bitField, [Array]$names)
    {
        return [BitFieldConverter]::ToStringValueArray($bitField, [BitFieldConverter]::Length($bitField), $names, 0)
    }

    static [StringValue[]]ToStringValueArray([Object]$bitField, [int]$length, [Array]$names)
    {
        return [BitFieldConverter]::ToStringValueArray($bitField, $length, $names, 0)
    }

    static [StringValue[]]ToStringValueArray([Object]$bitField, [int]$length, [Array]$names, [int]$offset)
    {
        if ($bitField -eq 0)
        {
            return [StringValue]::new(-1, $(Get-LocalizedString "NONE"))
        }
        
        $list = [ArrayList]::new()
        
        $expand = $false

        for ($i = 0; $i -le $length - 1 ; $i++)
        {
            if ($expand)
            {
                if ($bitField -band (1 -shl $i))
                {         
                    $list.Add( [StringValue]::new($i + $offset, $names[$i], $true) ) | Out-Null
                }
                else
                {
                    $list.Add( [StringValue]::new($i + $offset, $names[$i], $false) ) | Out-Null 
                }
            }
            else
            {
                if ($bitField -band (1 -shl $i))
                {         
                    $list.Add( [StringValue]::new($i + $offset, $names[$i]) ) | Out-Null
                }
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
    SMBString([Object]$value, [Byte]$index)
    {
        if ( [String]::IsNullOrEmpty($value) )
        {
            $this | Add-Member Value $null

            $this | Add-Member DisplayValue "$(Get-LocalizedString "N/A")"
        }
        else
        {
            $this | Add-Member Value $value.ToString()

            $this | Add-Member DisplayValue $value.ToString()
        }

        $this | Add-Member Index $index
    }

    SMBString([String]$string)
    {
        $this | Add-Member Value $string

        $this | Add-Member DisplayValue $string

        $this | Add-Member Index -1
    }

    [String]ToString()
    {
        if ([Settings]::Expand)
        {                       
            if ([Settings]::NoEmphasis)
            {
                return [String]::Format("Strings[{0}] ({1})", $this.Index, $this.DisplayValue)
            }
            else 
            {
                return [char]0x001b + "[1m" + [String]::Format("Strings[{0}] ({1})", $this.Index, $this.DisplayValue) + [char]0x001b + "[0m"
            }
        }
        else
        {       
            $allWhiteSpace = [Linq.Enumerable]::All([char[]]$this.DisplayValue, [Func[char,bool]]{ [char]::IsWhiteSpace($args[0]) })
            
            if ( ($allWhiteSpace) -or ($this.DisplayValue.StartsWith(" ")) -or ($this.DisplayValue.EndsWith(" ")) )
            {
                if ([Settings]::NoEmphasis)
                {
                    return "`"" + "$($this.DisplayValue)" + "`""
                }
                else 
                {
                    return [char]0x001b + "[1m" + "`"" + "$($this.DisplayValue)" + "`"" + [char]0x001b + "[0m"
                }
                
            }
            else 
            {
                if ([Settings]::NoEmphasis)
                {
                    return $($this.DisplayValue)
                }
                else
                {
                    return [char]0x001b + "[1m" + "$($this.DisplayValue)" + [char]0x001b + "[0m" 
                }
            }
        }
    }
}

class SMBHandle
{
    hidden [UInt16]$Value
    
    SMBHandle()
    {
        $this.Value = [UInt16]::MaxValue
    }
    
    SMBHandle([UInt16]$value)
    {
        $this.Value = $value
    }

    [String]ToString()
    {
        if ($this.Value -eq [UInt16]::MaxValue)
        {
            return Get-LocalizedString "N/A"
        }
        else 
        {
            return [String]::Format("0x{0:X4}", $this.Value)
        }
    }

    static [UInt16]op_Implicit([SMBHandle]$value)
    {
        return $value.Value
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
        $this.Value = $null
        $this.DisplayValue = Get-LocalizedString "NOT_AVAILABLE"
    }
    
    StringValue([Object]$value)
    {   
        if ($null -eq $value)
        {
            $this.Value = $value
            $this.DisplayValue = Get-LocalizedString "NOT_AVAILABLE"
        }
        else
        {
            $this.Value = $value

            $this.DisplayValue = $value
        }
    }

    StringValue([Object]$value, [String]$format)
    {
        if ($null -eq $value)
        {
            $this.DisplayValue = Get-LocalizedString "NOT_AVAILABLE"
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
        
        if ($exceptionValue -is [Array])
        {
            if ($exceptionValue -contains $value)
            {
                $exception = $true
            }
        }
        else
        {
            if ($value -eq $exceptionValue)
            {
                $exception = $true
            }
        }
        
        if ($exception)
        {
            $this.Displayvalue = Get-LocalizedString $exceptionString
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
            $this.Displayvalue = Get-LocalizedString $exceptionString
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
            $this.Displayvalue = Get-LocalizedString $exceptionString
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
            $outOfSpecification = Get-LocalizedString "OUT_OF_SPEC"
                
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
            $outOfSpecification = Get-LocalizedString "OUT_OF_SPEC"
                
            $this.DisplayValue = [String]::Format("{0} ($outOfSpecification)", $value)
        }

        if ((-not ($names.[int]0)) -and ($value -eq 0))
        {
            $this.Resolved = $false
            
            $this.DisplayValue = Get-LocalizedString "NONE"
        }

    }

    [String]ToString()
    {
        return $this.ToString("G", [CultureInfo]::CurrentCulture);
    }
 
    [String]ToString([String]$format)
    {
        return $this.ToString($format, [CultureInfo]::CurrentCulture);
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
                
                if ($null -eq $this.Value)
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

class StringValueArray : StringValue
{
    [Boolean]$Supported

   StringValueArray([Object]$value, [String]$name, [Boolean]$supported)
   {   
        if ([String]::IsNullOrEmpty($name))
        {
          $outOfSpecification = Get-LocalizedString "OUT_OF_SPEC"
                
          $this.DisplayValue = [String]::Format("{0} ($outOfSpecification)", $value)

          $this.Value = $value
        }
        else
        {
            $this.Value = $value

            $this.DisplayValue = $name

            $this.Supported = $supported
        }
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
    None
    Unknown
}

class StringValueMemorySize : StringValue
{
    [Object]$SizeInBytes
    [MemorySizeUnit]$Unit

    static [MemorySizeUnit]AdjustSizeUnit([Object]$sizeInBytes)
    {
        # Useless therefore essential
        $1eb = 1.15292150460685E+18
        $1zb = 1.18059162071741E+21
        $1yb = 1.20892581961463E+24
        
        if ($sizeInBytes -ge $1yb)
        {
            return [MemorySizeUnit]::YB
        }
        elseif ($sizeInBytes -ge $1zb)
        {
            return [MemorySizeUnit]::ZB
        }
        elseif ($sizeInBytes -ge $1eb)
        {
            return [MemorySizeUnit]::EB
        }
        elseif ($sizeInBytes -ge 1pb)
        {
            return [MemorySizeUnit]::PB
        }
        elseif ($sizeInBytes -ge 1tb)
        {
            return [MemorySizeUnit]::TB
        }
        elseif ($sizeInBytes -ge 1gb)
        {
            return [MemorySizeUnit]::GB
        }
        elseif ($sizeInBytes -ge 1mb)
        {
            return [MemorySizeUnit]::MB
        }
        elseif ($sizeInBytes -ge 1kb)
        {
            return [MemorySizeUnit]::kB
        }
        else
        {
            return [MemorySizeUnit]::B
        }
    }

    StringValueMemorySize([Object]$sizeInBytes, [MemorySizeUnit]$unit) : base()
    { 
        $1eb = 1.15292150460685E+18
        $1zb = 1.18059162071741E+21
        $1yb = 1.20892581961463E+24

        $dataSizes = @(1, 1kb, 1mb, 1gb, 1tb, 1pb, $1eb, $1zb, $1yb)

        if ([Settings]::MemorySizeUnit -eq [MemorySizeUnit]::Auto)
        {
            if ($unit -eq [MemorySizeUnit]::Auto)
            {
                $_unit = [StringValueMemorySize]::AdjustSizeUnit($sizeInBytes)

                $localizedUnit = Get-LocalizedString $_unit
            
                $dataSize = $dataSizes[[int]$_unit]
            }
            else 
            {
                $_unit = $unit
            
                $localizedUnit = Get-LocalizedString $unit
            
                $dataSize = $dataSizes[[int]$unit]
            }   
        }
        else
        {
            $customUnit = [Settings]::MemorySizeUnit

            $_unit = $customUnit
            
            $localizedUnit = Get-LocalizedString $customUnit
            
            $dataSize = $dataSizes[[int]$customUnit]   
        }

        $this.Value = $sizeInBytes / $dataSize

        $this.SizeInBytes = $sizeInBytes

        $this.DisplayValue = [String]::Format("{0:N0} $localizedUnit", $this.Value)

        $this.Unit = $_unit
    }

    StringValueMemorySize([Object]$value, [String]$dictionaryName, [ref]$classRef, [Object]$SizeInBytes, [MemorySizeUnit]$unit) : base()
    {        
        $this.Value = $value
        
        $this.SizeInBytes = $SizeInBytes

        $this.Unit = $unit

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
            $outOfSpecification = Get-LocalizedString "OUT_OF_SPEC"
                
            $this.DisplayValue = [String]::Format("{0} ($outOfSpecification)", $value)
        }
    }
}

#
# Temperature units.
#
enum TemperatureUnit
{
   Auto
   Celsius
   Fahrenheit
   Unknown
}

class StringValueTemperature : StringValue
{
    [Object]$Value
    [String]$DisplayValue
    [TemperatureUnit]$Unit
    hidden [Sbyte]$Precision
    
    StringValueTemperature([Object]$temperature, [String]$string) : base()
    {
        $this.Value = $temperature

        $this.DisplayValue = $string

        $this.Unit = [TemperatureUnit]::Unknown

        $this.Precision = -1
    }

    StringValueTemperature([Object]$temperatureInCelsius, [TemperatureUnit]$unit, [Sbyte]$precision) : base()
    {
        $temperature = 0
        $localizedUnit = ""

        if ([Settings]::TemperatureUnit -eq [TemperatureUnit]::Celsius)
        {   
            $localizedUnit = Get-LocalizedString "CELSIUS"
            
            $temperature = $temperatureInCelsius
        }
        elseif ([Settings]::TemperatureUnit -eq [TemperatureUnit]::Fahrenheit)
        {
            $localizedUnit = Get-LocalizedString "FAHRENHEIT"
            
            $temperature = ($temperatureInCelsius * 9/5) + 32 
        }
        elseif ([Settings]::TemperatureUnit -eq [TemperatureUnit]::Auto) 
        {
            $cultureName = (Get-Culture).Name

            $region = [RegionInfo]::new($cultureName)
            
            if ($region.IsMetric)
            {
                $localizedUnit = Get-LocalizedString "CELSIUS"
            
                $temperature = $temperatureInCelsius
            }
            else 
            {
                $localizedUnit = Get-LocalizedString "FAHRENHEIT"
            
                $temperature = ($temperatureInCelsius * 9/5) + 32     
            }
        }
        
        $this.Value = $temperature

        $this.DisplayValue = [String]::Format("{0:F$($precision)} $localizedUnit", $this.Value)

        $this.Unit = $unit

        $this.Precision = $precision
    }

    [StringValue]ToFahrenheit()
    {
        $temperature = ($this.Value * 9/5) + 32 

        $localizedUnit = Get-LocalizedString "FAHRENHEIT"

        $string = [String]::Format("{0:F$($this.Precision)} $localizedUnit", $this.Value)

        return [StringValue]::new($temperature, $string)
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

class StringValueDateTime : StringValue
{
    hidden [string]$Format
    
    StringValueDateTime() : base()
    {
        $notDefined = Get-LocalizedString "NOT_DEFINED"

        $this.DisplayValue = $notDefined
    }
    
    StringValueDateTime([Object]$value) : base($value)
    {
        $pattern = [CultureInfo]::CurrentCulture.DateTimeFormat.LongDatePattern
        
        $this.Format = "{0:$pattern}"

        if ($null -eq $value)
        {   
            $this.DisplayValue = Get-LocalizedString "NOT_DEFINED"
        }
    }
    
    StringValueDateTime([Object]$value, [String]$format) : base($value, $format)
    {
        $this.Format = $format

        if ($null -eq $value)
        {   
            $notDefined = [Localization]::LocalizedString("NOT_DEFINED")
            
            $this.DisplayValue = $notDefined
        }
    }

    [String]ToString()
    {
        return $this.ToString("G", [CultureInfo]::CurrentCulture);
    }
 
    [String]ToString([String]$format)
    {
        return $this.ToString($format, [CultureInfo]::CurrentCulture);
    }

    [String]ToString([String]$format, [IFormatProvider]$formatProvider)
    {           
        if ($null -eq $this.value)
        {
            return $this.DisplayValue
        }

        if (-Not ($formatProvider))
        {
            $formatProvider = [CultureInfo]::CurrentCulture
        }

        if (($format -eq "0") -or ($format -eq [String]::Empty))
        {           
            if ($this.Format)
            {
                 $longDateString = [String]::Format($formatProvider, $this.Format, $this.Value)
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

class StringValueOrderedDictionary : StringValue
{   
    StringValueOrderedDictionary() : base()
    {
    }

    StringValueOrderedDictionary([Object]$value) : base($value)
    {
        $this.DisplayValue = ( $value.GetEnumerator() | ForEach-Object { "$($_.Key) $($_.Value)" } ) -Join " "
    }
    
    StringValueOrderedDictionary([Object]$value, [String]$format) : base($value, $format)
    {
    }

    static [OrderedDictionary]op_Implicit([StringValueOrderedDictionary]$stringValueOrderedDictionary)
    {
        return $stringValueOrderedDictionary.Value
    }

    [String]toString()
    {
        return $this.DisplayValue
    }

    [String]ToString([String]$format, [IFormatProvider]$formatProvider)
    {
        return $this.DisplayValue
        
        if (-Not ($formatProvider))
        {
            $formatProvider = [CultureInfo]::CurrentCulture
        }

        $string = ( $this.Value.GetEnumerator() | ForEach-Object { "$($_.Key) $($_.Value)" } ) -Join " "

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
                return $this.DisplayValue
            }
        }
        else
        {
            return [String]::Format($formatProvider, $format, $this.Value)
        }
    }
}

class StringValueFormated : StringValue
{
    StringValueFormated([Object]$value, [OrderedDictionary]$values, [Array]$formats) 
    {
        $this.Value = $values

        $result = ""

        for ($index = 0; $index -lt $values.Count; $index++) 
        {
            $item = $values[$index].Value
            $format = $formats[$index] 
        
            $result = $result + [String]::Format($format, $item)
        }

        $this.DisplayValue = $result
    }

    [String]toString()
    {
        return $this.DisplayValue
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

    SMBIOSType([int]$type, [string]$name)
    {
        $this.Type = $type
        $this.Name = $name
    }

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
# Defines a SMBIOSAvailableType
#
class SMBIOSAvailableType
{
    [int]$Count
    [int]$Type
    [string]$Name
    [UInt16[]]$Handle

    SMBIOSAvailableType([int]$count, [int]$type, [string]$name, [UInt16[]]$handle)
    {
        $this.Count = $count
        $this.Type = $type
        $this.Name = $name
        $this.Handle = $handle
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
    static [Version]$SupportedVersion
    static [Version]$Version
    static [Encoding]$Encoding
    static [Array]$Types
    static [Array]$Descriptions
    static [Array]$AvailableTypes
    static [List[Hashtable]]$Structures
    static [Byte[]]$TableData
    static [UInt32]$TableDataSize
    static [Byte[]]$EntryPoint
    static [UInt64]$StructureTableAddress
    static [String]$Hash

    static SMBIOS()
    {
        # Define the supported vesion of SMBIOS
        [SMBIOS]::SupportedVersion = [Version]::new("3.8.0")
        
        # Generates SMBIOS types list
        $typesList = [ArrayList]::new()

        $SMBIOSTypes = [SMBIOSStructure]::StringArrays["SMBIOSType"]

        foreach ( $type in $SMBIOSTypes.GetEnumerator() )
        {
            $typesList.Add( [SMBIOSType]::new( $type.Key, $type.Value ) )
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

    # Using the ioreg tool to retrieve SMBIOS information on Mac.
    # The SMBIOS-EPS property contains the entry point of the SMBIOS.
    # The SMBIOS property contains the SMBIOS table.
    # SMBIOS is not longer used by Apple on Mac with Apple silicon.
    static [Byte[]] ReadAppleSMBIOSProperty([String]$property)
    {    
        $tableDataList = [List[Byte]]::new()
        
        $AppleSMBIOSProperty = /usr/sbin/ioreg -c AppleSMBIOS -r | Select-String $property
    
        if ($AppleSMBIOSProperty)
        {
            $SMBIOSProperty = ($AppleSMBIOSProperty -Split "= ")[1].TrimStart("<").TrimEnd(">")

            $length = $SMBIOSProperty.Length / 2

            for ($i = 0; $i -lt $length ; $i++) 
            {
                $hex = $SMBIOSProperty.SubString($i * 2, 2)
                $byte = [Convert]::ToByte($hex, 16)
                $tableDataList.Add($byte)
            }
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
        $revisionVersion = 0

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
                $revisionVersion = $entryPoint[0x1E]

                [SMBIOS]::StructureTableAddress = [BitConverter]::ToUInt32($entryPoint, 0x18)
            }
            3 {  
                [SMBIOS]::TableDataSize = [BitConverter]::ToUInt32($entryPoint, 0x0C)
                $majorVersion = $entryPoint[0x07]
                $minorVersion = $entryPoint[0x08]
                $revisionVersion = $entryPoint[0x09]

                [SMBIOS]::StructureTableAddress = [BitConverter]::ToUInt64($entryPoint, 0x10)
            }
        }

        [SMBIOS]::Version = [Version]::new($majorVersion, $minorVersion, $revisionVersion)
    }

    # Parse the SMBIOS table
    static [Void]ParseTableData()
    {
        $tableDataHash = $(Get-FileHash -InputStream $([System.IO.MemoryStream]::new([SMBIOS]::TableData)) -Algorithm MD5).Hash

        if ($tableDataHash -ne [SMBIOS]::Hash)
        {
            [SMBIOS]::Hash = $tableDataHash
            
            $structuresList = [List[Hashtable]]::new()

            $tableDataLength = [SMBIOS]::TableData.Count

            $offset = 0

            do
            {    
                # Read the header (fixed size)
                $type = [SMBIOS]::TableData[$offset] 
                $length = [SMBIOS]::TableData[$offset + 1]
                $handle = [BitConverter]::ToUInt16([SMBIOS]::TableData, $offset + 2)
                $data = [ArraySegment[Byte]]::new([SMBIOS]::TableData, $offset, $length)

                $variableLengthBegin = $offset + $length
                $location = $variableLengthBegin
                $variableLength = 0
                
                # Read the strings (variable size)     
                while ($location -lt $tableDataLength) 
                {
                    if (([SMBIOS]::TableData[$location] -eq 0x00) -and ([SMBIOS]::TableData[$location + 1] -eq 0x00))
                    {
                        $variableData = [ArraySegment[Byte]]::new([SMBIOS]::TableData, $variableLengthBegin, $variableLength)
                            
                        [ArrayList]$strings = [SMBIOS]::Encoding.GetString($variableData) -Split ("`0")
                        
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
}

###################################################################################################################################
# class SMBIOSStructureHeader                                                                                                     #
###################################################################################################################################
class SMBIOSStructureHeader
{
    [Byte]$Type
    [String]$Description
    [Byte]$Length
    [UInt16]$Handle

    SMBIOSStructureHeader([Byte]$type, [String]$description, [Byte]$length, [UInt16]$handle)
    {
        $this.Type = $type
        $this.Description = $description
        $this.Length = $length
        $this.Handle = $handle  
    }
    
    [String]ToString()
    {
        return [String]::Format($(Get-LocalizedString "SMBIOS_HEADER"), $this.Handle, $this.Type, $this.Description, $this.Length)
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

    hidden [Byte]$Type
    hidden [String]$Description
    hidden [Byte]$Length
    hidden [UInt16]$Handle
    hidden [OrderedDictionary]$Properties
    hidden [String[]]$Keywords
    hidden [Byte[]]$Data
    hidden [String[]]$Strings
    hidden [Boolean]$Obsolete

    # for compatibility with version 0.8
    hidden [Byte]$_Type
    hidden [String]$_Description
    hidden [UInt16]$_Handle

    SMBIOSStructure([Byte]$type, [String]$description, [String[]]$keywords, [Byte]$length, [UInt16]$handle, [Byte[]]$data, [String[]]$strings)
    {
        $this.Type = $type
        $this.Description = $description
        $this.Length = $length
        $this.Keywords = $keywords
        $this.Handle = $handle
        $this.Data = $data
        $this.Strings = $strings
        $this.Properties = [Ordered]@{}

        # for compatibility with version 0.8
        $this._Type = $this.Type
        $this._Description = $this.Description
        $this._Handle = $this.Handle
    }

    hidden [Byte]Get_Type()
    {
        return $this.Type
    }

    hidden [String]Get_Description()
    {
        return $this.Description
    }

    hidden [UInt16]Get_Handle()
    {
        return $this.Handle
    }

    hidden [SMBIOSStructureHeader]Get_Header()
    {
        return [SMBIOSStructureHeader]::new($this.Type, $this.Description, $this.Length, $this.Handle)
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

    hidden [SMBString]GetStringAtOffset([Byte]$offset)
    {
        $index = $this.data[$offset] - 1

        if ($index -ge 0)
        {
            if ( [String]::IsNullOrEmpty( $this.strings[$index] ) )
            {
                return [SMBString]::new([String]::Empty, [Byte]::MaxValue)   
            }
            else
            {
                return [SMBString]::new($this.strings[$index], $index)   
            }
        }
        else 
        {
            return [SMBString]::new([String]::Empty, [Byte]::MaxValue)
        }
    }

    hidden [ArraySegment[Byte]]GetData()
    {
        return $this.Data
    }

    hidden [String[]]GetStrings()
    {
        return $this.Strings
    }

    hidden [Byte]GetDMIType()
    {
        return $this.Type
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
        $cultureName = (Get-Culture).Name

        if (Test-Path -Path $(Join-Path -Path $PSScriptRoot -ChildPath $cultureName))
        {
            $xml = [xml](Get-Content -Path "$PSScriptRoot/$cultureName/$type.xml")

        }
        else
        {
            $xml = [xml](Get-Content -Path "$PSScriptRoot/en-US/$type.xml")
        }
        
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

        if ($this.PropertyNamesEx)
        {
            $propertiesList = $propertiesList + $this.PropertyNamesEx
        }

        if (-Not [Settings]::HideHeader)
        {
            $propertiesList = @("_Header") + $propertiesList
        }
   
        foreach ($property in $propertiesList)
        {
            try
            {
                $methodInfo = $runtimeType.GetMethod("Get$property")
                
                if ($property.StartsWith("_"))
                {
                    $propertyName = $property.Replace("_","")
                }
                else 
                {
                    $propertyName = $property
                }

                try
                {
                    [System.Runtime.CompilerServices.RuntimeHelpers]::PrepareMethod($methodInfo.MethodHandle)

                    $object = $methodInfo.Invoke($this, $null)

                    $this.Properties.Add($propertyName, $object) | Out-Null      
                }
                catch
                {
                    
                    Write-Warning "Property `"$propertyName`" Not Found For Type $($this.Type) ($( $this.Description ))"
                }
            }
            catch
            {
                Write-Warning ($error[0].Exception.Message)
            }  
        }
    }

    hidden [OrderedDictionary]GetProperties()
    {        
       return $this.Properties
    }

    # Used by types 9, 41 and 42
    # Segment Group Number, Bus Number, Device/Function Number
    hidden [StringValue]Get_BusAddress([Byte]$offset)
    {
        $segmentGroupNumber = $this.GetWordAtOffset($offset)
        $busNumber = $this.GetByteAtOffset($offset + 0x02)
        $deviceAndFunctionNumber = $this.GetByteAtOffset($offset + 0x03)

        if (($segmentGroupNumber -ne 0xFFFF) -or ($busNumber -ne 0xFF) -or ($deviceAndFunctionNumber -ne 0xFF))
        {
            $busAddress = "{0:x4}:{1:x2}:{2:x2}.{3}" -f $segmentGroupNumber, $busNumber, ($deviceAndFunctionNumber -shr 3), ($deviceAndFunctionNumber -band 0x7)
            
            return [StringValue]::new( [Ordered]@{ SegmentGroupNumber = $segmentGroupNumber; 
                                                   BusNumber          = $busNumber;
                                                   DeviceNumber       = ($deviceAndFunctionNumber -shr 3);
                                                   FunctionNumber     = ($deviceAndFunctionNumber -band 0x7) }, $busAddress.ToUpper() )
        }
        else 
        {
            $notDefined = Get-LocalizedString "NOT_DEFINED"

            return [StringValue]::new(-1, $notDefined)
        }
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
        $releaseDate = $($this.GetStringAtOffset(0x08)).DisplayValue

        if ([String]::IsNullOrEmpty($releaseDate))
        {
            $notAvailable = Get-LocalizedString "NOT_AVAILABLE"
        
            return [StringValueDateTime]::new($null, $notAvailable)
        }
        else 
        {
            $culture = [CultureInfo]::CreateSpecificCulture("en-US")
            
            [DateTime]$date = [DateTime]::new(0)

            if( [DateTime]::TryParse($releaseDate, $culture, [DateTimeStyles]::None, [ref]$date) )
            {         
                return [StringValueDateTime]::new($date)
            }
            else 
            {
                return [StringValueDateTime]::new($releaseDate, $releaseDate)
            }
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

            if ($characteristicsByte1 -gt 0)
            {
                $featuresList = $featuresList + [BitFieldConverter]::ToStringValueArray($characteristicsByte1, 8, "CharacteristicsByte1", $offset, [ref]$this)
            }

            $offset = $offset + 8
        }

        if ( [SMBIOS]::Version -ge [Version]::new(2, 3) )
        {    
            $characteristicsByte2 = $this.GetByteAtOffset(0x13)

            if ($characteristicsByte2 -gt 0)
            {
                $featuresList = $featuresList + [BitFieldConverter]::ToStringValueArray($characteristicsByte2, 8, "CharacteristicsByte2", $offset, [ref]$this)
            }

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
    hidden [StringValue]GetUUID()
    {
        $UUID = $null
        
        $rawUUID = [Byte[]][ArraySegment[Byte]]::new($this.data, 0x08, 16)

        $only0x00 = [Linq.Enumerable]::All($rawUUID, [Func[byte,bool]]{ $args[0] -eq 0x00 })

        $only0xFF = [Linq.Enumerable]::All($rawUUID, [Func[byte,bool]]{ $args[0] -eq 0xFF })

        if ($only0x00)
        {
            $value = 0x00
            
            $UUID = Get-LocalizedString "NOT_SETTABLE"
        }
        elseif ($only0xFF)
        { 
            $value = 0xFF
            
            $UUID = Get-LocalizedString "NOT_PRESENT"
        } 
        else
        {
            $value = [Guid]::new($rawUUID)
            
            $UUID = $value.ToString().ToUpper()
        }

        return [StringValue]::new($value, $UUID)
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
            $labels.Add( "Manufacturer"           )
            $labels.Add( "Product"                ) 
            $labels.Add( "Version"                ) 
            $labels.Add( "SerialNumber"           )
            $labels.Add( "AssetTag"               )    
            $labels.Add( "Features"               ) 
            $labels.Add( "LocationInChassis"      ) 
            $labels.Add( "ChassisHandle"          ) 
            $labels.Add( "BoardType"              ) 
            $labels.Add( "ContainedObjectHandles" ) 
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
    hidden [Array]GetContainedObjectHandles()
    {
        $numberOfContainedObjectHandles = $this.GetByteAtOffset(0x0E)

        $objectsHandles = [List[UInt16]]::new()

        if ($numberOfContainedObjectHandles -gt 0)
        {
            for ($objectHandle = 0 ; $objectHandle -lt $numberOfContainedObjectHandles ; $objectHandle++) 
            {
                $handle = $this.GetWordAtOffset(0x0F + ($objectHandle * 2))

                $objectsHandles.Add( $handle )
            }
    
            return $objectsHandles
        } 

        $objectsHandles.Add($numberOfContainedObjectHandles)

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

    hidden [ArrayList]$PropertyNamesEx

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
        
        [SystemEnclosure]::PropertyNames = $labels
    }

    SystemEnclosure([Byte]$type, [String]$description, [String[]]$keywords, [Byte]$length, [UInt16]$handle, [Byte[]]$data, [String[]]$strings) : base($type, $description, $keywords, $length, $handle, $data, $strings) 
    {
        $labels = [Collections.ArrayList]::new()

        if ( [SMBIOS]::Version -ge [Version]::new(2, 7) )
        {
            $labels.Add( "SKUNumber"          )     
        }

        $this.PropertyNamesEx = $labels
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

        $containedElementsList = [Collections.ArrayList]::new()

        if ($containedElementCount -gt 0)
        {
            $containedElements = [ArraySegment[Byte]]::new($this.data, 0x15, $containedElementCount * $containedElementRecordLength)

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

        $none = Get-LocalizedString "NONE"
            
        return [StringValue]::new(-1, $none) 
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
class ProcessorInformation : SMBIOSStructure 
{
    hidden static [Hashtable]$StringArrays
    hidden static [Hashtable]$StringArrayNameAlias

    hidden static [Array]$PropertyNames

    hidden [ArrayList]$PropertyNamesEx

    static ProcessorInformation()
    {
        $stringTables = [ProcessorInformation]::GetStringTables("Type_4")

        [ProcessorInformation]::StringArrays = $stringTables.StringArrays
                                
        [ProcessorInformation]::StringArrayNameAlias = $stringTables.StringArrayNameAlias

        $labels = [Collections.ArrayList]::new() 

        if ( [SMBIOS]::Version -ge [Version]::new(2, 0) )
        {
            $labels.Add( "SocketDesignation" )
            $labels.Add( "_Type"             )
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
            $labels.Add( "Status"            )
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
  
        [ProcessorInformation]::PropertyNames = $labels
    }

    ProcessorInformation([Byte]$type, [String]$description, [String[]]$keywords, [Byte]$length, [UInt16]$handle, [Byte[]]$data, [String[]]$strings) : base($type, $description, $keywords, $length, $handle, $data, $strings) 
    {   
        $labels = [Collections.ArrayList]::new()

        if ( [SMBIOS]::Version -ge [Version]::new(2, 5) )
        {    
            $labels.Add( "CoreCount"         )
            $labels.Add( "CoreEnabled"       )
            $labels.Add( "ThreadCount"       )
            $labels.Add( "Characteristics"   )
        }

        if ( [SMBIOS]::Version -ge [Version]::new(3, 6) )
        {    
            $labels.Add( "ThreadEnabled"     )
        }

        $this.PropertyNamesEx = $labels
    }
    
    # Get VendorID
    hidden [String]GetVendorID()
    {        
        $manufacturer = $this.GetManufacturer()

        $version = $this.GetVersion()

        # GenuineIntel 
        if ( $manufacturer -like "*Intel*" )
        {
            return "GenuineIntel"
        }

        # AuthenticAMD
        if ( ($manufacturer -like "*AMD*") -or ($version -like "*AMD*") )
        {
            return "AuthenticAMD"
        }

        # Red Hat (Nutanix)
        if ( $manufacturer -like "*Red Hat*" )
        {
            return "GenuineIntel"
        }

        # ARM
        $family = $this.GetFamily().Value

        if ($(@(0x100..0x103) + 0x118 + 0x119) -contains $family)
        {
            return "ARM"
        }

        return $null
    }
       
    # Get SocketDesignation
    hidden [SMBString]GetSocketDesignation()
    {
        return $this.GetStringAtOffset(0x04)
    }

    # Get Type
    hidden [StringValue]Get_Type()
    {   
        $processorType = $this.GetByteAtOffset(0x05)

        return [StringValue]::new($processorType, "ProcessorType", [ref]$this)
    }
    
    # Get Family
    hidden [StringValue]GetFamily()
    {
        $family = $this.GetByteAtOffset(0x06)

        if ($family -eq 0xFE)
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

        [Byte[]]$array = [BitConverter]::GetBytes([UInt64]$id)
        
        [Byte[]]$reverseArray = [Linq.Enumerable]::Reverse($array)

        $processorId = [BitConverter]::ToString($reverseArray).Replace("-","")

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
        $value = $this.GetWordAtOffset(0x26)
        
        $arm64SocID = [BitField]::Get($value, 9)

        if ($arm64SocID)
        {
            $bank = [BitField]::Extract($signature, 24, 7)

            $manufacturer = [BitField]::Extract($signature, 16, 8)

            $id = [BitField]::Extract($signature, 0, 16)

            $processorID = $this.GetID().Value

            $highWord = [BitField]::HighUInt64($processorID)

            $revision = [BitField]::Extract($highWord, 0, 32)

            $orderedSignature = [Ordered]@{ JEP106Bank = $bank ; JEP106Manufacturer = $manufacturer ; ID = $id ; Revision = $revision }

            return [StringValueOrderedDictionary]::new($orderedSignature)
        }
        else
        {   
            $implementer = [BitField]::Extract($signature, 24, 8)
        
            $variant = [BitField]::Extract($signature, 20, 4)
                
            $arch = [BitField]::Extract($signature, 16, 4)
                
            $part = [BitField]::Extract($signature, 4, 12)

            $revision = [BitField]::Extract($signature, 0, 4)

            $orderedSignature = [Ordered]@{ Implementer = $implementer ; Variant = $variant ; Architecture = $arch ; Part = $part ; Revision = $revision }

            return [StringValueOrderedDictionary]::new($orderedSignature)
        }

        return $null
    }

    # Get Signature
    hidden [StringValueOrderedDictionary]GetSignature()
    {  
        $id = $this.GetQuadWordAtOffset(0x08)

        $signature = [BitField]::LowUInt64($id)

        $vendorID = $this.GetVendorID()

        switch ($vendorID)
        {
            "GenuineIntel"
            {
                return $this.GetSignatureGenuineIntel($signature)
            }
            "AuthenticAMD"
            {
                return $this.GetSignatureAuthenticAMD($signature)
            }
            "ARM"
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
            return [BitFieldConverter]::ToStringValueArray($flags, $vendorID + "Features", [ref]$this)
        }
        else
        {
            return [StringValue]::new(0, 0x00, $null, $(Get-LocalizedString "UNKNOWN"))
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
        if ($value -band 0x80) 
        {            
            [Float]$voltage = ($value -band 0x7F) / 10

            $voltagesList.Add( [StringValue]::new($voltage, "{0:F01} V") )
        }
        elseif (($value -band 0x07) -eq 0x00)
        {
            $voltagesList.Add( [StringValue]::new($value, 0x00, $null, "UNKNOWN") )
        }
        else 
        {    
            $voltageCapability = @(
                [Float]5.0,
                [Float]3.3,
                [Float]2.9
            )

            $voltages = [BitFieldConverter]::ToArray($value, 3, $voltageCapability)

            if ($voltages)
            {
                foreach($voltage in $voltages)
                {
                    $voltagesList.Add( [StringValue]::new($voltage, "{0:F01} V") )
                }  
            }     
        }

        return $voltagesList
    }
    
    # Get ExternalClock
    hidden [StringValue]GetExternalClock()
    {
        $externalClock = $this.GetWordAtOffset(0x12)
        
        if ($externalClock -eq 0)
        {
            return [StringValue]::new($externalClock, 0x00, $null, "UNKNOWN")
        }
        else
        {
            return  [StringValue]::new($externalClock, "{0} MHz")
        }
    }
    
    # Get MaxSpeed
    hidden [StringValue]GetMaxSpeed()
    {
        $maxSpeed = $this.GetWordAtOffset(0x14)
        
        if ($maxSpeed -eq 0)
        {
            return [StringValue]::new($maxSpeed, 0x00, $null, "UNKNOWN")
        }
        else
        {
            return  [StringValue]::new($maxSpeed, "{0} MHz")
        }
    }
    
    # Get CurrentSpeed
    hidden [StringValue]GetCurrentSpeed()
    {
        $currentSpeed = $this.GetWordAtOffset(0x16)
        
        if ($currentSpeed -eq 0)
        {
            return [StringValue]::new($currentSpeed, 0x00, $null, "UNKNOWN")
        }
        else
        {
            return  [StringValue]::new($currentSpeed, "{0} MHz")
        }
    }
    
    # Get SocketPopulated
    hidden [bool]GetSocketPopulated()
    {
        $value = $this.GetByteAtOffset(0x18)

        return [BitField]::Get($value, 6)
    }
    
    # Get Status
    hidden [StringValue]GetStatus()
    {
        $value = $this.GetByteAtOffset(0x18)
        
        $status = [BitField]::Extract($value, 0, 3)

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
                $notLnCache = [String]::Format($(Get-LocalizedString "NOT_LN_CACHE"), $level)

                return [StringValue]::new($handle, $notLnCache)
            }
            else
            {
                return [StringValue]::new($handle, $(Get-LocalizedString "NOT_PROVIDED"))
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
    
    # Get Family2
    hidden [UInt16]GetFamily2()
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

    # Get GetThreadEnabled
    hidden [UInt16]GetThreadEnabled()
    {
        return $this.GetWordAtOffset(0x30)
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
            $labels.Add( "SocketDesignation"       )
            $labels.Add( "BankConnections"         )
            $labels.Add( "CurrentSpeed"            )
            $labels.Add( "CurrentMemoryType"       )
            $labels.Add( "InstalledSize"           )
            $labels.Add( "InstalledSizeConnection" )
            $labels.Add( "EnabledSize"             )
            $labels.Add( "EnabledSizeConnection"   )
            $labels.Add( "ErrorStatus"             )
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
            $connections.Add( [StringValue]::new(-1, $(Get-LocalizedString "NONE")) )
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

        if (($currentMemoryType -band 0x07FF) -eq 0)
        {
            return [StringValue]::new(-1, $(Get-LocalizedString "NONE"))
        }
        else
        {    
            return [BitFieldConverter]::ToStringValueArray($currentMemoryType, "CurrentMemoryType", [ref]$this)
        }
    }

    hidden [StringValueMemorySize]_Size($size)
    {        
        $memorySize = [BitField]::Extract($size, 0, 7)

        if ($memorySize -eq 0x7D)
        {
            return [StringValueMemorySize]::new($size, "_Size", [ref]$this, -1, [MemorySizeUnit]::Unknown)
        }
        elseif ($memorySize -eq 0x7E)
        {
            return [StringValueMemorySize]::new($size, "_Size", [ref]$this, -1, [MemorySizeUnit]::None)
        }
        elseif ($memorySize -eq 0x7F)
        {             
            return [StringValueMemorySize]::new($size, "_Size", [ref]$this, -1, [MemorySizeUnit]::None)
        }
        else
        {
            $effectiveSize = [Math]::Pow(2, $memorySize)

            $unit = [MemorySizeUnit]::MB

            $sizeInBytes = $effectiveSize * 1mb

            return [StringValueMemorySize]::new($sizeInBytes, $unit)
        }
    }

    hidden [StringValue]_SizeConnection($size)
    {
        $connection = [BitField]::Get($size, 8)
        
        if ($size -eq 0x7F)
        {                         
            return [StringValue]::new($connection, $(Get-LocalizedString "NOT_AVAILABLE"))
        }
        else
        {
             return [StringValue]::new($connection, "_Connection", [ref]$this)
        }
    }        

    # Get InstalledSize
    hidden [StringValueMemorySize]GetInstalledSize()
    {
        $installedSize =  $this.GetByteAtOffset(0x09)

        return $this._Size($installedSize)
    }

    # Get InstalledSizeConnection
    hidden [StringValue]GetInstalledSizeConnection()
    {
        $installedSize =  $this.GetByteAtOffset(0x09)

        return $this._SizeConnection($installedSize)
    }

    # Get EnabledSize
    hidden [StringValueMemorySize]GetEnabledSize()
    {
        $enabledSize =  $this.GetByteAtOffset(0x0A)

        return $this._Size($enabledSize)
    }

    # Get EnabledSizeConnection
    hidden [StringValue]GetEnabledSizeConnection()
    {
        $installedSize =  $this.GetByteAtOffset(0x09)

        return $this._SizeConnection($installedSize)
    }

    # Get ErrorStatus
    hidden [StringValue]GetErrorStatus()
    {
        $errorStatus = $this.GetByteAtOffset(0x0B)

        if ($errorStatus -le 0x04)
        {
            return [StringValue]::new($errorStatus, "ErrorStatus", [ref]$this)
        }
        else
        {
            return [StringValue]::new($errorStatus -band 0x03)
        }
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
            return [StringValueMemorySize]::new($maximumSize, "_Size", [ref]$this, -1, [MemorySizeUnit]::None)
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

    hidden [ArrayList]$PropertyNamesEx

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

        [SystemSlots]::PropertyNames = $labels
    }
    
    SystemSlots([Byte]$type, [String]$description, [String[]]$keywords, [Byte]$length, [UInt16]$handle, [Byte[]]$data, [String[]]$strings) : base($type, $description, $keywords, $length, $handle, $data, $strings)
    {
        $labels = [Collections.ArrayList]::new()

        if ( [SMBIOS]::Version -ge [Version]::new(2, 6) )
        {
            $labels.Add( "BusAddress"           )
        }
        if ( [SMBIOS]::Version -ge [Version]::new(3, 2) )
        {
            $labels.Add( "PeerDevices"          )
        }
        if ( [SMBIOS]::Version -ge [Version]::new(3, 4) )
        {
            $labels.Add( "SlotInformation"      )
            $labels.Add( "SlotPhysicalWidth"    )
            $labels.Add( "SlotPitch"            )
        }
        if ( [SMBIOS]::Version -ge [Version]::new(3, 5) )
        {
            $labels.Add( "SlotHeight"           )
        }

        $this.PropertyNamesEx = $labels
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

        return [StringValue]::new($slotDataBusWidth, "_SlotWidth", [ref]$this)
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

        $characteristics2 = 0

        if ( [SMBIOS]::Version -ge [Version]::new(2, 1) )
        {   
            $characteristics2 = $this.GetByteAtOffset(0x0C)
        }

        if (($characteristics1 -band (1 -shl 0)))
        {   
            return [StringValue]::new(0xFE, $(Get-LocalizedString "UNKNOWN"))
        }
        elseif (($characteristics1 -band 0xFE) -eq 0 -and ($characteristics2 -band 7) -eq 0)
        {
            return [StringValue]::new(-1 , $(Get-LocalizedString "NONE"))
        }
        else 
        {
            if ($characteristics1 -gt 0)
            {
                $characteristics =  $characteristics + [BitFieldConverter]::ToStringValueArray($characteristics1, 8, "SlotCharacteristics1", [ref]$this)
            }

            if ( [SMBIOS]::Version -ge [Version]::new(2, 1) -and ($characteristics2 -gt 0) )
            {   
                $characteristics = $characteristics + [BitFieldConverter]::ToStringValueArray($characteristics2, 4, "SlotCharacteristics2", 8, [ref]$this)
            }
        }

        return $characteristics
    }

    # Get BusAddress
    hidden [StringValue]GetBusAddress()
    { 
        return ([SMBIOSStructure]$this).Get_BusAddress(0x0D)   
    }

    # Get PeerDevicesCount
    hidden [Byte]GetPeerDevicesCount()
    {       
        return $this.GetByteAtOffset(0x12)
    }

    # Get PeerDevices
    hidden [StringValue[]]GetPeerDevices()
    {        
        $peerDevicesCount = $this.GetPeerDevicesCount()
        
        if ($peerDevicesCount -eq 0)
        { 
            return [StringValue]::new(-1, $(Get-LocalizedString "NONE"))
        }
        
        $peerDevices = [Collections.ArrayList]::new()

        for ($i = 0; $i -lt $peerDevicesCount; $i++) 
        {
            $segmentGroupNumber = $this.GetWordAtOffset(0x13 + ($i * 5))
            $busNumber = $this.GetByteAtOffset(0x13 + ($i * 5) + 0x02)
            $deviceAndFunctionNumber = $this.GetByteAtOffset(0x13 + ($i * 5) + 0x03)
            $width = $this.GetByteAtOffset(0x13 + ($i * 5) + 0x04)

            if (($segmentGroupNumber -ne 0xFFFF) -or ($busNumber -ne 0xFF) -or ($deviceAndFunctionNumber -ne 0xFF))
            {
                $busAddress = "{0:x4}:{1:x2}:{2:x2}.{3}" -f $segmentGroupNumber, $busNumber, ($deviceAndFunctionNumber -shr 3), ($deviceAndFunctionNumber -band 0x7)
                
                $peerDevice = [StringValue]::new( [Ordered]@{ SegmentGroupNumber = $segmentGroupNumber; 
                                                    BusNumber          = $busNumber;
                                                    DeviceNumber       = ($deviceAndFunctionNumber -shr 3);
                                                    FunctionNumber     = ($deviceAndFunctionNumber -band 0x7);
                                                    Width              = $width }, $busAddress.ToUpper() + $(" (Width {0})" -f $width) )
            }
            else 
            {
                return [StringValue]::new(-1, $(Get-LocalizedString "NOT_DEFINED"))
            }
            
            $peerDevices.Add( $peerDevice )
        }
        
        return $peerDevices
    }

    # Get SlotInformation
    hidden [StringValue]GetSlotInformation()
    {         
        $slotPhysicalWidth = $this.GetByteAtOffset(0x13 + $($this.GetPeerDevicesCount() * 5))

        return [StringValue]::new($slotPhysicalWidth, "_SlotWidth", [ref]$this)
    }

    # Get SlotPhysicalWidth
    hidden [StringValue]GetSlotPhysicalWidth()
    {
        $slotPhysicalWidth = $this.GetByteAtOffset(0x14 + $($this.GetPeerDevicesCount() * 5))

        return [StringValue]::new($slotPhysicalWidth, "_SlotWidth", [ref]$this)
    }

    # Get SlotPitch
    hidden [StringValue]GetSlotPitch()
    {
        $slotPitch = $this.GetWordAtOffset(0x15 + $($this.GetPeerDevicesCount() * 5))
        
        return [StringValue]::new($slotPitch / 100, 0x00, "{0:N1} mm", $slotPitch, "UNKNOWN")
    }
    
    # Get SlotHeight
    hidden [StringValue]GetSlotHeight()
    {
        $height = $this.GetByteAtOffset(0x17 + $($this.GetPeerDevicesCount() * 5))

        return [StringValue]::new($height, "SlotHeight", [ref]$this)
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
    
    [String]ToString() 
    {
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

            $description = $($this.strings[$this.data[5 + 2 * ($i - 1)] - 1])
            
            if ([String]::IsNullOrEmpty($description))
            {
                $description = Get-LocalizedString "NOT_SPECIFIED"
            }

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
        else 
        {
            return [StringValue]::new(-1, $(Get-LocalizedString "NONE"))
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
            
            [Byte[]]$descriptor = [Linq.Enumerable]::ToArray($descriptorSegment)

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
        
        if ( [SMBIOS]::Version -ge [Version]::new(2, 1) )
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

        $unit = [MemorySizeUnit]::Auto

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

    hidden [ArrayList]$PropertyNamesEx

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

        [MemoryDevice]::PropertyNames = $labels   
    }

    MemoryDevice([Byte]$type, [String]$description, [String[]]$keywords, [Byte]$length, [UInt16]$handle, [Byte[]]$data, [String[]]$strings) : base($type, $description, $keywords, $length, $handle, $data, $strings)
    {   
        $labels = [Collections.ArrayList]::new()

        if ( [SMBIOS]::Version -ge [Version]::new(2, 6) )
        {
            $labels.Add( "Rank"                                    )
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
        if ( [SMBIOS]::Version -ge [Version]::new(3, 7) )
        {
            $labels.Add( "PMIC0ManufacturerID"                     )
            $labels.Add( "PMIC0RevisionNumber"                     )
            $labels.Add( "RCDManufacturerID"                       )
            $labels.Add( "RCDRevisionNumber"                       )
        }

        $this.PropertyNamesEx = $labels
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

        return [StringValue]::new($totalWidth, @(0x00, 0xFFFF), "{0} bits", "UNKNOWN")
    }

    # Get DataWidth
    hidden [StringValue]GetDataWidth()
    {
        $dataWidth = $this.GetWordAtOffset(0x0A)  

        return [StringValue]::new($dataWidth, @(0x00, 0xFFFF), "{0} bits", "UNKNOWN")
    }

    # Get Size
    hidden [StringValueMemorySize]GetSize()
    {
        $size = $this.GetWordAtOffset(0x0C) 

        $sizeInBytes = 0

        if ($size -eq 0x0000)
        {
            return [StringValueMemorySize]::new($size, "Size", [ref]$this, -1, [MemorySizeUnit]::None)
        }

        if ($size -eq 0xFFFE)
        {
            return [StringValueMemorySize]::new($size, "Size", [ref]$this, -1, [MemorySizeUnit]::Unknown)
        }

        if ($size -eq 0x7FFF)
        {
            $size = $this.ExtendedSize()

            $effectiveSize = [BitFieldConverter]::ToInt($size, 0, 30)

            $sizeInBytes = $effectiveSize * 1mb
        }
        else 
        {
            $effectiveSize = $size -band 0x7FFF

            if ($size -band (1 -shl 15))
            { 
                $sizeInBytes = $effectiveSize * 1kb
            }
            else
            {
                $sizeInBytes = $effectiveSize * 1mb
            }
        }
        
        $unit = [MemorySizeUnit]::Auto

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

    # Get Rank
    hidden [StringValue]GetRank()
    {
        $attributes = $this.GetByteAtOffset(0x1B)

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
            return [StringValueMemorySize]::new(0xFFFF, "OtherSize", [ref]$this, -1, [MemorySizeUnit]::Unknown)
        }
        elseif (([BitField]::LowUInt64($size) -eq 0x00) -and ([BitField]::HighUInt64($size) -eq 0x00))
        {            
            return [StringValueMemorySize]::new($size, "OtherSize", [ref]$this, -1, [MemorySizeUnit]::None)
        }
        else
        {
            $unit = [MemorySizeUnit]::Auto
            
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

    # Get ExtendedSpeed
    hidden [UInt32]ExtendedSpeed()
    {
        return $this.GetDoubleWordAtOffset(0x54) -band [UInt32]0x7FFFFFFF
    }

    # Get ExtendedConfiguredMemorySpeed
    hidden [UInt32]ExtendedConfiguredMemorySpeed()
    {
        return $this.GetDoubleWordAtOffset(0x58) -band [UInt32]0x7FFFFFFF
    }

    # Get PMIC0ManufacturerID
    hidden [UInt16]PMIC0ManufacturerID()
    {
        return $this.GetWordAtOffset(0x5C)
    }

    # Get PMIC0RevisionNumber
    hidden [UInt16]PMIC0RevisionNumber()
    {
        return $this.GetWordAtOffset(0x5E)
    }

    # Get RCDManufacturerID
    hidden [UInt16]RCDManufacturerID()
    {
        return $this.GetWordAtOffset(0x60)
    }

    # Get RCDRevisionNumber
    hidden [UInt16]RCDRevisionNumber()
    {
        return $this.GetWordAtOffset(0x62)
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

        return [StringValue]::new([UInt64]$startingAddress * 1kb, "0x{0:X16}")
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

        return [StringValue]::new([UInt64]$endingAddress * 1kb + 1023, "0x{0:X16}")
    }

    # Get RangeSize
    hidden [StringValueMemorySize]GetRangeSize()
    {
        $startingAddress = $this.GetStartingAddress().Value

        $endingAddress = $this.GetEndingAddress().Value

        if ($startingAddress -eq $endingAddress)
        {
            return [StringValueMemorySize]::new(0, [MemorySizeUnit]::B)
        }

        $size = $endingAddress - $startingAddress + 1

        $unit = [MemorySizeUnit]::Auto

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

        return [StringValue]::new([UInt64]$startingAddress * 1kb, "0x{0:X16}")    
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

        return [StringValue]::new([UInt64]$endingAddress * 1kb + 1023, "0x{0:X16}")    
    }

    # Get RangeSize
    hidden [StringValueMemorySize]GetRangeSize()
    {
        $startingAddress = $this.GetStartingAddress().Value

        $endingAddress = $this.GetEndingAddress().Value

        if ($startingAddress -eq $endingAddress)
        {
            return [StringValueMemorySize]::new(0, [MemorySizeUnit]::B)
        }

        $size = $endingAddress - $startingAddress + 1

        $unit = [MemorySizeUnit]::Auto

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
            return [StringValueDateTime]::new($null, $(Get-LocalizedString "UNKNOWN"))
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

        if ( [SMBIOS]::Version -ge [Version]::new(2, 2) )
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
            $labels.Add( "NextScheduledPowerOn" )
        }

        [SystemPowerControls]::PropertyNames = $labels 
    }

    SystemPowerControls([Byte]$type, [String]$description, [String[]]$keywords, [Byte]$length, [UInt16]$handle, [Byte[]]$data, [String[]]$strings) : base($type, $description, $keywords, $length, $handle, $data, $strings)
    {
    }

    hidden [StringValueDateTime]GetNextScheduledPowerOn()
    {
        $schedule = [ArraySegment[Byte]]::new($this.Data, 4, 5)

        if ([Linq.Enumerable]::Sum([Int[]]$schedule) -eq 0)
        {   
            return [StringValueDateTime]::new($null, $(Get-LocalizedString "NOT_DEFINED"))   
        }
        else
        {
            $currentDate = Get-Date

            $year = $currentDate.Year
            
            $month  = $this.ValidateData(4, @(1..12), $currentDate.Month)

            $day    = $this.ValidateData(5, @(1..31), $currentDate.Day)

            $hour   = $this.ValidateData(6, @(0..23), $currentDate.Hour)

            $minute = $this.ValidateData(7, @(0..59), $currentDate.Minute)

            $second = $this.ValidateData(8, @(0..59), $currentDate.Second)

            $nextScheduledPowerOn = [DateTime]::new($year, $month, $day, $hour, $minute, $second)

            if ($nextScheduledPowerOn -lt $currentDate)
            {
                $nextScheduledPowerOn = $nextScheduledPowerOn.AddYears(1)
            }

            $format = [CultureInfo]::CurrentCulture.DateTimeFormat.FullDateTimePattern

            return [StringValueDateTime]::new($nextScheduledPowerOn, "{0:$format}")    
        }
    }

    hidden [Int]ValidateData([Int]$offset, [Array]$range, [Int]$defaultResult)
    {
        $unitOftime = [Int][BitConverter]::ToString($this.Data, $offset, 1)
    
        if (-Not ($unitOftime -in $range) )
        {
            $unitOftime = $defaultResult
        }
    
        return $unitOftime
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
        $deviceTypeAndStatus = 103 #$this.GetByteAtOffset(0x06)
        
        $deviceType = [BitField]::Extract($deviceTypeAndStatus, 0, 5)

        return [StringValue]::new($deviceType, "DeviceType", [ref]$this)     
    }

    # Get Status
    hidden [StringValue]GetStatus()
    {
        $deviceTypeAndStatus = 103 #$this.GetByteAtOffset(0x06)
        
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
            return [StringValueTemperature]::new($temperature, $(Get-LocalizedString "UNKNOWN")) 
        }
        else
        {
            return [StringValueTemperature]::new($temperature / 10, [TemperatureUnit]::Celsius, 1)
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
            return [StringValueTemperature]::new($resolution, $(Get-LocalizedString "UNKNOWN"))
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
        
        if ( [SMBIOS]::Version -ge [Version]::new(2, 2) )
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
            $labels.Add( "Checksum"               )
            $labels.Add( "16bitEntryPointAddress" )
            $labels.Add( "32bitEntryPointAddress" )
        }

        [BootIntegrityServicesEntryPoint]::PropertyNames = $labels 
    }

    BootIntegrityServicesEntryPoint([Byte]$type, [String]$description, [String[]]$keywords, [Byte]$length, [UInt16]$handle, [Byte[]]$data, [String[]]$strings) : base($type, $description, $keywords, $length, $handle, $data, $strings)
    {
    }
    
    # Calculate Checksum
    hidden [bool]CalculateChecksum([byte[]]$data) 
    {
        $checksum = 0

        for ($i = 0; $i -lt $data.Length; $i++)
        {
            $checksum = $checksum -bxor $data[$i]
        }

        return $checksum
    }

    # Get Checksum
    hidden [StringValue]GetChecksum()
    {
        if ($this.Checksum($this.Data))
        {
            return [StringValue]::new($true, $(Get-LocalizedString "OK"))
        }
        else 
        {
            return [StringValue]::new($false, $(Get-LocalizedString "INVALID"))
        }
    }

    # Get 16bitEntryPointAddress
    hidden [StringValue]Get16bitEntryPointAddress()
    {
        $bisEntry16 = $this.GetDoubleWordAtOffset(0x08)
        
        $segment = $bisEntry16 -shr  16
        $offset  = $bisEntry16 -band 0xFFFF
        
        $string = [String]::Format("{0:X4}:{1:X4}", $segment, $offset)

        $value = [Ordered]@{ Segment = $([StringValue]::new($segment, [String]::Format("{0:X4}", $segment))); 
                             Offset  = $([StringValue]::new($offset,  [String]::Format("{0:X4}", $offset ))) }

        return [StringValue]::new($value, $string)
    }

    # Get 32bitEntryPointAddress
    hidden [StringValue]Get32bitEntryPointAddress()
    {
        $bisEntry32 = $this.GetDoubleWordAtOffset(0x0C)
        
        return [StringValue]::new($bisEntry32, "0x{0:X8}")  
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
            return [StringValue]::new($memoryArrayErrorAddress, $(Get-LocalizedString "UNKNOWN")) 
        }

        return [StringValue]::new($memoryArrayErrorAddress, "0x{0:X16}")
    }

    # Get DeviceErrorAddress
    hidden [StringValue]GetDeviceErrorAddress()
    {
        $deviceErrorAddress = $this.GetQuadWordAtOffset(0x13)

        if (([BitField]::HighUInt64($deviceErrorAddress) -eq -0x80000000) -and ([BitField]::LowUInt64($deviceErrorAddress) -eq 0x00))
        {
            return [StringValue]::new($deviceErrorAddress, $(Get-LocalizedString "UNKNOWN")) 
        }

        return [StringValue]::new($deviceErrorAddress, "0x{0:X16}")  
    }

    # Get ErrorResolution
    hidden [StringValue]GetErrorResolution()
    {
        $errorResolution = $this.GetDoubleWordAtOffset(0x1B)

        return [StringValue]::new($errorResolution, -0x80000000, "0x{0:X16}", $(Get-LocalizedString "UNKNOWN"))
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
class MemoryChannelDevice
{
    [String]$Load
    [UInt16]$Handle
    
    MemoryChannelDevice([String]$load, [UInt16]$handle)
    {
        $this.Load = $load
        $this.Handle = $handle
    }

    [String]ToString()
    {
        return [String]::Format("Load {0} Handle 0x{1:X4}", $($this.Load),$($this.Handle))
    }
}

class MemoryChannel : SMBIOSStructure 
{    
    hidden static [Hashtable]$StringArrays
    hidden static [Hashtable]$StringArrayNameAlias

    static [Array]$PropertyNames

    static MemoryChannel()
    {
        $stringTables = [MemoryChannel]::GetStringTables("Type_37")

        [MemoryChannel]::StringArrays = $stringTables.StringArrays
                                
        [MemoryChannel]::StringArrayNameAlias = $stringTables.StringArrayNameAlias
        
        $labels = [Collections.ArrayList]::new() 
        
        if ( [SMBIOS]::Version -ge [Version]::new(2, 3, 1) )
        {
            $labels.Add( "_Type"       )
            $labels.Add( "MaximumLoad" )
            $labels.Add( "Devices"     )
        }

        [MemoryChannel]::PropertyNames = $labels 
    }

    MemoryChannel([Byte]$type, [String]$description, [String[]]$keywords, [Byte]$length, [UInt16]$handle, [Byte[]]$data, [String[]]$strings) : base($type, $description, $keywords, $length, $handle, $data, $strings)
    {    
    }

    # Get ChannelType
    hidden [StringValue]Get_Type()
    {
        $channelType = $this.GetByteAtOffset(0x04)

        return [StringValue]::new($channelType, "ChannelType", [ref]$this)
    }

    # Get MaximumLoad
    hidden [Int]GetMaximumLoad()
    {
        $maximumLoad = $this.GetByteAtOffset(0x05)

        return $maximumLoad
    }

    # Get Devices
    hidden [Array]GetDevices()
    {
        $deviceCount = $this.GetByteAtOffset(0x06)

        $devices = [Collections.ArrayList]::new() 

        for ($i = 0; $i -lt $deviceCount; $i++)
        {
            $load = $this.GetByteAtOffset(0x07 + 3 * $i)
            
            $handle = [BitConverter]::ToUInt16($this.data, 0x07 + 3 * $i + 1) 

            $devices.Add( [MemoryChannelDevice]::new($load, $handle) )
        }
        
        return $devices
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
        $stringTables = [IPMIDeviceInformation]::GetStringTables("Type_38")

        [IPMIDeviceInformation]::StringArrays = $stringTables.StringArrays
                                
        [IPMIDeviceInformation]::StringArrayNameAlias = $stringTables.StringArrayNameAlias
        
        $labels = [Collections.ArrayList]::new() 
        
        if ( [SMBIOS]::Version -ge [Version]::new(2, 3, 1) )
        {
            $labels.Add( "InterfaceType"          )
			$labels.Add( "SpecificationRevision"  )
            $labels.Add( "I2CTargetAddress"       )
            $labels.Add( "I2CSlaveAddress"        )
            $labels.Add( "NVStorageDeviceAddress" )
            $labels.Add( "BaseAddress"            )
            $labels.Add( "Bus"                    )
            $labels.Add( "RegisterSpacing"        )
            $labels.Add( "InterruptPolarity"      )
            $labels.Add( "InterruptTriggerMode"   )
            $labels.Add( "InterruptNumber"        )
        }

        [IPMIDeviceInformation]::PropertyNames = $labels 
    }

    IPMIDeviceInformation([Byte]$type, [String]$description, [String[]]$keywords, [Byte]$length, [UInt16]$handle, [Byte[]]$data, [String[]]$strings) : base($type, $description, $keywords, $length, $handle, $data, $strings)
    {
    }

    # Get InterfaceType
    hidden [StringValue]GetInterfaceType()
    {
        $interfaceType = $this.GetByteAtOffset(0x04)

        return [StringValue]::new($interfaceType, "InterfaceType", [ref]$this)
    }

    # Get SpecificationRevision
    hidden [Version]GetSpecificationRevision()
    {
        $revision = $this.GetByteAtOffset(0x05)
        
        $major = [BitField]::Extract($revision, 4, 4)

        $minor = [BitField]::Extract($revision, 0, 4)

        return [Version]::new($major, $minor)
    }

    # Get I2CTargetAddress
    hidden [StringValue]GetI2CTargetAddress()
    {
        $I2CTargetAddress = $this.GetByteAtOffset(0x06)

        return [StringValue]::new($I2CTargetAddress, "0x{0:X2}")
    }

    # Get I2CSlaveAddress
    hidden [StringValue]GetI2CSlaveAddress()
    {
        $I2CTargetAddress = $this.GetByteAtOffset(0x06)

        return [StringValue]::new($I2CTargetAddress -shr 1, "0x{0:X2}")
    }

    # Get NVStorageDeviceAddress
    hidden [StringValue]GetNVStorageDeviceAddress()
    {
        $NVStorageDeviceAddress = $this.GetByteAtOffset(0x07)

        return [StringValue]::new($NVStorageDeviceAddress, 0xFF, "0x{0:X}", "NOT_PRESENT")
    }

    # Get BaseAddress
    hidden [StringValue]GetBaseAddress()
    {
        $interfaceType = $this.GetByteAtOffset(0x04)

        $baseAddress = $this.GetQuadWordAtOffset(0x08)

        if ($interfaceType -eq 0x04)
        {
            $format = "0x{0:X2}"

            $baseAddress = [BitField]::Extract($baseAddress, 0, 7)
        }
        else
        {
            [UInt32]$baseAddressHigh = [BitField]::HighUInt64($baseAddress)
            [UInt32]$baseAddressLow  = [BitField]::LowUInt64($baseAddress) -shr 1

            $format = "0x{0:X8}{1:X8}"

            $string = [String]::Format($format, $baseAddressLow, $baseAddressHigh)

            return [StringValue]::new($baseAddress, $string)
            
        }

       return [StringValue]::new() 
    }

    # Get Bus
    hidden [StringValue]GetBus()
    {
        $interfaceType = $this.GetByteAtOffset(0x04)

        if ($interfaceType -eq 0x04)
        {
            $bus = 0x04
        }
        else
        {
            $baseAddress = $this.GetQuadWordAtOffset(0x08)
            $lowPart = [BitField]::LowUInt64($baseAddress)
            $bus = [BitField]::Get($lowPart, 0)
        }

        return [StringValue]::new($bus, "Bus", [ref]$this)
    }

    # Get BaseAddressModifier
    hidden [StringValue]BaseAddressModifier()
    {
        $baseAddressModifier = $this.GetByteAtOffset(0x10)
        
        return [StringValue]::new($baseAddressModifier, 0x00, "{0:G}", "UNUSED")
    }

    # Get RegisterSpacing
    hidden [StringValue]GetRegisterSpacing()
    {
        $interfaceType = $this.GetByteAtOffset(0x04)

        if ($interfaceType -eq 0x04)
        {            
            return [StringValue]::new(-1, $(Get-LocalizedString "NOT_APPLICABLE"))
        }
        else
        {   
            $baseAddressModifier = $this.GetByteAtOffset(0x10)

            $registerSpacing = [BitField]::Extract($baseAddressModifier, 6, 2)

            return [StringValue]::new($registerSpacing, "RegisterSpacing", [ref]$this)
        }
    }

    # Get InterruptPolarity
    hidden [StringValue]GetInterruptPolarity()
    {
        $interfaceType = $this.GetByteAtOffset(0x04)

        if ($interfaceType -eq 0x04)
        {
            return [StringValue]::new(-1, $(Get-LocalizedString "NOT_APPLICABLE"))
        }
        else
        {
            $baseAddressModifier = $this.GetByteAtOffset(0x10)
            
            $interruptInfo = [BitField]::Get($baseAddressModifier, 4)

            if ($interruptInfo)
            {
                $interruptPolarity = [BitField]::Get($baseAddressModifier, 1)
            
                return [StringValue]::new($interruptPolarity, "InterruptPolarity", [ref]$this)
            }
            else
            {
                return [StringValue]::new(-1, $(Get-LocalizedString "NOT_APPLICABLE"))
            }
        }
    }

    # Get InterruptTriggerMode
    hidden [StringValue]GetInterruptTriggerMode()
    {
        $interfaceType = $this.GetByteAtOffset(0x04)

        if ($interfaceType -eq 0x04)
        {
            return [StringValue]::new(-1, $(Get-LocalizedString "NOT_APPLICABLE"))
        }
        else
        {
            $baseAddressModifier = $this.GetByteAtOffset(0x10)
            
            $interruptInfo = [BitField]::Get($baseAddressModifier, 4)

            if ($interruptInfo)
            {
                $interruptTriggerMode = [BitField]::Get($baseAddressModifier, 0)
            
                return [StringValue]::new($interruptTriggerMode, "InterruptTriggerMode", [ref]$this)
            }
            else
            {
                return [StringValue]::new(-1, $(Get-LocalizedString "NOT_APPLICABLE"))
            }
        }
    }

    # Get InterruptNumber
    hidden [StringValue]GetInterruptNumber()
    {
       $interruptNumber = $this.GetByteAtOffset(0x11)

       return [StringValue]::new($interruptNumber, 0x00, "{0:G}", $(Get-LocalizedString "UNSPECIFIED"))
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
        
        if ( [SMBIOS]::Version -ge [Version]::new(2, 3, 1) )
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
            $labels.Add( "BusAddress"           )
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

    # Get BusAddress
    hidden [StringValue]GetBusAddress()
    {
        return ([SMBIOSStructure]$this).Get_BusAddress(0x07)
    }
}


###################################################################################################################################
# Type 42                                                                                                                         #
###################################################################################################################################
enum IPAddressFormat {
    Unknown = 0x00
    IPv4    = 0x01
    IPv6    = 0x02
}

enum AssignmentOrDiscovery {
    Unknown       = 0x00
    Static        = 0x01
    DHCP          = 0x02
    AutoConfigure = 0x03
    HostSelected  = 0x04
}

class ManagementControllerHostInterface : SMBIOSStructure 
{    
    hidden static [Hashtable]$StringArrays
    hidden static [Hashtable]$StringArrayNameAlias

    hidden static [ArrayList]$PropertyNames

    hidden [ArrayList]$PropertyNamesEx

    static ManagementControllerHostInterface()
    {
        $stringTables = [ManagementControllerHostInterface]::GetStringTables("Type_42")
        
        [ManagementControllerHostInterface]::StringArrays = $stringTables.StringArrays
                                
        [ManagementControllerHostInterface]::StringArrayNameAlias = $stringTables.StringArrayNameAlias
        
        $labels = [Collections.ArrayList]::new()

        [ManagementControllerHostInterface]::PropertyNames = $labels 
    }

    ManagementControllerHostInterface([Byte]$type, [String]$description, [String[]]$keywords, [Byte]$length, [UInt16]$handle, [Byte[]]$data, [String[]]$strings) : base($type, $description, $keywords, $length, $handle, $data, $strings)
    {
        $labels = [Collections.ArrayList]::new() 
        
        if ( [SMBIOS]::Version -lt [Version]::new(3, 2) )
        {
            $labels.Add( "InterfaceType" )

            $interfaceType = $this.GetByteAtOffset(0x04)

            # OEM
            if ( ( $interfaceType -eq 0xF0 ) -and ( $this.Data.Length -ge 0x09 ) )
            {
                $labels.Add( "VendorID")
            }
        }
        if ( [SMBIOS]::Version -ge [Version]::new(3, 2) )
        {
            $labels.Add( "HostInterfaceType" )
            $labels.Add( "DeviceType"        )

            $interfaceSpecificDataLength = $this.GetByteAtOffset(0x05)

            if ($interfaceSpecificDataLength -gt 0)
            {
                $deviceType = $this.GetByteAtOffset(0x06)

                switch ($deviceType)
                { 
                    0x02 { # USB Network Interface
                        $labels.Add( "VendorID"                      )
                        $labels.Add( "ProductID"                     )
                        $labels.Add( "SerialNumber"                  )
                    }
                    0x03 { # PCI/PCIe Network Interface
                        $labels.Add( "VendorID"                      )
                        $labels.Add( "ProductID"                     )
                        $labels.Add( "SubsystemVendorID"             )
                        $labels.Add( "SubsystemID"                   )
                    }
                    0x04 { # USB Network Interface v2
                        $labels.Add( "VendorID"                      )
                        $labels.Add( "ProductID"                     )
                        $labels.Add( "SerialNumber"                  )
                        $labels.Add( "MACAddress"                    )
                        
                        if ( $interfaceSpecificDataLength -eq 0x11 ) # v1.3
                        {
                            $labels.Add( "Characteristics"               )
                            $labels.Add( "CredentialBootstrappingHandle" )
                        }
                    }
                    0x05 { # PCI/PCIe Network Interface v2
                        $labels.Add( "VendorID"                      )
                        $labels.Add( "ProductID"                     )
                        $labels.Add( "SubsystemVendorID"             )
                        $labels.Add( "SubsystemID"                   )
                        $labels.Add( "MACAddress"                    )
                        $labels.Add( "BusAddress"                    )
                        
                        if ( $interfaceSpecificDataLength -eq 0x18 ) # v1.3
                        {              
                            $labels.Add( "Characteristics"               )
                            $labels.Add( "CredentialBootstrappingHandle" )
                        }
                    }
                    {$_ -ge 0x80 -and $_ -le 0xFF} 
                    { # OEM
                        $labels.Add( "VendorIANA"                    )
                        $labels.Add( "VendorData"                    )
                    }
                }
            }

            $interfaceTypeDataLength = $this.GetByteAtOffset(0x05)
    
            $protocolsCount = $this.GetByteAtOffset(0x06 + $interfaceTypeDataLength)

            if ($protocolsCount -gt 0)
            {
                $labels.Add( "ProtocolType" )

                $base = 0x08 + $interfaceTypeDataLength

                $protocolType = $this.GetByteAtOffset($base + 0x00)

                switch ($protocolType) {
                    0x04 { # RedfishOverIP
                        $labels.Add( "ServiceUUID"                   )
                        $labels.Add( "HostIPAssignmentType"          )
                        $labels.Add( "HostIPAddress"                 )
                        $labels.Add( "HostIPMask"                    )
                        $labels.Add( "RedfishServiceIPDiscoveryType" )
                        $labels.Add( "RedfishServiceIPAddress"       )
                        $labels.Add( "RedfishServiceIPMask"          )
                        $labels.Add( "RedfishServiceIPPort"          )
                        $labels.Add( "RedfishServiceVlanId"          )
                        $labels.Add( "RedfishServiceHostname"        )
                        break
                    }
                    Default {
                        $labels.Add( "Protocols"                     )
                    }
                }
            }
        }
        
        $this.PropertyNamesEx = $labels
    }

    # Get InterfaceType
    hidden [StringValue]GetInterfaceType()
    {
        $interfaceType = $this.GetByteAtOffset(0x04) 

        return [StringValue]::new($interfaceType, "InterfaceType", [ref]$this)
    }

    # Get HostInterfaceType
    hidden [StringValue]GetHostInterfaceType()
    {
        return $this.GetInterfaceType()
    }
    
    hidden [StringValue]GetDeviceType()
    {        
        $deviceType = $this.GetByteAtOffset(0x06)

        return [StringValue]::new($deviceType, "DeviceType", [ref]$this)
    }

    hidden [StringValue]GetVendorID()
    {
        if ( [SMBIOS]::Version -lt [Version]::new(3, 2) ) 
        {
            $vendorId = [Byte[]][ArraySegment[Byte]]::new($this.data, 0x05, 4)
            
            return [StringValue]::new($vendorId, [String]::Format("0x{0:X2}{1:X2}{2:X2}{3:X2}", $vendorId[0x00], $vendorId[0x01], $vendorId[0x02], $vendorId[0x03] ) )      
        }
        else 
        {
            $deviceType = $this.GetByteAtOffset(0x06)

            $offset = 0
    
            switch ($deviceType) {
                0x04 { $offset = 0x01 } # USB Network Interface v2
                0x05 { $offset = 0x01 } # PCI/PCIe Network Interface v2
            }

            $vendorId = $this.GetWordAtOffset(0x07 + $offset)
        }

        return [StringValue]::new($vendorId, "0x{0:X4}")
    }

    hidden [StringValue]GetProductID()
    {
        $deviceType = $this.GetByteAtOffset(0x06)

        $offset = 0

        switch ($deviceType) {
            0x04 { $offset = 0x01 } # USB Network Interface v2
            0x05 { $offset = 0x01 } # PCI/PCIe Network Interface v2
        }
        
        $productId = $this.GetWordAtOffset(0x07 + $offset + 0x02)

        return [StringValue]::new($productId, "0x{0:X4}")
    }

    hidden [SMBString]GetSerialNumber()
    {    
        $deviceType = $this.GetByteAtOffset(0x06)

        switch ($deviceType) 
        {
            0x02 { # USB Network Interface
                $serialNumberLength = $this.GetByteAtOffset(0x07 + 0x04) - 2

                $rawSerialNumber = [ArraySegment[Byte]]::new($this.data, 0x07 + 0x06, $serialNumberLength)
                
                $serialNumber = [UnicodeEncoding]::Unicode.GetString($rawSerialNumber)
                
                if ($serialNumberLength -eq 0)
                {
                    return $this.GetStringAtOffset(0xFF)
                }
                else
                {
                    return [SMBString]::new($serialNumber)
                }
            }
            0x04 { # USB Network Interface v2

                return $this.GetStringAtOffset(0x07 + 0x05)
            }
        }

        return [StringValue]::new()      
    }
    
    # Get SubsystemVendorID
    hidden [StringValue]GetSubsystemVendorID()
    {
        $deviceType = $this.GetByteAtOffset(0x06)

        $offset = 0

        switch ($deviceType) {
            0x05 { $offset = 0x01 }
        }
        
        $subsystemVendorID = $this.GetWordAtOffset(0x07 + $offset + 0x04)

        return [StringValue]::new($subsystemVendorID, "0x{0:X4}")
    }

    # Get SubsystemID
    hidden [StringValue]GetSubsystemID()
    {
        $deviceType = $this.GetByteAtOffset(0x06)

        $offset = 0

        switch ($deviceType) {
            0x05 { $offset = 0x01 }
        }
        
        $subsystemID = $this.GetWordAtOffset(0x07 + $offset + 0x06)

        return [StringValue]::new($subsystemID, "0x{0:X4}")
    }

    # Get MACAddress
    hidden [StringValue]GetMACAddress()
    {
        $deviceType = $this.GetByteAtOffset(0x06)

        $offset = 0

        switch ($deviceType) {
            0x04 { $offset = 0x06 } # USB Network Interface v2
            0x05 { $offset = 0x09 } # PCI/PCIe Network Interface v2
        }

        $MACAddress = [Byte[]][Linq.Enumerable]::Reverse( [ArraySegment[Byte]]::new($this.data, 0x07 + $offset, 6) )

        return [StringValue]::new( [PhysicalAddress]::new($MACAddress), [BitConverter]::ToString($MACAddress) )
    }

    # Get Address
    hidden [StringValue]GetBusAddress()
    {
        return ([SMBIOSStructure]$this).Get_BusAddress(0x0F)
    }
   
    # Get Characteristics
    hidden [StringValue[]]GetCharacteristics()
    {
        $deviceType = $this.GetByteAtOffset(0x06)

        $offset = 0

        switch ($deviceType) {
            0x04 { $offset = 0x0C } # USB Network Interface v2
            0x05 { $offset = 0x13 } # PCI/PCIe Network Interface v2
        }
        
        $characteristics = $this.GetWordAtOffset(0x07 + $offset)

        return [BitFieldConverter]::ToStringValueArray($characteristics, 1, "Characteristics", [ref]$this)
    }

    # Get CredentialBootstrappingHandle
    hidden [StringValue]GetCredentialBootstrappingHandle()
    {
        $deviceType = $this.GetByteAtOffset(0x06)

        $offset = 0

        switch ($deviceType) {
            0x04 { $offset = 0x0E } # USB Network Interface v2
            0x05 { $offset = 0x15 } # PCI/PCIe Network Interface v2
        }

        $handle = $this.GetWordAtOffset(0x07 + $offset)

        if ($handle -eq [UInt16]::MaxValue)
        {         
            return [StringValue]::new($handle, $(Get-LocalizedString "NOT_SUPPORTED"))
        }
        else
        {
            return [StringValue]::new($handle, "0x{0:X4}")
        }

    }
   
    # Get VendorIANA
    hidden [StringValue]GetVendorIANA()
    {
        $vendorIANA = [Byte[]][ArraySegment[Byte]]::new($this.data, 0x07, 4)

        return [StringValue]::new($vendorIANA, [String]::Format("0x{0:X2}{1:X2}{2:X2}{3:X2}", $vendorIANA[0x00], $vendorIANA[0x01], $vendorIANA[0x02], $vendorIANA[0x03] ) ) 
    }

    # Get VendorData
    hidden [StringValue]GetVendorData()
    {
        $vendorData = [Byte[]][ArraySegment[Byte]]::new($this.data, 0x07 + 0x04, $this.Data.Length - 0x07 - 0x04) 

        if ($vendorData.Length -eq 0)
        {
            return [StringValue]::new(-1, $(Get-LocalizedString "NONE"))
        }
        else 
        {
            return [StringValue]::new($vendorData, [BitConverter]::ToString($vendorData).Replace("-", "") ) 
        }  
    }

    # Get GetProtocolBaseAddress
    hidden [Int]GetProtocolBaseAddress()
    {
        $interfaceTypeDataLength = $this.GetByteAtOffset(0x05)

        $base = 0x08 + $interfaceTypeDataLength + 0x02

        return $base
    }

    # Get GetProtocolType
    hidden [StringValue]GetProtocolType()
    {
        $interfaceTypeDataLength = $this.GetByteAtOffset(0x05)
        
        $base = 0x08 + $interfaceTypeDataLength

        $protocolType = $this.GetByteAtOffset($base + 0x00)

        return [StringValue]::new($protocolType, "ProtocolType", [ref]$this)
    }

    # Get ServiceUUID
    hidden [StringValue]GetServiceUUID()
    {
        $base = $this.GetProtocolBaseAddress()
        
        $serviceUUID = [Byte[]][ArraySegment[Byte]]::new($this.data, $base + 0x00, 16)

        $guid = [Guid]::new($serviceUUID).Guid.ToUpper()

        return [StringValue]::new([Guid]::new($serviceUUID), $guid)
    }

    # Get IPAssignmentOrDiscoveryType
    hidden [StringValue]GetIPAssignmentOrDiscoveryType([int]$offset)
    {
        $base = $this.GetProtocolBaseAddress()
        
        $hostIPAssignmentType = $this.GetByteAtOffset($base + $offset)

        return [StringValue]::new($hostIPAssignmentType, "AssignmentType", [ref]$this)
    }

    # Get IPAddressFormat
    hidden [StringValue]GetIPAddressFormat([int]$offset)
    {
        $base = $this.GetProtocolBaseAddress()
        
        $IPAddressFormat = $this.GetByteAtOffset($base + $offset)

        return [StringValue]::new($IPAddressFormat, "IPAddressFormat", [ref]$this)
    }

    # Get IsStaticOrAutoConfigure
    hidden [bool]IsStaticOrAutoConfigure([int]$offset)
    {
        $assignmentOrDiscoveryType = $this.GetIPAssignmentOrDiscoveryType($offset)

        if ( ($assignmentOrDiscoveryType.Value -eq  [AssignmentOrDiscovery]::Static ) -or ($assignmentOrDiscoveryType.Value -eq [AssignmentOrDiscovery]::AutoConfigure) )
        {
            return $true
        }
    
        return $false
    }

    # Get IPAddress
    hidden [StringValue]GetIPAddress([int]$offset, [StringValue]$IPAddressFormat, [bool]$IsStaticOrAutoConfigure)
    {
        
        if ($IsStaticOrAutoConfigure)
        {
            $base = $this.GetProtocolBaseAddress()
            
            $IPAddress = 0

            $IPAddressLength = 0

            if ($IPAddressFormat.Value -eq [IPAddressFormat]::IPv4)
            {
                $IPAddressLength = 4
            }
            elseif ($IPAddressFormat.Value -eq [IPAddressFormat]::IPv6) 
            {
                $IPAddressLength = 16
            }
            else 
            {
                $IPAddressLength = 0
            }
            
            $IPAddress = [Byte[]][ArraySegment[Byte]]::new($this.data, $base + $offset, $IPAddressLength)

            return [StringValue]::new([IPAddress]::new($IPAddress))
        }

        return [StringValue]::new(-1, $(Get-LocalizedString "NOT_DEFINED"))
    }

    # Get HostIPAssignmentType
    hidden [StringValue]GetHostIPAssignmentType()
    {
        return $this.GetIPAssignmentOrDiscoveryType(0x10)
    }

    # Get HostIPAddress
    hidden [StringValue]GetHostIPAddress()
    {
        return $this.GetIPAddress(0x12, $this.GetIPAddressFormat(0x11), $this.IsStaticOrAutoConfigure(0x10))
    }
    
    hidden [StringValue]GetHostIPMask()
    {
        return $this.GetIPAddress(0x22, $this.GetIPAddressFormat(0x11), $this.IsStaticOrAutoConfigure(0x10))
    }

    # Get RedfishServiceIPDiscoveryType
    hidden [StringValue]GetRedfishServiceIPDiscoveryType()
    {
        return $this.GetIPAssignmentOrDiscoveryType(0x32)
    }

    # Get RedfishServiceIPAddress
    hidden [StringValue]GetRedfishServiceIPAddress()
    {
        return $this.GetIPAddress(0x34, $this.GetIPAddressFormat(0x33), $this.IsStaticOrAutoConfigure(0x32))
    }
    
   # Get RedfishServiceIPMask
    hidden [StringValue]GetRedfishServiceIPMask()
    {
        return $this.GetIPAddress(0x44, $this.GetIPAddressFormat(0x33), $this.IsStaticOrAutoConfigure(0x32))
    }

    # Get RedfishServiceIPPort
    hidden [StringValue]GetRedfishServiceIPPort()
    {
        if ($this.IsStaticOrAutoConfigure(0x32))
        {
            $base = $this.GetProtocolBaseAddress()

            $redfishServiceIPPort = $this.GetWordAtOffset($base + 0x54)

            return [StringValue]::new($redfishServiceIPPort)
        }
  
        return [StringValue]::new(-1, $(Get-LocalizedString "NOT_DEFINED"))
    }

    # Get RedfishServiceVlanId
    hidden [StringValue]GetRedfishServiceVlanId()
    {
        if ($this.IsStaticOrAutoConfigure(0x32))
        {
            $base = $this.GetProtocolBaseAddress()

            $redfishServiceVlanId = $this.GetDoubleWordAtOffset($base + 0x56)
            
            return [StringValue]::new($redfishServiceVlanId)
        }

        return [StringValue]::new(-1, $(Get-LocalizedString "NOT_DEFINED"))
    }

    # Get RedfishServiceHostname
    hidden [SMBString]GetRedfishServiceHostname()
    {
        $base = $this.GetProtocolBaseAddress()
        
        $redfishServiceHostnameLength = $this.GetByteAtOffset($base + 0x5A)

        $rawRedfishServiceHostname = [Byte[]][ArraySegment[Byte]]::new($this.data, $base + 0x5B, $redfishServiceHostnameLength) 

        $redfishServiceHostname = [UnicodeEncoding]::ASCII.GetString($rawRedfishServiceHostname)
                
        if ($redfishServiceHostnameLength -eq 0)
        {
            return $this.GetStringAtOffset(0xFF)
        }
        else
        {
            return [SMBString]::new($redfishServiceHostname)
        }
    }

    # Get Protocols
    hidden [StringValue]GetProtocols()
    {
        $base = $this.GetProtocolBaseAddress()

        $protocols = [Byte[]][ArraySegment[Byte]]::new($this.data, $base, $this.data.Length - $base) 
        
        if ($protocols)
        {
            return [StringValue]::new($protocols, [BitConverter]::ToString($protocols).Replace("-",""))
        }
               
        return [StringValue]::new(-1, $(Get-LocalizedString "NOT_DEFINED"))
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
            $labels.Add( "SpecificationVersion"  )
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
        $vendor = [ArraySegment[Byte]]::new($this.data, 0x04, 4)

        $vendorID = "'"

        foreach ($char in $vendor) 
        {
            if (($char -eq 0x00) -or ($char -eq 0x20))
            {
                $vendorID = $vendorID + " "
            }
            else 
            {
                $vendorID = $vendorID + $([Text.Encoding]::ASCII.GetChars($char))
            }
        }

        $vendorID = $vendorID + "'"

        return [StringValue]::new($vendor, $vendorID)
    }

    # Get SpecVersion
    hidden [Version]GetSpecificationVersion()
    {
        $majorSpecVersion = $this.GetByteAtOffset(0x08)

        $minorSpecVersion = $this.GetByteAtOffset(0x09)  

        return [Version]::new($majorSpecVersion, $minorSpecVersion)
    }

    # Get FirmwareVersion
    hidden [Version]GetFirmwareVersion()
    {
        $major = 0
        $minor = 0
        
        switch ($this.GetSpecificationVersion().Major) 
        {
            0x01 { 
                $major = $this.GetByteAtOffset(0x0C)
                $minor = $this.GetByteAtOffset(0x0D)
             } 
            0x02 { 
                $major = [BitField]::Extract($this.GetDoubleWordAtOffset(0x0A), 16, 16)
                $minor = [BitField]::Extract($this.GetDoubleWordAtOffset(0x0A),  0, 16)
             }
        }

        return [version]::new($major, $minor)
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
        $stringTables = [ProcessorAdditionalInformation]::GetStringTables("Type_44")

        [ProcessorAdditionalInformation]::StringArrays = $stringTables.StringArrays
                                
        [ProcessorAdditionalInformation]::StringArrayNameAlias = $stringTables.StringArrayNameAlias
        
        $labels = [Collections.ArrayList]::new() 
        
        if ( [SMBIOS]::Version -ge [Version]::new(3, 3) )
        {
            $labels.Add( "ReferencedHandle" )
            $labels.Add( "ProcessorType"    )
        }

        [ProcessorAdditionalInformation]::PropertyNames = $labels 
    }

    ProcessorAdditionalInformation([Byte]$type, [String]$description, [String[]]$keywords, [Byte]$length, [UInt16]$handle, [Byte[]]$data, [String[]]$strings) : base($type, $description, $keywords, $length, $handle, $data, $strings)
    {
    }

    hidden [UInt16]GetReferencedHandle()
    {
        return $this.GetWordAtOffset(0x04)
    }

    hidden [StringValue]GetProcessorType()
    {
        $processorType = $this.GetByteAtOffset(0x07)

        return [StringValue]::new($processorType, "ProcessorType", [ref]$this)
    }
}


###################################################################################################################################
# Type 45                                                                                                                         #
###################################################################################################################################
class FirmwareInventoryInformation : SMBIOSStructure 
{    
    hidden static [Hashtable]$StringArrays
    hidden static [Hashtable]$StringArrayNameAlias

    static [Array]$PropertyNames

    static FirmwareInventoryInformation()
    {
         $stringTables = [FirmwareInventoryInformation]::GetStringTables("Type_45")

        [FirmwareInventoryInformation]::StringArrays = $stringTables.StringArrays
                                
        [FirmwareInventoryInformation]::StringArrayNameAlias = $stringTables.StringArrayNameAlias
        
        $labels = [Collections.ArrayList]::new() 
        
        if ( [SMBIOS]::Version -ge [Version]::new(3, 5) )
        {
            $labels.Add( "FirmwareComponentName"  )
            $labels.Add( "FirmwareVersion"        )
            $labels.Add( "FirmwareId"             )
            $labels.Add( "ReleaseDate"            )
            $labels.Add( "Manufacturer"           )
            $labels.Add( "LowestSupportedVersion" )
            $labels.Add( "ImageSize"              )
            $labels.Add( "Characteristics"        )
            $labels.Add( "State"                  )
            $labels.Add( "AssociatedComponents"   )
        }

        [FirmwareInventoryInformation]::PropertyNames = $labels 
    }

    FirmwareInventoryInformation([Byte]$type, [String]$description, [String[]]$keywords, [Byte]$length, [UInt16]$handle, [Byte[]]$data, [String[]]$strings) : base($type, $description, $keywords, $length, $handle, $data, $strings)
    {
    }

    # Get Version
    hidden [StringValue]GetVersion([String]$version)
    {
        $versionFormat = $this.GetByteAtOffset(0x06)

        return [StringValue]::new($versionFormat, $version)
    }

    # Get FirmwareComponentName
    hidden [SMBString]GetFirmwareComponentName()
    {
        return $this.GetStringAtOffset(0x04)
    }

    # Get FirmwareVersion
    hidden [StringValue]GetFirmwareVersion()
    {
        $firmwareVersion = $($this.GetStringAtOffset(0x05)).DisplayValue

        return $this.GetVersion($firmwareVersion)
    }

    # Get FirmwareId
    hidden [StringValue]GetFirmwareId()
    {
        $firmwareIdFormat = $this.GetByteAtOffset(0x08)
        
        $firmwareId = $($this.GetStringAtOffset(0x07)).DisplayValue

        return [StringValue]::new($firmwareIdFormat, $firmwareId)
    }

    # Get ReleaseDate
    hidden [StringValueDateTime]GetReleaseDate()
    {
        $releaseDate = $($this.GetStringAtOffset(0x09)).DisplayValue

        if ([String]::IsNullOrEmpty($releaseDate))
        {
            return [StringValueDateTime]::new($null, $(Get-LocalizedString "NOT_AVAILABLE"))
        }
        else 
        {
            $culture = [CultureInfo]::CreateSpecificCulture("en-US")
            
            [DateTime]$date = [DateTime]::new(0)

            if( [DateTime]::TryParse($releaseDate, $culture, [DateTimeStyles]::None, [ref]$date) )
            {
                if ($date -eq $([DateTime]"2021-05-15T00:00:00Z") )
                {
                    return [StringValueDateTime]::new($date, $(Get-LocalizedString "UNKNOWN"))  
                }
                else
                {
                    return [StringValueDateTime]::new($date)
                }
            }
            else
            {   
                return [StringValueDateTime]::new($releaseDate, $releaseDate)
            }
        }
    }

    # Get Manufacturer
    hidden [SMBString]GetManufacturer()
    {
        return $this.GetStringAtOffset(0x0A)
    }

    # Get LowestSupportedVersion
    hidden [StringValue]GetLowestSupportedVersion()
    {
        $lowestSupportedVersion =  $($this.GetStringAtOffset(0x0B)).DisplayValue

        return $this.GetVersion($lowestSupportedVersion)
    }

    # Get ImageSize
    hidden [StringValueMemorySize]GetImageSize()
    {
        $sizeInBytes = $this.GetQuadWordAtOffset(0x0C)
        
        if ($sizeInBytes -eq  [UInt64]::MaxValue)
        {
            return [StringValueMemorySize]::new(0xFFFFFFFF, "Size", [ref]$this, -1, [MemorySizeUnit]::Unknown)
        }
        else
        {
            $unit = [MemorySizeUnit]::B
        }

        return [StringValueMemorySize]::new($sizeInBytes, $unit)
    }

    # Get Characteristics
    hidden [StringValue[]]GetCharacteristics()
    {
        $characteristics = $this.GetWordAtOffset(0x14)

        return [BitFieldConverter]::ToStringValueArray($characteristics, 2, "Characteristics", [ref]$this)
    }

    # Get State
    hidden [StringValue]GetState()
    {
        $state = $this.GetByteAtOffset(0x16)

        return [StringValue]::new($state, "State", [ref]$this)
    }

    # Get AssociatedComponents
    hidden [UInt16[]]GetAssociatedComponents()
    {
        $components = $this.GetByteAtOffset(0x17)

        $associatedComponents = [Collections.ArrayList]::new()

        if ($components.Count -ge 1)
        {
            for ($component=0; $component -lt $components; $component++)
            {
                $handle = $this.GetWordAtOffset(0x18 + $component * 2)

                $associatedComponents.Add($handle)
            }
        }

        return $associatedComponents
    }
}


###################################################################################################################################
# Type 46                                                                                                                         #
###################################################################################################################################
class StringProperty : SMBIOSStructure 
{    
    hidden static [Hashtable]$StringArrays
    hidden static [Hashtable]$StringArrayNameAlias

    static [Array]$PropertyNames

    static StringProperty()
    {
        $labels = [Collections.ArrayList]::new()
        
        if ( [SMBIOS]::Version -ge [Version]::new(3, 5) )
        {
            $labels.Add( "StringPropertyID"    )
            $labels.Add( "StringPropertyValue" )
            $labels.Add( "ParentHandle"        )
        }

        [StringProperty]::PropertyNames = $labels 
    }

    StringProperty([Byte]$type, [String]$description, [String[]]$keywords, [Byte]$length, [UInt16]$handle, [Byte[]]$data, [String[]]$strings) : base($type, $description, $keywords, $length, $handle, $data, $strings)
    {
    }

    # Get StringPropertyID
    hidden [UInt16]GetStringPropertyID()
    {
        return $this.GetWordAtOffset(0x04)
    }

    # Get StringPropertyValue
    hidden [Byte]GetStringPropertyValue()
    {
        return $this.GetByteAtOffset(0x6)
    }
    
    # Get ParentHandle
    hidden [UInt16]GetParentHandle()
    {
        return $this.GetWordAtOffset(0x07)
    }
}

###################################################################################################################################
# Type 47..125                                                                                                                   #
###################################################################################################################################
class Reserved : SMBIOSStructure
{ 
    static [Array]$PropertyNames

    static Reserved()
    {
        $labels = [Collections.ArrayList]::new() 
    
        $labels.Add( "Data"    )
        $labels.Add( "Strings" )

        [Reserved]::PropertyNames = $labels 
    }
    
    Reserved([Byte]$type, [String]$description, [String[]]$keywords, [Byte]$length, [UInt16]$handle, [Byte[]]$data, [String[]]$strings) : base($type, $description, $keywords, $length, $handle, $data, $strings)
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

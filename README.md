# SMBIOS

SMBIOS is a PowerShell module.

This module allow to get the SMBIOS table contents in the form of objects and various information about SMBIOS.

## Requirements

- Windows PowerShell 5.1
- PowerShell 7.x

## Supported platforms

- Windows
- Linux
- macOS (Intel-based Mac)

## Supported SMBIOS version

[3.8.0](https://www.dmtf.org/sites/default/files/standards/documents/DSP0134_3.8.0.pdf)

## Installation

```PS> Install-Module -Name SMBIOS```

## Usage

Get-SMBIOS

Get-SMBIOS -Type 0

Get-SMBIOS -Type 1,2

Get-SMBIOS -Type 0 -Property Vendor

Get-SMBIOS -Type 0 -Property Vendor,Version

Get-SMBIOS -FilePath C:\Users\vanso\Desktop\Dell_XPS.dump

> [!TIP]
> The Get-SMBIOS function can read files exported with dmidecode.

Get-SMBIOS -ListTypes

Get-SMBIOS -ListAvailableTypes

Get-SMBIOS -ExcludeOEMTypes

Get-SMBIOS -Raw

Get-SMBIOSVersion

Get-SMBIOSInfo

Export-SMBIOS -File C:\users\vanso\Desktop\Dell_XPS.dump

> [!WARNING]
> The file exported by the Export-SMBIOS function is incompatible with dmidecode.

## Available functions in the module

| Function name            | Description                                                                          |
|:-------------------------|:-------------------------------------------------------------------------------------|
| Get-SMBIOS               | Gets the SMBIOS table contents in the form of objects.                                |
| Get-SMBIOSVersion        | Gets the SMBIOS version.                                                              |
| Get-SMBIOSInfo           | Gets general info about the SMBIOS.                                                     |
| Export-SMBIOS            | Export a dump of the SMBIOS to a file that can be read with the Get-SMBIOS function. |
| Get-SMBIOSTypes          | List the standard SMBIOS types.                                                      |
| Get-SMBIOSAvailableTypes | List the available SMBIOS types in a synthetic way.                                  |
| Get-SMBIOSTableData      | Gets the SMBIOS table data as an array of bytes.                                      |
| Get-SMBIOSEntryPoint     | Gets the SMBIOS entry point as an array of bytes.                                     |

> [!NOTE]
> The module is currently only localized in English (United States) with the exception of date representation which uses the current locale.

## Help Get-SMBIOS

Get-SMBIOS [[-Type] \<Byte[]\>] [[-Property] \<String[]\>] [-HideHeader] [-Expand] [-MemorySizeUnit {B | kB | MB | GB
| TB | PB | EB | ZB | YB | Auto | None | Unknown}] [-TemperatureUnit {Auto | Celsius | Fahrenheit | Unknown}]
[-FilePath \<String\>] [-MaximumVersion \<Version\>] [-ExcludeOEMTypes] [-ExcludeType \<Byte[]\>] [-NoEmphasis]
[\<CommonParameters\>]

Get-SMBIOS [-Debugging] [-Type \<Byte[]\>] [-Property \<String[]\>] [-Expand] [-MemorySizeUnit {B | kB | MB | GB | TB
| PB | EB | ZB | YB | Auto | None | Unknown}] [-TemperatureUnit {Auto | Celsius | Fahrenheit | Unknown}]
[-FilePath \<String\>] [-MaximumVersion \<Version\>] [-AddSMBIOSData \<List\`1\>] [-UpdateSMBIOSData \<List\`1\>]
[-ExcludeOEMTypes] [-ExcludeType \<Byte[]\>] [\<CommonParameters\>]

> [!CAUTION]
> The Debugging parameter is for debugging purpose only.

Get-SMBIOS [-Raw] [[-Type] \<Byte[]\>] [-FilePath \<String\>] [\<CommonParameters\>]

Get-SMBIOS [-Handle \<UInt16[]\>] [-FilePath \<String\>] [\<CommonParameters\>]

Get-SMBIOS [-FilePath \<String\>] [-ListAvailableTypes] [-ExcludeOEMTypes] [\<CommonParameters\>]

Get-SMBIOS [-ListTypes] [\<CommonParameters\>]

Get-SMBIOS [-Version] [\<CommonParameters\>] (Deprecated)

Get-SMBIOS [-Statistics] [\<CommonParameters\>] (Deprecated)

## Supported types

All the types described in the SMBIOS specification version 3.8.0 are fully supported.

## License

This module is released under the terms of the GNU General Public License (GPL), Version 2.

It uses parts of the [DMI Decode](https://www.nongnu.org/dmidecode/) project, also available on [GitHub](https://github.com/mirror/dmidecode).

# SMBIOS

SMBIOS is a PowerShell module.

This module expose one function named Get-SMBIOS that allows to get the SMBIOS table contents in the form of objects.

## Requirements

- Windows PowerShell 5.1
- PowerShell Core

## Supported platforms

- Windows
- Linux
- MacOS

## Supported SMBIOS version

[3.4.0a](https://www.dmtf.org/sites/default/files/standards/documents/DSP0134_3.4.0a.pdf)

## Supported types

The following types are fully supported :

| Type | Name                             |
|-----:|:---------------------------------|
| 0    | BIOS                             |
| 1    | System                           |
| 2    | Baseboard                        |
| 3    | Chassis                          |
| 4    | Processor                        |
| 5    | Memory Controller                |
| 6    | Memory Module                    |
| 7    | Cache                            |
| 8    | Port Connector                   |
| 9    | System Slots                     |
| 10   | On Board Devices                 |
| 11   | OEM Strings                      |
| 12   | System Configuration Options     |
| 13   | BIOS Language                    |
| 14   | Group Associations               |
| 15   | System Event Log                 |
| 16   | Physical Memory Array            |
| 17   | Memory Device                    |
| 18   | 32-bit Memory Error              |
| 19   | Memory Array Mapped Address      |
| 20   | Memory Device Mapped Address     |
| 21   | Built-in Pointing Device         |
| 22   | Portable Battery                 |
| 23   | System Reset                     |
| 24   | Hardware Security                |
| 26   | Voltage Probe                    |
| 27   | Cooling Device                   |
| 28   | Temperature Probe                |
| 29   | Electrical Current Probe         |
| 30   | Out-of-band Remote Access        |
| 32   | System Boot                      |
| 33   | 64-bit Memory Error              |
| 34   | Management Device                |
| 35   | Management Device Component      |
| 36   | Management Device Threshold Data |
| 39   | Power Supply                     |
| 40   | Additional Information           |
| 41   | Onboard Device                   |
| 43   | TPM Device                       |
| 126  | Inactive                         |
| 127  | End Of Table                     |

The following types are not currently fully supported :

| Type | Name                                 |
|-----:|:-------------------------------------|
| 25   | System Power Controls                |
| 31   | Boot Integrity Services              |
| 37   | Memory Channel                       |
| 38   | IPMI Device                          |
| 42   | Management Controller Host Interface |
| 44   | Processor Additional Information     |

## License

This module is released under the terms of the GNU General Public License (GPL), Version 3.

It uses parts of the [DMI Decode](https://www.nongnu.org/dmidecode/) project, also available on [GitHub](https://github.com/mirror/dmidecode).

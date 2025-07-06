# Changelog

## [1.0] - 2024-07-06

### What's new

#### Functions Added
- `Get-SMBIOSVersion` retrieves the SMBIOS version
- `Get-SMBIOSInfo` retrieves general SMBIOS information
- `Export-SMBIOS` exports SMBIOS entry point and table data to a file for use with `Get-SMBIOS`
- `Get-SMBIOSTypes` lists standard SMBIOS types
- `Get-SMBIOSAvailableTypes` lists available SMBIOS types
- `Get-SMBIOSTableData` retrieves SMBIOS table data as a byte array
- `Get-SMBIOSEntryPoint` retrieves the SMBIOS entry point as a byte array

#### Parameters Added
- `-HideHeader` hides the header
- `-ExcludeType` excludes specific types
- `-FilePath` allows reading exported SMBIOS files with `Export-SMBIOS` or `dmidecode`
- `-NoEmphasis` removes bold emphasis from strings
- `-MaximumVersion` restricts the decoding of the table

#### Added support for new types
- Firmware Inventory Information (Type 45)
- String Property (Type 46)
  
### Updates and Fixes

#### Specifications
- Compliance with SMBIOS version 3.8.0

#### Strings
- Strings are now clearly identifiable with **bold** emphasis
- Empty or null strings are displayed as **N/A**
- Strings with leading or trailing blank characters are enclosed in double quotes

#### Get-SMBIOS
- The parameter `-ListAvailableTypes` now displays the number of structures and associated handles for each type.
- The parameter `-Raw` now can be used for a specific types
- The parameter `-Version` is deprecated and replaced by the new function `Get-SMBIOSVersion`
- The parameter `-Statistics` is deprecated and replaced by the new function `Get-SMBIOSInfo`

#### SMBIOS Types
- Add a description for `Reserved` types

#### Type 4 (Processor Information)
- Platform-specific information is no longer used
- The `Architecture` property has been removed
- The `ProcessorType` property has been renamed to `Type`
- The `ProcessorStatus` property has been renamed to `Status`
- The `Family` property now returns a correct result for extended values
- The `Voltage` property now returns a correct result
- The `ExternalClock`, `MaxSpeed`, `CurrentSpeed` properties now returns a correct result when the value is `unknown`
- The `Signature` property now correctly handles an unknown manufacturer
- Improv support for ARM processors

#### Type 6 (Memory Module Information)
- The `CurrentMemoryType`property now returns a correct result when no memory types have been specified
- The `InstalledSize`, `EnabledSize`, `ErrorStatus` properties now returns a correct result
- The `InstalledSizeConnection`, `EnabledSizeConnection` properties have been added

#### Type 7 (Cache Information)
- The `ErrorCorrectionType`, `MaximumCacheSize`, `InstalledSize` properties now returns a correct result when the value is `None`
- The `SupportedSRAMType` and `CurrentSRAMType` properties now returns a type `[StringValue](-1, NONE)` when not defined instead of `$null`

#### Type 8 (Port Connector Information)
- The `InternalConnectorType` property now returns a correct result when the value is `SAS/SATA Plug Receptacle` or `USB Type-C Receptacle`
- The `ExternalConnectorType` property now returns a correct result when the value is `SAS/SATA Plug Receptacle` or `USB Type-C Receptacle`

#### Type 9 (System Slot Information)
- The `BusAddress` property now return a correct value
- The `PeerDevices` property now enumerate each peer device
- The `SlotLength` properties values (`Long Length` and `Short Length`) have been renamed to (`Long` and `Short`)

#### Type 16 (Physical Memory Array)
- The `MaximumCapacity` property now automatically adjusting the size unit

#### Type 17 (Memory Device)
- The `TotalWidth`, `DataWidth` properties now returns a correct result when the value is `unknown`
- The `Size` property now returns a correct result when no module is installed or the value is `unknown` and automatically adjusting the size unit
- The `TypeDetail` property now returns a correct result when the value is `None`
- The `NonVolatileSize`, `VolatileSize`, `CacheSize`, `LogicalSize` properties now return a correct result when no portion is present or the size is `unknown` and automatically adjusting the size unit
- The `Attributes` property has been renamed to `Rank` and now returns a correct result
- The `MemoryOperatingModeCapability` now returns a correct result for `Byte-accessible persistent memory` and `Block-accessible persistent memory`

#### Type 19 (Memory Array Mapped Address)
- The `EndingAddress` property now returns a correct result
- The `RangeSize` property now returns a correct result and automatically adjusting the size unit

#### Type 20 (Memory Device Mapped Address)
- The `EndingAddress` property now returns a correct result
- The `RangeSize` property now returns a correct result and automatically adjusting the size unit

#### Type 25 (System Power Controls)
- This type is now fully supported

#### Type 27 (Cooling Device)
- The `DeviceType` property now returns a correct result when the value is `Active Cooling` or `Passive Cooling`

#### Type 28 (Temperature Probe)
- `MaximumValue`, `MinimumValue`, `Tolerance`, `NominalValue`, `Resolution` properties now returns a correct result when the value is `unknown`

#### Type 31 (Boot Integrity Services)
- This type is now fully supported

#### Type 37 (Memory Channel)
- This type is now fully supported

#### Type 38 (IPMI Device)
- This type is now fully supported

#### Type 41 (Onboard Device)
- `BusAddress` property now return a correct value

#### Type 42 (Management Controller Host Interface)
- This type is now fully supported

#### Type 43 (TPM Device)
- The `VendorID` property now return whitespace in the abbreviation
- The `SpecVersion` property has been renamed to `SpecificationVersion`
- The `FirmwareRevision` property now returns a type `[Version]` instead of type `[UInt32]`

#### Type 44 (Processor Additional Information)
- This type is now fully supported


[1.0]:  https://github.com/vanso/SMBIOS/releases/tag/v1.0

## [0.8] - 2020-05-10

- First public release.

[0.8]: https://github.com/vanso/SMBIOS/releases/tag/v0.8

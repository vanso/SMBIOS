ConvertFrom-StringData -StringData @'
B = bytes
kB = kB
MB = MB
GB = GB
TB = TB
PB = PB
EB = EB
ZB = ZB
YB = YB

OUT_OF_SPEC = Out-of-Specification
NOT_DEFINED = Not Defined
NOT_AVAILABLE = Not Available
UNKNOWN = Unknown
UNSPECIFIED = Unspecified
NOT_SPECIFIED = Not Specified
NOT_SUPPORTED = Not Supported
UNUSED = Unused
NOT_APPLICABLE = Not Applicable
N/A = N/A

START_OEM_RANGE = Start Of OEM Specific Type Range
END_OEM_RANGE = End Of OEM Specific Type Range

DONE = Done

# Type 1 - UUID
NOT_SETTABLE = Not Settable
NOT_PRESENT = Not Present

# Type 4 - CacheHandle
NOT_PROVIDED = Not Provided
NO_LN_CACHE = No L{0} Cache

# Type 6 - CurrentMemoryType
NONE = None

# Type 6 - ErrorStatus
OK = OK

# Type 15 - HeaderFormat
OEM_SPECIFIC = OEM-specific

# Type 15 - SupportedEventLogTypeDescriptors
OEM_SYSTEM_SPECIFIC = System- and OEM-specific

# Type 27, 28 - Temperature
CELSIUS = °C
FAHRENHEIT = °F

# Type 31
INVALID = Invalid

SMBIOS_HEADER = Handle 0x{0:X4}, DMI type {1} ({2}), {3} bytes
SMBIOS_PRESENT = SMBIOS {0} present.
SMBIOS_NOT_FULLY_SUPPORTED = SMBIOS implementations newer than version {0} are not fully supported by this version.
SMBIOS_ENTRY_POINT_NOT_FOUND = SMBIOS entry point not found.
SMBIOS_TABLE_DATA_NOT_FOUND = SMBIOS table data not found.
SMBIOS_ENTRY_POINT_ERROR = An error occurred when reading the SMBIOS entry point ({0}).
SMBIOS_TABLE_DATA_ERROR = An error occurred when reading the SMBIOS table ({0}).
SMBIOS_READ_FILE_ERROR = An error occurred when reading the file ({0}).
SMBIOS_WRITE_FILE_ERROR = An error occurred when writing the file ({0}).
SMBIOS_NOT_SUPPORTED_MAC_APPLE_SILICON = SMBIOS is not supported on Mac with Apple silicon.
SMBIOS_MAXIMUM_VERSION_GREATER_SMBIOS_VERSION = The MaximumVersion parameter ({0}) is greater than the SMBIOS version ({1}).
SMBIOS_VERSION = SMBIOS version : {0}
SMBIOS_MAXIMUM_VERSION = SMBIOS maximum version : {0}
SMBIOS_SIZE_INFO = {0} structures found in {1} bytes.

SMBIOS_PROGRESS_ACTIVITY = Structures remaining to be readed : {0}
SMBIOS_PROGRESS_STATUS = Reading structure : {0} - Type : {1} ({2}), Handle : 0x{3:X4}, Length : {4} bytes

DEPRECATED_VERSION_PARAMETER = The Version parameter is deprecated since version 1.0. Use the Get-SMBIOSVersion function instead.
DEPRECATED_STATISTICS_PARAMETER = The Statistics parameter is deprecated since version 1.0. Use the Get-SMBIOSInfo function instead.

'@
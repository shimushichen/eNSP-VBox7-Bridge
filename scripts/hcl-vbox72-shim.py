# =============================================================================
# HCL 5.10.3 -> VirtualBox 7.2 compatibility shim (prototype, for gen_py cache)
#
# This block is appended to the win32com-generated wrapper
#   %TEMP%\gen_py\3.8\D7569351-1750-46F0-936E-BD127D5BC264x0x1x3.py
# after HCL has generated it against Oracle VirtualBox 7.2.16.
#
# It is a *prototype*: it has been syntax-checked against Python 3.8 but not
# executed inside HCL. Do not treat it as a deployed fix.
# =============================================================================

_HCL_COMPAT_MARKER = "VESPERASH_HCL_VBOX72_SHIM_V1"

_hcl_Dispatch = Dispatch

# PlatformArchitecture.x86 == 1 in VirtualBox 7.2 XIDL.
_HCL_PLATFORM_X86 = 1
_HCL_IMACHINE_IID = "{E36A5081-A82A-40BD-9E4E-42A44D6CE50F}"


def _hcl_create_machine_5(self, aSettingsFile, aName, aGroups, aOSTypeId, aFlags):
    """VirtualBox 6.0 createMachine(settingsFile, name, groups, osTypeId, flags).

    VirtualBox 7.2 expects:
      createMachine(settingsFile, name, platform, groups, osTypeId,
                    flags, cipher, passwordId, password)
    """
    if isinstance(aGroups, str):
        aGroups = [aGroups]
    ret = self._oleobj_.InvokeTypes(
        1610743851, LCID, 1, (9, 0),
        ((8, 1), (8, 1), (3, 1), (8200, 1), (8, 1),
         (8, 1), (8, 1), (8, 1), (8, 1)),
        aSettingsFile, aName, _HCL_PLATFORM_X86, aGroups, aOSTypeId,
        aFlags, "", "", "")
    if ret is not None:
        ret = _hcl_Dispatch(ret, "CreateMachine", _HCL_IMACHINE_IID)
    return ret


def _hcl_open_machine(self, aSettingsFile, aPassword=""):
    """VirtualBox 6.0 openMachine(settingsFile) -> 7.2 adds aPassword."""
    ret = self._oleobj_.InvokeTypes(
        1610743852, LCID, 1, (9, 0), ((8, 1), (8, 1)),
        aSettingsFile, aPassword)
    if ret is not None:
        ret = _hcl_Dispatch(ret, "OpenMachine", _HCL_IMACHINE_IID)
    return ret


def _hcl_check_firmware_present(self, aFirmwareType, aVersion,
                                aUrl=pythoncom.Missing, aFile=pythoncom.Missing):
    """VirtualBox 6.0 checkFirmwarePresent(fwType, version, url, file)."""
    return self._ApplyTypes_(
        1610743883, 1, (3, 0),
        ((3, 1), (3, 1), (8, 1), (16392, 2), (16392, 2)),
        "CheckFirmwarePresent", None,
        _HCL_PLATFORM_X86, aFirmwareType, aVersion, aUrl, aFile)


def _hcl_sp_max_nics(self, aChipset):
    return self.Platform.GetMaxNetworkAdapters(aChipset)


def _hcl_sp_max_nics_of_type(self, aChipset, aType):
    return self.Platform.GetMaxNetworkAdaptersOfType(aChipset, aType)


def _hcl_sp_max_devices_per_port(self, aBus):
    return self.Platform.GetMaxDevicesPerPortForStorageBus(aBus)


def _hcl_sp_min_ports(self, aBus):
    return self.Platform.GetMinPortCountForStorageBus(aBus)


def _hcl_sp_max_ports(self, aBus):
    return self.Platform.GetMaxPortCountForStorageBus(aBus)


def _hcl_sp_max_instances(self, aChipset, aBus):
    return self.Platform.GetMaxInstancesOfStorageBus(aChipset, aBus)


def _hcl_sp_device_types(self, aBus):
    return self.Platform.GetDeviceTypesForStorageBus(aBus)


def _hcl_sp_hotplug(self, aControllerType):
    return self.Platform.GetStorageControllerHotplugCapable(aControllerType)


def _hcl_sp_max_usb(self, aChipset, aType):
    return self.Platform.GetMaxInstancesOfUSBControllerType(aChipset, aType)


def _hcl_machine_audio_adapter(self):
    return self.AudioSettings.Adapter


def _hcl_machine_bios_settings(self):
    return self.FirmwareSettings


def _hcl_machine_rtc_use_utc(self):
    return self.Platform.RTCUseUTC


def _hcl_machine_chipset_type(self):
    return self.Platform.ChipsetType


def _hcl_machine_firmware_type(self):
    return self.FirmwareSettings.FirmwareType


def _hcl_machine_vram_size(self):
    return self.GraphicsAdapter.VRAMSize


def _hcl_machine_monitor_count(self):
    return self.GraphicsAdapter.MonitorCount


def _hcl_machine_graphics_controller_type(self):
    return self.GraphicsAdapter.GraphicsControllerType


def _hcl_machine_accel_3d(self):
    return bool(self.GraphicsAdapter.IsFeatureEnabled(2))  # Acceleration3D


def _hcl_machine_hpet(self):
    return self.Platform.X86.HPETEnabled


_hcl_orig_machine_setattr = DispatchBaseClass.__dict__.get("__setattr__") or object.__setattr__


def _hcl_machine_setattr(self, name, value):
    """Route VirtualBox 6.0 setter names to their 7.2 replacements."""
    lname = name.lower()
    if lname == "audioadapter":
        raise AttributeError("IMachine.AudioAdapter is read-only in HCL/6.0")
    if lname == "rtcuseutc":
        self.Platform.RTCUseUTC = value
        return
    if lname == "chipsettype":
        self.Platform.ChipsetType = value
        return
    if lname == "firmwaretype":
        self.FirmwareSettings.FirmwareType = value
        return
    if lname == "vramsize":
        self.GraphicsAdapter.VRAMSize = value
        return
    if lname == "monitorcount":
        self.GraphicsAdapter.MonitorCount = value
        return
    if lname == "graphicscontrollertype":
        self.GraphicsAdapter.GraphicsControllerType = value
        return
    if lname == "accelerate3denabled":
        self.GraphicsAdapter.SetFeature(2, bool(value))  # Acceleration3D
        return
    if lname == "hpetenabled":
        self.Platform.X86.HPETEnabled = value
        return
    if lname == "iobase":
        self.IOAddress = value
        return
    return _hcl_orig_machine_setattr(self, name, value)


def _hcl_serial_iobase_get(self):
    return self.IOAddress


_hcl_orig_serial_setattr = DispatchBaseClass.__dict__.get("__setattr__") or object.__setattr__


def _hcl_serial_setattr(self, name, value):
    if name.lower() == "iobase":
        self.IOAddress = value
        return
    return _hcl_orig_serial_setattr(self, name, value)


IVirtualBox.CreateMachine = _hcl_create_machine_5
IVirtualBox.OpenMachine = _hcl_open_machine
IVirtualBox.CheckFirmwarePresent = _hcl_check_firmware_present

ISystemProperties.GetMaxNetworkAdapters = _hcl_sp_max_nics
ISystemProperties.GetMaxNetworkAdaptersOfType = _hcl_sp_max_nics_of_type
ISystemProperties.GetMaxDevicesPerPortForStorageBus = _hcl_sp_max_devices_per_port
ISystemProperties.GetMinPortCountForStorageBus = _hcl_sp_min_ports
ISystemProperties.GetMaxPortCountForStorageBus = _hcl_sp_max_ports
ISystemProperties.GetMaxInstancesOfStorageBus = _hcl_sp_max_instances
ISystemProperties.GetDeviceTypesForStorageBus = _hcl_sp_device_types
ISystemProperties.GetStorageControllerHotplugCapable = _hcl_sp_hotplug
ISystemProperties.GetMaxInstancesOfUSBControllerType = _hcl_sp_max_usb
ISystemProperties.ExclusiveHwVirt = property(
    lambda self: self.Platform.ExclusiveHwVirt,
    lambda self, value: setattr(self.Platform, "ExclusiveHwVirt", value))
ISystemProperties.MaxBootPosition = property(
    lambda self: self.Platform.MaxBootPosition)
ISystemProperties.SerialPortCount = property(
    lambda self: self.Platform.SerialPortCount)
ISystemProperties.ParallelPortCount = property(
    lambda self: self.Platform.ParallelPortCount)
ISystemProperties.RawModeSupported = property(
    lambda self: self.Platform.RawModeSupported)

IMachine.AudioAdapter = property(_hcl_machine_audio_adapter)
IMachine.BIOSSettings = property(_hcl_machine_bios_settings)
IMachine.RTCUseUTC = property(_hcl_machine_rtc_use_utc)
IMachine.ChipsetType = property(_hcl_machine_chipset_type)
IMachine.FirmwareType = property(_hcl_machine_firmware_type)
IMachine.VRAMSize = property(_hcl_machine_vram_size)
IMachine.MonitorCount = property(_hcl_machine_monitor_count)
IMachine.GraphicsControllerType = property(_hcl_machine_graphics_controller_type)
IMachine.Accelerate3DEnabled = property(_hcl_machine_accel_3d)
IMachine.HPETEnabled = property(_hcl_machine_hpet)
IMachine.__setattr__ = _hcl_machine_setattr

ISerialPort.IOBase = property(_hcl_serial_iobase_get)
ISerialPort.__setattr__ = _hcl_serial_setattr


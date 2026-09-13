-- MainTank required detailed Archive storage companion
-- Loaded normally with MainTank; no UI or combat logic lives in this addon.
MainTankArchivePackageVersion = "1.2.70-PL14"
if not MainTankArchiveDB then MainTankArchiveDB = { version = 8, profiles = {} } end
MainTankArchiveDB.version = MainTankArchiveDB.version or 8
MainTankArchiveDB.profiles = MainTankArchiveDB.profiles or {}

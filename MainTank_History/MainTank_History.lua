-- MainTank required lightweight History storage companion
-- Loaded normally with MainTank; no UI or combat logic lives in this addon.
MainTankHistoryPackageVersion = "1.2.69-PL13"
if not MainTankHistoryDB then MainTankHistoryDB = { version = 8, profiles = {} } end
MainTankHistoryDB.version = MainTankHistoryDB.version or 8
MainTankHistoryDB.profiles = MainTankHistoryDB.profiles or {}

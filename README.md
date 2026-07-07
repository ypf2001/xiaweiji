# xiaweiji

TIA Portal V21 project for the potato fertigation PLC layer.

## SCL Source Of Truth

- Primary PLC source: `D:\dw_plc\xiaweiji\src\xiaweiji.scl`
- DigitalTwin mirror: `D:\Digital Twin\plc\xiaweiji\src\xiaweiji.scl`
- The two files must stay byte-for-byte identical. Edit the primary PLC source, then sync the mirror before running DigitalTwin or TIA Openness import workflows.
- DigitalTwin's `plc_openness_v21\run_import_xiaweiji.ps1` defaults to this PLC repository source and refuses to run when the hashes differ, unless `-AllowMismatchedScl` is passed explicitly.

Check source consistency:

```powershell
Get-FileHash "D:\dw_plc\xiaweiji\src\xiaweiji.scl"
Get-FileHash "D:\Digital Twin\plc\xiaweiji\src\xiaweiji.scl"
```

## Import And Compile

Import the SCL source and compile the PLC software:

```powershell
powershell -ExecutionPolicy Bypass -File tools\import_scl_openness.ps1 -Compile
```

Warnings are allowed, but compile errors must fail the script.

## Git Hygiene

TIA Portal may regenerate search indexes and transient metadata while opening or saving the project. These generated files are ignored so acceptance status focuses on intentional source, script, README, and project changes.

# ED25519-ASIC-Implementation

## Hardware Developer Workflow

This project uses a version-controlled Tcl workflow to keep the repository clean. **Do not push `.xpr`, `.cache`, or `.runs` folders to GitHub.**

### How to Build the Project
When you pull new code from GitHub, you must regenerate your local Vivado project:
1. Delete the inner `ED25519/ED25519` folder if it exists (this clears old caches).
2. Open Vivado.
3. Open the Tcl Console at the bottom of the welcome screen.
4. Run: `cd [Your-Path]/ED25519-ASIC-Implementation/ED25519`
5. Run: `source build_project.tcl`

### How to Add New Hardware Files
Do not use Vivado's "Create File" button, as it will bury your code in ignored folders.
1. Create your new `.v` or `.sv` file directly inside the `ED25519.srcs/` folder using VS Code.
2. In Vivado, click **Add Sources -> Add Files**.
3. **CRITICAL:** Uncheck the *"Copy sources into project"* box before clicking Finish.
4. Before you commit your code to Git, run `write_project_tcl -force build_project.tcl` in the Vivado console so the build script knows about your new file!

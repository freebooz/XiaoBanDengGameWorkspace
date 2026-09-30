"""Start the installed official MCP add-on in this dedicated Blender session."""
import addon_utils
import bpy

addon_utils.enable("blender_mcp", default_set=True, persistent=True)
bpy.context.scene.blendermcp_port = 9878
bpy.context.preferences.addons["blender_mcp"].preferences.telemetry_consent = False
bpy.ops.blendermcp.start_server()
print("XBD_BLENDER_MCP_READY port=9878", flush=True)

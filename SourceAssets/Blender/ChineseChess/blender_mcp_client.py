"""Use the public MCP stdio protocol to operate the installed Blender MCP server."""
import asyncio
import json
import os
from pathlib import Path
import sys
from datetime import timedelta

from mcp import ClientSession, StdioServerParameters
from mcp.client.stdio import stdio_client

USER_PROMPT = "调用blender mcp按此图制作棋盘和棋子。"

async def main():
    environment = dict(os.environ)
    environment["BLENDER_HOST"] = "127.0.0.1"
    environment["BLENDER_PORT"] = "9878"
    environment["BLENDER_MCP_DISABLE_TELEMETRY"] = "true"
    parameters = StdioServerParameters(command="uvx", args=["mcp-for-blender"], env=environment)
    async with stdio_client(parameters) as (reader, writer):
        async with ClientSession(reader, writer, read_timeout_seconds=240.0) as session:
            await session.initialize()
            mode = sys.argv[1]
            if mode == "inspect":
                listing = await session.list_tools()
                print(json.dumps([t.model_dump(by_alias=True, exclude_none=True) for t in listing.tools if t.name in ("get_addon_status", "get_scene_info", "get_viewport_screenshot", "execute_blender_code")], ensure_ascii=False))
                for name in ("get_addon_status", "get_scene_info"):
                    response = await session.call_tool(name, {"user_prompt": USER_PROMPT})
                    print(response.model_dump_json())
            elif mode == "exec":
                script = Path(sys.argv[2]).resolve()
                code = "__file__ = " + repr(str(script)) + "\n" + script.read_text(encoding="utf-8-sig")
                response = await session.call_tool("execute_blender_code", {"code": code, "user_prompt": USER_PROMPT})
                print(response.model_dump_json())
            elif mode == "call":
                response = await session.call_tool(sys.argv[2], json.loads(sys.argv[3]))
                output = response.model_dump()
                for content in output.get("content", []):
                    if content.get("type") == "image":
                        import base64
                        image_path = Path(__file__).with_name("MCP_viewport.png")
                        image_path.write_bytes(base64.b64decode(content.pop("data")))
                        content["saved_path"] = str(image_path)
                print(json.dumps(output, ensure_ascii=False))

asyncio.run(main())

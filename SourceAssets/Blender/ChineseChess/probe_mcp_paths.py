import os
from pathlib import Path
import bpy
print('FILE', repr(__file__))
root = Path(__file__).resolve().parent
print('ROOT', repr(str(root)), repr(root.as_posix()))
print('BLEND', repr(bpy.data.filepath))
path = root / 'mcp_path_probe.txt'
print('WRITE', repr(str(path)), repr(os.fspath(path)))
path.write_text('MCP path OK', encoding='utf-8')
progress = root / 'build_progress.txt'
progress.write_text('MCP progress probe OK', encoding='utf-8')
print('PATH_PROBE_PASS')
for filename in ['XBD_ChineseChess_Set_preview.png', 'XBD_ChineseChess_Set.blend']:
    p=root/filename
    try:
        with open(p.as_posix(), 'ab'):
            pass
        print('OPEN_EXISTING_OK', filename, p.stat().st_size)
    except Exception as e:
        print('OPEN_EXISTING_ERROR', filename, repr(e))

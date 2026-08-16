"""DIY Excel live attach-mode fallback bridge (GetActiveObject).

Dual-mode Excel (HD-110 research):
  - PRIMARY: sbroenne mcp-server-excel (exclusive access, rich 326 ops).
  - FALLBACK: this script attaches to the EXACT live sheet the user is typing in
    (GetActiveObject) without taking exclusive ownership. Same stdio shape as
    ppt-mcp / word-mcp-live, so the wrapper pipes it identically.

Run standalone (stdio, MCP):  `python excel_fallback.py`
Requires: pywin32 + mcp (pinned in requirements.txt). Windows only.
"""
import win32com.client
from mcp.server.fastmcp import FastMCP

mcp = FastMCP("Live-Excel-Bridge")


def get_active_excel():
    """Bind to the currently open Excel instance, or spawn a background one."""
    try:
        return win32com.client.GetActiveObject("Excel.Application")
    except Exception:
        return win32com.client.Dispatch("Excel.Application")


@mcp.tool()
def read_active_range(sheet_name: str, cell_range: str) -> str:
    """Read values from a range (e.g. 'A1:C10') in an active sheet of the open workbook."""
    excel = get_active_excel()
    wb = excel.ActiveWorkbook
    if not wb:
        return "Error: no open workbook found."
    sheet = wb.Sheets(sheet_name)
    cells = sheet.Range(cell_range).Value
    return f"Data in {cell_range}: {str(cells)}"


@mcp.tool()
def write_to_active_cell(sheet_name: str, cell: str, value: str) -> str:
    """Write a value directly into the active user screen in real-time."""
    excel = get_active_excel()
    wb = excel.ActiveWorkbook
    if not wb:
        return "Error: no active workbook open."
    sheet = wb.Sheets(sheet_name)
    sheet.Range(cell).Value = value
    excel.Visible = True  # optional visual feedback
    return f"Successfully wrote '{value}' to cell {cell}."


if __name__ == "__main__":
    mcp.run(transport="stdio")
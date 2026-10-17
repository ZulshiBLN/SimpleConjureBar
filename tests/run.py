"""Smoke test: loads the addon in a mocked WoW API (Lua 5.1 via lupa) and runs tests/scenario.lua.
Usage: pip install lupa   then   python tests/run.py   (expects "ERRORS: none")"""
import sys, re
from lupa import lua51
import os
HERE=os.path.dirname(os.path.abspath(__file__))+os.sep
ADDON=os.path.join(HERE,'..','SimpleConjureBar')+os.sep
TEST=HERE
files=[l.strip() for l in open(ADDON+'SimpleConjureBar.toc',encoding='utf-8') if l.strip() and not l.startswith('#')]
def make(locale='deDE'):
    lua=lua51.LuaRuntime(unpack_returned_tuples=True)
    lua.execute(open(TEST+'mock.lua',encoding='utf-8').read())
    lua.globals().STATE.locale=locale
    lua.execute('BEFORE = {} for k in pairs(_G) do BEFORE[k]=true end NS = {}')
    for f in files:
        src=open(ADDON+f,encoding='utf-8').read()
        fn=lua.eval('function(src, name) local f, err = loadstring(src, name); if not f then error(err) end; return f end')(src, f)
        fn('SimpleConjureBar', lua.globals().NS)
    return lua
lua=make()
g=lua.globals()
newg=lua.execute('local t = {} for k in pairs(_G) do if not BEFORE[k] then t[#t+1]=k end end table.sort(t) return table.concat(t, ",")')
print("NEW GLOBALS:", newg)
script=open(TEST+'scenario.lua').read()
lua.execute(script)
errs=lua.execute('return table.concat(STATE.errors, "\\n")')
print("ERRORS:\n"+(errs or "none"))

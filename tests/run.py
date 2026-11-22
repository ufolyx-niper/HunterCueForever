"""Offline Lua 5.1 validation. Requires lupa==2.8 (lupa.lua51, not default Lua)."""
from pathlib import Path
from lupa.lua51 import LuaRuntime
import re

root=Path(__file__).resolve().parents[1]
lua=LuaRuntime(unpack_returned_tuples=True)
assert lua.eval('_VERSION')=='Lua 5.1'
lua.execute((root/'tests/mock.lua').read_text(encoding='utf-8'))
for name in ('Data.lua','Engine.lua','Adapter.lua','UI.lua'):
    text=(root/'HunterCueForever'/name).read_text(encoding='utf-8')
    lua.execute('assert(loadstring(...))("HunterCueForever", NS)',text)
lua.execute((root/'tests/cases.lua').read_text(encoding='utf-8'))
for class_name,build in [('MAGE',16001),('HUNTER',120100)]:
    other=LuaRuntime()
    other.execute((root/'tests/mock.lua').read_text(encoding='utf-8'))
    other.globals().CLASS=class_name;other.globals().BUILD=build
    for name in ('Data.lua','Engine.lua','Adapter.lua','UI.lua'):
        other.execute('assert(loadstring(...))("HunterCueForever", NS)',(root/'HunterCueForever'/name).read_text(encoding='utf-8'))
    other.execute('NS.events.scripts.OnEvent(NS.events,"PLAYER_LOGIN"); assert(NS.db==nil and HunterCueForeverFrame==nil)')
reload=LuaRuntime()
reload.execute((root/'tests/mock.lua').read_text(encoding='utf-8'))
reload.execute('HunterCueForeverDB={enabled=false,cooldowns=false}; UNKNOWN_EVENT="PLAYER_TALENT_UPDATE"')
for name in ('Data.lua','Engine.lua','Adapter.lua','UI.lua'):
    reload.execute('assert(loadstring(...))("HunterCueForever", NS)',(root/'HunterCueForever'/name).read_text(encoding='utf-8'))
reload.execute('NS.events.scripts.OnEvent(NS.events,"PLAYER_LOGIN"); assert(NS.db.enabled==false and NS.db.cooldowns==false and not HunterCueForeverFrame.shown); assert(NS.missingEvents[1]=="PLAYER_TALENT_UPDATE"); assert(SlashCmdList.HUNTERCUEFOREVER)')
# The pure decision and UI layers cannot bypass the adapter with raw game reads.
for name in ('Engine.lua','Data.lua','UI.lua'):
    text=(root/'HunterCueForever'/name).read_text(encoding='utf-8')
    assert not re.search(r'\b(?:C_Spell|C_UnitAuras|UnitPower|UnitGUID|UnitName|UnitCastingInfo|IsPlayerSpell|GetTime)\b',text),name
all_lua='\n'.join(p.read_text(encoding='utf-8') for p in (root/'HunterCueForever').glob('*.lua'))
for forbidden in ('CastSpellByName','CastSpellByID','RunMacroText','MoveForwardStart','TargetUnit','COMBAT_LOG_EVENT_UNFILTERED'):
    assert forbidden not in all_lua,forbidden
print('PASS: Lua 5.1 syntax, decision/state/API/UI cases, adapter boundary and no-automation checks')

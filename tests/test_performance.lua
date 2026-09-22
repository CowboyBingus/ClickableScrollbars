-- Work-count contracts, independent of hardware and synthetic timing estimates.
rawset(_G, '__CLICKABLE_SCROLLBARS_TEST', true)
local module = assert(loadfile(assert(arg[2])))()
local directory = assert(arg[0]:match('^(.*)[/\\]'))
local fixture = assert(loadfile(directory .. '/runtime_fixture.lua'))()
for _, visible in ipairs({false,true}) do
    local f=fixture(module,{visible=visible})
    f.x=200
    local reads,resolves=f.reads,f.resolves
    for _=1,1000 do f.press();f.release();f.tick(50);f.env.render() end
    assert(f.captures==0 and f.wheels==0 and f.writes==0 and f.logs==0 and f.state.errors==0,
           'ordinary clicks must perform no capture, injection, mutation or file IO')
    assert(f.resolves-resolves==1000, 'at most one bounded owner lookup per new press')
    assert(f.reads-reads==(visible and 1000 or 0), 'no native model reads when no owner is visible')
    print(('performance: 1000 %s clicks, zero captures/writes/logs'):format(visible and 'menu-content' or 'gameplay'))
end
local f=fixture(module,{visible=false})
local reads,resolves=f.reads,f.resolves
for _=1,10000 do f.tick();f.env.render() end
assert(f.reads==reads and f.resolves==resolves and f.captures==0 and f.logs==0,
       'idle frames must not poll native menus or capture pixels')
f.press();reads,resolves=f.reads,f.resolves
for _=1,10000 do f.tick();f.env.render() end
assert(f.reads==reads and f.resolves==resolves and f.captures==0 and f.logs==0,
       'holding fire outside menus must not repeat searches')
print('performance: 20000 idle/held frames, zero repeated searches or capture/file IO')

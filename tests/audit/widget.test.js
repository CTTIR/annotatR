// Standalone behavioural regressions: node --test tests/audit/widget.test.js
// A simulated canvas checks routing and geometry commands, not browser pixels.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');

function harness(delayed = false, canvasSize = 100) {
  let widget;
  const ready = [];
  const handlers = {}, inputs = [], images = [], registrations = {}, listeners = new Set();
  const ctx = {
    HTMLWidgets: { widget(x) { widget = x; } },
    Shiny: {
      addCustomMessageHandler(name, fn) { handlers[name] = fn; registrations[name] = (registrations[name] || 0) + 1; },
      setInputValue(name, value) { (name.endsWith("_ready") ? ready : inputs).push({name, value}); }
    },
    Image: class { set src(value) { this.uri = value; images.push(this); if (!delayed) this.onload(); } },
    window: { addEventListener(name, fn) { listeners.add(fn); }, removeEventListener(name, fn) { listeners.delete(fn); } }
  };
  ctx.window.Shiny = ctx.Shiny;
  ctx.document = { createElement() {
    const canvas = {setAttribute(){}, focus(){}, style: {}, events: {}, moves: [], commands: [],
      getBoundingClientRect() { return {left:0, top:0, width:canvasSize, height:canvasSize}; },
      addEventListener(name, fn) { this.events[name] = fn; }, removeEventListener(name) { delete this.events[name]; }, remove() {}
    };
    canvas.getContext = () => ({
      setTransform() {}, beginPath() {}, moveTo(x,y) { canvas.moves.push([x,y]); }, lineTo(x,y) { canvas.commands.push(["lineTo",x,y]); },
      arc(x,y) { canvas.commands.push(["arc",x,y]); }, closePath() { canvas.commands.push(["closePath"]); }, fill(rule) { canvas.commands.push(["fill",rule]); }, stroke() {},
      clearRect() { canvas.moves = []; canvas.commands = []; canvas.pixels = null; }, drawImage(im) { canvas.pixels = im.uri; }
    });
    return canvas;
  }};
  vm.createContext(ctx);
  vm.runInContext(fs.readFileSync(path.join(__dirname,'../../inst/htmlwidgets/atcanvas.js'),'utf8'),ctx);
  function create(id, features=[]) {
    let canvas;
    const el = {id, isConnected: true, getBoundingClientRect() { return {width:100,height:100}; },
      appendChild(child) { canvas = child; }};
    const w = widget.factory(el,100,100);
    const value = {tileSource:{width:100,height:100,dataUri:'fixture'}, identity:{entry_id:'entry-a',revision:0},tool:'erase',annotations:{features}};
    w.renderValue(value);
    return {canvas, w, el, value, render(changes = {}) { Object.assign(value, changes); w.renderValue(value); }, click(x,y) { canvas.events.mousedown({clientX:x,clientY:y}); }};
  }
  return {create, inputs, ready, handlers, images, registrations, listeners};
}
const ring = (x0,y0,x1,y1) => [[x0,y0],[x1,y0],[x1,y1],[x0,y1],[x0,y0]];
const feature = geometry => ({type:'Feature',properties:{roi_id:'roi',layer:'L',label:'a'},geometry});

test('A24 hole hit-testing ignores empty interior and selects shell', () => {
  const h = harness();
  const a = h.create('a',[feature({type:'Polygon',coordinates:[ring(0,0,100,100),ring(40,40,60,60)]})]);
  a.click(50,50);
  assert.equal(h.inputs.length,0,'a click in a hole must not erase the polygon');
  a.click(20,20);
  assert.equal(h.inputs.at(-1).name,'a_erased');
  assert.equal(h.inputs.at(-1).value.payload,'roi');
});

test('A24 polygon display submits the exterior and hole contours', () => {
  const h = harness();
  const a = h.create('a',[feature({type:'Polygon',coordinates:[ring(0,0,100,100),ring(40,40,60,60)]})]);
  assert.deepEqual(a.canvas.moves,[[0,0],[40,40]]);
});

test('A24 MultiPolygon display submits both disconnected components', () => {
  const h = harness();
  const a = h.create('a',[feature({type:'MultiPolygon',coordinates:[[ring(0,0,20,20)],[ring(80,80,100,100)]]})]);
  assert.deepEqual(a.canvas.moves,[[0,0],[80,80]]);
});

test('A24 MultiPolygon hit-testing selects a component and ignores the gap', () => {
  const h = harness();
  const a = h.create('a',[feature({type:'MultiPolygon',coordinates:[[ring(0,0,20,20)],[ring(80,80,100,100)]]})]);
  a.click(50,50);
  assert.equal(h.inputs.length,0);
  a.click(90,90);
  assert.equal(h.inputs.at(-1)?.name,'a_erased');
});

test('A25 tool routing targets each mounted widget independently', () => {
  const h = harness();
  const a = h.create('a'), b = h.create('b');
  h.handlers['atcanvas-set_tool']({id:'a',tool:'point'});
  a.click(20,20);
  assert.equal(h.inputs.at(-1)?.name,'a_created');
  assert.equal(h.inputs.at(-1).value.payload.geometry.type,'Point');
  h.inputs.length = 0;
  b.click(30,30);
  assert.equal(h.inputs.length,0);
  h.handlers['atcanvas-set_tool']({id:'b',tool:'point'});
  b.click(30,30);
  assert.equal(h.inputs.at(-1)?.name,'b_created');
});


test('polygon contours close and fill even-odd, without filling lines', () => {
  const h = harness(), a = h.create('a',[feature({type:'Polygon',coordinates:[ring(0,0,100,100),ring(40,40,60,60)]})]);
  assert.equal(a.canvas.commands.filter(x=>x[0]==='lineTo').length,8);
  assert.equal(a.canvas.commands.filter(x=>x[0]==='closePath').length,2);
  assert.deepEqual(a.canvas.commands.filter(x=>x[0]==='fill'),[['fill','evenodd']]);
  a.render({annotations:{features:[feature({type:'LineString',coordinates:[[10,10],[30,30],[50,10]]})]}});
  assert.equal(a.canvas.commands.filter(x=>x[0]==='fill').length,0);
});

for (const [type, coordinates, hit] of [
  ['Point',[20,20],[20,20]], ['MultiPoint',[[20,20],[80,80]],[80,80]],
  ['LineString',[[10,10],[30,30]],[20,20]],
  ['Polygon',[ring(10,10,30,30)],[20,20]],
  ['MultiPolygon',[[ring(10,10,30,30)],[ring(70,70,90,90)]],[80,80]]
]) test(type+' hit and translation preserve every coordinate and properties', () => {
  const h = harness(), f = feature({type,coordinates}), before = JSON.parse(JSON.stringify(coordinates));
  const a = h.create('a',[f]);
  h.handlers['atcanvas-set_tool']({id:'a',tool:'edit'});
  a.click(...hit); a.canvas.events.mousemove({clientX:hit[0]+5,clientY:hit[1]+7}); a.canvas.events.mouseup({});
  const emitted = h.inputs.at(-1)?.value;
  assert.equal(emitted?.entry_id,'entry-a'); assert.equal(emitted?.revision,0);
  assert.equal(emitted?.payload.roi_id,'roi');
  const shift = c => typeof c[0]==='number' ? [c[0]+5,c[1]+7] : c.map(shift);
  assert.deepEqual(JSON.parse(JSON.stringify(emitted.payload.geometry.coordinates)),shift(before));
  assert.equal(f.properties.label,'a');
});

for (const changed of [{entry_id:'entry-b',revision:0},{entry_id:'entry-a',revision:1}])
for (const tool of ['rect','freehand','circle','polygon','edit']) test(tool+' is cancelled on '+JSON.stringify(changed), () => {
  const h = harness(), a = h.create('a',[feature({type:'Polygon',coordinates:[ring(0,0,100,100)]})]);
  h.handlers['atcanvas-set_tool']({id:'a',tool}); a.click(20,20);
  a.render({identity:changed,tool,annotations:{features:[]}});
  a.canvas.events.mousemove({clientX:40,clientY:40}); a.canvas.events.mouseup({}); a.canvas.events.dblclick({});
  assert.equal(h.inputs.length,0);
});

test('base and overlay loads ignore older generations and missing sources clear pixels', () => {
  const h = harness(true), a = h.create('a');
  const old = h.images[0];
  a.render({tileSource:{width:100,height:100,dataUri:'new'},identity:{entry_id:'entry-b',revision:1}});
  h.images[1].onload(); old.onload(); assert.equal(a.canvas.pixels,'new');
  h.handlers['atcanvas-set_overlay']({id:'a',overlay:'old-overlay',alpha:0.5});
  const overlay = h.images.at(-1);
  a.render({tileSource:{width:100,height:100,dataUri:null}}); overlay.onload();
  assert.equal(a.canvas.pixels,null);
  a.render({tileSource:{width:100,height:100,dataUri:'pending'}});
  a.render({identity:{entry_id:'entry-b',revision:2}});
  h.images.at(-1).onload(); assert.equal(a.canvas.pixels,'pending');
});

test('one dispatcher per message survives remount, disposal removes listeners and callbacks', () => {
  const h = harness(true), a = h.create('a'), b = h.create('b');
  const fresh = h.create('a');
  assert.equal(h.listeners.size,2);
  assert.ok(Object.values(h.registrations).every(n=>n===1));
  assert.equal(Object.keys(a.canvas.events).length,0);
  fresh.w.dispose(); assert.equal(h.listeners.size,1);
  h.images.at(-1).onload(); assert.equal(fresh.canvas.pixels,null);
  h.images[1].onload();
  h.handlers['atcanvas-set_tool']({id:'b',tool:'point'}); b.click(10,10);
  assert.equal(h.inputs.at(-1).name,'b_created');
});

test('creation captures the displayed target at gesture birth', () => {
  const h = harness(), a = h.create('a');
  a.render({tool:'rect',options:{creationTarget:{layer:'L',label:'first'}}});
  a.click(10,10);
  a.value.options.creationTarget = {layer:'L',label:'second'};
  a.canvas.events.mousemove({clientX:30,clientY:30}); a.canvas.events.mouseup({});
  assert.deepEqual(JSON.parse(JSON.stringify(h.inputs.at(-1).value.payload.target)),{layer:'L',label:'first'});
});

test('MultiPoint display draws disconnected circles and lines select only their stroke', () => {
  const h = harness(), a = h.create('a',[feature({type:'MultiPoint',coordinates:[[20,20],[80,80]]})]);
  assert.deepEqual(a.canvas.commands.filter(x=>x[0]==='arc'),[['arc',20,20],['arc',80,80]]);
  assert.deepEqual(a.canvas.commands.filter(x=>x[0]==='fill'),[['fill',undefined]],'overlapping point markers use a union fill');
  a.click(50,50); assert.equal(h.inputs.length,0);
  a.render({annotations:{features:[feature({type:'LineString',coordinates:[[10,10],[30,30],[50,10]]})]}});
  a.click(30,15); assert.equal(h.inputs.length,0,'line interior must not behave like a polygon');
  a.click(20,20); assert.equal(h.inputs.at(-1).value.payload,'roi');
});

test('only the newest overlay callback can paint and disposal cancels pending overlays', () => {
  const h = harness(true), a = h.create('a');
  h.handlers['atcanvas-set_overlay']({id:'a',overlay:'old',alpha:0.5}); const old = h.images.at(-1);
  h.handlers['atcanvas-set_overlay']({id:'a',overlay:'new',alpha:0.5}); const recent = h.images.at(-1);
  recent.onload(); old.onload(); assert.equal(a.canvas.pixels,'new');
  h.handlers['atcanvas-set_overlay']({id:'a',overlay:'pending',alpha:0.5});
  a.w.dispose(); h.images.at(-1).onload(); assert.equal(a.canvas.pixels,null);
});

test('a same-source render restarts its pending overlay without accepting the old callback', () => {
  const h = harness(true), a = h.create('a');
  h.images[0].onload();
  h.handlers['atcanvas-set_overlay']({id:'a',overlay:'requested-overlay',alpha:0.25});
  const old = h.images.at(-1);
  a.render({tool:'point'});
  assert.equal(h.images.filter(im=>im.uri==='requested-overlay').length,2,
    'a compatible render must retain and restart the pending overlay');
  const retry = h.images.at(-1);
  old.onload(); assert.equal(a.canvas.pixels,'fixture','the superseded callback must stay ignored');
  retry.onload(); assert.equal(a.canvas.pixels,'requested-overlay');
  const count = h.images.length;
  a.render({tool:'erase'});
  assert.equal(h.images.length,count,'an already-loaded compatible overlay is retained without a new request');
  assert.equal(a.canvas.pixels,'requested-overlay');
});

test('failed decode reports not ready and blocks drawing until current load succeeds', () => {
  const h=harness(true),a=h.create('a');
  a.render({tool:'point'}); a.click(20,20);
  assert.equal(h.inputs.filter(x=>x.name==='a_created').length,0);
  assert.equal(typeof h.images.at(-1).onerror,'function');
  h.images.at(-1).onerror();
  assert.equal(h.ready.at(-1).name,'a_ready');
  assert.equal(h.ready.at(-1).value.payload.ready,false);
});
test('keyboard rectangle anchors and Escape cancellation create real geometry', () => {
  const h=harness(),a=h.create('a'); a.render({tool:'rect'});
  assert.equal(a.canvas.tabIndex,0);
  const key=key=>a.canvas.events.keydown({key,preventDefault(){},stopPropagation(){}});
  key('Enter'); key('ArrowRight'); key('ArrowDown'); key('Enter');
  const f=h.inputs.filter(x=>x.name==='a_created').at(-1).value.payload;
  assert.deepEqual(JSON.parse(JSON.stringify(f.geometry.coordinates)),[ring(50,50,51,51)]);
  key('Enter'); key('ArrowRight'); key('Escape'); key('Enter'); key('Escape');
  assert.equal(h.inputs.filter(x=>x.name==='a_created').length,1);
});
test('protected and hidden features cannot be hit by erase', () => {
  const h=harness(), f=feature({type:'Point',coordinates:[20,20]}); f.properties.locked=true;
  const a=h.create('a',[f]); a.click(20,20);
  assert.equal(h.inputs.filter(x=>x.name==='a_erased').length,0);
});

test('pointer coordinates use canvas content dimensions rather than bordered host size',()=>{
 const h=harness(false,98),a=h.create('a');a.render({tool:'point'});a.click(49,49);
 assert.deepEqual(JSON.parse(JSON.stringify(h.inputs.at(-1).value.payload.geometry.coordinates)),[50,50]);
});

// Start widget-app.R first. Environment overrides keep this runner portable.
const {chromium} = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const assert = require('node:assert/strict');
const path = require('node:path');
(async () => {
  const browser = await chromium.launch({headless:true,
    ...(process.env.CHROMIUM_PATH ? {executablePath:process.env.CHROMIUM_PATH} : {})});
  try {
    const page = await browser.newPage({viewport:{width:1200,height:650}});
    const errors = []; page.on('pageerror', error => errors.push(error.message));
    await page.addInitScript(() => {
      window.fixtureResizeListeners = new Set();
      const add = window.addEventListener, remove = window.removeEventListener;
      window.addEventListener = function (name, listener, options) {
        if (name === 'resize') fixtureResizeListeners.add(listener);
        return add.call(this,name,listener,options);
      };
      window.removeEventListener = function (name, listener, options) {
        if (name === 'resize') fixtureResizeListeners.delete(listener);
        return remove.call(this,name,listener,options);
      };
    });
    await page.goto(process.env.ANNOTATR_BROWSER_URL || 'http://127.0.0.1:5818');
    await page.waitForFunction(() => document.querySelectorAll('canvas').length === 2 &&
      document.querySelector('#state').textContent.startsWith('[{'));
    await page.evaluate(() => {
      window.fixtureAcks = [];
      Shiny.addCustomMessageHandler('fixture-ack', x => window.fixtureAcks.push(x));
      window.fixtureEvents = []; window.fixtureHandlerAdds = [];
      const addHandler = Shiny.addCustomMessageHandler;
      Shiny.addCustomMessageHandler = function (name, fn) {
        fixtureHandlerAdds.push(name); return addHandler.call(this,name,fn);
      };
      $(document).on('shiny:inputchanged.fixture', e => {
        if (/canvas_(created|edited|erased)$/.test(e.name)) window.fixtureEvents.push({name:e.name,value:e.value});
      });
    });
    const state = () => page.locator('#state').textContent().then(JSON.parse);
    const action = async id => {
      await page.locator('#'+id).click();
      await page.waitForFunction(id => window.fixtureAcks.includes(id), id);
      await page.evaluate(() => { window.fixtureAcks = []; });
    };
    const a = page.locator('#a-canvas canvas'), b = page.locator('#b-canvas canvas');
    // Widget has a 100x90 image fitted into 570x360: scale=4, horizontal padding=85.
    const coords = async (locator,x,y) => {
      const box = await locator.boundingBox(), z = Math.min(box.width/100,box.height/90);
      return {x:(box.width-100*z)/2+x*z,y:(box.height-90*z)/2+y*z};
    };
    const click = async (locator,x,y) => locator.click({position:await coords(locator,x,y)});
    const drag = async (locator,x,y,dx,dy) => {
      const box = await locator.boundingBox(), p = await coords(locator,x,y), q = await coords(locator,x+dx,y+dy);
      await locator.evaluate(c => {
        window.fixtureDrag = [];
        c.addEventListener('mousedown',e=>fixtureDrag[0]=[e.clientX,e.clientY],{once:true});
        const move=e=>fixtureDrag[1]=[e.clientX,e.clientY]; c.addEventListener('mousemove',move);
        window.fixtureEndDrag=()=>c.removeEventListener('mousemove',move);
      });
      await page.mouse.move(box.x+p.x,box.y+p.y); await page.mouse.down();
      await page.mouse.move(box.x+q.x,box.y+q.y,{steps:4}); await page.mouse.up();
      const observed=await page.evaluate(()=>{fixtureEndDrag();return fixtureDrag;});
      const z=Math.min(box.width/100,box.height/90);
      return [(observed[1][0]-observed[0][0])/z,(observed[1][1]-observed[0][1])/z];
    };
    const pixel = async (id,x,y) => page.evaluate(({id,x,y}) => {
      const c = document.querySelector('#'+id+' canvas'), z = Math.min(c.width/100,c.height/90);
      return Array.from(c.getContext('2d').getImageData((c.width-100*z)/2+x*z,(c.height-90*z)/2+y*z,1,1).data);
    },{id,x,y});
    await page.waitForFunction(() => {
      const c = document.querySelector('#a-canvas canvas');
      return c.getContext('2d').getImageData(c.width/2,c.height/2,1,1).data[0] === 255;
    });
    const hole = await pixel('a-canvas',50,45), shell = await pixel('a-canvas',20,45);
    assert.deepEqual(hole,[255,255,255,255]); assert.ok(shell[0]<255);
    await click(a,50,45); assert.equal(await page.evaluate(()=>fixtureEvents.length),0);
    if (process.env.ANNOTATR_BROWSER_ARTIFACT_DIR) {
      require('node:fs').mkdirSync(process.env.ANNOTATR_BROWSER_ARTIFACT_DIR,{recursive:true});
      await page.screenshot({path:path.join(process.env.ANNOTATR_BROWSER_ARTIFACT_DIR,'t10-widget-hole.png')});
    }
    const before = await state();
    await action('edit_b'); const actualDrag = await drag(b,12.5,15,5,3);
    await page.waitForFunction(() => JSON.parse(document.querySelector('#state').textContent)[1].revision === 1);
    const edited = (await state())[1].rois[0];
    assert.equal(edited.id,before[1].rois[0].id); assert.equal(edited.level,1);
    assert.equal(edited.geometry.type,'MultiPolygon');
    assert.deepEqual(edited.attributes,{note:'keep',score:7}); assert.equal(edited.author,'owner');
    // Chromium quantizes pointer positions when the fitted viewport has a
    // fractional scale. Compare against observed DOM pointer displacement,
    // then apply the independent stored-level ratios 40/100 and 30/90.
    const expectedFirst=[2+actualDrag[0]*0.4,2+actualDrag[1]/3];
    const expectedSecond=[32+actualDrag[0]*0.4,22+actualDrag[1]/3];
    for(const [actual,expected] of [[edited.geometry.coordinates[0][0][0],expectedFirst],
      [edited.geometry.coordinates[1][0][0],expectedSecond]])
      actual.forEach((value,i)=>assert.ok(Math.abs(value-expected[i])<0.0001,JSON.stringify({actual,expected})));
    await action('point_a'); await click(a,20,20);
    await page.waitForFunction(() => JSON.parse(document.querySelector('#state').textContent)[0].revision === 1);
    await action('point_b'); await click(b,50,45);
    await page.waitForFunction(() => JSON.parse(document.querySelector('#state').textContent)[1].revision === 2);
    assert.deepEqual((await state()).map(x=>x.rois.length),[2,2]);
    // Stale source/revision and raw events reach real server ingress and are rejected.
    await page.evaluate(() => {
      const e = fixtureEvents.find(x=>x.name==='a-canvas_created').value;
      Shiny.setInputValue('a-canvas_created',e,{priority:'event'});
      Shiny.setInputValue('b-canvas_erased',JSON.parse(document.querySelector('#state').textContent)[1].rois[0].id,{priority:'event'});
      Shiny.setInputValue('b-canvas_erased',{entry_id:'old-entry',revision:2,payload:JSON.parse(document.querySelector('#state').textContent)[1].rois[0].id},{priority:'event'});
    });
    // Proxy acknowledgment is a round trip barrier after the invalid inputs.
    await action('erase_a'); assert.deepEqual((await state()).map(x=>x.revision),[1,2]);
    await click(a,20,45);
    await page.waitForFunction(() => JSON.parse(document.querySelector('#state').textContent)[0].revision === 2);
    // Removing the output really disposes its resize and pointer listeners.
    await page.evaluate(() => { window.oldCanvas = document.querySelector('#a-canvas canvas'); window.resizeBeforeRemount = fixtureResizeListeners.size; });
    await page.locator('#remount').click();
    await page.waitForFunction(() => document.querySelector('#a-canvas canvas') && document.querySelector('#a-canvas canvas') !== oldCanvas);
    assert.equal(await page.evaluate(()=>oldCanvas.isConnected),false);
    assert.equal(await page.evaluate(()=>fixtureResizeListeners.size === resizeBeforeRemount),true);
    assert.deepEqual(await page.evaluate(()=>fixtureHandlerAdds.filter(x=>x.startsWith('atcanvas-'))),[]);
    await action('point_a'); await click(a,50,45);
    await page.waitForFunction(() => JSON.parse(document.querySelector('#state').textContent)[0].revision === 3);
    // A real pointer gesture spanning render identity replacement emits nothing.
    await page.evaluate(() => {
      window.widgetValue = structuredClone(Shiny.shinyapp.$values['a-canvas'].x);
      HTMLWidgets.find('#a-canvas').renderValue({...widgetValue,tool:'rect'});
      window.beforeCancelled = fixtureEvents.length;
    });
    const box = await a.boundingBox(), start = await coords(a,20,20), end = await coords(a,40,40);
    await page.mouse.move(box.x+start.x,box.y+start.y); await page.mouse.down();
    await page.evaluate(() => HTMLWidgets.find('#a-canvas').renderValue({...widgetValue,tool:'rect',
      identity:{entry_id:'new-entry',revision:0}}));
    await page.mouse.move(box.x+end.x,box.y+end.y); await page.mouse.up();
    assert.equal(await page.evaluate(()=>fixtureEvents.length === beforeCancelled),true);
    // Actual network image loads deliberately complete out of order.
    let releaseOld, oldRequested;
    const oldRequest = new Promise(resolve=>{oldRequested=resolve;});
    const oldGate = new Promise(resolve=>{releaseOld=resolve;});
    const svg = colour => `<svg xmlns="http://www.w3.org/2000/svg" width="100" height="90"><rect width="100" height="90" fill="${colour}"/></svg>`;
    await page.route('**/slow-red.svg',async route=>{oldRequested();await oldGate;await route.fulfill({contentType:'image/svg+xml',body:svg('red')});});
    await page.route('**/fast-blue.svg',route=>route.fulfill({contentType:'image/svg+xml',body:svg('blue')}));
    await page.evaluate(() => {
      const NativeImage = window.Image; window.fixtureLoads = [];
      window.Image = function () {
        const im = new NativeImage(); im.addEventListener('load',()=>fixtureLoads.push(im.src)); return im;
      };
      window.loadFixture = uri => HTMLWidgets.find('#a-canvas').renderValue({...widgetValue,
        annotations:{features:[]},tileSource:{width:100,height:90,dataUri:uri}});
      loadFixture('/slow-red.svg');
    });
    await oldRequest;
    await page.evaluate(()=>loadFixture('/fast-blue.svg'));
    await page.waitForFunction(()=>fixtureLoads.some(x=>x.endsWith('/fast-blue.svg')));
    assert.deepEqual(await pixel('a-canvas',50,45),[0,0,255,255]);
    releaseOld();
    await page.waitForFunction(()=>fixtureLoads.some(x=>x.endsWith('/slow-red.svg')));
    assert.deepEqual(await pixel('a-canvas',50,45),[0,0,255,255]);
    // A requested overlay survives a same-source render while it is still loading.
    let releaseOverlay, overlayRequested;
    const overlayRequest = new Promise(resolve=>{overlayRequested=resolve;});
    const overlayGate = new Promise(resolve=>{releaseOverlay=resolve;});
    await page.route('**/slow-overlay.svg',async route=>{
      overlayRequested(); await overlayGate;
      await route.fulfill({contentType:'image/svg+xml',body:svg('lime')});
    });
    await action('overlay_a'); await overlayRequest;
    await page.evaluate(()=>loadFixture('/fast-blue.svg'));
    releaseOverlay();
    await page.waitForFunction(()=>fixtureLoads.filter(x=>x.endsWith('/slow-overlay.svg')).length === 2);
    const overlayPixel = await pixel('a-canvas',50,45);
    assert.equal(overlayPixel[0],0); assert.equal(overlayPixel[3],255);
    assert.ok(Math.abs(overlayPixel[1]-127.5)<=1.5 && Math.abs(overlayPixel[2]-127.5)<=1.5,
      'the retained half-opacity green overlay must blend with the blue base: '+JSON.stringify(overlayPixel));
    await page.evaluate(()=>loadFixture(null));
    assert.deepEqual(await pixel('a-canvas',50,45),[0,0,0,0]);
    await page.evaluate(()=>HTMLWidgets.find('#a-canvas').renderValue(widgetValue));
    await page.waitForFunction(()=>fixtureLoads.some(x=>x.startsWith('data:image/svg+xml')));
    const evidence = {hole,shell,independentProxyCounts:(await state()).map(x=>x.rois.length),multiEdit:edited,
      remounted:true,noAccumulatedHandlers:true,cancelledGesture:true,outOfOrderImages:true,pendingOverlaySurvivesRender:overlayPixel,missingSourceCleared:true,errors};
    assert.deepEqual(errors,[]);
    if (process.env.ANNOTATR_BROWSER_ARTIFACT_DIR) {
      const fs = require('node:fs'), dir = process.env.ANNOTATR_BROWSER_ARTIFACT_DIR;
      fs.mkdirSync(dir,{recursive:true});
      await page.screenshot({path:path.join(dir,'t10-widget.png')});
      fs.writeFileSync(path.join(dir,'t10-widget.json'),JSON.stringify(evidence,null,2)+'\n');
    }
    console.log(JSON.stringify(evidence,null,2));
  } finally { await browser.close(); }
})().catch(error=>{console.error(error);process.exitCode=1;});

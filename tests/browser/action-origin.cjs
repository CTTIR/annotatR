// Use app-journey.R. This probe delays actual widget render delivery while
// activating ordinary product controls; it does not forge their envelopes.
const {chromium}=require(process.env.PLAYWRIGHT_MODULE||'playwright');
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
(async()=>{
 const browser=await chromium.launch({headless:true,...(process.env.CHROMIUM_PATH?{executablePath:process.env.CHROMIUM_PATH}:{})});
 const page=await browser.newPage({viewport:{width:1450,height:980},deviceScaleFactor:1.5});
 const errors=[];page.on('pageerror',e=>errors.push(e.message));const evidence={};
 const state=()=>page.locator('#fixture_state').textContent().then(JSON.parse);
 const wait=fn=>page.waitForFunction(`(${fn})(JSON.parse(document.querySelector('#fixture_state')?.textContent||'{}'))`);
 const sync=async()=>{const value=Date.now()+Math.random();await page.evaluate(value=>Shiny.setInputValue('fixture_ping',value,{priority:'event'}),value);await page.waitForFunction(value=>JSON.parse(document.querySelector('#fixture_state').textContent).ping===value,value);};
 try {
  await page.goto(process.env.ANNOTATR_BROWSER_URL||'http://127.0.0.1:5819');
  await wait(s=>s.cursor===1&&s.error);
  await page.locator('#queue-nxt').click();await wait(s=>s.cursor===2&&s.ready);
  const origin=await page.evaluate(()=>atcanvasIdentity('canvas-canvas'));
  await page.evaluate(()=>{
   const widget=HTMLWidgets.find('#canvas-canvas'),render=widget.renderValue;
   window.originEvents=[];window.delayedRenders=[];
   const send=Shiny.setInputValue;
   Shiny.setInputValue=function(name,value,options){originEvents.push({name,value:structuredClone(value)});return send.call(this,name,value,options);};
   widget.renderValue=function(value){delayedRenders.push(value);};
   window.releaseCanvas=()=>{widget.renderValue=render;render.call(widget,delayedRenders.at(-1));};
  });
  for(const cursor of [3,4,5]){
   await page.locator('#queue-nxt').click();await page.waitForFunction(cursor=>JSON.parse(document.querySelector('#fixture_state').textContent).cursor===cursor,cursor);
  }
  await page.waitForFunction(()=>window.annotatRIdentity?.entry_id===JSON.parse(document.querySelector('#fixture_state').textContent).entry_id&&delayedRenders.length>=3);
  const pending=await state();assert.equal(pending.ready,false);
  assert.notEqual(pending.entry_id,origin.entry_id);assert.deepEqual(await page.evaluate(()=>atcanvasIdentity('canvas-canvas')),origin);
  evidence.divergent={rendered:origin,server:await page.evaluate(()=>annotatRIdentity)};
  for(const id of ['session-complete','session-save','session-flag']){await page.locator('#'+id).click();await sync();}
  await page.locator('#canvas-canvas canvas').focus();
  for(const key of ['s','f','Shift+Enter','Control+z','Shift+V']){await page.keyboard.press(key);await sync();}
  const rejected=await state();evidence.afterMutations=rejected;
  assert.equal(rejected.attempts,0,'an unseen entry must not be saved or completed');
  assert.equal(rejected.status[4],'pending');assert.equal(rejected.cursor,5);assert.equal(rejected.revision,0);
  const controls=await page.evaluate(()=>originEvents.filter(e=>/^(session-(complete|save|flag)|key_(save|flag|commit_advance|undo|paste_forward))$/.test(e.name)));
  assert.equal(controls.length,8);
  for(const e of controls)assert.deepEqual({entry_id:e.value.entry_id,revision:e.value.revision},origin,e.name);
  evidence.controlOrigins=controls;
  await page.evaluate(()=>releaseCanvas());await wait(s=>s.cursor===5&&s.ready);
  await page.locator('#session-save').click();await wait(s=>s.attempts===1&&s.saved==='saved');
  // The current failed-display stamp permits saving retained annotations.
  await page.locator('#queue-prev').click();await wait(s=>s.cursor===4&&s.error?.includes('decoded'));
  const failed=await state();assert.equal(failed.ready,false);assert.ok(failed.rois.annotations.length>0);
  await page.waitForFunction(()=>atcanvasIdentity('canvas-canvas')?.entry_id===JSON.parse(document.querySelector('#fixture_state').textContent).entry_id);
  await page.locator('#session-save').click();await wait(s=>s.attempts===2&&s.saved==='saved');
  await page.locator('#canvas-canvas canvas').focus();await page.keyboard.press('s');await wait(s=>s.attempts===3);
  evidence.savedAfterDecodeFailure=await state();
  // Keyboard recovery still uses current server identity while a render is held.
  await page.evaluate(()=>{
   const widget=HTMLWidgets.find('#canvas-canvas'),render=widget.renderValue;
   window.delayedRenders=[];widget.renderValue=function(value){delayedRenders.push(value);};
   window.releaseCanvas=()=>{widget.renderValue=render;render.call(widget,delayedRenders.at(-1));};
  });
  await page.keyboard.press('p');await wait(s=>s.cursor===3&&s.error);
  await page.keyboard.press('p');await wait(s=>s.cursor===2);
  assert.equal((await state()).attempts,3);
  await page.evaluate(()=>releaseCanvas());await wait(s=>s.cursor===2&&s.ready);
  evidence.recovered=await state();evidence.errors=errors;assert.deepEqual(errors,[]);
  if(process.env.ANNOTATR_BROWSER_ARTIFACT_DIR){const dir=process.env.ANNOTATR_BROWSER_ARTIFACT_DIR;fs.mkdirSync(dir,{recursive:true});fs.writeFileSync(path.join(dir,'t11-action-origin.json'),JSON.stringify(evidence,null,2));await page.screenshot({path:path.join(dir,'t11-action-origin.png')});}
  console.log(JSON.stringify(evidence,null,2));
 }catch(error){console.error('State:',await state().catch(()=>null));throw error;}finally{await browser.close();}
})().catch(error=>{console.error(error);process.exitCode=1;});

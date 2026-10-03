// Full app controls, keyboard geometry and recovery. Run app-journey.R first.
const {chromium}=require(process.env.PLAYWRIGHT_MODULE||'playwright');
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
(async()=>{
 const browser=await chromium.launch({headless:true,...(process.env.CHROMIUM_PATH?{executablePath:process.env.CHROMIUM_PATH}:{})});
 const page=await browser.newPage({viewport:{width:1450,height:980},deviceScaleFactor:1.5});
 const errors=[];page.on('pageerror',e=>errors.push(e.message));
 const evidence={viewport:{width:1450,height:980},deviceScaleFactor:1.5};
 try {
  await page.goto(process.env.ANNOTATR_BROWSER_URL||'http://127.0.0.1:5819');
  const state=()=>page.locator('#fixture_state').textContent().then(JSON.parse);
  const wait=async fn=>page.waitForFunction(`(${fn})(JSON.parse(document.querySelector('#fixture_state').textContent||'{}'))`);
  await wait(s=>s.cursor===1 && s.error);
  await page.evaluate(()=>{
   window.intentLog=[];window.held=[];
   const send=Shiny.setInputValue;
   Shiny.setInputValue=function(name,value,options){
    intentLog.push({name,value:structuredClone(value)});
    if(window.holdName===name){held.push({name,value:structuredClone(value),options});return;}
    return send.call(this,name,value,options);
   };
   window.releaseIntent=()=>{window.holdName=null;for(const e of held.splice(0))send(e.name,e.value,e.options);};
  });
  const tabTo=async selector=>{
   for(let i=0;i<120;i++){
    if(await page.evaluate(selector=>document.activeElement?.matches(selector),selector))return;
    await page.keyboard.press('Tab');
   }
   throw Error('Keyboard focus did not reach '+selector);
  };
  const focusCanvas=()=>tabTo('#canvas-canvas canvas');
  const sync=async()=>{const value=Date.now()+Math.random();await page.evaluate(value=>Shiny.setInputValue('fixture_ping',value,{priority:'event'}),value);await page.waitForFunction(value=>JSON.parse(document.querySelector('#fixture_state').textContent).ping===value,value);};
  const ready=async cursor=>{await page.waitForFunction(cursor=>{const s=JSON.parse(document.querySelector('#fixture_state').textContent);return s.cursor===cursor&&s.ready&&window.atcanvasIdentity('canvas-canvas')?.revision===s.revision&&window.annotatRIdentity?.revision===s.revision;},cursor);};
  const hold=async name=>page.evaluate(name=>{window.holdName=name},name);
  const release=async()=>{await page.evaluate(()=>releaseIntent());await sync();};
  await focusCanvas();await page.keyboard.press('n');await ready(2);
  evidence.initialRecovery=await state();
  evidence.stylePixels=await page.evaluate(()=>{
    const c=document.querySelector('#canvas-canvas canvas'),z=Math.min(c.width/30,c.height/30);
    const pixel=(x,y)=>Array.from(c.getContext('2d').getImageData((c.width-30*z)/2+x*z,(c.height-30*z)/2+y*z,1,1).data);
    return {hidden:pixel(10,10),locked:pixel(22,22)};
  });
  assert.deepEqual(evidence.stylePixels.hidden,[255,255,255,255]);
  assert.ok(evidence.stylePixels.locked[1]>evidence.stylePixels.locked[0]);
  await tabTo('#layers-label input[value="first"]');
  await page.keyboard.press('ArrowDown');await wait(s=>s.active_label==='second');
  assert.equal(await page.evaluate(()=>document.activeElement.matches('#layers-label input[value="second"]')),true,'radio focus survives native selection');
  await focusCanvas();await page.keyboard.press('w');await wait(s=>s.tool==='rect');
  await page.keyboard.press('Enter');await page.keyboard.press('Shift+ArrowRight');await page.keyboard.press('Shift+ArrowDown');await page.keyboard.press('Enter');
  await wait(s=>s.revision===1);await ready(2);
  let current=await state();const rectangle=current.rois.annotations.at(-1);
  assert.equal(rectangle.label,'second');assert.deepEqual(rectangle.geometry.coordinates,[[[15,15],[25,15],[25,25],[15,25],[15,15]]]);
  assert.equal(await page.locator('#layers-label input[value="second"]').isChecked(),true,'selection stays after annotation rerender');
  evidence.keyboardRectangle=rectangle;
  evidence.canvas=await page.locator('#canvas-canvas canvas').boundingBox();
  if(process.env.ANNOTATR_BROWSER_ARTIFACT_DIR){fs.mkdirSync(process.env.ANNOTATR_BROWSER_ARTIFACT_DIR,{recursive:true});await page.screenshot({path:path.join(process.env.ANNOTATR_BROWSER_ARTIFACT_DIR,'t11-keyboard.png')});}
  await page.keyboard.press('Control+z');await wait(s=>s.revision===2);await ready(2);
  assert.equal((await state()).rois.annotations.length,1);
  await page.keyboard.press('Control+Shift+z');await wait(s=>s.revision===3);await ready(2);
  await page.keyboard.press('Enter');await page.keyboard.press('ArrowLeft');await page.keyboard.press('Escape');await sync();
  assert.equal((await state()).revision,3);
  await page.keyboard.press('Shift+Enter');await wait(s=>s.cursor===3&&s.error);
  assert.equal((await state()).attempts,1);assert.equal((await state()).status[1],'complete');
  evidence.commit=await state();
  // Failed reader entries and browser decode failures retain current navigation identity.
  await page.keyboard.press('n');await wait(s=>s.cursor===4&&s.error?.includes('decoded'));
  const decode=await state();assert.equal(decode.ready,false);
  const beforeDecode=decode.revision;
  await page.keyboard.press('y');await page.keyboard.press('Enter');await sync();
  assert.equal((await state()).revision,beforeDecode);
  evidence.decodeFailure=await state();
  await page.locator('#queue-nxt').click();await ready(5);
  await page.locator('#canvas-copy').click();await wait(s=>s.revision===1);await ready(5);
  assert.equal((await state()).rois.locked.length,1,'copy respects the locked target layer');
  assert.equal((await state()).rois.annotations.length,2);
  await page.locator('#canvas-undo').click();await wait(s=>s.revision===2);await ready(5);
  await page.locator('#canvas-redo').click();await wait(s=>s.revision===3);await ready(5);
  await page.locator('#queue-prev').click();await wait(s=>s.cursor===4&&s.error?.includes('decoded'));
  await focusCanvas();await page.keyboard.press('p');await wait(s=>s.cursor===3&&s.error);
  await page.locator('#queue-prev').click();await ready(2);
  assert.equal((await state()).rois.annotations.at(-1).id,rectangle.id);
  // A stale click and raw deletion use a real current ROI ID: acceptance would remove it.
  await hold('canvas-undo');await page.locator('#canvas-undo').click();
  await page.locator('#queue-nxt').click();await wait(s=>s.cursor===3);await release();
  await page.locator('#queue-prev').click();await ready(2);
  assert.equal((await state()).revision,3,'queued ordinary Undo cannot cross entries');
  await hold('session-complete');await page.locator('#session-complete').click();
  await page.locator('#queue-nxt').click();await wait(s=>s.cursor===3);await release();
  assert.equal((await state()).attempts,1);assert.notEqual((await state()).status[2],'complete');
  await page.locator('#queue-prev').click();await ready(2);
  await page.evaluate(id=>{
   Shiny.setInputValue('canvas-canvas_erased',{entry_id:'wrong-entry',revision:3,payload:id},{priority:'event'});
   Shiny.setInputValue('canvas-canvas_erased',id,{priority:'event'});
  },rectangle.id);await sync();
  assert.equal((await state()).rois.annotations.at(-1).id,rectangle.id);
  // Actual +layer/+label controls capture their fields before delayed delivery.
  await page.locator('#layers-new_layer').fill('original');await hold('layers-add_layer');
  await page.locator('#layers-add_layer').click();await page.locator('#layers-new_layer').fill('later');await release();
  await wait(s=>s.labels.original);await ready(2);assert.equal((await state()).labels.later,undefined);
  await page.locator('#layers-new_label').fill('captured');await hold('layers-add_label');
  await page.locator('#layers-add_label').click();
  await page.locator('#layers-new_label').fill('later');
  await page.locator('#layers-layer input[value="annotations"]').check();await wait(s=>s.active_layer==='annotations');
  await release();await wait(s=>Array.isArray(s.labels.original)&&s.labels.original.includes('captured'));await ready(2);
  assert.equal((await state()).labels.annotations.includes('captured'),false);
  // Copy-forward cannot change the locked target; ROI protection survives all deletion controls.
  const protectedId=(await state()).rois.annotations[0].id,layerLockedId=(await state()).rois.locked[0].id;
  await page.locator('a[data-value="Summary"]').click();
  for(const id of [protectedId,layerLockedId]){
   await page.locator('#roitable-del_id').fill(id);await page.locator('#roitable-delete').click();await sync();
  }
  assert.equal((await state()).rois.annotations[0].id,protectedId);assert.equal((await state()).rois.locked[0].id,layerLockedId);
  // Delayed ROI text control preserves its clicked target even after text changes.
  await page.locator('#roitable-del_id').fill(rectangle.id);await hold('roitable-delete');
  await page.locator('#roitable-delete').click();await page.locator('#roitable-del_id').fill(protectedId);await release();
  await wait(s=>s.rois.annotations.length===1);await ready(2);
  // Dirty replacement with a bad first image retains a recoverable queue.
  await page.locator('a[data-value="Data"]').click();
  const replacement=(await state()).replacement;
  await page.locator('#data-dir').fill(replacement);await hold('data-load');await page.locator('#data-load').click();
  await page.locator('#data-dir').fill('/changed-after-click');await release();
  await wait(s=>s.recovery&&s.error&&s.cursor===1);
  assert.equal((await state()).autosave,false);evidence.failedReplacement=await state();
  await page.locator('#data-restore').click();await ready(2);
  assert.equal((await state()).saved,'unsaved');assert.ok((await state()).labels.original.includes('captured'));
  evidence.restored=await state();
  // Native buttons retain Enter; a save activation is exactly one save, not a canvas anchor.
  await page.locator('a[data-value="Annotate"]').click();await tabTo('#session-save');
  await page.keyboard.press('Enter');await wait(s=>s.saved==='saved'&&s.attempts===2);
  await focusCanvas();await page.keyboard.press('y');await wait(s=>s.tool==='point');await page.keyboard.press('Enter');
  await wait(s=>s.saved==='unsaved');await ready(2);
  await page.keyboard.press('e');await wait(s=>s.tool==='polygon');
  await page.keyboard.press('Space');await page.keyboard.press('ArrowRight');await page.keyboard.press('Space');
  await page.keyboard.press('ArrowDown');await page.keyboard.press('Space');await page.keyboard.press('Enter');
  await wait(s=>s.rois.annotations.length===3);await ready(2);
  evidence.keyboardPolygon=(await state()).rois.annotations.at(-1);
  assert.equal(evidence.keyboardPolygon.geometry.type,'Polygon');
  await page.keyboard.press('s');await wait(s=>s.saved==='saved'&&s.attempts===3);
  await page.keyboard.press('Control+e');await page.locator('#export-run').waitFor({state:'visible'});
  await tabTo('#export-formats input[value="mask_tiff"]');await page.keyboard.press('Space');
  await tabTo('#export-run');
  const downloadPromise=page.waitForEvent('download');await page.keyboard.press('Enter');const download=await downloadPromise;
  assert.equal(await download.failure(),null);
  await wait(s=>s.attempts===3);
  await page.waitForFunction(()=>document.querySelector('#export-outcome').textContent.includes('complete'));
  assert.match(await page.locator('#export-outcome').textContent(),/1 complete; 0 failed/);
  evidence.final=await state();evidence.errors=errors;
  // Pointer coordinates use the actual canvas box at this viewport/display scale.
  await page.locator('a[data-value="Annotate"]').click();await page.locator('#canvas-tool_point').click();await page.waitForFunction(()=>document.querySelector('#canvas-canvas canvas').dataset.tool==='point');
  const box=await page.locator('#canvas-canvas canvas').boundingBox(),z=Math.min(box.width/30,box.height/30);
  await page.locator('#canvas-canvas canvas').click({position:{x:(box.width-30*z)/2+5*z,y:(box.height-30*z)/2+7*z}});
  await wait(s=>s.rois.annotations.length===4);
  evidence.scaledPointer=(await state()).rois.annotations.at(-1).geometry.coordinates;
  assert.ok(Math.abs(evidence.scaledPointer[0]-5)<0.01&&Math.abs(evidence.scaledPointer[1]-7)<0.01,JSON.stringify(evidence.scaledPointer));
  // A new browser session reopens the real checkpoint through at_resume().
  const resumed=await browser.newPage({viewport:{width:1100,height:800},deviceScaleFactor:1.5});
  resumed.on('pageerror',e=>errors.push(e.message));
  await resumed.goto((process.env.ANNOTATR_BROWSER_URL||'http://127.0.0.1:5819')+'?resume=1');
  await resumed.waitForFunction(()=>{const s=JSON.parse(document.querySelector('#fixture_state')?.textContent||'{}');return s.cursor===2&&s.ready;});
  evidence.resumed=JSON.parse(await resumed.locator('#fixture_state').textContent());
  assert.deepEqual(evidence.resumed.rois,evidence.final.rois);assert.equal(evidence.resumed.saved,'saved');
  await resumed.close();
  assert.deepEqual(errors,[]);
  if(process.env.ANNOTATR_BROWSER_ARTIFACT_DIR){const dir=process.env.ANNOTATR_BROWSER_ARTIFACT_DIR;fs.mkdirSync(dir,{recursive:true});await download.saveAs(path.join(dir,'t11-export.zip'));await page.screenshot({path:path.join(dir,'t11-app.png'),fullPage:true});fs.writeFileSync(path.join(dir,'t11-app.json'),JSON.stringify(evidence,null,2));}
  console.log(JSON.stringify(evidence,null,2));
 } catch(e){console.error('State:',await page.locator('#fixture_state').textContent().catch(()=>''));console.error('Active:',await page.evaluate(()=>document.activeElement?.outerHTML).catch(()=>''));throw e;}
 finally{await browser.close();}
})();

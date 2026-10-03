const {chromium}=require(process.env.PLAYWRIGHT_MODULE||'playwright');
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
(async()=>{const browser=await chromium.launch({headless:true,...(process.env.CHROMIUM_PATH?{executablePath:process.env.CHROMIUM_PATH}:{})});try{
 const page=await browser.newPage({viewport:{width:1250,height:850},deviceScaleFactor:1.5});const errors=[];page.on('pageerror',e=>errors.push(e.message));
 await page.goto(process.env.ANNOTATR_BROWSER_URL||'http://127.0.0.1:5820');
 await page.waitForFunction(()=>document.querySelector('#canvas-display')?.textContent.includes('requires package magick'));
 const canvas=page.locator('#canvas-canvas canvas');assert.equal(await canvas.getAttribute('aria-disabled'),'true');
 const before=await page.evaluate(()=>atcanvasIdentity('canvas-canvas'));
 await canvas.focus();await page.keyboard.press('y');await page.keyboard.press('Enter');
 await page.locator('#session-save').click();await page.waitForFunction(()=>document.querySelector('#session-saved')?.textContent.includes('saved'));
 assert.deepEqual(await page.evaluate(()=>atcanvasIdentity('canvas-canvas')),before);
 const pixel=await canvas.evaluate(c=>Array.from(c.getContext('2d').getImageData(c.width/2,c.height/2,1,1).data));assert.deepEqual(pixel,[0,0,0,0]);
 assert.deepEqual(errors,[]);
 const evidence={display:await page.locator('#canvas-display').textContent(),identity:before,pixel,errors};
 if(process.env.ANNOTATR_BROWSER_ARTIFACT_DIR){fs.mkdirSync(process.env.ANNOTATR_BROWSER_ARTIFACT_DIR,{recursive:true});await page.screenshot({path:path.join(process.env.ANNOTATR_BROWSER_ARTIFACT_DIR,'t11-minimal.png'),fullPage:true});fs.writeFileSync(path.join(process.env.ANNOTATR_BROWSER_ARTIFACT_DIR,'t11-minimal.json'),JSON.stringify(evidence,null,2));}
 console.log(JSON.stringify(evidence,null,2));
}finally{await browser.close();}})();

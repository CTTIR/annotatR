const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
test('keyboard envelopes capture rendered canvas identity, preserve payload, and suppress missing identity', () => {
  let keydown, identity = {entry_id:'entry-a',revision:3};
  const inputs = [], Shiny = {setInputValue(name,value) { inputs.push({name,value}); }};
  const context = {Shiny, window:{Shiny,atcanvasIdentity:()=>identity},
    document:{activeElement:null,addEventListener(name,fn) { if(name==="keydown") keydown=fn; }}};
  vm.runInNewContext(fs.readFileSync(path.join(__dirname,'../../inst/shiny/annotatR/www/keys.js'),'utf8'),context);
  keydown({preventDefault(){},key:'y'}); identity = {entry_id:'entry-b',revision:0};
  assert.deepEqual(JSON.parse(JSON.stringify(inputs[0])),{name:'key_tool',value:{entry_id:'entry-a',revision:3,payload:'point'}});
  keydown({preventDefault(){},key:'2'}); assert.equal(inputs[1].value.payload,2);
  identity = null; keydown({preventDefault(){},key:'n'}); assert.equal(inputs.length,2);
});

test('shortcuts prevent browser undo and leave native controls alone',()=>{
 let keydown;const inputs=[];const document={activeElement:null,addEventListener(name,fn){if(name==='keydown')keydown=fn;}};
 const Shiny={setInputValue(name,value){inputs.push({name,value});}};
 vm.runInNewContext(fs.readFileSync(path.join(__dirname,'../../inst/shiny/annotatR/www/keys.js'),'utf8'),
  {Shiny,document,window:{Shiny,atcanvasIdentity:()=>({entry_id:'current',revision:1})}});
 let prevented=0;const event={key:'z',ctrlKey:true,preventDefault(){prevented++;}};
 keydown(event);assert.equal(prevented,1);assert.equal(inputs[0].name,'key_undo');
 document.activeElement={tagName:'BUTTON'};keydown({key:'Enter',shiftKey:true,preventDefault(){throw Error('native button intercepted');}});assert.equal(inputs.length,1);
 document.activeElement={tagName:'INPUT'};keydown({key:'n',preventDefault(){throw Error('native input intercepted');}});assert.equal(inputs.length,1);
 document.activeElement={tagName:'CANVAS'};keydown({key:'Enter',shiftKey:true,preventDefault(){prevented++;}});assert.equal(inputs.filter(x=>x.name==='key_commit_advance').length,1);
});

test('real action handler snapshots form values and current identity before delayed delivery',()=>{
 let click;const inputs=[],field={value:'original',querySelector(){return null;}};
 const Shiny={setInputValue(name,value){inputs.push({name,value});}};
 const document={getElementById(){return field;},addEventListener(name,fn){if(name==='click')click=fn;}};
 const window={Shiny,annotatRIdentity:{entry_id:'current',revision:2},atcanvasIdentity:()=>({entry_id:'current',revision:2})};
 vm.runInNewContext(fs.readFileSync(path.join(__dirname,'../../inst/shiny/annotatR/www/keys.js'),'utf8'),{Shiny,document,window});
 const button={id:'layers-add_layer',getAttribute(){return '{"new_layer":"layers-new_layer"}';}};
 click({target:{closest(){return button;}},preventDefault(){},stopImmediatePropagation(){}});
 field.value='later';window.annotatRIdentity={entry_id:'next',revision:0};
 assert.deepEqual(JSON.parse(JSON.stringify(inputs)),[{name:'layers-add_layer',value:{entry_id:'current',revision:2,payload:{new_layer:'original'}}}]);
});

test('divergent server stamps never replace the displayed mutation origin',()=>{
 let click,keydown;const inputs=[];
 const rendered={entry_id:'displayed',revision:4},server={entry_id:'unseen',revision:9,ready:false};
 const Shiny={setInputValue(name,value){inputs.push({name,value});}};
 const document={activeElement:{tagName:'CANVAS'},getElementById(){return {value:'original',querySelector(){return null;}};},
  addEventListener(name,fn){if(name==='click')click=fn;if(name==='keydown')keydown=fn;}};
 const window={Shiny,annotatRIdentity:server,atcanvasIdentity:()=>rendered};
 vm.runInNewContext(fs.readFileSync(path.join(__dirname,'../../inst/shiny/annotatR/www/keys.js'),'utf8'),{Shiny,document,window});
 for(const id of ['session-save','session-complete','session-flag','canvas-undo','canvas-redo','canvas-copy','layers-add_layer','layers-add_label','roitable-delete','data-load','data-restore']) {
  click({target:{closest(){return {id,getAttribute(){return '{}';}};}},preventDefault(){},stopImmediatePropagation(){}});
 }
 for(const event of [{key:'s'},{key:'f'},{key:'d'},{key:'z',ctrlKey:true},{key:'Enter',shiftKey:true},{key:'V',shiftKey:true},{key:'y'},{key:'2'}])
  keydown({...event,preventDefault(){}});
 assert.ok(inputs.length>10);
 for(const event of inputs) assert.deepEqual({entry_id:event.value.entry_id,revision:event.value.revision},rendered,event.name);
 inputs.length=0;
 for(const id of ['queue-nxt','queue-prev','queue-next_pending'])
  click({target:{closest(){return {id,getAttribute(){return '{}';}};}},preventDefault(){},stopImmediatePropagation(){}});
 for(const key of ['n','p','N'])keydown({key,preventDefault(){}});
 for(const event of inputs)assert.equal(event.value.entry_id,'unseen',event.name);
 // Saving a known rendered entry remains available after its display fails.
 window.atcanvasIdentity=()=>({entry_id:'unseen',revision:9});inputs.length=0;
 keydown({key:'s',preventDefault(){}});assert.equal(inputs[0].value.entry_id,'unseen');
 // An absent widget cannot be replaced by a server-origin mutation stamp.
 window.atcanvasIdentity=()=>null;inputs.length=0;
 keydown({key:'s',preventDefault(){}});assert.equal(inputs.length,0);
});

test('same-entry mutation intent retains the rendered revision while server output is pending',()=>{
 let keydown;const inputs=[];const Shiny={setInputValue(name,value){inputs.push({name,value});}};
 const document={activeElement:null,addEventListener(name,fn){if(name==='keydown')keydown=fn;}};
 const window={Shiny,annotatRIdentity:{entry_id:'entry',revision:5,ready:true},atcanvasIdentity:()=>({entry_id:'entry',revision:4})};
 vm.runInNewContext(fs.readFileSync(path.join(__dirname,'../../inst/shiny/annotatR/www/keys.js'),'utf8'),{Shiny,document,window});
 keydown({key:'Enter',shiftKey:true,preventDefault(){}});
 assert.equal(inputs[0].value.revision,4);
});

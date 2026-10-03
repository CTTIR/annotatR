// Run from the repository root. Diagnostic output is not a pass/fail test result.
const fs=require('fs'), vm=require('vm');
let widget, handlers={}, inputs=[];
const ctx={HTMLWidgets:{widget(x){widget=x;}},Shiny:{addCustomMessageHandler(n,fn){handlers[n]=fn;},setInputValue(n,v){inputs.push({n,v});}},Image:class {set src(v){this.onload();}},window:{addEventListener(){}}};
ctx.window.Shiny=ctx.Shiny;
let canvas;
ctx.document={createElement(){canvas={style:{},events:{},paths:0,getBoundingClientRect(){return {left:0,top:0,width:100,height:100}},addEventListener(n,fn){this.events[n]=fn},getContext(){return {beginPath(){},moveTo(){canvas.paths++;},lineTo(){},arc(){},closePath(){},fill(){},stroke(){},clearRect(){},drawImage(){}}}};return canvas;}};
vm.createContext(ctx);vm.runInContext(fs.readFileSync('inst/htmlwidgets/atcanvas.js','utf8'),ctx);
function create(id,features=[]){const el={id,getBoundingClientRect(){return {width:100,height:100}},appendChild(){}};const w=widget.factory(el,100,100);const c=canvas;w.renderValue({tileSource:{width:100,height:100,dataUri:'test'},tool:'erase',annotations:{features}});return {w,c};}
const f={type:'Feature',properties:{roi_id:'donut',layer:'L',label:'a'},geometry:{type:'Polygon',coordinates:[[[0,0],[100,0],[100,100],[0,100],[0,0]],[[40,40],[60,40],[60,60],[40,60],[40,40]]]}};
const a=create('a',[f]);
a.c.events.mousedown({clientX:50,clientY:50});
console.log('Click inside empty donut hole emits:',JSON.stringify(inputs));
inputs=[];
create('b');
handlers['atcanvas-set_tool']({id:'a',tool:'point'});
a.c.events.mousedown({clientX:20,clientY:20});
console.log('Set first widget to point after mounting second, click still emits:',JSON.stringify(inputs));

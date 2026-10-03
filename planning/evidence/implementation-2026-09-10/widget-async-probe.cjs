const fs = require('node:fs'), vm = require('node:vm');
const pending = [], painted = []; let widget, canvas;
const context = {
  HTMLWidgets: { widget(value) { widget = value; } },
  Image: class { set src(uri) { this.uri = uri; pending.push(this); } },
  window: { addEventListener() {} },
  document: { createElement() {
    canvas = { style: {}, addEventListener() {}, getContext() {
      return { clearRect() {}, drawImage(im) { painted.push(im.uri); } };
    } }; return canvas;
  } }
};
vm.createContext(context);
vm.runInContext(fs.readFileSync('inst/htmlwidgets/atcanvas.js', 'utf8'), context);
const element = {id:'probe',appendChild() {},getBoundingClientRect() {return {width:100,height:100};}};
const instance = widget.factory(element,100,100);
const input = uri => ({tileSource:{width:100,height:100,dataUri:uri},annotations:{features:[]}});
instance.renderValue(input('old-entry'));
instance.renderValue(input('new-entry'));
pending[1].onload();
const afterNew = painted.at(-1);
pending[0].onload();
const afterDelayedOld = painted.at(-1);
instance.renderValue(input(null));
console.log(JSON.stringify({afterNew,afterDelayedOld,afterMissingCurrent:painted.at(-1)},null,2));
if (afterNew !== 'new-entry' || afterDelayedOld !== 'old-entry' || painted.at(-1) !== 'old-entry') process.exitCode=1;

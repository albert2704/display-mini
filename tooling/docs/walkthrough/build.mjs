import { mkdirSync, writeFileSync, copyFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const dir = path.dirname(fileURLToPath(import.meta.url));
const media = path.resolve(dir, '../../../docs/media');
mkdirSync(path.join(dir, 'assets'), { recursive: true });
mkdirSync(path.join(dir, 'compositions'), { recursive: true });
const steps = [
  { seconds: 5, image: 'panel', label: '01 / DISPLAY CONTROLS', title: 'One panel.\nEvery screen.', body: 'Adjust brightness, resolution and supported monitor speakers from the menu bar.', note: 'Unmute brings back the last confirmed volume.', height: 580 },
  { seconds: 5, image: 'presets', label: '02 / PRESETS', title: 'Save your\ndaily setup.', body: 'Set your levels, name a preset and choose Save Current. Apply it whenever you need it.', note: 'Missing displays are skipped automatically.', height: 570 },
  { seconds: 3, image: 'shortcuts', label: '03 / KEYBOARD SHORTCUTS', title: 'Pick an\naction.', body: 'Open the keyboard button in the footer, then click the shortcut you want to change.', note: 'Brightness and volume target the screen under your pointer.', height: 600 },
  { seconds: 3, image: 'shortcut-editor', label: '04 / RECORD', title: 'Click\nRecord Shortcut.', body: 'Use your keyboard to choose a combination. The compact key menu is also available.', note: 'Include Control or Command.', height: 600 },
  { seconds: 3, image: 'shortcut-listening', label: '05 / PRESS YOUR KEYS', title: 'Press your\ncombination.', body: 'The recorder waits for a supported key and your chosen modifiers.', note: 'Escape cancels recording without changing the draft.', height: 600 },
  { seconds: 5, image: 'shortcut-recorded', label: '06 / REVIEW & SAVE', title: 'Check it.\nSave it.', body: 'Review the captured keys, then click Save. Conflicting assignments show a message.', note: 'Your shortcuts are remembered after relaunch.', height: 600 },
];
let start = 0;
const transition = 0.35;
const slots = steps.map((step, i) => {
  const id = `step${i + 1}`;
  const duration = step.seconds + (i < steps.length - 1 ? transition : 0);
  const keys = i >= 4 ? '<div class="keys" aria-label="Control Shift K"><span class="keycap">⌃ Control</span><span class="keycap">⇧ Shift</span><span class="keycap">K</span></div>' : '';
  const highlight = i === 3 ? 'record' : i === 5 ? 'save' : null;
  copyFileSync(path.join(media, `${step.image}.png`), path.join(dir, 'assets', `${step.image}.png`));
  writeFileSync(path.join(dir, 'compositions', `${id}.html`), `<!doctype html><html lang="en"><body><template>
<style>
#${id}{position:absolute;inset:0;width:100%;height:100%;font-family:system-ui,sans-serif;color:#18263a}
#${id} .copy{position:absolute;left:66px;top:174px;width:585px}
#${id} .eyebrow{color:#0866cf;font-size:19px;letter-spacing:2px;font-weight:700;margin:0 0 25px}
#${id} h1{font-size:59px;letter-spacing:-2.2px;line-height:1.05;white-space:pre-line;margin:0 0 27px;font-weight:750}
#${id} .body{font-size:25px;line-height:1.5;max-width:520px;margin:0}
#${id} .note{margin:29px 0 0;font-size:19px;line-height:1.45;color:#475972;max-width:490px}
#${id} .keys{display:flex;gap:10px;margin-top:20px;height:48px}
#${id} .keycap{display:flex;align-items:center;justify-content:center;padding:0 16px;border:1px solid #a9bbd1;border-bottom-width:3px;border-radius:9px;background:#fff;color:#18263a;font-size:24px;font-weight:650}
#${id} .keys+.note{margin-top:18px}
#${id} .shot{position:absolute;left:731px;top:62px;width:480px;height:600px;display:flex;align-items:center;justify-content:center}
#${id} .image-frame{position:relative}
#${id} img{height:${step.height}px;width:auto;border:1px solid #bac6d5;border-radius:15px;box-shadow:0 16px 42px #243a531f;display:block}
#${id} .highlight{position:absolute;border:3px solid #0866cf;border-radius:9px;pointer-events:none;box-shadow:0 0 0 4px #0866cf20}
#${id} .record{left:34.5%;top:27.4%;width:31.5%;height:5.6%}
#${id} .save{left:83%;top:92.1%;width:13%;height:5.2%}
</style>
<div id="${id}" data-composition-id="${id}" data-width="1280" data-height="720" data-duration="${duration}">
<div class="copy"><p class="eyebrow">${step.label}</p><h1>${step.title}</h1><p class="body">${step.body}</p>${keys}<p class="note">${step.note}</p></div>
<div class="shot"><div class="image-frame"><img src="assets/${step.image}.png" alt="Display Mini ${step.image.replaceAll('-', ' ')} with sample data">${highlight ? `<div class="highlight ${highlight}" aria-hidden="true"></div>` : ''}</div></div>
</div>
<script>
const tl=gsap.timeline({paused:true});
tl.fromTo('#${id} .copy',{opacity:${i === 0 ? 1 : 0},x:14},{opacity:1,x:0,duration:${transition},ease:'power2.out'},0);
tl.fromTo('#${id} .shot',{opacity:${i === 0 ? 1 : 0},y:${i < 3 ? 14 : 0},scale:${i < 3 ? 0.98 : 1}},{opacity:1,y:0,scale:1,duration:${transition},ease:'power2.out'},0);
${keys ? `tl.fromTo('#${id} .keycap',{opacity:0,y:10,scale:0.94},{opacity:1,y:0,scale:1,duration:0.3,stagger:0.2,ease:'power3.out'},${i === 4 ? 0.8 : 0.45});` : ''}
${highlight ? `tl.fromTo('#${id} .highlight',{opacity:0,scale:1.06},{opacity:1,scale:1,duration:0.4,ease:'power2.out'},${i === 3 ? 0.65 : 1.4});
tl.to('#${id} .highlight',{opacity:0.4,duration:0.35,repeat:1,yoyo:true,ease:'sine.inOut'},${i === 3 ? 1.5 : 2.4});` : ''}
${i < steps.length - 1 ? `tl.to('#${id} .copy',{opacity:0,x:-10,duration:0.22,ease:'power1.in'},${step.seconds - 0.22});
tl.to('#${id} .shot',{opacity:0,duration:${transition},ease:'none'},${step.seconds});` : ''}
window.__timelines['${id}']=tl;
</script></template></body></html>`);
  const slot = `<div id="${id}" class="clip" data-composition-id="${id}" data-composition-src="compositions/${id}.html" data-start="${start}" data-duration="${duration}" data-track-index="${i + 1}" data-width="1280" data-height="720"></div>`;
  start += step.seconds;
  return slot;
});
writeFileSync(path.join(dir, 'index.html'), `<!doctype html><html lang="en"><head><meta charset="utf-8">
<script src="https://cdn.jsdelivr.net/npm/gsap@3.14.2/dist/gsap.min.js"></script>
<style>
*{box-sizing:border-box}html,body{margin:0;width:1280px;height:720px;overflow:hidden;background:#edf2f8}
#root{width:100%;height:100%;font-family:system-ui,sans-serif;color:#18263a}
.clip{position:absolute;inset:0}.brand{position:absolute;left:66px;top:50px;font-size:26px;font-weight:750;letter-spacing:-.8px}
.badge{position:absolute;left:250px;top:55px;font-size:13px;letter-spacing:1.5px;font-weight:650;color:#475972}
.rule{position:absolute;left:66px;top:106px;height:1px;width:580px;background:#c7d3e2}
.footer{position:absolute;left:66px;bottom:36px;font-size:15px;color:#475972;letter-spacing:.2px}
.track{position:absolute;left:0;right:0;bottom:0;height:5px;background:#d2dce9}
#progress{width:100%;height:100%;background:#0866cf;transform-origin:left center}
</style></head><body>
<div id="root" data-composition-id="main" data-start="0" data-duration="24" data-width="1280" data-height="720">
<div class="brand">Display Mini</div><div class="badge">QUICK TOUR / 0.3.0</div><div class="rule"></div>
${slots.join('\n')}
<div class="footer">Native interface · Sample data · No audio</div><div class="track"><div id="progress"></div></div>
</div><script>const tl=gsap.timeline({paused:true});tl.fromTo('#progress',{scaleX:0},{scaleX:1,duration:24,ease:'none'},0);window.__timelines.main=tl;</script></body></html>`);
console.log('Prepared a 24 second native UI walkthrough.');

import { spawn } from "node:child_process";
import { mkdir, writeFile } from "node:fs/promises";
import path from "node:path";
import { pathToFileURL } from "node:url";
import { StringDecoder } from "node:string_decoder";

const [source,dest,widthInput,heightInput] = process.argv.slice(2);
const [width,height] = [Number(widthInput),Number(heightInput)];
const output = path.resolve(dest);
await mkdir(path.dirname(output), {recursive:true});
const instance = spawn("C:/Program Files/Google/Chrome/Application/chrome.exe", [
  "--headless=new", "--disable-gpu", "--no-first-run", "--no-default-browser-check",
  "--remote-debugging-pipe", "--user-data-dir="+path.resolve(".tmp/mahjong-ui-render-profile")
], {windowsHide:true,stdio:["ignore","ignore","pipe","pipe","pipe"]});
const inflight = new Map();
const decoder = new StringDecoder("utf8");
let seq = 0;
let buffer = "";
instance.stdio[4].on("data", data=>{
  buffer += decoder.write(data);
  let end;
  while ((end = buffer.indexOf("\0")) >= 0) {
    const json = buffer.slice(0,end);
    buffer = buffer.slice(end+1);
    if (!json) continue;
    const message = JSON.parse(json);
    const pending = inflight.get(message.id);
    if (!pending) continue;
    inflight.delete(message.id);
    clearTimeout(pending.timer);
    if (message.error) pending.reject(Error(message.error.message));
    else pending.resolve(message.result);
  }
});
const request = (method,params={},sessionId) => new Promise((resolve,reject)=>{
  const id = ++seq;
  const timer = setTimeout(()=>{ inflight.delete(id); reject(Error("DevTools timeout: "+method)); },15000);
  inflight.set(id,{resolve,reject,timer});
  instance.stdio[3].write(JSON.stringify({id,method,params,sessionId})+"\0");
});
let screen;
try {
  const {targetId} = await request("Target.createTarget",{url:"about:blank"});
  const {sessionId} = await request("Target.attachToTarget",{targetId,flatten:true});
  await request("Emulation.setDeviceMetricsOverride",{width,height,deviceScaleFactor:1,mobile:false},sessionId);
  await request("Page.navigate",{url:pathToFileURL(path.resolve(source)).href},sessionId);
  for(let i=0;i<30;i++){
    const {result} = await request("Runtime.evaluate",{expression:`(() => {
      if(document.readyState!=="complete"||!document.querySelector("main[data-screen]")) return null;
      return { screen:document.querySelector("main").dataset.screen, title:document.title,
        size:[innerWidth,innerHeight], images:[...document.images].every(im=>im.complete&&im.naturalWidth>0),
        text:document.body.innerText, view:[...document.querySelectorAll("button")].every(e=>e.getBoundingClientRect().bottom<=innerHeight) }
    })()`,returnByValue:true},sessionId);
    screen = result.value;
    if(screen?.images) break;
    await new Promise(r=>setTimeout(r,180));
  }
  if(!screen?.images||!screen.view||screen.size[0]!==width||screen.size[1]!==height) throw Error(JSON.stringify(screen));
  await request("Runtime.evaluate",{expression:"document.fonts.ready",awaitPromise:true},sessionId);
  const {data} = await request("Page.captureScreenshot",{format:"png",fromSurface:true},sessionId);
  await writeFile(output,Buffer.from(data,"base64"));
  console.log(JSON.stringify(screen));
} finally {
  try { await request("Browser.close"); } catch { instance.kill(); }
}

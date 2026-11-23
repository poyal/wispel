const fs=require('node:fs');
const path=require('node:path');
const {spawn}=require('node:child_process');
const {setTimeout:wait}=require('node:timers/promises');
const assert=require('node:assert/strict');

async function inspect(){
    const address=fs.readFileSync(process.argv[2],'utf8').trim().replace(/^\uFEFF/,'');
    assert.equal(new URL(address).hostname,'127.0.0.1');
    const profile=fs.mkdtempSync(path.resolve('artifacts/qa/chrome-'));
    const chrome=spawn(process.env.WISPEL_QA_CHROME||'C:/Program Files/Google/Chrome/Application/chrome.exe',[
        '--headless=new','--disable-gpu','--no-first-run','--disable-background-networking','--remote-debugging-port=0',
        '--remote-debugging-address=127.0.0.1','--user-data-dir='+profile,'about:blank'
    ],{windowsHide:true,stdio:'ignore'});
    let ws;
    try{
        let port;
        for(let i=0;i<100&&!port;i++){try{port=fs.readFileSync(path.join(profile,'DevToolsActivePort'),'utf8').split('\n')[0]}catch{await wait(150)}}
        assert.ok(port,'Chrome debugging endpoint missing');
        const targets=await(await fetch('http://127.0.0.1:'+port+'/json/list')).json();
        ws=new WebSocket(targets.find(t=>t.type==='page').webSocketDebuggerUrl);
        await new Promise((ok,fail)=>{ws.onopen=ok;ws.onerror=fail});
        let id=0;const requests=new Map();
        ws.onmessage=event=>{const m=JSON.parse(event.data);if(requests.has(m.id)){const callback=requests.get(m.id);requests.delete(m.id);m.error?callback.reject(m.error):callback.resolve(m.result)}};
        const cmd=(method,params={})=>new Promise((resolve,reject)=>{const rid=++id;requests.set(rid,{resolve,reject});ws.send(JSON.stringify({id:rid,method,params}))});
        const value=async expression=>(await cmd('Runtime.evaluate',{expression,returnByValue:true})).result.value;
        await cmd('Emulation.setDeviceMetricsOverride',{width:1250,height:840,mobile:false,deviceScaleFactor:1});
        await cmd('Page.navigate',{url:address});
        for(let i=0;i<60;i++){if(await value('document.querySelector("#service")?.textContent==="실행 중"'))break;await wait(125)}
        assert.equal(await value('document.querySelector("#service")?.textContent'),'실행 중');
        assert.ok(await value('document.querySelectorAll(".metrics article").length===3'));
        assert.ok(await value('document.querySelectorAll("details").length>0'));
        await value('document.querySelector("details").open=true');
        const png=await cmd('Page.captureScreenshot',{format:'png'});
        fs.writeFileSync('artifacts/screens/windows-diagnostics.png',Buffer.from(png.data,'base64'));
        await cmd('Emulation.setDeviceMetricsOverride',{width:390,height:840,mobile:true,deviceScaleFactor:1});
        assert.ok(await value('document.documentElement.scrollWidth<=390'));
        console.log('PASS live diagnostic metrics, event details, desktop screenshot and narrow layout');
    }finally{ws?.close();chrome.kill()}
}
inspect().catch(e=>{console.error(e.message);process.exitCode=1});

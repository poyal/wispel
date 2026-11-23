// Run only against an isolated QA installation. The operator CLI issues one-use credentials.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {readFileSync} from 'node:fs';
import https from 'node:https';
import {randomUUID} from 'node:crypto';
import {setTimeout as sleep} from 'node:timers/promises';
import {performance} from 'node:perf_hooks';

const home = process.env.WISPEL_QA_HOME;
const exe = process.env.WISPEL_QA_EXE;
if (!home || !exe || !process.env.WISPEL_QA_CA) throw Error('Set WISPEL_QA_HOME, WISPEL_QA_EXE and WISPEL_QA_CA');
const ca = readFileSync(process.env.WISPEL_QA_CA);
const cli = (...args) => execFileSync(exe, [...args, '--home', home], {encoding:'utf8'}).trim();
const cfg = JSON.parse(readFileSync(home+'/server.json','utf8').replace(/^\uFEFF/,''));
function api(path, method, body, token) {
    return new Promise((resolve,reject) => {
        const headers = {'Content-Type':'application/json'};
        if (token) headers.Authorization='Bearer '+token;
        const req=https.request(cfg.Url+path,{method,headers,ca,timeout:8000},res=>{
            let text='';res.setEncoding('utf8');
            res.on('data',chunk=>text+=chunk);res.on('end',()=>resolve({code:res.statusCode,data:text?JSON.parse(text):null}));
        });
        req.on('error',reject);req.on('timeout',()=>req.destroy(Error('request timed out')));
        req.end(body ? JSON.stringify(body) : undefined);
    });
}
async function pair(role,platform,name) {
    const invite=new URL(cli('pair',role));
    const params={code:invite.searchParams.get('code'),platform,name};
    const res=await api('/v1/pair','POST',params);
    assert.equal(res.code,200);assert.equal((await api('/v1/pair','POST',params)).code,403);
    return res.data;
}
function notice(sender,kind,time=Date.now()) {return {eventId:randomUUID(),sourceId:sender.id,kind,occurredAt:time};}
const status=()=>JSON.parse(cli('status'));
async function waitForAck(ids,seconds=45) {
    const until=Date.now()+seconds*1000;
    do {
        const rows=status().events;
        if(ids.every(id=>rows.some(r=>r.eventId===id && r.status==='ack')))return;
        await sleep(750);
    }while(Date.now()<until);
    throw Error('Missing receiver acknowledgement for '+ids.length+' events');
}
const mode=process.argv[2]??'check';
if(mode==='attach'){
    const sender=await pair('send','ios','시험 아이폰');
    assert.equal((await api('/v1/events','POST',notice(sender,'kakao'),'invalid')).code,401);
    const e=notice(sender,'sms');
    assert.equal((await api('/v1/events','POST',{...e,body:'WISPEL_PRIVATE_MARKER'},sender.token)).code,400);
    assert.equal((await api('/v1/events','POST',{...e,sourceId:randomUUID()},sender.token)).code,403);
    const ids=[];
    for(const kind of ['call','missedCall','sms','kakao','slack','mail']){
        const event=notice(sender,kind);
        const res=await api('/v1/events','POST',event,sender.token);assert.equal(res.code,200);
        assert.equal((await api('/v1/events','POST',event,sender.token)).data.status,'duplicate');
        assert.equal((await api('/v1/events','POST',{...event,occurredAt:event.occurredAt+1},sender.token)).code,409);
        ids.push(event.eventId);
    }
    await waitForAck(ids);
    assert.ok(!JSON.stringify(status()).includes('WISPEL_PRIVATE_MARKER'));
    console.log('PASS 6 event kinds, receiver ACK, duplicate/conflict, authentication, source binding, metadata allowlist');
} else if(mode==='soak'){
    const sender=await pair('send','ios','연속 수신 시험');
    const size=Number(process.argv[3]??60);
    const interval=Number(process.argv[4]??1000);
    const delays=[];
    for(let i=0;i<size;i++){
        const e=notice(sender,i%2?'sms':'kakao');
        const start=performance.now();
        assert.equal((await api('/v1/events','POST',e,sender.token)).code,200);
        await waitForAck([e.eventId]);
        delays.push(Math.ceil(performance.now()-start));
        if(interval)await sleep(interval);
    }
    delays.sort((a,b)=>a-b);
    console.log(JSON.stringify({passed:size,intervalMs:interval,medianObservedMs:delays[Math.floor(size/2)],p95ObservedMs:delays[Math.min(size-1,Math.floor(size*.95))],maximumObservedMs:delays.at(-1)}));
} else if(mode==='seed'){
    const sender=await pair('send','ios','업무용 아이폰');
    const sequence=['sms','mail','slack','slack','missedCall','kakao','kakao','kakao'];
    const now=Date.now(),ids=[];
    for(const [i,kind] of sequence.entries()){
        const e=notice(sender,kind,now-(sequence.length-i)*3000);
        assert.equal((await api('/v1/events','POST',e,sender.token)).code,200);
        ids.push(e.eventId);
    }
    await waitForAck(ids);
    console.log('PASS design fixture: Kakao 3, missed call 1, Slack 2, mail 1, SMS 1');
} else if(mode==='emit'){
    const sender=await pair('send','ios','지연 시험 아이폰');
    const event=notice(sender,process.argv[3]??'kakao',Date.now()-Number(process.argv[4]??0));
    assert.equal((await api('/v1/events','POST',event,sender.token)).code,200);
    console.log(event.eventId);
} else if(mode==='apple'){
    const receiver=await pair('receive','ios','시험용 아이폰 본폰');
    assert.equal((await api('/v1/apns','PUT',{value:'invalid'},receiver.token)).code,400);
    console.log('PASS iOS receiver registration and APNs device token validation');
} else {console.log(JSON.stringify(status()));}

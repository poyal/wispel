function buildBoard() {
  const concepts = [
    {id:'plume',name:'Plume',label:'깃결',desc:'가장 최근 알림 하나를 부드럽게 띄우고, 그 아래에 나머지 기록을 모읍니다.',palette:['#aaa1d4','#eeebf7','#fffefa']},
    {id:'folio',name:'Folio',label:'기록지',desc:'날짜와 시각을 기준으로 정렬한 기록지입니다. 언제 무엇이 왔는지 한 줄씩 훑어봅니다.',palette:['#a85136','#e0cdb7','#faf3e5']},
    {id:'orbit',name:'Orbit',label:'고요한 궤도',desc:'어두운 화면의 작은 고리에 오늘의 알림 분포를 담습니다. 폰과 손목에서 같은 색으로 종류를 읽습니다.',palette:['#a5e8d3','#497d76','#172e30']},
    {id:'tiles',name:'Mosaic',label:'알림 타일',desc:'앱별 건수를 타일로 묶어 보여줍니다. 타일을 누르면 해당 종류의 기록만 확인합니다.',palette:['#476ad1','#f3c45d','#b7cdb8']},
    {id:'relay',name:'Relay',label:'기기 경로',desc:'보내는 폰과 받는 폰을 먼저 보여줍니다. 기기 역할과 마지막 수신 시각을 한눈에 확인합니다.',palette:['#264fc1','#b7cbfc','#e6edf8']}
  ];
  const views = {home:'안드로이드 홈',settings:'기기 설정',ios:'아이폰 단축어',watch:'워치 알림',server:'Windows 서버'};
  const events = [
    {app:'카카오톡',icon:'chat',time:'14:31',qty:3},
    {app:'부재중 전화',icon:'call',time:'14:18',qty:1},
    {app:'Slack',icon:'hash',time:'13:52',qty:2},
    {app:'메일플러그',icon:'mail',time:'11:04',qty:1},
    {app:'새 문자',icon:'sms',time:'09:42',qty:1}
  ];
  const settingsKinds = ['전화 알림','부재중 전화','새 문자','카카오톡','Slack','메일플러그'];
  const paths = {
    home:'M3 10L12 3l9 7v10h-6v-6H9v6H3z',
    settings:'M3 6h7m5 0h6M3 12h12m5 0h1M3 18h3m5 0h10 M13 3v6m5 0v6M9 15v6',
    chat:'M4 4h16v12H11l-5 4v-4H4z',
    call:'M5 16q7-9 14 0l-2 3-3-2v-2h-4v2l-3 2z M6 4l5 5m0-4v4H7',
    hash:'M10 3L7 21m10-18l-3 18M4 9h17M3 15h17',
    mail:'M3 5h18v14H3z M3 6l9 7 9-7',
    sms:'M3 4h18v13H9l-5 4v-4H3z M7 9h10m-10 4h6',
    phone:'M7 2h10q1 0 1 2v16q0 2-1 2H7q-1 0-1-2V4q0-2 1-2z M10 18h4',
    pause:'M8 4v16m8-16v16',play:'M6 3l14 9-14 9z',
    clock:'M12 3a9 9 0 1 0 .01 0 M12 6v6l4 2',
    arrow:'M4 12h15m-6-6l6 6-6 6',watch:'M8 5l1-4h6l1 4m-8 14l1 4h6l1-4 M6 5h12v14H6z',
    inbox:'M5 4h14l3 11v5H2v-5z M3 15h5l1 2h6l1-2h5',
    bell:'M5 16h14l-2-3V9a5 5 0 0 0-10 0v4z M10 20h4',
    external:'M5 19L19 5M8 5h11v11',retry:'M19 10a7 7 0 1 0 0 6 M19 4v6h-6'
  };
  const state = concepts.map(()=>({paused:'',until:0,watch:new Set(settingsKinds),receive:new Set(settingsKinds),history:'7일',test:false}));
  let view='home', selected=0, detailView='home';
  const gallery=document.querySelector('#gallery'), detail=document.querySelector('#detail'), sheet=document.querySelector('#sheet');
  const icon=(name,size=16)=>`<canvas class="icon" aria-hidden="true" data-icon="${name}" width="48" height="48" style="width:${size}px;height:${size}px"></canvas>`;
  const art=(type)=>`<canvas class="art art-${type}" data-art="${type}" width="450" height="240" aria-hidden="true"></canvas>`;
  const button=(action,text,cls='',label='')=>`<button type="button" data-action="${action}" class="${cls}"${label?` aria-label="${label}"`:''}>${text}</button>`;
  const dot=(e)=>`<span class="app-icon i-${e.icon}">${icon(e.icon)}</span>`;
  const total=events.reduce((n,e)=>n+e.qty,0);
  function status(ios=false) {
    return `<div class="status"><b>${ios?'9:41':'14:32'}</b><span class="signal" aria-hidden="true"><i></i><i></i><i></i><em></em></span></div>`;
  }
  function list(items,mode='') {
    return `<div class="events ${mode}">${items.map(e=>`<div class="event"><time>${e.time}</time>${dot(e)}<div class="event-label"><strong>${e.app}</strong><small>업무용 아이폰</small></div><b class="qty">${e.qty}건</b></div>`).join('')}</div>`;
  }
  function route() {
    return `<div class="route"><div>${icon('phone',20)}<strong>업무용 아이폰</strong><small>보내기 전용</small></div>${icon('arrow',17)}<div>${icon('phone',20)}<strong>안드로이드 본폰</strong><small>받기 전용</small></div></div>`;
  }
  function home(i) {
    const s=state[i], pause=button('pause',icon(s.paused?'play':'pause',13)+(s.paused?'재개':'잠시 쉬기'),'pill');
    const source=`<div class="source">${icon('phone',13)} 업무용 아이폰 <span>· 마지막 수신 14:31</span></div>`;
    const header=`<div class="app-head"><span class="word">Wispel</span>${pause}</div>`;
    const section=(name,n)=>`<div class="section-label"><b>${name}</b><span>${n}</span></div>`;
    let body='';
    if(i===0) body=`<h3>최근 알림</h3>${source}<div class="hero feather">${art('feather')}<small>가장 최근</small><strong>카카오톡 <em>3건</em></strong><span>오후 2:31</span></div>${section('이전 알림','오늘')}${list(events.slice(1))}`;
    if(i===1) body=`<div class="folio-title"><small>2026년 · 월요일</small><h3>11월 23일</h3></div>${source}${section('최근 알림',`오늘 ${total}건`)}${list(events,'timeline')}`;
    if(i===2) body=`<h3>최근 알림</h3>${source}<div class="orbit-stat">${art('ring')}<div><strong>${total}</strong><small>오늘 받은 알림</small></div></div>${section('최근 기록','오늘')}${list(events,'compact')}`;
    if(i===3) body=`<h3>최근 알림</h3>${source}${section('앱별로 보기',`오늘 ${total}건`)}<div class="tile-grid">${events.map(e=>button('app-'+e.icon,`${icon(e.icon,18)}<b>${e.qty}<small>건</small></b><strong>${e.app}</strong>`,'tile t-'+e.icon)).join('')}</div>${section('마지막 수신','14:31')}${list(events.slice(0,1))}`;
    if(i===4) body=`<h3>최근 알림</h3><div class="route-hero"><small>알림 전달 경로</small>${route()}<div class="last">마지막 수신 <b>14:31</b></div></div>${section('수신 기록',`오늘 ${total}건`)}${list(events,'compact')}`;
    return header+(s.paused?`<div class="notice">전달 일시정지 · ${s.paused}</div>`:'')+body;
  }
  function settings(i) {
    const s=state[i];
    const row=(key,title,sub)=>button(key,`<b>${title}</b><span>${sub} ›</span>`,'setting-row');
    return `<div class="app-head"><span class="word">Wispel</span></div><h3>설정</h3>
      <div class="section-label"><b>기기 관리</b></div><div class="device-card"><small>이 폰 · 받기 전용</small><strong>안드로이드 본폰</strong><div>← 업무용 아이폰 · 보내기 전용</div></div>
      <div class="section-label"><b>알림 설정</b></div>${row('receive','받을 알림',`${s.receive.size}종류`)}${row('watch','워치에 표시',`${s.watch.size}종류`)}${row('sound','소리와 진동','시스템 채널')}${row('pause','잠시 쉬기',s.paused||'꺼짐')}${row('history','기록 보관',s.history)}`;
  }
  function ios() {
    const rows=(names)=>names.map(name=>`<div class="shortcut"><b>${name}</b>${button('shortcut-'+name,'받기','get',`${name} 단축어 받기`)}</div>`).join('');
    return `<div class="app-head"><span class="word">Wispel</span></div><h3>단축어 받기</h3><div class="device-card"><small>이 폰 · 보내기 전용</small><strong>업무용 아이폰</strong><div>→ 안드로이드 본폰</div></div><div class="section-label"><b>기본 앱 알림</b></div>${rows(['전화','문자'])}<div class="section-label"><b>일반 앱 알림</b></div>${rows(['카카오톡','Slack','메일플러그'])}${button('ios-test','시험 알림 보내기','primary')}`;
  }
  function watch(i) {
    const s=state[i], visible=s.watch.has('부재중 전화')&&s.receive.has('부재중 전화')&&!s.paused;
    return `<div class="watch-wrap"><span class="strap"></span><div class="dial"><time>14:18</time>${icon('call',24)}<b>${visible?'부재중 전화':'알림 없음'}</b><small>${visible?'업무용 아이폰':'위스펠'}</small></div></div><div class="watch-caption">Wear OS 시스템 알림 미리보기</div>`;
  }
  function server(i,large) {
    const s=state[i], stage=s.test?'시험 알림':'카카오톡';
    return `<div class="server ${large?'large':''}"><div class="window-head"><i></i><i></i><i></i><span>Wispel · 로컬 관리</span></div><div class="server-pad"><div class="app-head"><span class="word">Wispel</span><small>서비스 실행 중</small></div><h3>전달 현황</h3><div class="stats"><div><small>발송 대기</small><b>0</b></div><div><small>최근 오류</small><b>0</b></div></div><div class="section-label"><b>등록 기기</b></div>${route()}<div class="section-label"><b>최근 이벤트</b><span>${stage}</span></div><ol class="trace">${['서버 접수','FCM 접수','본폰 수신 확인'].map((t,j)=>`<li><b>${t}</b><time>${s.test?'14:32':'14:31'}:0${j}</time></li>`).join('')}</ol>${button('test','본폰에 시험 알림 보내기','primary')}${button('register','기기 등록','secondary')}</div></div>`;
  }
  function frame(i,key,large=false) {
    if(key==='watch') return watch(i);
    if(key==='server') return server(i,large);
    return `<div class="phone ${key}">${status(key==='ios')}<div class="screen">${key==='home'?home(i):key==='ios'?ios():settings(i)}</div>${key==='ios'?'<div class="ios-home"></div>':`<nav class="phone-nav" aria-label="본폰 메뉴">${button('nav-home',icon('inbox',14)+'최근 알림',key==='home'?'active':'')}${button('nav-settings',icon('settings',14)+'설정',key==='settings'?'active':'')}</nav>`}</div>`;
  }
  function viewButtons(active) {
    return Object.entries(views).map(([key,label])=>`<button data-view="${key}" aria-pressed="${key===active}">${label}</button>`).join('');
  }
  function paint(root) {
    for(const c of root.querySelectorAll('canvas')) {
      const ctx=c.getContext('2d');
      ctx.clearRect(0,0,c.width,c.height);
      if(c.dataset.icon) {
        ctx.save();ctx.scale(2,2);ctx.strokeStyle=getComputedStyle(c).color;ctx.lineWidth=1.65;ctx.lineCap='round';ctx.lineJoin='round';
        const path=paths[c.dataset.icon]; if(path) ctx.stroke(new Path2D(path));ctx.restore();
      } else if(c.dataset.art==='feather') {
        ctx.save();ctx.translate(210,130);ctx.rotate(-0.72);
        for(let k=0;k<66;k++) {
          const t=k/65,x=-120+260*t, y=27*Math.sin(t*Math.PI)-22*t, width=70*Math.pow(Math.sin(t*Math.PI),0.8);
          ctx.strokeStyle=`rgba(99,79,151,${0.28+0.27*t})`;ctx.lineWidth=1.5;
          for(const side of [-1,1]) {
            ctx.beginPath();ctx.moveTo(x,y);ctx.quadraticCurveTo(x+8+24*t,y+side*width*.55,x+24+20*t,y+side*width);ctx.stroke();
          }
        }
        ctx.restore();
      } else {
        const colors=['#abeece','#e3baba','#78bfb9','#bcabdc','#e6c78e'];
        let angle=-Math.PI/2;
        events.forEach((e,j)=>{const end=angle+2*Math.PI*e.qty/total;ctx.beginPath();ctx.strokeStyle=colors[j];ctx.lineWidth=9;ctx.arc(225,120,95,angle+.035,end-.035);ctx.stroke();angle=end;});
      }
    }
  }
  function draw() {
    for(const s of state) if(s.until && Date.now()>=s.until){s.paused='';s.until=0;}
    document.querySelector('#views').innerHTML=viewButtons(view);
    gallery.innerHTML=concepts.map((c,i)=>`<article class="board ${c.id}" data-i="${i}"><div class="board-top"><span>${c.label}</span><div class="palette" aria-hidden="true">${c.palette.map(p=>`<i style="background:${p}"></i>`).join('')}</div></div><h2>${button('expand',c.name+' '+icon('external',15),'expand',`${c.label} 시안 크게 보기`)}</h2><p class="summary">${c.desc}</p><div class="stage stage-${view}">${frame(i,view)}</div>${button('expand','크게 보기 ↗','open-detail')}</article>`).join('');
    paint(gallery);
    if(detail.open) renderDetail();
  }
  function renderDetail() {
    const c=concepts[selected];
    document.querySelector('#detail-heading').textContent=c.name+' · '+c.label;
    document.querySelector('#detail-copy').textContent=c.desc;
    document.querySelector('#detail-views').innerHTML=viewButtons(detailView);
    const stage=document.querySelector('#detail-stage');
    stage.className=`stage ${c.id} stage-${detailView}`;stage.innerHTML=frame(selected,detailView,true);paint(stage);
  }
  function openDetail(i,key) {
    selected=i;detailView=key;
    if(!detail.open) detail.showModal();
    renderDetail();
  }
  function popup(title,body) {
    document.querySelector('#sheet-content').innerHTML=`<h2 id="sheet-title">${title}</h2>${body}`;
    if(!sheet.open) sheet.showModal();
  }
  function act(i,key) {
    const s=state[i];
    if(key==='expand') return openDetail(i,view);
    if(key.startsWith('nav-')) return openDetail(i,key.slice(4));
    if(key==='pause') {
      if(s.paused){s.paused='';s.until=0;draw();return;}
      return popup('잠시 쉬기','<p>쉬는 동안 기록은 유지하고 본폰과 워치 알림을 멈춥니다.</p>'+button('rest-hour','1시간','choice')+button('rest-manual','다시 켤 때까지','choice'));
    }
    if(key.startsWith('rest-')) {
      s.paused=key==='rest-hour'?'1시간':'다시 켤 때까지';s.until=key==='rest-hour'?Date.now()+3600000:0;sheet.close();draw();return;
    }
    if(key==='receive'||key==='watch') {
      const group=s[key];
      return popup(key==='watch'?'워치에 표시':'받을 알림',`<p>업무용 아이폰에서 오는 알림</p>${settingsKinds.map(n=>`<label class="check">${n}<input type="checkbox" data-group="${key}" value="${n}" ${group.has(n)?'checked':''}></label>`).join('')}`);
    }
    if(key==='sound') return popup('소리와 진동','<p>기본값은 무음입니다. 실제 앱에서는 종류별 Android 시스템 알림 채널 설정을 엽니다.</p>');
    if(key==='history') return popup('기록 보관',button('keep','7일 보관','choice')+button('forget','기록 남기지 않기','choice'));
    if(key==='keep'||key==='forget'){s.history=key==='keep'?'7일':'꺼짐';sheet.close();draw();return;}
    if(key.startsWith('shortcut-')) return popup(key.slice(9)+' 단축어 받기','<ol><li>iCloud 공유 단축어 추가</li><li>자동화 켜기</li><li>잠금 중 실행 허용 확인</li></ol><p>이 시안은 가져오기 절차를 미리 보여줍니다.</p>');
    if(key.startsWith('app-')) {
      const e=events.find(row=>row.icon===key.slice(4));return popup(e.app,`<p>업무용 아이폰 · 오늘 ${e.qty}건</p><p>마지막 수신 ${e.time}</p>`);
    }
    if(key==='ios-test') return popup('시험 알림','<p>예시 결과 · Windows 서버 접수</p><p>본폰의 최근 알림에서 실제 수신 시각을 확인합니다.</p>');
    if(key==='test'){s.test=true;draw();return popup('시험 알림','<p>예시 이벤트의 서버 접수, FCM 접수, 본폰 수신 확인 시각을 갱신했습니다.</p>');}
    if(key==='register') return popup('기기 등록',button('qr-send','서브폰 추가 · 보내기 전용','choice')+button('qr-receive','본폰 등록 · 받기 전용','choice'));
    if(key.startsWith('qr-')) return popup('등록 역할 확인',`<p>${key==='qr-send'?'서브폰 · 보내기 전용':'본폰 · 받기 전용'}</p><p>실제 서버에서는 선택한 역할의 일회용 QR을 표시합니다.</p>`);
  }
  document.addEventListener('click',event=>{
    const b=event.target.closest('button');if(!b)return;
    if(b.id==='close'){detail.close();return;}
    if(b.classList.contains('sheet-close')){sheet.close();return;}
    if(b.dataset.view){
      if(detail.open){detailView=b.dataset.view;renderDetail();}
      else{view=b.dataset.view;draw();}
      return;
    }
    if(!b.dataset.action)return;
    const board=b.closest('[data-i]');if(board) selected=Number(board.dataset.i);
    act(selected,b.dataset.action);
  });
  sheet.addEventListener('change',event=>{
    const el=event.target;if(!el.dataset.group)return;
    const group=state[selected][el.dataset.group];
    if(el.checked) group.add(el.value);else group.delete(el.value);
    draw();
  });
  draw();
}

buildBoard();

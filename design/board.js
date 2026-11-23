function buildBoard() {
  const views = {home:'최근 알림',settings:'기기 설정',ios:'단축어 받기',watch:'손목 알림'};
  const labels = {home:'Android · 받기 전용',settings:'Android · 받기 전용',ios:'iOS · 보내기 전용',watch:'Wear OS · 알림 미리보기'};
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
  const state = {paused:'',until:0,watch:new Set(settingsKinds),receive:new Set(settingsKinds),history:'7일'};
  let detailView='home';
  const gallery=document.querySelector('#gallery'), detail=document.querySelector('#detail'), sheet=document.querySelector('#sheet');
  const icon=(name,size=16)=>`<canvas class="icon" aria-hidden="true" data-icon="${name}" width="48" height="48" style="width:${size}px;height:${size}px"></canvas>`;
  const button=(action,text,cls='',label='')=>`<button type="button" data-action="${action}" class="${cls}"${label?` aria-label="${label}"`:''}>${text}</button>`;
  const dot=(e)=>`<span class="app-icon i-${e.icon}">${icon(e.icon)}</span>`;
  const total=events.reduce((n,e)=>n+e.qty,0);
  function status(ios=false) {
    return `<div class="status"><b>${ios?'9:41':'14:32'}</b><span class="signal" aria-hidden="true"><i></i><i></i><i></i><em></em></span></div>`;
  }
  function list(items,mode='') {
    return `<div class="events ${mode}">${items.map(e=>`<div class="event"><time>${e.time}</time>${dot(e)}<div class="event-label"><strong>${e.app}</strong><small>업무용 아이폰</small></div><b class="qty">${e.qty}건</b></div>`).join('')}</div>`;
  }
  function home() {
    const s=state, pause=button('pause',icon(s.paused?'play':'pause',13)+(s.paused?'재개':'잠시 쉬기'),'pill');
    const source=`<div class="source">${icon('phone',13)} 업무용 아이폰 <span>· 마지막 수신 14:31</span></div>`;
    const header=`<div class="app-head"><span class="word">Wispel</span>${pause}</div>`;
    const section=(name,n)=>`<div class="section-label"><b>${name}</b><span>${n}</span></div>`;
    const body=`<h3>최근 알림</h3>${source}${section('앱별로 보기',`오늘 ${total}건`)}<div class="tile-grid">${events.map(e=>button('app-'+e.icon,`${icon(e.icon,18)}<b>${e.qty}<small>건</small></b><strong>${e.app}</strong>`,'tile t-'+e.icon)).join('')}</div>${section('마지막 수신','14:31')}${list(events.slice(0,1))}`;
    return header+(s.paused?`<div class="notice">전달 일시정지 · ${s.paused}</div>`:'')+body;
  }
  function settings() {
    const s=state;
    const row=(key,title,sub)=>button(key,`<b>${title}</b><span>${sub} ›</span>`,'setting-row');
    return `<div class="app-head"><span class="word">Wispel</span></div><h3>설정</h3>
      <div class="section-label"><b>기기 관리</b></div><div class="device-card"><small>이 폰 · 받기 전용</small><strong>안드로이드 본폰</strong><div>← 업무용 아이폰 · 보내기 전용</div></div>
      <div class="section-label"><b>알림 설정</b></div>${row('receive','받을 알림',`${s.receive.size}종류`)}${row('watch','워치에 표시',`${s.watch.size}종류`)}${row('sound','소리와 진동','시스템 채널')}${row('pause','잠시 쉬기',s.paused||'꺼짐')}${row('history','기록 보관',s.history)}`;
  }
  function ios() {
    const rows=(names)=>names.map(name=>`<div class="shortcut"><b>${name}</b>${button('shortcut-'+name,'받기','get',`${name} 단축어 받기`)}</div>`).join('');
    return `<div class="app-head"><span class="word">Wispel</span></div><h3>단축어 받기</h3><div class="device-card"><small>이 폰 · 보내기 전용</small><strong>업무용 아이폰</strong><div>→ 안드로이드 본폰</div></div><div class="section-label"><b>기본 앱 알림</b></div>${rows(['전화','문자'])}<div class="section-label"><b>일반 앱 알림</b></div>${rows(['카카오톡','Slack','메일플러그'])}${button('ios-test','시험 알림 보내기','primary')}`;
  }
  function watch() {
    const s=state, visible=s.watch.has('부재중 전화')&&s.receive.has('부재중 전화')&&!s.paused;
    return `<div class="watch-wrap"><span class="strap"></span><div class="dial"><time>14:18</time>${icon('call',24)}<b>${visible?'부재중 전화':'알림 없음'}</b><small>${visible?'업무용 아이폰':'위스펠'}</small></div></div><div class="watch-caption">Wear OS 시스템 알림 미리보기</div>`;
  }
  function frame(key) {
    if(key==='watch') return watch();
    return `<div class="phone ${key}">${status(key==='ios')}<div class="screen">${key==='home'?home():key==='ios'?ios():settings()}</div>${key==='ios'?'<div class="ios-home"></div>':`<nav class="phone-nav" aria-label="본폰 메뉴">${button('nav-home',icon('inbox',14)+'최근 알림',key==='home'?'active':'')}${button('nav-settings',icon('settings',14)+'설정',key==='settings'?'active':'')}</nav>`}</div>`;
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
      }
    }
  }
  function draw() {
    if(state.until && Date.now()>=state.until){state.paused='';state.until=0;}
    gallery.innerHTML=Object.entries(views).map(([key,label])=>`<article class="board tiles" data-screen="${key}"><div class="board-top">${labels[key]}</div><h2>${label}</h2><div class="stage stage-${key}">${frame(key)}</div>${button('expand','크게 보기 ↗','open-detail',label+' 크게 보기')}</article>`).join('');
    paint(gallery);
    if(detail.open) renderDetail();
  }
  function renderDetail() {
    document.querySelector('#detail-heading').textContent=views[detailView];
    document.querySelector('#detail-copy').textContent=labels[detailView];
    document.querySelector('#detail-views').innerHTML=viewButtons(detailView);
    const stage=document.querySelector('#detail-stage');
    stage.className=`stage tiles stage-${detailView}`;
    stage.innerHTML=frame(detailView);paint(stage);
  }
  function openDetail(key) {
    detailView=key;
    if(!detail.open) detail.showModal();
    renderDetail();
  }
  function popup(title,body) {
    document.querySelector('#sheet-content').innerHTML=`<h2 id="sheet-title">${title}</h2>${body}`;
    if(!sheet.open) sheet.showModal();
  }
  function act(key) {
    const s=state;
    if(key.startsWith('nav-')) return openDetail(key.slice(4));
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
  }
  document.addEventListener('click',event=>{
    const b=event.target.closest('button');if(!b)return;
    if(b.id==='close'){detail.close();return;}
    if(b.classList.contains('sheet-close')){sheet.close();return;}
    if(b.dataset.view){
      detailView=b.dataset.view;renderDetail();return;
    }
    if(b.dataset.action==='expand') return openDetail(b.closest('[data-screen]').dataset.screen);
    if(b.dataset.action) act(b.dataset.action);
  });
  sheet.addEventListener('change',event=>{
    const el=event.target;if(!el.dataset.group)return;
    const group=state[el.dataset.group];
    if(el.checked) group.add(el.value);else group.delete(el.value);
    draw();
  });
  draw();
}

buildBoard();

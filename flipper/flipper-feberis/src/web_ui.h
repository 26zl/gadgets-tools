// Embedded dashboard with safe DOM rendering.
#pragma once

static const char INDEX_HTML[] PROGMEM = R"HTML(<!doctype html><html><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; connect-src 'self'">
<title>Feberis Recon</title><style>
body{background:#111;color:#ddd;font:14px system-ui;margin:0;padding:10px}h1{font-size:16px;color:#4fd}
.row{display:flex;gap:10px;flex-wrap:wrap}.card{background:#1b1b1b;border:1px solid #333;border-radius:8px;padding:8px;flex:1;min-width:130px}
b{color:#4fd}small{color:#888}table{width:100%;border-collapse:collapse;font-size:12px}
td,th{text-align:left;padding:2px 4px;border-bottom:1px solid #262626}
a.btn{display:inline-block;background:#243;color:#8fd;padding:6px 10px;border-radius:6px;text-decoration:none;margin:6px 6px 0 0}
canvas{background:#000;border:1px solid #333;border-radius:8px;width:100%;height:180px;margin-top:8px}</style></head><body>
<h1>Feberis Pro — Recon</h1>
<div class="row"><div class="card">GPS: <b id="fix">-</b><br>Sats: <b id="sats">0</b></div>
<div class="card">APs seen: <b id="cnt">0</b></div></div>
<p><small id="stat"></small></p>
<p><a class="btn" href="/wigle.csv">Download WiGLE CSV</a><a class="btn" href="/track.gpx">Download GPX</a></p>
<canvas id="map" width="320" height="180" role="img" aria-label="AP scatter map"></canvas>
<table><thead><tr><th>SSID</th><th>RSSI</th><th>Ch</th><th>Enc</th></tr></thead><tbody id="tb"></tbody></table>
<script>
const $=id=>document.getElementById(id);
function k(n){return Math.round(n/1024);}
async function tick(){
 try{
  const d=await (await fetch('/data.json')).json();
  $('fix').style.color='#4fd';
  $('fix').textContent=d.gps.fix?d.gps.lat.toFixed(5)+', '+d.gps.lng.toFixed(5)
                                :(d.gps.time?'time ok, no fix':'no fix');
  $('sats').textContent=d.gps.sats;
  $('cnt').textContent=d.count+(d.dropped?' (+'+d.dropped+' dropped)':'');
  $('stat').textContent='heap '+k(d.heap)+'k (min '+k(d.minheap)+'k) · '
    +(d.scanning?'scanning':'idle')+' · '+d.count+'/'+d.max+' APs · '
    +d.track+' trkpts @'+d.trkgap+'s'
    +(d.dropped?' · '+d.dropped+' AP drop':'')+(d.scanfails?' · '+d.scanfails+' scanfail':'');
  const tb=$('tb');tb.textContent='';
  for(const a of d.aps){
   const tr=document.createElement('tr');
   for(const v of [a.ssid||'<hidden>',a.rssi,a.ch,a.enc]){
    const td=document.createElement('td');td.textContent=v;tr.appendChild(td);
   }
   tb.appendChild(tr);
  }
  draw(d);
 }catch(e){$('fix').style.color='#f66';$('fix').textContent='offline';}
}
function draw(d){
 const c=$('map').getContext('2d');c.clearRect(0,0,320,180);
 let pts=d.aps.filter(a=>a.lat!==undefined);
 if(d.gps.fix)pts=pts.concat([{lat:d.gps.lat,lng:d.gps.lng,me:1}]);
 if(!pts.length)return;
 const la=pts.map(p=>p.lat),lo=pts.map(p=>p.lng);
 const nla=Math.min(...la),xla=Math.max(...la),nlo=Math.min(...lo),xlo=Math.max(...lo);
 const sx=v=>10+(xlo-nlo?(v-nlo)/(xlo-nlo):.5)*300,sy=v=>170-(xla-nla?(v-nla)/(xla-nla):.5)*160;
 pts.forEach(p=>{c.fillStyle=p.me?'#4fd':'#f84';c.beginPath();c.arc(sx(p.lng),sy(p.lat),p.me?5:3,0,7);c.fill();});
}
tick();setInterval(tick,2000);
</script></body></html>)HTML";

const C='mi-carrito-v65',F=['./','index.html','zxing.min.js','manifest.json','icon-192.png','icon-512.png'];
self.addEventListener('install',e=>{e.waitUntil(caches.open(C).then(c=>c.addAll(F)));self.skipWaiting()});
self.addEventListener('activate',e=>{e.waitUntil(caches.keys().then(k=>Promise.all(k.filter(x=>x!==C&&!x.startsWith('mi-carrito-ocr')).map(x=>caches.delete(x)))));self.clients.claim()});
const put=(n,req,res)=>{if(res&&res.ok){const c=res.clone();caches.open(n).then(x=>x.put(req,c))}return res};
self.addEventListener('fetch',e=>{const u=new URL(e.request.url);
  if(e.request.method!=='GET'||u.origin!==location.origin)return;
  /* archivos para leer etiquetas: primero la copia guardada (son grandes y no cambian) */
  if(u.pathname.includes('/ocr/')||u.pathname.includes('/pdf/')){e.respondWith(caches.open('mi-carrito-ocr-v1').then(c=>c.match(e.request).then(r=>r||fetch(e.request).then(res=>put('mi-carrito-ocr-v1',e.request,res)))));return}
  /* resto: red con límite de 3 s y, si no llega, la copia guardada */
  e.respondWith(new Promise(ok=>{let done=false;
    const fb=()=>caches.match(e.request).then(r=>r||caches.match('index.html'));
    const t=setTimeout(()=>fb().then(r=>{if(r&&!done){done=true;ok(r)}}),3000);
    fetch(e.request).then(res=>{put(C,e.request,res);if(!done){done=true;clearTimeout(t);ok(res)}})
      .catch(()=>fb().then(r=>{if(!done){done=true;clearTimeout(t);ok(r||Response.error())}}));}));
});

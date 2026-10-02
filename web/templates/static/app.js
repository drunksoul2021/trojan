'use strict';
const $=id=>document.getElementById(id);
let token=sessionStorage.getItem('trojan-token')||'', currentUser='', records=[], server={}, socket;
function notify(message,ok=false){$('notice').textContent=message;$('notice').className=ok?'ok':'';}
function b64(value){const bytes=new TextEncoder().encode(value);return btoa(Array.from(bytes,x=>String.fromCharCode(x)).join(''));}
function decode(value){return new TextDecoder().decode(Uint8Array.from(atob(value),x=>x.charCodeAt(0)));}
async function request(path,method='GET',data){
 const options={method,headers:{Authorization:'Bearer '+token}};
 if(data instanceof FormData)options.body=data;
 else if(data){options.headers['Content-Type']='application/x-www-form-urlencoded';options.body=new URLSearchParams(data);}
 const response=await fetch(path,options), body=await response.json();
 if(response.status===401){signOut();throw Error('登录已过期，请重新登录。');}
 if(!response.ok)throw Error(body.message||'请求失败（'+response.status+'）');
 if(body.Msg&&body.Msg!=='success')throw Error(body.Msg);
 return body.Data??body.data??body;
}
function signOut(){token='';sessionStorage.removeItem('trojan-token');$('login').hidden=false;$('dashboard').hidden=true;$('logout').hidden=true;$('identity').textContent='';if(socket)socket.close();}
function bytes(value){if(value<0)return '不限';const units=['B','KB','MB','GB','TB'];let n=0;while(value>=1024&&n<4){value/=1024;n++;}return value.toFixed(n?2:0)+' '+units[n];}
async function copy(text){await navigator.clipboard.writeText(text);notify('已复制。',true);}
async function load(){
 const identity=await request('/auth/loginUser');currentUser=identity.username;
 $('login').hidden=true;$('dashboard').hidden=false;$('logout').hidden=false;$('identity').textContent=currentUser;$('adminActions').hidden=currentUser!=='admin';
 server=await request('/trojan/user');records=server.userList||[];
 $('server').textContent='连接地址：'+server.domain+':'+server.port;
 $('users').replaceChildren();
 for(const user of records){
  const row=document.createElement('tr');
  for(const value of [user.Username,bytes(user.Download+user.Upload),bytes(user.Quota),user.ExpiryDate||'长期']){const td=document.createElement('td');td.textContent=value;row.append(td);}
  const actions=document.createElement('td');
  const button=(label,handler,danger=false)=>{const b=document.createElement('button');b.textContent=label;b.className=danger?'danger':'';b.onclick=()=>run(handler);actions.append(b);};
  button('复制链接',()=>copy('trojan://'+encodeURIComponent(decode(user.Password))+'@'+server.domain+':'+server.port+'?sni='+encodeURIComponent(server.domain)+'#'+encodeURIComponent(user.Username)));
  if(currentUser==='admin'){
   button('复制订阅',()=>copy(location.origin+'/trojan/user/subscribe?token='+encodeURIComponent(b64(JSON.stringify({user:user.Username,pass:decode(user.Password)})))));button('编辑',()=>edit(user));button('限额',()=>setQuota(user));button('期限',()=>setExpiry(user));
   button('清空流量',async()=>{if(confirm('清空 '+user.Username+' 的流量统计？')){await request('/trojan/data?id='+user.ID,'DELETE');await load();}});
   button('删除',async()=>{if(confirm('删除用户 '+user.Username+'？')){await request('/trojan/user?id='+user.ID,'DELETE');await load();}},true);
  }
  row.append(actions);$('users').append(row);
 }
 if(!records.length){const row=$('users').insertRow();const cell=row.insertCell();cell.colSpan=5;cell.textContent='暂无用户。';}
}
async function run(action){try{await action();}catch(e){notify(e.message);}}
function edit(user){const form=$('userForm');form.elements.id.value=user?.ID||'';form.elements.username.value=user?.Username||'';form.elements.password.value=user?decode(user.Password):'';$('formTitle').textContent=user?'编辑用户':'新增用户';$('userDialog').showModal();}
async function setQuota(user){const input=prompt('流量上限（GB），-1 表示不限，0 表示停用',user.Quota<0?'-1':String(user.Quota/1073741824));if(input===null)return;const value=Number(input);if(!Number.isFinite(value)||value< -1)throw Error('请输入有效的流量限额。');await request('/trojan/data','POST',{id:user.ID,quota:Math.round(value<0?-1:value*1073741824)});await load();}
async function setExpiry(user){const input=prompt('可用天数，0 表示长期',user.UseDays||0);if(input===null)return;const value=Number(input);if(!Number.isInteger(value)||value<0)throw Error('请输入非负整数天数。');if(value===0)await request('/trojan/user/expire?id='+user.ID,'DELETE');else await request('/trojan/user/expire','POST',{id:user.ID,useDays:value});await load();}
$('loginForm').onsubmit=event=>{event.preventDefault();run(async()=>{const data=Object.fromEntries(new FormData(event.target));const result=await request('/auth/login','POST',data);token=result.token;sessionStorage.setItem('trojan-token',token);event.target.elements.password.value='';notify('');await load();});};
$('logout').onclick=signOut;$('refresh').onclick=()=>run(load);$('add').onclick=()=>edit();$('cancelUser').onclick=()=>$('userDialog').close();
$('userForm').onsubmit=event=>{event.preventDefault();run(async()=>{const form=Object.fromEntries(new FormData(event.target));form.password=b64(form.password);await request(form.id?'/trojan/user/update':'/trojan/user','POST',form);$('userDialog').close();notify('用户已保存。',true);await load();});};
$('restart').onclick=()=>run(async()=>{if(confirm('重启 Trojan 会断开当前客户端连接，继续？')){await request('/trojan/restart','POST');notify('重启命令已执行。',true);}});
$('resetPassword').onclick=()=>run(async()=>{const password=prompt('请输入新的管理员密码（至少 6 位）');if(password===null)return;if(password.length<6)throw Error('密码至少 6 位。');await request('/auth/reset_pass','POST',{password});signOut();notify('密码已修改，请重新登录。',true);});
$('export').onclick=()=>run(async()=>{const response=await fetch('/trojan/export',{headers:{Authorization:'Bearer '+token}});if(!response.ok)throw Error('导出失败。');const url=URL.createObjectURL(await response.blob()),a=document.createElement('a');a.href=url;a.download='trojan-users.csv';a.click();URL.revokeObjectURL(url);});
$('import').onclick=()=>{if(confirm('导入 CSV 会替换当前用户列表，请先导出备份。继续？'))$('importFile').click();};
$('importFile').onchange=event=>run(async()=>{const file=event.target.files[0];if(!file)return;const form=new FormData();form.append('file',file);await request('/trojan/import','POST',form);await load();event.target.value='';notify('导入完成。',true);});
$('logs').onclick=()=>{if(socket)socket.close();$('logPanel').hidden=false;$('logText').textContent='';socket=new WebSocket((location.protocol==='https:'?'wss://':'ws://')+location.host+'/trojan/log?token='+encodeURIComponent(token));socket.onmessage=event=>{const log=$('logText');log.textContent=(log.textContent+event.data+'\n').slice(-50000);log.scrollTop=log.scrollHeight;};socket.onerror=()=>notify('日志连接失败，请检查服务状态。');};
$('closeLogs').onclick=()=>{if(socket)socket.close();$('logPanel').hidden=true;};
if(token)run(load);

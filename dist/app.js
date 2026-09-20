const dialog=document.querySelector('#download-dialog');
document.querySelectorAll('[data-download]').forEach(button=>button.addEventListener('click',()=>dialog.showModal()));
document.querySelector('.dialog-close').addEventListener('click',()=>dialog.close());
dialog.addEventListener('click',event=>{if(event.target===dialog){const r=dialog.getBoundingClientRect();if(event.clientX<r.left||event.clientX>r.right||event.clientY<r.top||event.clientY>r.bottom)dialog.close();}});
const notch=document.querySelector('#notch');
const toggle=document.querySelector('#notch-toggle');
let hoverBlocked=false;
function setExpanded(value){notch.classList.toggle('expanded',value);toggle.setAttribute('aria-expanded',String(value));document.querySelector('#notch-content').inert=!value;document.querySelector('#close-hint').textContent=value?'esc to close':'open';if(!value)hoverBlocked=true;}
notch.addEventListener('pointerleave',()=>{hoverBlocked=false;});
toggle.addEventListener('pointerenter',event=>{if(event.pointerType==='mouse'&&!hoverBlocked)setExpanded(true);});
toggle.addEventListener('click',()=>setExpanded(!notch.classList.contains('expanded')));
document.addEventListener('keydown',event=>{if(event.key==='Escape'&&!dialog.open)setExpanded(false);});
const detail=document.querySelector('#position-detail');
const details=['Unclaimed fees <strong>$132.43</strong> · USD P&L <strong>+$119.95</strong>','Unclaimed fees <strong>$8.29</strong> · USD P&L <span class="negative">−$0.26</span>'];
document.querySelectorAll('[data-position]').forEach(button=>{button.setAttribute('aria-controls','position-detail');button.setAttribute('aria-expanded','false');button.addEventListener('click',()=>{const index=button.dataset.position;const same=detail.dataset.active===index&&!detail.hidden;detail.hidden=same;detail.dataset.active=index;detail.innerHTML=details[Number(index)];document.querySelectorAll('[data-position]').forEach(row=>row.setAttribute('aria-expanded',String(row===button&&!same)));});});

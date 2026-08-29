import{aC as p}from"./app-BCBv5ZJL.js";import{e as d}from"./battery-2S6aJXQq.js";async function H(t=240){const r=(await d(`{ cat '${p.CHARGE_HISTORY}' 2>/dev/null; cat '${p.CHARGE_HISTORY}.pending' 2>/dev/null; } | tail -n ${t+1}`)).stdout.trim();if(!r)return[];const u=r.split(/\r?\n/).filter(Boolean),n=[];for(const i of u){if(i.startsWith("ts,"))continue;const s=i.split(",");if(s.length<2)continue;const c=Number(s[0]),o=Number(s[1]);if(!Number.isFinite(c)||!Number.isFinite(o))continue;const l=s[2],m=s[3],a=l&&l!=="--"?Number(l):null,f=m?Number(m):null;n.push({ts:c,level:o,temp:Number.isFinite(a)?a:null,currentUa:Number.isFinite(f)?f:null,status:s[4]||"",source:s[5]||""})}return n}function b(t){if(t==="0")return 0;const e=t.match(/^\+?(?:(\d+)d)?(?:(\d+)h)?(?:(\d+)m(?!s))?(?:(\d+)s)?(?:(\d+)ms)?$/);if(!e)return null;const[,r,u,n,i,s]=e;return!r&&!u&&!n&&!i&&!s?null:Number(r||0)*864e5+Number(u||0)*36e5+Number(n||0)*6e4+Number(i||0)*1e3+Number(s||0)}function h(t){const e=t.match(/RESET:TIME:\s*(\d{4})-(\d{2})-(\d{2})-(\d{2})-(\d{2})-(\d{2})/);if(!e)return null;const[,r,u,n,i,s,c]=e.map(Number),o=new Date(r,u-1,n,i,s,c).getTime();return Number.isFinite(o)?Math.floor(o/1e3):null}async function $(){const t=`awk '
/RESET:TIME:/ { reset = $0; count = 0; next }
/^[[:space:]]*[+0]/ {
  if (count < 1200) {
    lines[++count] = $0;
  } else {
    for (i = 1; i < 1200; i++) lines[i] = lines[i + 1];
    lines[1200] = $0;
  }
}
END {
  if (reset != "") print reset;
  for (i = 1; i <= count; i++) print lines[i];
}'`;let e="";return e=(await d(`dumpsys batterystats --history 2>/dev/null | ${t}`,15e3)).stdout.trim(),e||(e=(await d(`dumpsys batterystats 2>/dev/null | sed -n '/Battery History/,$p' | ${t}`,15e3)).stdout.trim()),y(e)}function y(t){if(!t.trim())return[];const e=[];let r=null;for(const u of t.split(/\r?\n/)){const n=u.trim();if(!n)continue;const i=h(n);if(i!=null){r=i;continue}if(r==null)continue;const s=n.match(/^(\+?[\dhmsd]+|0)\s+\(\d+\)\s+(\d{1,3})\b(.*)$/);if(!s)continue;const c=b(s[1]);if(c==null)continue;const o=Number(s[2]);if(!Number.isFinite(o)||o<0||o>100)continue;const l=s[3],m=l.match(/\btemp=(\d+)/),a=l.match(/\bplug=(\w+)/),f=l.match(/\bstatus=(\w+)/);e.push({ts:r+Math.floor(c/1e3),level:o,temp:m?Math.round(Number(m[1])/10):null,currentUa:null,status:f?f[1]:"",source:a&&a[1]!=="none"?a[1]:"none"})}return e}function R(t,e){if(!e.length)return t;const r=new Set(t.map(n=>Math.round(n.ts/60)));return[...t,...e.filter(n=>!r.has(Math.round(n.ts/60)))].sort((n,i)=>n.ts-i.ts)}async function T(){return(await d(`cat '${p.COMPAT_HINT}' 2>/dev/null`)).stdout.trim()}export{$ as a,T as b,H as l,R as m};

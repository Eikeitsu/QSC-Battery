import{N as p}from"./app-SQbgAxWT.js";import{a0 as d}from"./theme-iP-ptnCn.js";async function H(e=240){const s=(await d(`{ cat '${p.CHARGE_HISTORY}' 2>/dev/null; cat '${p.CHARGE_HISTORY}.pending' 2>/dev/null; } | tail -n ${e+1}`)).stdout.trim();if(!s)return[];const o=s.split(/\r?\n/).filter(Boolean),r=[];for(const i of o){if(i.startsWith("ts,"))continue;const t=i.split(",");if(t.length<2)continue;const l=Number(t[0]),u=Number(t[1]);if(!Number.isFinite(l)||!Number.isFinite(u))continue;const c=t[2],m=t[3],a=c&&c!=="--"?Number(c):null,f=m?Number(m):null;r.push({ts:l,level:u,temp:Number.isFinite(a)?a:null,currentUa:Number.isFinite(f)?f:null,status:t[4]||"",source:t[5]||""})}return r}function b(e){if(e==="0")return 0;const n=e.match(/^\+?(?:(\d+)d)?(?:(\d+)h)?(?:(\d+)m(?!s))?(?:(\d+)s)?(?:(\d+)ms)?$/);if(!n)return null;const[,s,o,r,i,t]=n;return!s&&!o&&!r&&!i&&!t?null:Number(s||0)*864e5+Number(o||0)*36e5+Number(r||0)*6e4+Number(i||0)*1e3+Number(t||0)}function N(e){const n=e.match(/RESET:TIME:\s*(\d{4})-(\d{2})-(\d{2})-(\d{2})-(\d{2})-(\d{2})/);if(!n)return null;const[,s,o,r,i,t,l]=n.map(Number),u=new Date(s,o-1,r,i,t,l).getTime();return Number.isFinite(u)?Math.floor(u/1e3):null}async function $(){const e=`awk '
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
}'`;let n="";return n=(await d(`dumpsys batterystats --history 2>/dev/null | ${e}`,15e3)).stdout.trim(),n||(n=(await d(`dumpsys batterystats 2>/dev/null | sed -n '/Battery History/,$p' | ${e}`,15e3)).stdout.trim()),y(n)}function y(e){if(!e.trim())return[];const n=[];let s=null;for(const o of e.split(/\r?\n/)){const r=o.trim();if(!r)continue;const i=N(r);if(i!=null){s=i;continue}if(s==null)continue;const t=r.match(/^(\+?[\dhmsd]+|0)\s+\(\d+\)\s+(\d{1,3})\b(.*)$/);if(!t)continue;const l=b(t[1]);if(l==null)continue;const u=Number(t[2]);if(!Number.isFinite(u)||u<0||u>100)continue;const c=t[3],m=c.match(/\btemp=(\d+)/),a=c.match(/\bplug=(\w+)/),f=c.match(/\bstatus=(\w+)/);n.push({ts:s+Math.floor(l/1e3),level:u,temp:m?Math.round(Number(m[1])/10):null,currentUa:null,status:f?f[1]:"",source:a&&a[1]!=="none"?a[1]:"none"})}return n}async function R(){return(await d(`cat '${p.COMPAT_HINT}' 2>/dev/null`)).stdout.trim()}export{$ as a,R as b,H as l};

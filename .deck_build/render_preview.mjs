import fs from 'node:fs/promises';
import path from 'node:path';
import { inflateRawSync } from 'node:zlib';
import { createRequire } from 'node:module';

const root='C:/Users/SiyamSadikul/Downloads/genius_tcg_v7_genshin_style';
const pptx=await fs.readFile(path.join(root,'presentations/Genius_Invokation_Project_Idea.pptx'));
const req=createRequire('C:/Users/SiyamSadikul/AppData/Local/OpenAI/Codex/runtimes/cua_node/a9ba6825a525118c/bin/node_modules/.codex-preview.cjs');
const sharp=req('sharp');
const entries=new Map(); let offset=0;
while(offset+30<pptx.length && pptx.readUInt32LE(offset)===0x04034b50){
  const method=pptx.readUInt16LE(offset+8), size=pptx.readUInt32LE(offset+18), nameLen=pptx.readUInt16LE(offset+26), extraLen=pptx.readUInt16LE(offset+28);
  const name=pptx.subarray(offset+30,offset+30+nameLen).toString('utf8');
  const start=offset+30+nameLen+extraLen, packed=pptx.subarray(start,start+size);
  entries.set(name,method===8?inflateRawSync(packed):packed);
  offset=start+size;
}
const xmlDecode=s=>s.replaceAll('&lt;','<').replaceAll('&gt;','>').replaceAll('&quot;','"').replaceAll('&apos;',"'").replaceAll('&amp;','&');
const attr=(s,k)=>{const m=s.match(new RegExp(`${k}="([^"]*)"`));return m?m[1]:'';};
const rectEmu=(xml)=>{const m=xml.match(/<a:off x="(\d+)" y="(\d+)"\/><a:ext cx="(\d+)" cy="(\d+)"/);return m?m.slice(1).map(Number):[0,0,0,0];};
const size=1.3333333333;
const px=n=>Number(n)/12700*size;
const wrap=(str,max)=>{const out=[];let line='';for(const word of str.split(/\s+/)){const t=line?`${line} ${word}`:word;if(t.length>max&&line){out.push(line);line=word;}else line=t;}if(line)out.push(line);return out;};
const renders=[];
for(let n=1;n<=8;n++){
  const xml=entries.get(`ppt/slides/slide${n}.xml`).toString('utf8');
  const bg=xml.match(/<p:bg>.*?<a:srgbClr val="([A-Fa-f0-9]+)"/s)?.[1]||'FFFFFF';
  const relxml=entries.get(`ppt/slides/_rels/slide${n}.xml.rels`).toString('utf8');
  const relMap=new Map([...relxml.matchAll(/<Relationship Id="([^"]+)"[^>]*Target="([^"]+)"/g)].map(m=>[m[1],m[2].replace('../media/','ppt/media/')]));
  const shapes=[]; let id=2;
  for(const m of xml.matchAll(/<p:sp>(.*?)<\/p:sp>/gs)){
    const chunk=m[1], [x,y,w,h]=rectEmu(chunk), geom=chunk.match(/<a:prstGeom prst="([^"]+)"/)?.[1]||'rect';
    const box=`x="${px(x)}" y="${px(y)}" width="${px(w)}" height="${px(h)}"`;
    const spPr=chunk.match(/<p:spPr>(.*?)<\/p:spPr>/s)?.[1]||'';
    const lineColor=spPr.match(/<a:ln[^>]*>.*?<a:srgbClr val="([A-Fa-f0-9]+)"/s)?.[1];
    const fillColor=spPr.match(/<a:solidFill><a:srgbClr val="([A-Fa-f0-9]+)"/s)?.[1];
    if(fillColor) shapes.push(`<rect ${box} rx="${geom==='roundRect'?12:0}" fill="#${fillColor}"/>`);
    if(lineColor) shapes.push(`<rect ${box} rx="${geom==='roundRect'?12:0}" fill="none" stroke="#${lineColor}" stroke-width="1.5"/>`);
    const tx=chunk.match(/<p:txBody>(.*?)<\/p:txBody>/s)?.[1];
    if(tx){
      const lines=[...tx.matchAll(/<a:p>(.*?)<\/a:p>/gs)];
      let yy=px(y), html='';
      for(const p of lines){
        const t=xmlDecode([...p[1].matchAll(/<a:t[^>]*>(.*?)<\/a:t>/gs)].map(q=>q[1]).join(''));
        const rp=p[1].match(/<a:rPr[^>]*>/)?.[0]||p[1].match(/<a:endParaRPr[^>]*>/)?.[0]||'';
        const fontSize=(Number(attr(rp,'sz'))||1800)/100*size;
        const color=p[1].match(/<a:srgbClr val="([A-Fa-f0-9]+)"/)?.[1]||'171E20';
        const font=p[1].match(/<a:latin typeface="([^"]+)"/)?.[1]||'Aptos';
        const bold=attr(rp,'b')==='1';
        const algn=p[1].match(/<a:pPr algn="([^"]+)"/)?.[1]||'l';
        const max=Math.max(8,Math.floor(px(w)/(fontSize*.53)));
        const wrapped=wrap(t,max);
        for(const ln of wrapped){
          const anchor=algn==='ctr'?'middle':algn==='r'?'end':'start';
          const txp=algn==='ctr'?px(x)+px(w)/2:algn==='r'?px(x)+px(w)-2:px(x);
          html+=`<text x="${txp}" y="${yy+fontSize}" text-anchor="${anchor}" font-family="${font},Georgia,serif" font-size="${fontSize}" font-weight="${bold?'bold':'normal'}" fill="#${color}">${xmlDecode(ln).replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;')}</text>`;
          yy+=fontSize*1.18;
        }
      }
      shapes.push(html);
    }
    id++;
  }
  for(const m of xml.matchAll(/<p:pic>(.*?)<\/p:pic>/gs)){
    const chunk=m[1],[x,y,w,h]=rectEmu(chunk),rid=chunk.match(/r:embed="([^"]+)"/)?.[1],target=relMap.get(rid),bytes=entries.get(target);
    if(bytes) shapes.push(`<image x="${px(x)}" y="${px(y)}" width="${px(w)}" height="${px(h)}" preserveAspectRatio="none" href="data:image/png;base64,${bytes.toString('base64')}"/>`);
  }
  const svg=`<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="1280" height="720" viewBox="0 0 1280 720"><rect width="1280" height="720" fill="#${bg}"/>${shapes.join('')}</svg>`;
  const file=path.join(root,`.deck_build/rendered/preview-${n}.png`);
  await fs.mkdir(path.dirname(file),{recursive:true});
  await fs.writeFile(path.join(root,`.deck_build/rendered/preview-${n}.svg`),svg);
  await sharp(Buffer.from(svg)).png().toFile(file); renders.push(file);
}
console.log(renders.join('\n'));

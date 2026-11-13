import fs from 'node:fs/promises';
import path from 'node:path';
import { deflateRawSync } from 'node:zlib';

const root = 'C:/Users/SiyamSadikul/Downloads/genius_tcg_v7_genshin_style';
const outDir = path.join(root, 'presentations');
const outPath = path.join(outDir, 'Genius_Invokation_Project_Idea.pptx');
await fs.mkdir(outDir, { recursive: true });
try { await fs.access(outPath); throw new Error(`Refusing to overwrite ${outPath}`); }
catch (e) { if (e.message.startsWith('Refusing')) throw e; }

const C = {
  ink:'171E20', deep:'182927', deep2:'243633', green:'31594C', gold:'D6B56F', goldLight:'F0D99F',
  cream:'F4EBDD', paper:'F4EFE4', white:'FCFAF4', body:'E6E4DC', muted:'AEB9B0', darkMuted:'57635E',
  line:'69766D', aqua:'9BC7C1', teal:'5D9287',
};
const pptW=960, pptH=540, emu=12700;
let picIndex=0;
const txt=(x,y,w,h,value,size=18,color=C.body,bold=false,font='Aptos',align='l')=>({t:'text',x,y,w,h,value,size,color,bold,font,align});
const rect=(x,y,w,h,fill,line=fill,lineWidth=0,round=false,trans=0)=>({t:'rect',x,y,w,h,fill,line,lineWidth,round,trans});
const line=(x,y,w,h,color,width=1)=>rect(x,y,w,h,color,color,0,false);
const img=(x,y,w,h,src)=>({t:'image',x,y,w,h,src});
const slide=(bg)=>({bg,items:[]});
const add=(s,...items)=>s.items.push(...items);
const header=(s,kicker,title,dark=true)=>{
  const head=dark?C.cream:C.ink, kick=dark?C.gold:C.green;
  add(s,txt(48,34,800,18,kicker.toUpperCase(),11,kick,true),txt(48,58,866,46,title,30,head,true,'Georgia'));
};
const footer=(s,n,dark=true)=>{
  const color=dark?C.muted:C.darkMuted, rule=dark?C.line:'D0C9BB';
  add(s,line(48,504,864,0.7,rule,0.65),txt(48,512,500,16,'GENIUS INVOKATION  /  PROJECT IDEA',9,color,true),txt(850,512,62,16,`${String(n).padStart(2,'0')} / 08`,9,color,true,'Aptos','r'));
};
const feature=(s,title,body,x,y,w,dark=true,bodySize=16)=>{
  add(s,txt(x,y,w,25,title,18,dark?C.goldLight:C.green,true,'Georgia'),txt(x,y+31,w,56,body,bodySize,dark?C.body:C.ink));
};
const phase=(s,n,title,body,x,y,w,h)=>{
  add(s,txt(x,y,38,30,`0${n}`,22,C.green,true,'Georgia'),txt(x,y+36,w,26,title,20,C.green,true,'Georgia'),txt(x,y+70,w,h-70,body,15.5,C.ink));
};

const deck=[];
// 1 — Intro
{
  const s=slide(C.deep);
  add(s,txt(52,58,390,18,'PROJECT IDEA',12,C.gold,true),txt(52,105,420,138,'Genius\nInvokation',42,C.cream,true,'Georgia'),
    txt(55,264,410,40,'A turn-based elemental card battler',23,C.goldLight,false,'Georgia'),
    txt(55,326,372,89,'Build a deck, roll for resources, then choose how to spend each turn. This Pygame prototype combines tactical card play with an AI opponent.',18,C.body),
    img(486,120,424,238,'genius_tcg/shots/12_inspect_card.png'),rect(486,120,424,238,'000000',C.gold,1.3,false,100),
    txt(486,382,424,28,'A strategy game built around resource choices',16,C.cream,true,'Aptos','c'),
    txt(55,455,600,20,'GAME CONCEPT  |  PLAYABLE PROTOTYPE',11,C.muted,true));
  footer(s,1,true); deck.push(s);
}
// 2 — Round flow
{
  const s=slide(C.paper); header(s,'01 / core loop','A match unfolds in rounds',false);
  add(s,txt(48,112,842,29,'Each round moves from preparation to action, then resolves effects before resources refresh.',17,C.darkMuted),
    line(110,188,736,1.4,'B9AE9A',1.4));
  phase(s,1,'Roll','Each player rolls 8 elemental dice and may reroll once. Before the first round, players choose their initial active combatant.',52,156,238,192);
  phase(s,2,'Action','Players alternate actions: use a skill, switch, play a card, tune a die, or end the round. Costs are paid from the rolled dice.',358,156,252,192);
  phase(s,3,'End phase','Summons resolve, round effects refresh, and each player draws 2 cards. The first player to end acts first next round.',672,156,236,192);
  add(s,line(48,394,864,0.8,'D0C9BB',0.8),txt(50,416,160,17,'WIN CONDITION',11,C.green,true),txt(50,441,810,31,'Defeat all three opposing combatants.',21,C.ink,true,'Georgia'));
  footer(s,2,false); deck.push(s);
}
// 3 — Deck and resource economy
{
  const s=slide(C.deep); header(s,'02 / resources','Decks, cards and elemental dice',true);
  add(s,txt(48,112,800,28,'A compact resource economy makes every action compete with the next one.',17,C.muted),line(48,155,864,0.8,C.line,0.8),
    txt(54,178,122,60,'30',43,C.goldLight,true,'Georgia'),txt(54,236,205,27,'cards per deck',18,C.cream,true,'Georgia'),
    txt(54,273,244,76,'At most 2 copies of a card. Players begin with 5 cards and can mulligan before play.',15.5,C.body),
    line(320,178,0.8,164,C.line,0.8),txt(358,178,122,60,'8',43,C.goldLight,true,'Georgia'),
    txt(358,236,210,27,'dice per round',18,C.cream,true,'Georgia'),
    txt(358,273,244,76,'Six elemental faces plus Omni. Each player gets one reroll before the action phase.',15.5,C.body),
    line(624,178,0.8,164,C.line,0.8),txt(661,178,122,60,'1',43,C.goldLight,true,'Georgia'),
    txt(661,236,225,27,'die can be tuned',18,C.cream,true,'Georgia'),
    txt(661,273,245,76,'Discard a card to convert one non-matching, non-Omni die into the active element.',15.5,C.body),
    line(48,373,864,0.8,C.line,0.8),txt(50,399,180,18,'PAYING AN ACTION',11,C.gold,true),
    txt(50,428,844,46,'Element-matched dice or Omni satisfy aligned cost; unaligned cost accepts any remaining die.',18,C.body));
  footer(s,3,true); deck.push(s);
}
// 4 — Cards and elemental reactions
{
  const s=slide(C.paper); header(s,'03 / tactical layer','Card roles and elemental reactions',false);
  add(s,txt(48,112,850,28,'Cards shape the board; matching elements create extra consequences.',17,C.darkMuted),
    txt(50,164,280,20,'CARD FAMILIES',12,C.green,true));
  feature(s,'Event','Immediate effects: draw, change resources or alter the current turn.',50,198,247,false,15);
  feature(s,'Support','Persistent board effects that can trigger or refresh over time.',50,284,247,false,15);
  feature(s,'Equipment and resonance','Equipment changes stats or skills; talent cards boost a skill. Resonance cards reward matching team elements.',50,370,247,false,14);
  add(s,line(330,160,0.8,308,'D0C9BB',0.8),txt(366,164,220,20,'ELEMENTS',12,C.green,true),
    txt(366,201,520,79,'Cryo  |  Hydro  |  Pyro\nElectro  |  Anemo  |  Geo\nOmni is a flexible payment die.',20,C.ink,true,'Georgia'),
    txt(366,304,250,20,'REACTION FLOW',12,C.green,true),
    txt(366,341,526,44,'Elemental hit -> aura remains -> different element hits -> reaction resolves',17,C.ink,true),
    txt(366,398,526,67,'Reactions may add damage, spread piercing damage, force a switch, freeze a target, or create a shield. Anemo and Geo can react with an existing aura.',15.5,C.darkMuted));
  footer(s,4,false); deck.push(s);
}
// 5 — Algorithms
{
  const s=slide(C.deep); header(s,'04 / AI architecture','Algorithms that drive decisions',true);
  add(s,txt(48,104,840,26,'The AI proposes a move; the rules engine checks and resolves it.',16,C.muted));
  const steps=[['Visible state',52],['Legal moves',278],['Search and score',504],['Apply action',730]];
  for(const [label,x] of steps) add(s,rect(x,142,174,38,C.deep2,C.gold,0.8,true),txt(x+8,151,158,20,label,14,C.cream,true,'Aptos','c'));
  for(const x of [230,456,682]) add(s,txt(x,146,38,29,'>',20,C.gold,true,'Aptos','c'));
  const algos=[
    ['Fuzzy logic - Easy','HP, energy, dice and hand size become low / medium / high signals. Rules adjust aggression, defence, burst and tempo priorities.'],
    ['A* lethal planner - Normal + Hard','Ranks lethal lines with f(n)=g(n)+h(n): g tracks resource spend; h estimates the damage still needed.'],
    ['Alpha-beta - Normal + Hard','Iterative-deepening minimax looks at replies and prunes weaker branches. Hard uses it to shortlist candidate moves.'],
    ['MCTS / UCT - Hard','Samples plausible hidden hands and deck orders, then runs rollouts. UCT balances strong results with exploring alternatives.'],
    ['Constraint solving - Payments + decks','All-different assigns unique dice to cost slots; MRV and forward checking prune choices. Sum constraints fill legal 30-card decks.'],
    ['Evaluation + rules engine','Scores HP, energy, board, dice and hand. The deterministic rules pipeline applies damage, aura reactions, shields and status effects.'],
  ];
  const pos=[[52,202],[500,202],[52,295],[500,295],[52,388],[500,388]];
  algos.forEach(([title,body],i)=>{
    const [x,y]=pos[i]; add(s,line(x,y,396,0.8,C.line,0.8),txt(x,y+8,396,22,title,16.5,C.goldLight,true,'Georgia'),txt(x,y+34,396,54,body,14.5,C.body));
  });
  footer(s,5,true); deck.push(s);
}
// 6 — Features
{
  const s=slide(C.deep2); header(s,'05 / prototype features','A playable loop with tools around it',true);
  feature(s,'Deck builder','Validates card count, copy limits and team compatibility; CSP auto-fill completes a legal list.',52,128,382,true,15.5);
  feature(s,'Three AI levels','Easy uses fuzzy scoring; Normal searches replies; Hard adds Monte Carlo rollouts.',52,225,382,true,15.5);
  feature(s,'Readable match flow','Battle log, hover details, round banners, reaction feedback and card animations explain each move.',52,322,382,true,15.5);
  feature(s,'Flexible controls','Drag or right-click to tune a die; select exact dice for card, switch and skill costs.',52,419,382,true,15.5);
  add(s,img(470,150,440,248,'genius_tcg/shots/m2_builder_full.png'),rect(470,150,440,248,'000000',C.gold,1,false,100),
    txt(470,411,440,34,'Deck editor: filters, cost curve, validation and auto-fill',15,C.cream,true,'Aptos','c'));
  footer(s,6,true); deck.push(s);
}
// 7 — Prototype visual
{
  const s=slide(C.paper); header(s,'06 / visual direction','How the game looks in play',false);
  add(s,txt(48,112,852,28,'A symmetrical tabletop board keeps combat, resources and the hand visible at once.',17,C.darkMuted),
    img(48,158,572,322,'genius_tcg/shots/10_board.png'),rect(48,158,572,322,'000000',C.green,1.2,false,100));
  feature(s,'Board','Two opposing rows, support and summon zones, plus a shared central play area.',660,170,248,false,15);
  feature(s,'Information','Battle log, dice tray and hand stay in view while the active player chooses.',660,258,248,false,15);
  feature(s,'Presentation','Parchment cards, gold trim and animated feedback give actions a clear visual rhythm.',660,346,248,false,15);
  add(s,txt(49,486,380,16,'Current prototype screenshot',10.5,C.darkMuted));
  footer(s,7,false); deck.push(s);
}
// 8 — Outro
{
  const s=slide(C.deep);
  add(s,txt(52,72,700,20,'GENIUS INVOKATION',12,C.gold,true),txt(52,148,740,196,'Plan the turn.\nRead the board.\nSpend every die with purpose.',38,C.cream,true,'Georgia'),
    line(52,382,360,1.2,C.gold,1.2),txt(52,406,710,46,'A strategy card game prototype powered by a rules engine and layered AI search.',19,C.body),
    txt(52,474,600,18,'THANK YOU  |  QUESTIONS?',11,C.goldLight,true));
  footer(s,8,true); deck.push(s);
}

const esc=s=>String(s).replaceAll('&','&amp;').replaceAll('<','&lt;').replaceAll('>','&gt;').replaceAll('"','&quot;');
const emuN=n=>Math.round(n*emu);
const shapeTreeStart='<p:spTree><p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>';
function rgb(hex){return hex.replace('#','').toUpperCase();}
function textXml(it,id){
  const ps=it.value.split('\n');
  const paragraphs=ps.map(line=>`<a:p><a:pPr algn="${it.align==='c'?'ctr':it.align==='r'?'r':'l'}"><a:lnSpc><a:spcPct val="100000"/></a:lnSpc><a:spcAft><a:spcPts val="250"/></a:spcAft></a:pPr><a:r><a:rPr lang="en-US" sz="${Math.round(it.size*100)}" b="${it.bold?1:0}" dirty="0"><a:solidFill><a:srgbClr val="${rgb(it.color)}"/></a:solidFill><a:latin typeface="${esc(it.font)}"/><a:ea typeface="${esc(it.font)}"/></a:rPr><a:t xml:space="preserve">${esc(line)}</a:t></a:r><a:endParaRPr lang="en-US" sz="${Math.round(it.size*100)}"/></a:p>`).join('');
  return `<p:sp><p:nvSpPr><p:cNvPr id="${id}" name="Text ${id}"/><p:cNvSpPr txBox="1"/><p:nvPr/></p:nvSpPr><p:spPr><a:xfrm><a:off x="${emuN(it.x)}" y="${emuN(it.y)}"/><a:ext cx="${emuN(it.w)}" cy="${emuN(it.h)}"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom><a:noFill/><a:ln><a:noFill/></a:ln></p:spPr><p:txBody><a:bodyPr wrap="square" lIns="0" tIns="0" rIns="0" bIns="0" anchor="t"/><a:lstStyle/>${paragraphs}</p:txBody></p:sp>`;
}
function rectXml(it,id){
  const geom=it.round?'roundRect':'rect';
  const fill=it.trans===100?'<a:noFill/>':`<a:solidFill><a:srgbClr val="${rgb(it.fill)}"${it.trans?`><a:alpha val="${Math.round((100-it.trans)*1000)}"/></a:srgbClr>`:'/>'}</a:solidFill>`;
  const ln=it.lineWidth<=0?'<a:ln><a:noFill/></a:ln>':`<a:ln w="${Math.round(it.lineWidth*12700)}"><a:solidFill><a:srgbClr val="${rgb(it.line)}"/></a:solidFill></a:ln>`;
  return `<p:sp><p:nvSpPr><p:cNvPr id="${id}" name="Shape ${id}"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr><p:spPr><a:xfrm><a:off x="${emuN(it.x)}" y="${emuN(it.y)}"/><a:ext cx="${emuN(it.w)}" cy="${emuN(it.h)}"/></a:xfrm><a:prstGeom prst="${geom}"><a:avLst/></a:prstGeom>${fill}${ln}</p:spPr></p:sp>`;
}
function imageXml(it,id,rid,name){
  return `<p:pic><p:nvPicPr><p:cNvPr id="${id}" name="${esc(name)}"/><p:cNvPicPr><a:picLocks noChangeAspect="1"/></p:cNvPicPr><p:nvPr/></p:nvPicPr><p:blipFill><a:blip r:embed="${rid}"/><a:stretch><a:fillRect/></a:stretch></p:blipFill><p:spPr><a:xfrm><a:off x="${emuN(it.x)}" y="${emuN(it.y)}"/><a:ext cx="${emuN(it.w)}" cy="${emuN(it.h)}"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></p:spPr></p:pic>`;
}
const rels=(items)=>`<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">${items.map(([id,type,target])=>`<Relationship Id="${id}" Type="${type}" Target="${target}"/>`).join('')}</Relationships>`;
const relOffice='http://schemas.openxmlformats.org/officeDocument/2006/relationships/';
const relPkg='http://schemas.openxmlformats.org/package/2006/relationships';
const relsLayout=relOffice+'slideLayout', relsMaster=relOffice+'slideMaster', relsSlide=relOffice+'slide', relsTheme=relOffice+'theme', relsImage=relOffice+'image';

const entries=[];
const put=(name,data)=>entries.push([name,Buffer.isBuffer(data)?data:Buffer.from(data,'utf8')]);
const slidesOverrides=deck.map((_,i)=>`<Override PartName="/ppt/slides/slide${i+1}.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slide+xml"/>`).join('');
put('[Content_Types].xml',`<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Default Extension="png" ContentType="image/png"/><Override PartName="/ppt/presentation.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml"/><Override PartName="/ppt/slideMasters/slideMaster1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideMaster+xml"/><Override PartName="/ppt/slideLayouts/slideLayout1.xml" ContentType="application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml"/><Override PartName="/ppt/theme/theme1.xml" ContentType="application/vnd.openxmlformats-officedocument.theme+xml"/>${slidesOverrides}</Types>`);
put('_rels/.rels',rels([['rId1',relOffice+'officeDocument','ppt/presentation.xml']]));
put('ppt/presentation.xml',`<?xml version="1.0" encoding="UTF-8" standalone="yes"?><p:presentation xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="${relOffice}" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"><p:sldMasterIdLst><p:sldMasterId id="2147483648" r:id="rId1"/></p:sldMasterIdLst><p:sldIdLst>${deck.map((_,i)=>`<p:sldId id="${256+i}" r:id="rId${i+2}"/>`).join('')}</p:sldIdLst><p:sldSz cx="${emuN(pptW)}" cy="${emuN(pptH)}" type="screen16x9"/><p:notesSz cx="6858000" cy="9144000"/><p:defaultTextStyle><a:defPPr><a:defRPr lang="en-US"/></a:defPPr></p:defaultTextStyle></p:presentation>`);
put('ppt/_rels/presentation.xml.rels',rels([['rId1',relsMaster,'slideMasters/slideMaster1.xml'],...deck.map((_,i)=>[`rId${i+2}`,relsSlide,`slides/slide${i+1}.xml`])]));
const baseTree=shapeTreeStart+'</p:spTree>';
put('ppt/slideMasters/slideMaster1.xml',`<?xml version="1.0" encoding="UTF-8" standalone="yes"?><p:sldMaster xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="${relOffice}" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"><p:cSld>${baseTree}</p:cSld><p:clrMap accent1="31594C" accent2="D6B56F" accent3="5D9287" accent4="9BC7C1" accent5="C77763" accent6="F0D99F" bg1="FFFFFF" bg2="F4EFE4" tx1="171E20" tx2="57635E" hlink="0563C1" folHlink="954F72"/><p:sldLayoutIdLst><p:sldLayoutId id="1" r:id="rId1"/></p:sldLayoutIdLst><p:txStyles><p:titleStyle><a:lvl1pPr><a:defRPr sz="3200" b="1"/></a:lvl1pPr></p:titleStyle><p:bodyStyle><a:lvl1pPr><a:defRPr sz="1800"/></a:lvl1pPr></p:bodyStyle><p:otherStyle><a:defPPr><a:defRPr sz="1800"/></a:defPPr></p:otherStyle></p:txStyles></p:sldMaster>`);
put('ppt/slideMasters/_rels/slideMaster1.xml.rels',rels([['rId1',relsLayout,'../slideLayouts/slideLayout1.xml'],['rId2',relsTheme,'../theme/theme1.xml']]));
put('ppt/slideLayouts/slideLayout1.xml',`<?xml version="1.0" encoding="UTF-8" standalone="yes"?><p:sldLayout xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="${relOffice}" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" type="blank" preserve="1"><p:cSld name="Blank">${baseTree}</p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sldLayout>`);
put('ppt/slideLayouts/_rels/slideLayout1.xml.rels',rels([['rId1',relsMaster,'../slideMasters/slideMaster1.xml']]));
put('ppt/theme/theme1.xml',`<?xml version="1.0" encoding="UTF-8" standalone="yes"?><a:theme xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" name="Genius Invocation"><a:themeElements><a:clrScheme name="Genius"><a:dk1><a:srgbClr val="171E20"/></a:dk1><a:lt1><a:srgbClr val="FCFAF4"/></a:lt1><a:dk2><a:srgbClr val="182927"/></a:dk2><a:lt2><a:srgbClr val="F4EFE4"/></a:lt2><a:accent1><a:srgbClr val="31594C"/></a:accent1><a:accent2><a:srgbClr val="D6B56F"/></a:accent2><a:accent3><a:srgbClr val="5D9287"/></a:accent3><a:accent4><a:srgbClr val="9BC7C1"/></a:accent4><a:accent5><a:srgbClr val="C77763"/></a:accent5><a:accent6><a:srgbClr val="F0D99F"/></a:accent6><a:hlink><a:srgbClr val="0563C1"/></a:hlink><a:folHlink><a:srgbClr val="954F72"/></a:folHlink></a:clrScheme><a:fontScheme name="Genius Fonts"><a:majorFont><a:latin typeface="Georgia"/><a:ea typeface="Georgia"/><a:cs typeface="Georgia"/></a:majorFont><a:minorFont><a:latin typeface="Aptos"/><a:ea typeface="Aptos"/><a:cs typeface="Aptos"/></a:minorFont></a:fontScheme><a:fmtScheme name="Genius Format"><a:fillStyleLst><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:fillStyleLst><a:lnStyleLst><a:ln w="6350"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln><a:ln w="12700"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln><a:ln w="19050"><a:solidFill><a:schemeClr val="phClr"/></a:solidFill></a:ln></a:lnStyleLst><a:effectStyleLst><a:effectStyle><a:effectLst/></a:effectStyle><a:effectStyle><a:effectLst/></a:effectStyle><a:effectStyle><a:effectLst/></a:effectStyle></a:effectStyleLst><a:bgFillStyleLst><a:solidFill><a:schemeClr val="phClr"/></a:solidFill><a:solidFill><a:schemeClr val="phClr"><a:lumMod val="95000"/></a:schemeClr></a:solidFill><a:solidFill><a:schemeClr val="phClr"><a:lumMod val="90000"/></a:schemeClr></a:solidFill></a:bgFillStyleLst></a:fmtScheme></a:themeElements></a:theme>`);

for(let si=0;si<deck.length;si++){
  const s=deck[si], shapes=[]; let nextId=2; const relItems=[['rId1',relsLayout,'../slideLayouts/slideLayout1.xml']];
  for(const it of s.items){
    if(it.t==='text') shapes.push(textXml(it,nextId++));
    else if(it.t==='rect') shapes.push(rectXml(it,nextId++));
    else if(it.t==='image'){
      const bytes=await fs.readFile(path.join(root,it.src));
      const media=`image${++picIndex}.png`, rid=`rId${relItems.length+1}`;
      put(`ppt/media/${media}`,bytes); relItems.push([rid,relsImage,`../media/${media}`]);
      shapes.push(imageXml(it,nextId++,rid,path.basename(it.src)));
    }
  }
  const xml=`<?xml version="1.0" encoding="UTF-8" standalone="yes"?><p:sld xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="${relOffice}" xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main"><p:cSld><p:bg><p:bgPr><a:solidFill><a:srgbClr val="${rgb(s.bg)}"/></a:solidFill><a:effectLst/></p:bgPr></p:bg>${shapeTreeStart}${shapes.join('')}</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sld>`;
  put(`ppt/slides/slide${si+1}.xml`,xml);
  put(`ppt/slides/_rels/slide${si+1}.xml.rels`,rels(relItems));
}

// Minimal ZIP writer for the Open Packaging Convention / OOXML container.
const crcTable=new Uint32Array(256);
for(let n=0;n<256;n++){let c=n;for(let k=0;k<8;k++)c=(c&1)?(0xedb88320^(c>>>1)):(c>>>1);crcTable[n]=c>>>0;}
const crc32=buf=>{let c=0xffffffff;for(const b of buf)c=crcTable[(c^b)&255]^(c>>>8);return (c^0xffffffff)>>>0;};
const locals=[],centrals=[];let offset=0;
for(const [name,data] of entries){
  const nb=Buffer.from(name,'utf8'), packed=deflateRawSync(data), crc=crc32(data);
  const l=Buffer.alloc(30);l.writeUInt32LE(0x04034b50,0);l.writeUInt16LE(20,4);l.writeUInt16LE(0x0800,6);l.writeUInt16LE(8,8);l.writeUInt16LE(0,10);l.writeUInt16LE(0,12);l.writeUInt32LE(crc,14);l.writeUInt32LE(packed.length,18);l.writeUInt32LE(data.length,22);l.writeUInt16LE(nb.length,26);l.writeUInt16LE(0,28);
  locals.push(l,nb,packed);
  const c=Buffer.alloc(46);c.writeUInt32LE(0x02014b50,0);c.writeUInt16LE(20,4);c.writeUInt16LE(20,6);c.writeUInt16LE(0x0800,8);c.writeUInt16LE(8,10);c.writeUInt16LE(0,12);c.writeUInt16LE(0,14);c.writeUInt32LE(crc,16);c.writeUInt32LE(packed.length,20);c.writeUInt32LE(data.length,24);c.writeUInt16LE(nb.length,28);c.writeUInt16LE(0,30);c.writeUInt16LE(0,32);c.writeUInt16LE(0,34);c.writeUInt16LE(0,36);c.writeUInt32LE(0,38);c.writeUInt32LE(offset,42);
  centrals.push(c,nb); offset+=l.length+nb.length+packed.length;
}
const cd=Buffer.concat(centrals), end=Buffer.alloc(22);end.writeUInt32LE(0x06054b50,0);end.writeUInt16LE(0,4);end.writeUInt16LE(0,6);end.writeUInt16LE(entries.length,8);end.writeUInt16LE(entries.length,10);end.writeUInt32LE(cd.length,12);end.writeUInt32LE(offset,16);end.writeUInt16LE(0,20);
await fs.writeFile(outPath,Buffer.concat([...locals,cd,end]));
console.log(`Wrote ${deck.length} slides to ${outPath} (${entries.length} package entries)`);

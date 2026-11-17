const esc = value => String(value).replace(/[&<>"']/g, char => ({
  "&":"&amp;", "<":"&lt;", ">":"&gt;", '"':"&quot;", "'":"&#39;"
})[char]);
export { esc };

export function button(label, tone = "primary") {
  return `<button class="btn ${tone}" type="button"${tone === "disabled" ? " disabled" : ""}>${esc(label)}</button>`;
}

export function pill(label, tone = "neutral") {
  return `<span class="pill ${tone}">${esc(label)}</span>`;
}

export function roomCode(number = "4826", copy = false) {
  return `<span class="room-code"><span class="room-caption">房间号</span><strong>${esc(number)}</strong>${copy ? '<span class="room-copy">复制</span>' : ""}</span>`;
}

const portraits = [[774,442,151],[101,431,155],[320,428,151],[573,441,153]];
export function face(index) {
  const p = portraits[index];
  if (!p) return '<span class="avatar-photo empty-face" aria-hidden="true">＋</span>';
  const [x,y,d] = p;
  const sizing = `${941/d*100}% ${1672/d*100}%`;
  const position = `${x/(941-d)*100}% ${y/(1672-d)*100}%`;
  return `<span class="avatar-photo" style="background-size:${sizing};background-position:${position}" aria-hidden="true"></span>`;
}

export function avatar(index, name = "", status = "") {
  return `<div class="avatar">${face(index)}${name || status ? `<div class="avatar-text">${name ? `<strong>${esc(name)}</strong>` : ""}${status ? `<span class="avatar-status">${esc(status)}</span>` : ""}</div>` : ""}</div>`;
}

const suits = {Wan:"万",Tong:"筒",Tiao:"条"};
const numbers = ["", "一","二","三","四","五","六","七","八","九"];
export const tileName = (suit, rank) => `${numbers[rank]}${suits[suit]}`;
export function tile(suit, rank) {
  return `<img class="tile" src="assets/tiles/T_Tile_${suit}_${String(rank).padStart(2,"0")}.png" alt="${tileName(suit,rank)}">`;
}

export function field(label, placeholder = "", kind = "text") {
  const icon = kind === "password" ? '<span class="field-icon" aria-hidden="true">◉</span>' : "";
  return `<div class="field"><span>${esc(label)}</span><div class="input">${esc(placeholder)}${icon}</div></div>`;
}

export function section(title, html) {
  return `<section class="panel"><h2 class="section-title">${esc(title)}</h2>${html}</section>`;
}

export function tabs(labels, active) {
  return `<div class="tabs">${labels.map((label,i)=>`<span class="tab${i === active ? " active" : ""}">${esc(label)}</span>`).join("")}</div>`;
}

export function toggle(label, on) {
  return `<div class="toggle-row"><span>${esc(label)}</span><span class="switch ${on ? "on" : ""}" role="switch" aria-checked="${Boolean(on)}"><i></i><b>${on ? "开" : "关"}</b></span></div>`;
}

const rulesCatalog = [
  {id:"battle",name:"血战到底",suit:"Tong",rank:8},
  {id:"guiyang",name:"贵阳麻将",suit:"Tiao",rank:1},
  {id:"bijie",name:"毕节三门牌",suit:"Wan",rank:3}
];
export function ruleCards(active = "guiyang", catalog = rulesCatalog) {
  return `<div class="rule-cards" aria-label="玩法">${catalog.map(rule => `
    <button type="button" class="rule-card${rule.id === active ? " is-active" : ""}" aria-pressed="${rule.id === active}" data-rule-id="${esc(rule.id)}">
      ${tile(rule.suit,rule.rank)}<strong>${esc(rule.name)}</strong>
    </button>`).join("")}</div>`;
}

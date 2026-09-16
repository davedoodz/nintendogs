import "./style.css";
import { createScene } from "./scene.js";
import {
  SPECIES,
  loadState,
  saveState,
  adopt,
  currentPet,
  care,
  buy,
} from "./state.js";

const state = loadState();
const $ = (s) => document.querySelector(s);
const esc = (s) =>
  String(s).replace(
    /[&<>"']/g,
    (c) =>
      ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[
        c
      ],
  );
const portrait = (species) => `/assets/portraits/${species}.png`;
const currency = (n) => `$${n.toFixed(2)}`;
let screen = "home",
  tool = "pet",
  previewSpecies = state.pets[state.selected]?.species || "pikachu";
let modal = null,
  lastStroke = 0,
  strokes = 0,
  namingCalls = 0,
  trainingCount = 0,
  wash = 0,
  washed = false,
  bathComplete = false,
  bookPage = 0;
let walkTimer = null,
  walkStep = 0,
  walkPaused = false,
  route = [],
  activeRoute = [],
  lastFocused = null;
let ready = false,
  scene;
const audioPool = new Map();
function sound(name = "menu_select1") {
  if (!state.sound) return;
  let a = audioPool.get(name);
  if (!a) {
    a = new Audio(`/assets/sounds/${name}.wav`);
    a.volume = 0.28;
    audioPool.set(name, a);
  }
  a.currentTime = 0;
  a.play().catch(() => {});
}
function persist() {
  try {
    saveState(state);
    return true;
  } catch {
    toast(
      "Your browser could not save. Allow local storage to keep your companion.",
    );
    return false;
  }
}
function toast(text) {
  const el = $(".toast");
  el.textContent = text;
  el.classList.add("visible");
  clearTimeout(toast.timer);
  toast.timer = setTimeout(() => el.classList.remove("visible"), 3800);
}

$("#app").innerHTML = `
<main class="app-shell">
  <header class="topbar"><div class="brand"><span class="brand-name">poképals<span class="brand-dot">.</span></span><span class="brand-subtitle">a little friend, every day</span></div>
  <div class="clock"><span id="today"></span><strong id="clock-time"></strong></div>
  <div class="top-actions"><button data-action="sound" aria-label="Toggle sound" id="sound-toggle">Sound on</button><button data-action="help">How to play</button></div></header>
  <section class="game-stage" aria-label="Companion room">
    <div id="scene"></div><div class="scene-loading" role="status">Getting your room ready…</div>
    <div class="scene-label"><span id="location-label">Home</span><span id="money"></span></div>
    <nav class="sidebar" aria-label="Main menu">
      <button class="menu-button" data-action="save"><span class="menu-icon book-icon">▤</span>Save</button>
      <button class="menu-button" data-action="supplies"><span class="menu-icon supplies-icon">▣</span>Supplies List</button>
      <button class="menu-button" data-action="go-out"><span class="menu-icon walk-icon">↗</span>Go Out</button>
      <button class="menu-button" data-action="status"><span class="menu-icon status-icon">♡</span>Companion’s Status</button>
    </nav>
    <div class="scene-tools" hidden></div>
    <div class="dialogue" hidden aria-live="polite"><div class="dialogue-text"></div><div class="dialogue-actions"></div></div>
    <div class="hud-bottom"><div class="pet-tabs" aria-label="Your companions"></div><button class="call-button" data-action="call" aria-label="Call your companion"><span>♪</span><small>Come here!</small></button><div class="interaction-hint">Click to call. Drag gently to pet.</div></div>
    <div class="toast" role="status"></div>
  </section>
  <footer class="credits"><span>A desktop care-game study · Inspired by Nintendogs</span><button data-action="credits">Asset credits</button><span id="save-status">Saved on this device</span></footer>
</main><div id="modal-root"></div>`;

function updateClock() {
  const d = new Date();
  $("#today").textContent = d.toLocaleDateString(undefined, {
    month: "short",
    day: "numeric",
    year: "numeric",
  });
  $("#clock-time").textContent = d.toLocaleTimeString(undefined, {
    hour: "2-digit",
    minute: "2-digit",
  });
}
updateClock();
setInterval(updateClock, 30000);
function hud() {
  $("#money").textContent = currency(state.money);
  $("#sound-toggle").textContent = state.sound ? "Sound on" : "Sound off";
  $(".pet-tabs").innerHTML = state.pets
    .map(
      (p, i) =>
        `<button class="pet-tab ${i === state.selected ? "active" : ""}" data-action="select-pet" data-index="${i}" aria-pressed="${i === state.selected}"><img src="${portrait(p.species)}" alt="${SPECIES[p.species].name}"><span>${esc(p.name || SPECIES[p.species].name)}</span></button>`,
    )
    .join("");
  $(".sidebar").hidden =
    !state.started || state.stage !== "home" || screen !== "home";
  $(".hud-bottom").hidden = !state.started;
}
function dialogue(text, buttons = []) {
  $(".dialogue").hidden = false;
  $(".dialogue-text").textContent = text;
  $(".dialogue-actions").innerHTML = buttons
    .map(
      ([label, action]) =>
        `<button class="primary-button" data-action="${action}">${esc(label)} <span aria-hidden="true">›</span></button>`,
    )
    .join("");
}
function hideDialogue() {
  $(".dialogue").hidden = true;
}
function closeModal() {
  $("#modal-root").innerHTML = "";
  modal = null;
  lastFocused?.focus();
}
function panel(title, content, { wide = false, back = "close" } = {}) {
  lastFocused = document.activeElement;
  modal = title;
  $("#modal-root").innerHTML =
    `<div class="overlay"><section class="panel ${wide ? "panel-wide" : ""}" role="dialog" aria-modal="true" aria-labelledby="panel-title"><header class="panel-header"><button class="close-button" data-action="${back}" aria-label="Back">↶</button><h1 id="panel-title">${esc(title)}</h1><span class="panel-money">${currency(state.money)}</span></header><div class="panel-content">${content}</div></section></div>`;
  (
    $("#modal-root input") ||
    $("#modal-root .primary-button") ||
    $("#modal-root .close-button")
  )?.focus();
}
function setLocation(mode, label) {
  screen = mode;
  scene?.setMode(mode);
  $("#location-label").textContent = label;
  hud();
}
function selectTool(value) {
  tool = value;
  scene?.setTool(value);
  document
    .querySelectorAll("[data-tool]")
    .forEach((b) => b.classList.toggle("active", b.dataset.tool === tool));
}
function home() {
  closeModal();
  setLocation("home", "Home");
  selectTool("pet");
  $(".scene-tools").hidden = true;
  hideDialogue();
  hud();
  const pet = currentPet(state);
  if (pet && previewSpecies !== pet.species) {
    previewSpecies = pet.species;
    scene?.setSpecies(pet.species).catch(assetError);
  }
}
function welcome() {
  scene?.setMode("kennel");
  $("#location-label").textContent = "Welcome";
  panel(
    "Welcome to Poképals",
    `<div class="welcome-card"><span class="eyebrow">A familiar kind of friendship</span><h2>Someone little.<br>Something wonderful.</h2><div class="starter-portraits">${Object.keys(
      SPECIES,
    )
      .map((s) => `<img src="${portrait(s)}" alt="${SPECIES[s].name}">`)
      .join(
        "",
      )}</div><p>Meet your companion, learn their name, and make a little home together.</p><button class="primary-button" data-action="kennel">Meet the companions ›</button><p class="small-note">Pikachu · Mudkip · Charmander<br>Mouse & keyboard · Progress saved on this device</p></div>`,
    { back: "help" },
  );
}
function kennel() {
  closeModal();
  setLocation("kennel", "Kennel");
  hideDialogue();
  panel(
    "Kennel",
    `<p class="panel-intro">Which companion would you like to meet?</p><div class="choice-grid">${Object.entries(
      SPECIES,
    )
      .map(
        ([id, s]) =>
          `<button class="choice-card ${previewSpecies === id ? "selected" : ""}" data-action="preview" data-species="${id}" style="--pet-color:${s.color}"><span class="dex-number">No. ${s.number}</span><img src="${portrait(id)}" alt="${s.name}"><strong>${s.name}</strong><span class="type-badge">${s.type}</span></button>`,
      )
      .join(
        "",
      )}</div><div class="kennel-detail"><h2>${SPECIES[previewSpecies].name}</h2><p>${SPECIES[previewSpecies].description}</p><span class="price">${currency(SPECIES[previewSpecies].price)}</span></div><div class="panel-actions"><button class="secondary-button" data-action="${state.started ? "home" : "welcome"}">Back</button><button class="primary-button" data-action="adopt-confirm" ${state.pets.length >= 3 || state.money < SPECIES[previewSpecies].price ? "disabled" : ""}>Choose ${SPECIES[previewSpecies].name} ›</button></div>${state.pets.length >= 3 ? "<p>Your home is full. All three friends are already here.</p>" : ""}`,
  );
  scene?.setSpecies(previewSpecies).catch(assetError);
}
function confirmAdopt() {
  panel(
    "A new friend",
    `<img class="confirmation-portrait" src="${portrait(previewSpecies)}" alt="${SPECIES[previewSpecies].name}"><h2>Bring ${SPECIES[previewSpecies].name} home?</h2><p>This companion costs ${currency(SPECIES[previewSpecies].price)}. Take your time — this is the start of a friendship.</p><div class="panel-actions"><button class="secondary-button" data-action="kennel">Keep looking</button><button class="primary-button" data-action="adopt">Bring them home</button></div>`,
  );
}
function bringHome() {
  if (!adopt(state, previewSpecies, ""))
    return toast("There is not enough money or space at home.");
  strokes = 0;
  closeModal();
  setLocation("home", "Home");
  selectTool("pet");
  persist();
  dialogue(
    "Your new companion seems a little nervous. Click “Come here!”, then gently stroke them to help them settle in.",
    [
      ["Come here!", "call"],
      ["Pet gently", "pet-gently"],
    ],
  );
}
function askName() {
  state.stage = "name";
  persist();
  panel(
    "A name for your companion",
    `<img class="confirmation-portrait" src="${portrait(currentPet(state).species)}" alt="Your companion"><h2>What will you call your new friend?</h2><p>On desktop, type their name and call it using the button. No microphone needed.</p><form id="name-form"><label for="pet-name">Companion’s name</label><input id="pet-name" name="name" maxlength="16" minlength="1" autocomplete="off" placeholder="e.g. Sunny" required><button class="primary-button" type="submit">Confirm name ›</button></form>`,
  );
}
function callName() {
  namingCalls++;
  scene?.react("call");
  sound("playerspeak");
  if (namingCalls >= 3) {
    state.stage = "training";
    persist();
    hud();
    dialogue(
      `${currentPet(state).name} knows their name! Now let’s teach your first trick. Gently drag downward over their head to ask them to sit.`,
      [["Show me how", "train"]],
    );
  } else
    dialogue(
      `“${currentPet(state).name}!” Your companion is listening. Call their name ${3 - namingCalls} more ${3 - namingCalls === 1 ? "time" : "times"}.`,
      [["Call their name", "call-name"]],
    );
}
function train() {
  if ($("#location-label").textContent !== "Training") trainingCount = 0;
  closeModal();
  setLocation("home", "Training");
  selectTool("pet");
  dialogue(
    `Let’s teach ${currentPet(state).name} to sit. Drag down over their head, or press S. ${trainingCount} of 3 completed. Then give the trick a name.`,
    [["Back to home", "finish-tutorial"]],
  );
}
function nameTrick() {
  const p = currentPet(state);
  panel(
    "A new trick!",
    `<h2>Three good sits!</h2><p>Give the trick a command so ${esc(p.name)} can remember it.</p><form id="trick-form"><label for="trick-name">Command</label><input id="trick-name" maxlength="20" value="Sit down" required><button class="primary-button" type="submit">Remember this trick</button></form>`,
  );
}
function trickGesture(action) {
  if (!state.started || modal || screen === "walk") return;
  if (screen === "bath" && bathComplete && ["wash", "rinse"].includes(action))
    return;
  const p = currentPet(state);
  if (action === "sit") {
    scene?.react("sit");
    sound("dog_shine");
    trainingCount++;
    if (
      state.stage === "training" ||
      $("#location-label").textContent === "Training"
    ) {
      if (trainingCount >= 3) nameTrick();
      else
        dialogue(
          `They sat! ${trainingCount} of 3. Praise your companion, then try the downward gesture again.`,
        );
    } else toast(`${p.name} sat down. Good friend!`);
  } else if (action === "wash" && screen === "bath" && !washed) {
    wash = Math.min(100, wash + 4);
    updateWash();
    if (wash >= 100) {
      washed = true;
      updateWash();
      dialogue(
        "All lathered up! Choose the shower and rinse away every last bubble.",
      );
    }
  } else if (action === "rinse" && screen === "bath" && washed) {
    wash = Math.max(0, wash - 5);
    updateWash();
    if (wash === 0) {
      bathComplete = true;
      p.cleanliness = 100;
      p.affection = Math.min(100, p.affection + 10);
      scene?.react("shake");
      sound("dog_shine");
      persist();
      dialogue("Sparkling clean! Your companion feels much better.", [
        ["Return home", "home"],
      ]);
    }
  } else if (["jump", "spin"].includes(action)) {
    scene?.react(action);
    toast(`${p.name} ${action === "jump" ? "jumped" : "spun around"}!`);
  } else if (action === "throw") {
    p.affection = Math.min(100, p.affection + 2);
    persist();
  }
}
function petStroke() {
  if (!state.started || modal || !ready) return;
  const now = performance.now();
  if (now - lastStroke < 180) return;
  lastStroke = now;
  strokes++;
  const p = currentPet(state);
  p.affection = Math.min(100, p.affection + 1);
  if (tool === "brush") p.cleanliness = Math.min(100, p.cleanliness + 2);
  if (strokes % 8 === 0) {
    sound("menu_praise");
    scene?.react("happy");
  }
  if (state.stage === "settle" && strokes >= 8) {
    scene?.react("happy");
    dialogue("Your companion is feeling at home. Now they need a name!", [
      ["Give them a name", "name"],
    ]);
  }
  if (strokes % 5 === 0) persist();
}
const categories = {
  Sports: [["disc", "Flying Disc", "A flying disc for practice and contests."]],
  Toys: [
    [
      "ball",
      "Tennis Ball",
      "Click the floor to throw. Your friend will fetch it.",
    ],
    [
      "bubbles",
      "Bubble Blower",
      "Click in the room to blow a stream of bubbles.",
    ],
  ],
  Care: [
    ["water", "Water Bottle", "Fresh water for a thirsty companion."],
    ["food", "Dry Food", "A filling meal for your little friend."],
    [
      "shampoo",
      "Short-Hair Shampoo",
      "Lather up with a sponge, then rinse clean.",
    ],
    ["brush", "Rubber Brush", "A little grooming goes a long way."],
    ["book", "Care Book", "Learn how to care for your companion."],
  ],
};
function supplies(category) {
  if (!category)
    return panel(
      "Supplies",
      `<p class="panel-intro">Everything for a happy little companion.</p><div class="inventory-grid">${Object.keys(
        categories,
      )
        .map(
          (c, i) =>
            `<button class="item-card" data-action="category" data-category="${c}"><span class="item-symbol">${["◉", "◇", "▤"][i]}</span><strong>${c}</strong></button>`,
        )
        .join("")}</div>`,
      { back: "home" },
    );
  panel(
    `Supplies · ${category}`,
    `<div class="supply-list">${categories[category].map(([id, name, desc]) => `<button class="supply-row item-card" data-action="use" data-item="${id}" ${["food", "water", "shampoo", "disc"].includes(id) && !state.inventory[id] ? "disabled" : ""}><span class="item-symbol">${{ water: "♧", food: "▰", shampoo: "▥", brush: "▦", book: "▤", ball: "◉", disc: "◎", bubbles: "◌" }[id]}</span><span><strong>${name}</strong><small>${desc}</small></span><span class="item-count">×${["brush", "book", "bubbles"].includes(id) ? "1" : state.inventory[id] || 0}</span><span>›</span></button>`).join("")}</div>`,
    { back: "supplies" },
  );
}
function useItem(item) {
  if (item === "book") return book();
  if (item === "shampoo") return bath();
  if (item === "food" || item === "water") {
    if (!care(state, item))
      return toast("You have run out. Visit the Pet Supply shop.");
    home();
    selectTool(item);
    scene?.react(item === "food" ? "eat" : "drink");
    sound("activity_accept");
    persist();
    dialogue(
      `${currentPet(state).name} is enjoying ${item === "food" ? "a meal" : "some fresh water"}.`,
      [["Put away", "home"]],
    );
    return;
  }
  home();
  selectTool(item);
  $(".scene-tools").hidden = false;
  $(".scene-tools").innerHTML =
    '<button class="secondary-button" data-action="home">Put away ↶</button>';
  dialogue(
    {
      ball: "Click the floor to throw the tennis ball. Your companion will fetch it!",
      disc: "Click to throw the disc. Try a long throw!",
      brush: "Drag the brush gently over your companion to groom them.",
      bubbles:
        "Click in the room to blow bubbles. Watch your friend follow them!",
    }[item],
  );
}
function updateWash() {
  const fill = $("#wash-fill");
  if (fill) fill.style.width = `${wash}%`;
  const label = $("#wash-label");
  if (label) label.textContent = washed ? "Rinse clean" : "Lather up";
}
function bath() {
  if (!state.inventory.shampoo)
    return toast("Buy shampoo at the Pet Supply shop first.");
  state.inventory.shampoo--;
  wash = 0;
  washed = false;
  bathComplete = false;
  closeModal();
  setLocation("bath", "Bath time");
  selectTool("sponge");
  persist();
  $(".scene-tools").hidden = false;
  $(".scene-tools").innerHTML =
    `<button class="secondary-button active" data-action="tool" data-tool="sponge">1 · Sponge</button><button class="secondary-button" data-action="tool" data-tool="shower">2 · Shower</button><div class="wash-meter"><span id="wash-label">Lather up</span><div class="progress-track"><span id="wash-fill" class="progress-fill" style="width:0%"></span></div></div><button class="secondary-button" data-action="home">Finish ↶</button>`;
  dialogue(
    "Drag the sponge over your companion to work up a lather. Then use the shower to rinse away the suds.",
  );
}
function status() {
  const p = currentPet(state);
  if (!p) return;
  const rows = [
    ["Hunger", p.hunger, p.hunger > 75 ? "Full" : "Hungry"],
    ["Thirst", p.thirst, p.thirst > 75 ? "Quenched" : "Thirsty"],
    [
      "Coat",
      p.cleanliness,
      p.cleanliness > 85 ? "Beautiful" : p.cleanliness > 55 ? "Clean" : "Dirty",
    ],
    [
      "Friendship",
      p.affection,
      p.affection > 65 ? "Best friends" : "Getting to know you",
    ],
  ];
  panel(
    "Companion’s Status",
    `<div class="status-heading"><img src="${portrait(p.species)}" alt="${SPECIES[p.species].name}"><div><h2>${esc(p.name)}</h2><span>${SPECIES[p.species].name} · ${SPECIES[p.species].type}</span></div></div><div class="stat-grid">${rows.map(([label, val, desc]) => `<div class="stat-row"><strong>${label}</strong><span>${desc}</span><div class="progress-track"><span class="progress-fill" style="width:${val}%"></span></div></div>`).join("")}</div><h3>Trick List</h3><p>${p.tricks.length ? p.tricks.map(esc).join(" · ") : "No tricks learned yet."}</p><div class="panel-actions"><button class="secondary-button" data-action="home">Home</button><button class="primary-button" data-action="train">Teach a trick</button></div>`,
    { back: "home" },
  );
}
const bookContent = [
  [
    "Caring for Your Companion",
    "Before you can truly care for your companion, you must first get to know them. On the home screen, choose Companion’s Status to check hunger, thirst and cleanliness. Pet gently and spend time together.",
  ],
  [
    "Food and Water",
    "Select Supplies List, then Care. Offer Dry Food when your companion is hungry and a Water Bottle when they are thirsty. You can buy more from Go Out → Shopping → Pet Supply.",
  ],
  [
    "Shampoo",
    "To bathe your companion, first use the sponge to work up a lather. Next, use the shower to rinse the suds away. Once all the dirt has been washed away, your companion will be sparkling clean!",
  ],
  [
    "Brushing",
    "Choose the Rubber Brush from your Care supplies. Drag over your companion with slow, gentle strokes. A clean coat makes a happy friend.",
  ],
  [
    "Teaching Tricks",
    "Call your companion close. Drag downward over their head to sit. After three successful attempts, give the trick a name. You can also press S to sit, J to jump, and R to spin.",
  ],
  [
    "Taking a Walk",
    "Your walk ends when you return home. Draw a route along the streets, starting and ending at the house. Along the way, your companion may find a present or meet another friend.",
  ],
];
function book() {
  const [title, text] = bookContent[bookPage];
  const [column, row] = [
    [0, 0],
    [0, 1],
    [1, 1],
    [0, 2],
    [0, 2],
    [0, 3],
  ][bookPage];
  panel(
    "Care",
    `<div class="book-pages"><div class="book-page book-illustration" style="--book-x:${column};--book-y:${row}"><div class="book-crop"></div></div><div class="book-page"><h2>${title}</h2><p>${text}</p><span class="page-number">${bookPage + 1} / ${bookContent.length}</span></div></div><div class="panel-actions"><button class="secondary-button" data-action="book-prev" ${bookPage === 0 ? "disabled" : ""}>‹ Previous</button><button class="primary-button" data-action="book-next" ${bookPage === bookContent.length - 1 ? "disabled" : ""}>Next ›</button></div>`,
    { wide: true, back: "supplies" },
  );
}
function goOut() {
  panel(
    "Go Out",
    `<div class="inventory-grid"><button class="item-card" data-action="shopping"><span class="item-symbol">▥</span><strong>Shopping</strong><small>Supplies and new friends</small></button><button class="item-card" data-action="map"><span class="item-symbol">↝</span><strong>Walk</strong><small>A little adventure together</small></button><button class="item-card" data-action="contests"><span class="item-symbol">♜</span><strong>Contests</strong><small>Check entry requirements</small></button></div>`,
    { back: "home" },
  );
}
function shopping() {
  panel(
    "Shopping",
    `<div class="inventory-grid"><button class="item-card" data-action="shop"><span class="item-symbol">▥</span><strong>Pet Supply</strong><small>Food, water and care</small></button><button class="item-card" data-action="kennel"><span class="item-symbol">⌂</span><strong>Kennel</strong><small>Meet another companion</small></button><button class="item-card" data-action="secondhand"><span class="item-symbol">⇄</span><strong>Secondhand Shop</strong><small>Sell spare supplies</small></button></div>`,
    { back: "go-out" },
  );
}
const products = [
  ["food", "Dry Food", 20],
  ["water", "Water Bottle", 10],
  ["shampoo", "Short-Hair Shampoo", 30],
  ["disc", "Flying Disc", 50],
];
function shop() {
  panel(
    "Pet Supply",
    `<p class="panel-intro">What would you like today?</p><div class="supply-list">${products.map(([id, name, price]) => `<button class="item-card supply-row" data-action="buy" data-item="${id}" ${state.money < price ? "disabled" : ""}><span><strong>${name}</strong><small>You have ${state.inventory[id] || 0}</small></span><span>${currency(price)}</span><span>Buy ›</span></button>`).join("")}</div>`,
    { back: "shopping" },
  );
}
function secondhand() {
  panel(
    "Secondhand Shop",
    `<p>Sell one spare supply for half its purchase price.</p><div class="supply-list">${products.map(([id, name, price]) => `<button class="item-card supply-row" data-action="sell" data-item="${id}" ${!state.inventory[id] ? "disabled" : ""}><strong>${name} ×${state.inventory[id] || 0}</strong><span>Sell · ${currency(price / 2)}</span></button>`).join("")}</div>`,
    { back: "shopping" },
  );
}
function contests() {
  panel(
    "Contests",
    `<p class="panel-intro">Before entering, make sure your companion is ready.</p><div class="supply-list"><button class="item-card" data-action="contest-check" data-contest="Disc Competition"><strong>Disc Competition</strong><small>Requires a Flying Disc</small></button><button class="item-card" data-action="contest-check" data-contest="Agility Trial"><strong>Agility Trial</strong><small>Practice together at the park</small></button><button class="item-card" data-action="contest-check" data-contest="Obedience Trial"><strong>Obedience Trial</strong><small>Requires a learned command</small></button></div>`,
    { back: "go-out" },
  );
}
function contestCheck(name) {
  const eligible =
    name === "Disc Competition"
      ? state.inventory.disc > 0
      : name === "Obedience Trial"
        ? currentPet(state).tricks.length > 0
        : state.walks > 0;
  panel(
    name,
    `<h2>${eligible ? "Ready to practice!" : "Not quite ready yet"}</h2><p>${eligible ? "Take your companion to the practice field." : name === "Disc Competition" ? "You can’t enter this competition if you don’t have a flying disc!" : name === "Obedience Trial" ? "Teach your companion a trick before entering." : "Take your companion for a walk first."}</p><button class="primary-button" data-action="${eligible ? "practice" : "contests"}" data-contest="${esc(name)}">${eligible ? "Practice together" : "Back to contests"}</button>`,
    { back: "contests" },
  );
}

// Route nodes follow a street loop over the original walk-map sprite.
const mapPoints = [
  [24, 79],
  [30, 79],
  [30, 93],
  [78, 93],
  [78, 70],
  [46, 70],
  [30, 70],
];
const mapLinks = [[1], [0, 2, 6], [1, 3], [2, 4], [3, 5], [4, 6], [5, 1]];
function map() {
  route = [0];
  panel(
    "Walk",
    `<p class="panel-intro">Draw a route that starts and ends at your house. Follow the street markers, then return home.</p><div class="walk-map" id="route-map"><div class="map-art"></div><svg class="walk-route" viewBox="0 0 100 100" preserveAspectRatio="none"><polyline id="route-line" points=""/></svg>${mapPoints.map(([x, y], i) => `<button class="map-node ${i === 0 ? "house-node" : ""}" style="left:${x}%;top:${y}%" data-action="route-node" data-node="${i}" aria-label="${i === 0 ? "Home" : `Street ${i}`}">${i === 0 ? "⌂" : i === 3 ? "?" : i === 6 ? "♡" : "·"}</button>`).join("")}</div><p id="route-status" class="route-status" aria-live="polite">Start at home. Select an adjacent street marker.</p><div class="panel-actions"><button class="secondary-button" data-action="route-reset">Start over</button><button class="primary-button" id="walk-start" data-action="start-walk" disabled>Go for a walk ›</button></div>`,
    { back: "go-out" },
  );
}
function addRoute(i) {
  if (route.length > 1 && route.at(-1) === 0) return;
  const last = route.at(-1);
  if (i === last) return;
  if (!mapLinks[last]?.includes(i))
    return toast("Follow the connected street markers.");
  if (route.length >= 12)
    return toast(
      "That is far enough for today. Start over and plan a shorter route.",
    );
  if (i === 0 && route.length < 4)
    return toast("Explore a little farther before heading home.");
  route.push(i);
  sound("menu_shift");
  $("#route-line").setAttribute(
    "points",
    route.map((n) => mapPoints[n].join(",")).join(" "),
  );
  const closed = route.length > 3 && i === 0;
  $("#walk-start").disabled = !closed;
  $("#route-status").textContent = closed
    ? "Your route is ready. Time for a little adventure!"
    : `${route.length - 1} streets planned. Finish at the house.`;
}
function startWalk() {
  if (route.length < 4 || route.at(-1) !== 0) return;
  activeRoute = [...route];
  walkStep = 0;
  walkPaused = false;
  closeModal();
  setLocation("walk", "Walk");
  selectTool("pet");
  hideDialogue();
  $(".scene-tools").hidden = false;
  $(".scene-tools").innerHTML =
    `<div class="walk-progress"><strong>Around the neighborhood</strong><span id="walk-progress-label"></span><div class="walk-map mini-map" aria-label="Your walking route"><div class="map-art"></div><svg class="walk-route" viewBox="0 0 100 100" preserveAspectRatio="none"><polyline points="${activeRoute.map((n) => mapPoints[n].join(",")).join(" ")}"/><circle id="walk-marker" cx="${mapPoints[0][0]}" cy="${mapPoints[0][1]}" r="3" fill="#ed8850" stroke="white" stroke-width="1"/></svg></div></div><button class="secondary-button" data-action="return-walk">Return home ↶</button>`;
  dialogue(
    "Hold a little curiosity close. Your companion is exploring the neighborhood.",
  );
  advanceWalk();
  walkTimer = setInterval(advanceWalk, 4200);
}
function advanceWalk() {
  if (walkPaused) return;
  walkStep++;
  $("#walk-progress-label").textContent =
    `${Math.min(walkStep, activeRoute.length)} / ${activeRoute.length} streets`;
  const point =
    mapPoints[activeRoute[Math.min(walkStep - 1, activeRoute.length - 1)]];
  $("#walk-marker")?.setAttribute("cx", point[0]);
  $("#walk-marker")?.setAttribute("cy", point[1]);
  if (walkStep === Math.max(2, Math.floor(activeRoute.length * 0.35))) {
    walkPaused = true;
    scene?.react("gift");
    dialogue(
      `${currentPet(state).name} found something! They’re bringing it to you.`,
      [["Open present", "open-gift"]],
    );
  } else if (walkStep === Math.max(3, Math.floor(activeRoute.length * 0.7))) {
    walkPaused = true;
    scene?.react("greet");
    dialogue(
      "A neighbor and their companion stopped to say hello. A gentle greeting makes a new friend.",
      [["Say hello", "greet"]],
    );
  } else if (walkStep >= activeRoute.length) finishWalk();
}
function finishWalk() {
  clearInterval(walkTimer);
  walkTimer = null;
  state.walks++;
  state.money += 100;
  const p = currentPet(state);
  p.hunger = Math.max(0, p.hunger - 18);
  p.thirst = Math.max(0, p.thirst - 20);
  p.cleanliness = Math.max(0, p.cleanliness - 15);
  p.affection = Math.min(100, p.affection + 12);
  persist();
  home();
  dialogue(
    "You’ve returned from your walk together. It was pretty tiring — offer some food and water. You earned $100.00 trainer points.",
    [["Welcome home", "home"]],
  );
}
function resumeTutorial() {
  if (!state.started) return welcome();
  if (state.stage === "settle") {
    closeModal();
    dialogue(
      "Your companion is still settling in. Call them close and gently stroke them.",
      [
        ["Come here!", "call"],
        ["Pet gently", "pet-gently"],
      ],
    );
  } else if (state.stage === "name") askName();
  else if (state.stage === "calls") {
    closeModal();
    dialogue(`Help ${currentPet(state).name} learn their name.`, [
      ["Call their name", "call-name"],
    ]);
  } else if (state.stage === "training") {
    if (trainingCount >= 3) nameTrick();
    else train();
  } else home();
}
function assetError(error) {
  $(".scene-loading").hidden = false;
  $(".scene-loading").textContent =
    `Could not load the 3D companion. ${error?.message || "Please reload to retry."}`;
}

const actions = {
  welcome,
  kennel,
  preview: async (b) => {
    previewSpecies = b.dataset.species;
    kennel();
  },
  "adopt-confirm": confirmAdopt,
  adopt: bringHome,
  name: askName,
  "call-name": callName,
  train,
  "finish-tutorial": () => {
    state.stage = "home";
    persist();
    home();
  },
  home,
  close: () => {
    if (!state.started) welcome();
    else if (state.stage !== "home") resumeTutorial();
    else if (screen === "kennel") home();
    else closeModal();
  },
  call: () => {
    if (state.stage === "calls") callName();
    else {
      scene?.react("call");
      sound("playerspeak");
      toast(`${currentPet(state)?.name || "Your companion"}, come here!`);
    }
  },
  "pet-gently": () => {
    scene?.react("happy");
    petStroke();
  },
  supplies: () => supplies(),
  category: (b) => supplies(b.dataset.category),
  use: (b) => useItem(b.dataset.item),
  tool: (b) => selectTool(b.dataset.tool),
  status,
  book,
  "book-prev": () => {
    bookPage = Math.max(0, bookPage - 1);
    book();
  },
  "book-next": () => {
    bookPage = Math.min(bookContent.length - 1, bookPage + 1);
    book();
  },
  "go-out": goOut,
  shopping,
  shop,
  secondhand,
  buy: (b) => {
    const [id, name, price] = products.find((p) => p[0] === b.dataset.item);
    if (buy(state, id, price)) {
      persist();
      sound("activity_accept");
      shop();
      toast(`Bought ${name}.`);
      hud();
    }
  },
  sell: (b) => {
    const [id, name, price] = products.find((p) => p[0] === b.dataset.item);
    if (state.inventory[id] > 0) {
      state.inventory[id]--;
      state.money += price / 2;
      persist();
      secondhand();
      hud();
      toast(`Sold ${name}.`);
    }
  },
  contests,
  "contest-check": (b) => contestCheck(b.dataset.contest),
  practice: (b) => {
    home();
    setLocation("park", "Practice field");
    selectTool(b.dataset.contest === "Disc Competition" ? "disc" : "pet");
    dialogue(
      "A little practice makes a big difference. Press S to sit, J to jump, or click to throw a disc.",
      [["Return home", "home"]],
    );
  },
  map,
  "route-reset": map,
  "route-node": (b) => addRoute(Number(b.dataset.node)),
  "start-walk": startWalk,
  "return-walk": () => {
    clearInterval(walkTimer);
    walkTimer = null;
    home();
    toast("You headed home early. Try the full route next time.");
  },
  "open-gift": () => {
    state.inventory.ball++;
    persist();
    sound("dog_shine");
    dialogue(
      "You found a Tennis Ball! It has been added to your Supplies List.",
      [["Keep walking", "walk-continue"]],
    );
  },
  greet: () => {
    currentPet(state).affection = Math.min(
      100,
      currentPet(state).affection + 5,
    );
    persist();
    dialogue("Your companions got along nicely. Time to head back.", [
      ["Keep walking", "walk-continue"],
    ]);
  },
  "walk-continue": () => {
    walkPaused = false;
    scene?.react("walk");
    hideDialogue();
  },
  save: () =>
    panel(
      "Save",
      `<h2>Save your efforts up to this point?</h2><p>Your companions, supplies, tricks and progress will be stored on this browser.</p><div class="panel-actions"><button class="secondary-button" data-action="home">No</button><button class="primary-button" data-action="save-confirm">Yes</button></div>`,
    ),
  "save-confirm": () => {
    if (persist()) {
      sound("save");
      home();
      $("#save-status").textContent = "Saved just now";
      toast("Your progress has been saved.");
    }
  },
  "select-pet": (b) => {
    if (state.stage !== "home" || screen === "walk") return;
    state.selected = Number(b.dataset.index);
    home();
    persist();
  },
  sound: () => {
    state.sound = !state.sound;
    persist();
    hud();
  },
  help: () =>
    panel(
      "How to play",
      `<h2>A little time together</h2><p><strong>Pet:</strong> hold and drag gently over your companion, not the floor.</p><p><strong>Call:</strong> click the gold call button. <strong>Train:</strong> drag down to sit, up to jump, sideways to spin. Keyboard: S / J / R.</p><p><strong>Care:</strong> Supplies List → Care for food, water, shampoo, brush and book.</p><p><strong>Play:</strong> select a toy, then click inside the room.</p><p><strong>Walk:</strong> Go Out → Walk. Connect neighboring markers and finish at the house.</p><p><strong>Navigate:</strong> Tab and Enter work on every menu. Escape closes a panel.</p><button class="primary-button" data-action="${state.started ? "close" : "welcome"}">Got it</button>`,
    ),
  credits: () =>
    panel(
      "About this study",
      `<h2>Poképals</h2><p>A local desktop interaction study combining Nintendogs care flows with Pikachu, Mudkip and Charmander.</p><p>Original models: PokéPark Wii, preserved by The Models Resource. Original Nintendogs UI sounds, care-book sprites, walk maps and bathroom textures: The Spriters Resource network. Portrait sprites: PokeAPI sprites collection.</p><p>Pokémon and Nintendogs belong to their respective rights holders. These extracted assets are not open-source or licensed for redistribution. This is an unofficial local study, not an official Nintendo product.</p><p>Character reactions are new procedural animations, not the games’ original animation clips. Voice/stylus inputs are adapted to buttons, typing and pointer gestures.</p><button class="primary-button" data-action="close">Back</button>`,
    ),
};
document.addEventListener("click", (e) => {
  const b = e.target.closest("[data-action]");
  if (!b || b.disabled) return;
  const action = actions[b.dataset.action];
  if (action) {
    if (b.dataset.action !== "sound") sound();
    action(b);
  }
});
document.addEventListener("submit", (e) => {
  if (e.target.id === "name-form") {
    e.preventDefault();
    const name = $("#pet-name").value.trim();
    if (!name) return;
    currentPet(state).name = name;
    state.stage = "calls";
    namingCalls = 0;
    persist();
    closeModal();
    hud();
    dialogue(
      `Your companion’s name is now ${name}! Call it clearly so they can learn it.`,
      [["Call their name", "call-name"]],
    );
  }
  if (e.target.id === "trick-form") {
    e.preventDefault();
    const command = $("#trick-name").value.trim();
    if (!command) return;
    const p = currentPet(state);
    if (!p.tricks.includes(command)) p.tricks.push(command);
    state.stage = "home";
    persist();
    home();
    sound("dog_shine");
    dialogue(
      `${p.name} learned “${command}”! You can now play, care for your friend, or go out together.`,
      [["Let’s play!", "home"]],
    );
  }
});
document.addEventListener("keydown", (e) => {
  if (e.key === "Escape" && modal) {
    e.preventDefault();
    actions.close();
    return;
  }
  if (e.key === "Tab" && modal) {
    const els = [
      ...$("#modal-root").querySelectorAll(
        "button:not([disabled]),input,a[href]",
      ),
    ];
    if (!els.length) return;
    const first = els[0],
      last = els.at(-1);
    if (e.shiftKey && document.activeElement === first) {
      e.preventDefault();
      last.focus();
    } else if (!e.shiftKey && document.activeElement === last) {
      e.preventDefault();
      first.focus();
    }
    return;
  }
  if (
    modal ||
    ["INPUT", "TEXTAREA"].includes(e.target.tagName) ||
    !state.started
  )
    return;
  const action = { s: "sit", j: "jump", r: "spin" }[e.key.toLowerCase()];
  if (action) {
    e.preventDefault();
    trickGesture(action);
  }
  if (screen === "bath" && e.key === "1") selectTool("sponge");
  if (screen === "bath" && e.key === "2") selectTool("shower");
});
document.addEventListener("pointerover", (e) => {
  if (e.buttons === 1 && e.target.matches(".map-node"))
    addRoute(Number(e.target.dataset.node));
});
try {
  scene = createScene($("#scene"), {
    onPet: petStroke,
    onGesture: trickGesture,
    onReady: () => {
      ready = true;
      $(".scene-loading").hidden = true;
    },
    onError: assetError,
  });
  await scene.setSpecies(previewSpecies);
  ready = true;
  $(".scene-loading").hidden = true;
  hud();
  resumeTutorial();
} catch (error) {
  assetError(error);
  hud();
  resumeTutorial();
}
window.addEventListener("pagehide", (e) => {
  if (e.persisted) return;
  clearInterval(walkTimer);
  scene?.dispose();
});

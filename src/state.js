export const SPECIES = {
  pikachu: {
    name: "Pikachu",
    type: "Electric",
    number: "025",
    color: "#eac749",
    description:
      "An energetic little companion. Curious, affectionate, and always ready to play.",
    price: 500,
  },
  mudkip: {
    name: "Mudkip",
    type: "Water",
    number: "258",
    color: "#7dc0cb",
    description:
      "A gentle companion with a playful side. Loves a good splash and a quiet afternoon.",
    price: 500,
  },
  charmander: {
    name: "Charmander",
    type: "Fire",
    number: "004",
    color: "#df9462",
    description:
      "A warm-hearted companion. A little shy at first, but a loyal friend once you bond.",
    price: 500,
  },
};
const KEY = "pokepals-save-v1";
export function freshState() {
  return {
    version: 1,
    started: false,
    stage: "choose",
    pets: [],
    selected: 0,
    money: 1000,
    inventory: { food: 5, water: 5, shampoo: 3, ball: 1, disc: 0 },
    walks: 0,
    contests: 0,
    savedAt: null,
    sound: true,
  };
}
export function loadState() {
  try {
    const s = JSON.parse(localStorage.getItem(KEY));
    if (
      s?.version === 1 &&
      Array.isArray(s.pets) &&
      s.pets.length <= 3 &&
      s.pets.every((p) => SPECIES[p.species] && typeof p.name === "string") &&
      s.inventory &&
      Number.isFinite(s.money)
    )
      return {
        ...freshState(),
        ...s,
        selected: Math.min(
          Math.max(0, s.selected || 0),
          Math.max(0, s.pets.length - 1),
        ),
      };
  } catch {}
  return freshState();
}
export function saveState(state) {
  state.savedAt = Date.now();
  localStorage.setItem(KEY, JSON.stringify(state));
}
export function adopt(state, species, name) {
  if (
    !SPECIES[species] ||
    state.pets.length >= 3 ||
    state.money < SPECIES[species].price
  )
    return false;
  state.pets.push({
    species,
    name,
    hunger: 62,
    thirst: 58,
    cleanliness: 65,
    affection: 15,
    tricks: [],
    adoptedAt: Date.now(),
  });
  state.selected = state.pets.length - 1;
  state.money -= SPECIES[species].price;
  state.started = true;
  state.stage = "settle";
  return true;
}
export function currentPet(state) {
  return state.pets[state.selected];
}
export function care(state, item) {
  const p = currentPet(state);
  if (!p || !(state.inventory[item] > 0)) return false;
  if (item === "food") p.hunger = 100;
  else if (item === "water") p.thirst = 100;
  else return false;
  state.inventory[item]--;
  p.affection = Math.min(100, p.affection + 5);
  return true;
}
export function buy(state, item, price) {
  if (state.money < price) return false;
  state.money -= price;
  state.inventory[item] = (state.inventory[item] || 0) + 1;
  return true;
}

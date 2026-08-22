// Mise OS domain model.
// Branch agents forecast demand, shortages route to surplus holders nearest-expiry
// first, and only the NET shortage escalates to procurement. On top of that sits the
// routing decision this project exists for: who physically executes each task — an AI
// agent, a robot, or a human in the field.
const fs = require('fs'), path = require('path');

const DATA = path.join(__dirname, '..', 'data');

/** The demand model: 8 cuisines of scraped restaurant menus exploded to ingredients. */
function loadMenuIntel() {
  const out = { restaurants: 0, branches: 0, dishes: 0, priced: 0, nullPrice: 0, ingredients: new Map() };
  for (const f of fs.readdirSync(path.join(DATA, 'menu-intel'))) {
    const d = JSON.parse(fs.readFileSync(path.join(DATA, 'menu-intel', f), 'utf8'));
    for (const r of d.restaurants) {
      out.restaurants++; out.branches += (r.branches || []).length;
      for (const dish of r.dishes || []) {
        out.dishes++;
        dish.price == null ? out.nullPrice++ : out.priced++;
        for (const ing of dish.ingredients || []) {
          const k = ing.name.toLowerCase();
          const e = out.ingredients.get(k) || { name: k, demand: 0, core: 0 };
          e.demand++; if (ing.is_core) e.core++;
          out.ingredients.set(k, e);
        }
      }
    }
  }
  return out;
}

/** The data-contract check that drives everything. Null price = blind routing. */
function priceNullRate(m) { return m.dishes ? m.nullPrice / m.dishes : 1; }

// Branch state for the worked scenario.
const BRANCHES = [
  { id: 'downtown', name: 'Downtown', onHand: 4.0,  par: 40, expiryDays: null },
  { id: 'marina',   name: 'Marina',   onHand: 34.0, par: 24, expiryDays: 2 },
  { id: 'mission',  name: 'Mission',  onHand: 16.0, par: 20, expiryDays: 6 },
];

/**
 * Transfer surplus before buying. A branch below its own par cannot donate, which is
 * why Mission (16.0 against par 20) is excluded despite holding stock.
 */
function plan(ingredient = 'tomato', unitPrice = 2.05) {
  const short = BRANCHES.filter(b => b.onHand < b.par)
    .map(b => ({ ...b, gap: +(b.par - b.onHand).toFixed(2) }))
    .sort((a, b) => b.gap - a.gap);
  const donors = BRANCHES.filter(b => b.onHand > b.par)
    .map(b => ({ ...b, surplus: +(b.onHand - b.par).toFixed(2) }))
    .sort((a, b) => (a.expiryDays ?? 99) - (b.expiryDays ?? 99));  // nearest expiry first

  const need = short[0];
  const transfers = [], tasks = [];
  let remaining = need ? need.gap : 0;

  for (const d of donors) {
    if (remaining <= 0) break;
    const qty = Math.min(d.surplus, remaining);
    remaining = +(remaining - qty).toFixed(2);
    transfers.push({ from: d.id, to: need.id, qty, expiryDays: d.expiryDays });
    tasks.push({
      kind: 'transfer', ingredient, qty, from: d.id, to: need.id,
      // A physical move between sites is robot work; the rehearsal shows it happening.
      executor: 'robot', rationale: `${qty}kg from ${d.name} (expires in ${d.expiryDays}d, use first)`,
    });
    tasks.push({
      kind: 'handoff', ingredient, qty, at: need.id,
      // A handoff at the service pass is a human touchpoint, not a robot one.
      executor: 'human', rationale: 'Crate handed to the cook at the service pass',
    });
  }

  const buyQty = +remaining.toFixed(2);
  const buyCost = +(buyQty * unitPrice).toFixed(2);
  if (buyQty > 0) tasks.push({
    kind: 'procure', ingredient, qty: buyQty, unitPrice, cost: buyCost,
    // Supplier negotiation is agent work — RFQ out, bids in, lowest landed cost.
    executor: 'agent', rationale: `Only the NET shortage is bought: ${buyQty}kg @ $${unitPrice}/kg`,
  });

  // Risk drives whether a human must accept before anything dispatches.
  const risk = (buyCost > 50 ? 2 : 0) + (transfers.some(t => t.expiryDays <= 2) ? 2 : 0);
  return {
    ingredient, need, transfers, tasks,
    buy: { qty: buyQty, unitPrice, cost: buyCost },
    risk, requiresHumanApproval: risk >= 2,
    summary: `Transfer ${transfers.reduce((s, t) => s + t.qty, 0)}kg, buy net ${buyQty}kg @ $${unitPrice} = $${buyCost}`,
  };
}

module.exports = { loadMenuIntel, priceNullRate, plan, BRANCHES };

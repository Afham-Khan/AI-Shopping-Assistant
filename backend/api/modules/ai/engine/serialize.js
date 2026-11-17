// engine items -> api shapes (RecommendedProduct = ProductCard + match)
const { toCard } = require('../../../../helpers/serializers');

const recommended = (item) => ({
  ...toCard(item.product),
  match: { score: item.score, reasons: item.reasons || [] },
});

const recommendedList = (items) => items.map(recommended);

const serializeBundle = (b) => ({
  title: b.title,
  template: b.template,
  goal: b.goal,
  total: b.total,
  budget: b.budget,
  remaining: b.remaining,
  items: b.items.map((it) => ({ role: it.role, required: it.required, product: recommended(it.product), alternatives: it.alternatives.map(toCard) })),
  skippedRoles: b.skippedRoles,
  explanation: b.explanation,
  savingsTips: b.savingsTips,
});

module.exports = { recommended, recommendedList, serializeBundle, toCard };

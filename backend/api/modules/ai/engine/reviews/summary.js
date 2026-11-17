// aspect-based review summarization: sentence sentiment x aspect detection -> pros/cons, label, summary, quotes
const models = require('../../models/ai.models');
const { scoreText } = require('./sentiment');
const { aspectsFor, detectAspects, LABELS } = require('./aspects');
const { getCatalog } = require('../retrieval/catalog');
const { list, truncate } = require('../format');

const cache = new Map(); // productId -> { stamp, result }

const LABELS_ORDER = ['Negative', 'Mixed', 'Positive', 'Very positive'];
// text sentiment runs warm (reviewers use kind words even at 3★), so the star average caps the label:
// "Very positive" needs about 4★, "Positive" about 3.2★, and below 2.5★ it is "Negative"
const labelFor = (score, avgStars = null) => {
  let label = score >= 0.45 ? 'Very positive' : score >= 0.15 ? 'Positive' : score > -0.15 ? 'Mixed' : 'Negative';
  if (avgStars !== null && Number.isFinite(avgStars)) {
    const cap = avgStars >= 3.95 ? 3 : avgStars >= 3.2 ? 2 : avgStars >= 2.5 ? 1 : 0;
    if (LABELS_ORDER.indexOf(label) > cap) label = LABELS_ORDER[cap];
  }
  return label;
};

// pure function so it can be unit-tested without a database
const summarizeReviews = (reviews, { categorySlug = null, title = 'this product' } = {}) => {
  if (!reviews.length) {
    return { reviewCount: 0, sentiment: { score: 0, label: 'Mixed' }, pros: [], cons: [], summary: `No reviews yet for ${title}.`, highlights: [] };
  }
  const dict = aspectsFor(categorySlug);
  const tally = new Map(); // aspect -> { pos, neg, sum }
  const scoredReviews = reviews.map((r) => {
    const text = [r.title, r.comment].filter(Boolean).join('. ');
    const analysis = scoreText(text);
    // stars are a strong prior; text refines it
    const starSignal = ((r.rating || 3) - 3) / 2;
    const blended = 0.55 * analysis.score + 0.45 * starSignal;
    for (const sentence of analysis.sentences) {
      const aspects = detectAspects(sentence.text, dict);
      if (!aspects.length) continue;
      // neutral wording inherits the review's overall tone
      const polarity = Math.abs(sentence.score) >= 0.1 ? sentence.score : starSignal * 0.5;
      for (const aspect of aspects) {
        if (!tally.has(aspect)) tally.set(aspect, { pos: 0, neg: 0, sum: 0, best: 0 });
        const t = tally.get(aspect);
        t.best = Math.max(t.best, polarity);
        if (polarity > 0.05) t.pos += 1;
        else if (polarity < -0.05) t.neg += 1;
        t.sum += polarity;
      }
    }
    return { review: r, text: r.comment, score: blended, analysis };
  });

  const overall = scoredReviews.reduce((s, r) => s + r.score, 0) / scoredReviews.length;
  const entries = [...tally].map(([aspect, t]) => ({ aspect, label: LABELS[aspect] || aspect, ...t }));
  // a pro needs real praise: one clearly positive remark or several mild ones (not just "okay for the price")
  const pros = entries.filter((e) => e.pos > e.neg && e.pos >= 1 && (e.best >= 0.4 || e.pos >= 3)).sort((a, b) => b.pos - a.pos)
    .slice(0, 5).map((e) => ({ aspect: e.label, mentions: e.pos }));
  const cons = entries.filter((e) => e.neg >= e.pos && e.neg >= 1).sort((a, b) => b.neg - a.neg)
    .slice(0, 5).map((e) => ({ aspect: e.label, mentions: e.neg }));

  const positiveShare = scoredReviews.filter((r) => r.score > 0.1).length / scoredReviews.length;
  const avgStars = reviews.reduce((a, r) => a + (r.rating || 3), 0) / reviews.length;
  const label = labelFor(overall, avgStars);
  const lead = {
    'Very positive': `Shoppers love ${title}`,
    Positive: `Most shoppers are happy with ${title}`,
    Mixed: `Opinions on ${title} are mixed`,
    Negative: `Many shoppers were disappointed with ${title}`,
  }[label];
  const proText = pros.length ? ` — praised for ${list(pros.slice(0, 2).map((p) => p.aspect.toLowerCase()))}` : '';
  const conText = cons.length ? `${pros.length ? ', though some mention' : '. Common complaints:'} ${list(cons.slice(0, 2).map((c) => c.aspect.toLowerCase()))}` : '';
  const summary = `${lead}${proText}${conText}. ${Math.round(positiveShare * 100)}% of ${reviews.length} reviews are positive.`;

  // most informative quotes: strongest positive and negative with some substance
  const pickQuote = (dir) => scoredReviews
    .filter((r) => (dir > 0 ? r.score > 0.2 : r.score < -0.2) && (r.text || '').length > 12)
    .sort((a, b) => dir * (b.score - a.score) + 0.002 * ((b.text || '').length - (a.text || '').length))[0];
  const highlights = [pickQuote(1), pickQuote(-1)].filter(Boolean).map((r) => truncate(r.text.replace(/\s+/g, ' '), 140));

  return {
    reviewCount: reviews.length,
    sentiment: { score: +overall.toFixed(3), label },
    pros,
    cons,
    summary,
    highlights: [...new Set(highlights)],
  };
};

const reviewSummary = async (productId) => {
  const id = Number(productId);
  const catalog = await getCatalog();
  const product = catalog.byId.get(id);
  if (!product && !(await models.productExists(id))) return null;
  const stamp = await models.reviewStamp(id);
  const hit = cache.get(id);
  if (hit && hit.stamp === stamp) return hit.result;
  const reviews = await models.reviewsFor(id);
  const result = summarizeReviews(reviews, { categorySlug: product?.category_slug, title: product?.title || 'this product' });
  cache.set(id, { stamp, result });
  return result;
};

module.exports = { reviewSummary, summarizeReviews, labelFor };

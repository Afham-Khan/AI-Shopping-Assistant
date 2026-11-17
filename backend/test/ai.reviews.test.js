const assert = require('node:assert/strict');
const { scoreSentence, scoreText } = require('../api/modules/ai/engine/reviews/sentiment');
const { aspectsFor, detectAspects } = require('../api/modules/ai/engine/reviews/aspects');
const { summarizeReviews } = require('../api/modules/ai/engine/reviews/summary');

describe('AI review sentiment (unit, no db)', () => {
  it('REV-01 positive and negative polarity', () => {
    assert.ok(scoreSentence('Great product!').score > 0);
    assert.ok(scoreSentence('Poor quality!').score < 0);
    assert.ok(scoreSentence('Waste of money').score < 0);
  });

  it('REV-02 negation flips polarity', () => {
    assert.ok(scoreSentence('not good').score < 0);
    assert.ok(scoreSentence('Would not recommend!').score < 0);
    assert.ok(scoreSentence('not long-lasting at all').score < 0);
  });

  it('REV-03 intensifiers strengthen sentiment', () => {
    assert.ok(scoreSentence('very good').score > scoreSentence('good').score);
    assert.ok(scoreSentence('slightly bad').score > scoreSentence('bad').score);
  });

  it('REV-04 the clause after "but" dominates', () => {
    assert.ok(scoreText('It looks nice but the battery is terrible.').score < 0);
    assert.ok(scoreText('A bit pricey but absolutely amazing.').score > 0);
  });

  it('REV-05 aspects are detected per category', () => {
    const dict = aspectsFor('smartphones');
    assert.ok(detectAspects('The battery drains quickly', dict).includes('battery'));
    assert.ok(detectAspects('Camera takes stunning photos', dict).includes('camera'));
    assert.ok(detectAspects('Lovely scent that lasts for hours', aspectsFor('fragrances')).includes('scent'));
  });

  it('REV-06 summary builds pros, cons, label and highlights', () => {
    const reviews = [
      { rating: 5, title: 'Love it', comment: 'The camera is amazing and photos look stunning. Great value for money.' },
      { rating: 4, title: 'Very good', comment: 'Excellent camera, but the battery drains quickly.' },
      { rating: 2, title: 'Meh', comment: 'Battery life is terrible. Camera is good though.' },
      { rating: 5, title: 'Superb', comment: 'Fast delivery and the camera is superb.' },
      { rating: 1, title: 'Bad', comment: 'Battery died in a few hours, very disappointed.' },
    ];
    const s = summarizeReviews(reviews, { categorySlug: 'smartphones', title: 'Test Phone' });
    assert.equal(s.reviewCount, 5);
    assert.ok(s.pros.some((p) => p.aspect === 'Camera' && p.mentions >= 3));
    assert.ok(s.cons.some((c) => c.aspect === 'Battery life'));
    assert.ok(['Very positive', 'Positive', 'Mixed', 'Negative'].includes(s.sentiment.label));
    assert.ok(s.sentiment.score >= -1 && s.sentiment.score <= 1);
    assert.match(s.summary, /Test Phone/);
    assert.ok(s.highlights.length >= 1);
  });

  it('REV-07 no reviews', () => {
    const s = summarizeReviews([], { title: 'X' });
    assert.equal(s.reviewCount, 0);
    assert.equal(s.sentiment.label, 'Mixed');
    assert.deepEqual(s.pros, []);
  });
});

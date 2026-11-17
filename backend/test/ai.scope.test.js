// off-script hardening: off-topic, store faq, questions about zel, feelings/abuse/crisis, noise, multi-intent,
// named-product facts, glossary and the optional persona-locked llm fallback.
const assert = require('node:assert/strict');
const supertest = require('supertest');
const app = require('../app');
const nlu = require('../api/modules/ai/engine/nlu');
const scope = require('../api/modules/ai/engine/nlu/scope');
const { conceptQuery } = require('../api/modules/ai/engine/concepts');
const { arithmetic } = require('../api/modules/ai/engine/dialogue/offscope');
const llm = require('../api/modules/ai/engine/llm');
const { respond } = require('../api/modules/ai/engine/dialogue/manager');
const { FREE_SHIPPING_THRESHOLD, SHIPPING_FEE } = require('../helpers/constants');
const { registerUser } = require('./helpers');

const api = supertest(app);
const VENDOR = /\b(?:openai|chatgpt|google|gemini|anthropic|claude|meta|llama|groq|microsoft)\b/i;
const say = async (text, opts = {}) => {
  const r = await respond({ text, context: opts.context || null, userId: opts.userId || null });
  return { ...r, intent: r.meta.intent, products: r.meta.products, chips: [...r.meta.suggestions, ...(r.meta.clarify?.options || [])] };
};

describe('AI scope hardening (off-script messages)', () => {
  describe('rule layer (unit)', () => {
    const detect = (text) => {
      const a = nlu.analyze(text);
      return a.signals;
    };

    it('SCOPE-01 crisis, profanity and insults are detected', () => {
      assert.equal(detect('i want to kill myself').crisis, true);
      assert.equal(detect('fuck you').profanity, true);
      assert.equal(detect('you are useless').insult, true);
      assert.equal(detect('show me phones').crisis, false);
      assert.equal(detect('show me phones').profanity, false);
    });

    it('SCOPE-02 noise: gibberish, numbers-only, emoji-only and other scripts', () => {
      assert.equal(detect('asdkjh').noise?.kind, 'gibberish');
      assert.equal(detect('qwerty uiop').noise?.kind, 'gibberish');
      assert.equal(detect('jjjjjjjj').noise?.kind, 'gibberish');
      assert.equal(detect('12345678').noise?.kind, 'numbers');
      assert.equal(detect('???').noise?.kind, 'empty');
      assert.equal(detect('میرا آرڈر').noise?.kind, 'script');
      assert.equal(detect('potatoes').noise, null);
      assert.equal(detect('laptop').noise, null);
    });

    it('SCOPE-03 off-topic topics, gated by shopping words', () => {
      assert.equal(detect('who won the cricket match').oos, 'sports');
      assert.equal(detect("what's the weather in karachi").oos, 'weather');
      assert.equal(detect('write my assignment').oos, 'study');
      assert.equal(detect('who is elon musk').oos, 'people');
      assert.equal(detect('cricket bat under 5000').oos, null);
      assert.equal(detect('headphones for music').oos, null);
      assert.equal(detect('any discount code').oos, null);
    });

    it('SCOPE-04 store faq topics and cities', () => {
      assert.equal(detect('do you deliver to lahore').faq, 'delivery_area');
      assert.equal(detect('do you deliver to lahore').city.fast, true);
      assert.equal(detect('do you deliver to quetta').city.fast, false);
      assert.equal(detect('how long is delivery').faq, 'delivery_time');
      assert.equal(detect('cash on delivery?').faq, 'cod');
      assert.equal(detect('what are the shipping charges').faq, 'shipping_fee');
      assert.equal(detect('do you ship internationally').faq, 'international');
      assert.equal(detect('any coupons').faq, 'coupons');
      assert.equal(detect('contact support').faq, 'contact');
    });

    it('SCOPE-05 glossary answers concepts but not product questions', () => {
      assert.equal(conceptQuery('what does ram mean').key, 'ram');
      assert.equal(conceptQuery('difference between ipad and tablet').key, 'ipad|tablet');
      assert.match(conceptQuery('what is a 5g phone').text, /5G/);
      assert.equal(conceptQuery('what is the price of iphone x'), null);
      assert.equal(conceptQuery('show me laptops'), null);
    });

    it('SCOPE-06 safe arithmetic only', () => {
      assert.deepEqual(arithmetic('what is 2 plus 2'), { expr: '2 + 2', value: 4 });
      assert.equal(arithmetic('15 times 7').value, 105);
      assert.equal(arithmetic('5 divided by 0'), null);
      assert.equal(arithmetic('hello'), null);
    });
  });

  describe('trained intents', () => {
    const cases = [
      ['who made you', 'about_assistant'], ['are you chatgpt', 'about_assistant'], ['how do you work', 'about_assistant'],
      ['do you deliver to lahore', 'store_info'], ['payment methods', 'store_info'], ['is cod available', 'store_info'],
      ['what is the weather today', 'out_of_scope'], ['write my essay', 'out_of_scope'], ['who won the match', 'out_of_scope'],
      ["i'm sad", 'feelings'], ['main udaas hoon', 'feelings'], ['you are useless', 'abuse'], ['bakwas band karo', 'abuse'],
    ];
    for (const [text, intent] of cases) {
      it(`SCOPE-07 "${text}" -> ${intent}`, () => assert.equal(nlu.analyze(text).intent, intent));
    }
  });

  describe('dialogue replies (db catalog)', () => {
    it('SCOPE-10 off-topic: honest, no random products, shopping chips', async () => {
      for (const text of ['who won the cricket match', "what's the weather", 'write my assignment', 'who is elon musk', 'translate hello to french']) {
        const r = await say(text);
        assert.equal(r.intent, 'out_of_scope', text);
        assert.equal(r.products.length, 0, text);
        assert.ok(r.chips.length > 0, text);
        assert.doesNotMatch(r.content, /didn't quite get|couldn't find anything matching/, text);
      }
      const cricket = await say('who won the cricket match');
      assert.doesNotMatch(cricket.content, /\bwon by\b/);
      assert.equal(cricket.meta.scope.topic, 'sports');
    });

    it('SCOPE-11 identity: Zel by the Zelora team, never an ai vendor', async () => {
      const made = await say('who made you');
      assert.equal(made.intent, 'about_assistant');
      assert.match(made.content, /Zel.*Zelora team/s);
      assert.doesNotMatch(made.content, VENDOR);
      const gpt = await say('are you ChatGPT');
      assert.match(gpt.content, /Zel/);
      assert.doesNotMatch(gpt.content.replace(/chatbot/gi, ''), VENDOR);
      const how = await say('how do you work');
      assert.match(how.content, /194|\d+ products/);
      assert.match(how.content, /rank/i);
    });

    it('SCOPE-12 store faq uses the real delivery, shipping and payment rules', async () => {
      const lahore = await say('do you deliver to Lahore');
      assert.equal(lahore.intent, 'store_info');
      assert.match(lahore.content, /Lahore/);
      assert.match(lahore.content, /2 days/);
      const quetta = await say('do you deliver to quetta');
      assert.match(quetta.content, /4 days/);
      const fee = await say('what are the shipping charges');
      assert.match(fee.content, new RegExp(`Rs ${FREE_SHIPPING_THRESHOLD.toLocaleString('en-US')}`));
      assert.match(fee.content, new RegExp(`Rs ${SHIPPING_FEE}`));
      const small = await say('how much is delivery charges for 3000 order');
      assert.match(small.content, /Rs 250/);
      assert.match(small.content.replace(/\*\*/g, ''), /Rs 2,000 more/);
      const pay = await say('what are the payment methods');
      assert.match(pay.content, /Cash on Delivery/);
      assert.match(pay.content, /card/);
      const coupons = await say('do you have any coupons');
      assert.match(coupons.content, /WELCOME10|FLAT500|AI15/);
      assert.doesNotMatch(coupons.content, /SUMMER25/); // expired
      for (const r of [lahore, quetta, fee, pay]) assert.equal(r.products.length, 0);
    });

    it('SCOPE-13 personal delivery questions still check the order', async () => {
      const session = await registerUser();
      const r = await say('where is my order', { userId: session.user.id });
      assert.equal(r.intent, 'order_status');
      const faq = await say('how long is delivery', { userId: session.user.id });
      assert.equal(faq.intent, 'store_info');
    });

    it('SCOPE-14 feelings, abuse and crisis', async () => {
      const sad = await say("I'm sad");
      assert.equal(sad.intent, 'feelings');
      assert.match(sad.content, /sorry/i);
      assert.equal(sad.products.length, 0);
      const crisis = await say('i want to kill myself');
      assert.match(crisis.content, /1122|Umang/);
      assert.equal(crisis.products.length, 0);
      assert.equal(crisis.meta.suggestions.length, 0);
      const swear = await say('fuck you');
      assert.equal(swear.intent, 'abuse');
      assert.match(swear.content, /friendly/);
      const insult = await say("you're a useless bot");
      assert.equal(insult.intent, 'abuse');
      assert.equal(insult.products.length, 0);
    });

    it('SCOPE-15 gibberish / numbers / emoji ask a clarifying question instead of guessing', async () => {
      for (const text of ['asdkjh', 'lkjsdf sdfkj werqwe', '???', '12345678', '100']) {
        const r = await say(text);
        assert.equal(r.products.length, 0, text);
        assert.ok(r.meta.clarify, text);
      }
      const budget = await say('50000');
      assert.equal(budget.intent, 'budget_query');
      const phone = await say('📱 under 50k');
      assert.ok(phone.products.length > 0);
      assert.ok(phone.products.every((p) => p.price <= 50000));
    });

    it('SCOPE-16 multi-intent answers the first need and offers the second as a chip', async () => {
      const r = await say('cheap phone and a cover for it');
      assert.equal(r.intent, 'product_search');
      assert.ok(r.products.length > 0);
      assert.ok(r.products.every((p) => p.category?.slug === 'smartphones' || /phone|realme|galaxy|iphone|oppo|vivo/i.test(p.title)));
      assert.ok(r.meta.suggestions[0].startsWith('Show a cover'));
      const faq = await say('show me shoes and also tell me the delivery time');
      assert.ok(faq.products.length > 0);
      assert.match(faq.content, /2 days/);
    });

    it('SCOPE-17 product facts by name, honest when the detail is missing', async () => {
      const water = await say('is iphone 13 waterproof');
      assert.equal(water.intent, 'product_question');
      assert.match(water.content, /iPhone 13 Pro/);
      assert.match(water.content, /plain iPhone 13/);
      const price = await say('what is the price of iphone x');
      assert.match(price.content, /iPhone X/);
      assert.match(price.content, /Rs [\d,]+/);
      const unknown = await say('can the iphone x fly to the moon');
      assert.match(unknown.content, /don't have that detail/);
      assert.ok(unknown.meta.suggestions.includes('Explain its specs'));
      const concept = await say('difference between iPad and tablet');
      assert.equal(concept.intent, 'concept');
      assert.match(concept.content, /Apple's brand of tablet/);
    });

    it('SCOPE-18 vague shopping shows inspiration, not a fallback', async () => {
      for (const text of ['something nice', 'surprise me', 'mjhe kuch acha sa chahiye', 'show me something cool']) {
        const r = await say(text);
        assert.ok(r.products.length > 0, text);
        assert.notEqual(r.intent, 'fallback', text);
      }
    });

    it('SCOPE-19 slot answers still win over the scope layer', async () => {
      const first = await say('gift for my mom');
      const second = await say('5000', { context: first.context });
      assert.equal(second.intent, 'gift_suggestion');
    });

    it('SCOPE-20 chat api: off-topic replies do not rename the conversation', async () => {
      const session = await registerUser();
      const res = await api.post('/api/v1/ai/chat').set(session.auth).send({ message: 'who won the cricket match' }).expect(200);
      assert.equal(res.body.data.message.meta.intent, 'out_of_scope');
      assert.equal(res.body.data.message.meta.scope.kind, 'out_of_scope');
      assert.equal(res.body.data.title, 'New chat');
    });
  });

  describe('optional llm fallback for general questions', () => {
    const fake = (reply, calls = { n: 0 }) => ({
      name: 'fake', model: () => 'fake-1', enabled: () => true,
      complete: async () => {
        calls.n += 1;
        if (reply instanceof Error) throw reply;
        return reply;
      },
    });
    beforeEach(() => llm.resetGuard({ perMinute: 100, dailyLimit: 100 }));

    it('LLM-G1 uses the persona answer when it is safe, and caches it', async () => {
      const calls = { n: 0 };
      const p = fake('Paris is the capital of France. Anything I can help you shop for today?', calls);
      const a = await llm.general({ query: 'capital of france', fallback: 'offline' }, { provider: p });
      assert.equal(a.source, 'fake');
      assert.match(a.content, /Paris/);
      const b = await llm.general({ query: 'capital of france', fallback: 'offline' }, { provider: p });
      assert.equal(b.cached, true);
      assert.equal(calls.n, 1);
    });

    it('LLM-G2 rejects vendor names, prices and long answers', async () => {
      for (const bad of ['I am Gemini, made by Google.', 'You can get it for Rs 5,000 today!', 'x'.repeat(600)]) {
        const r = await llm.general({ query: `q ${bad.length}`, fallback: 'offline' }, { provider: fake(bad) });
        assert.equal(r.content, 'offline');
        assert.equal(r.source, 'local');
      }
    });

    it('LLM-G3 any failure falls back silently', async () => {
      const r = await llm.general({ query: 'weather', fallback: 'offline' }, { provider: fake(new Error('timeout')) });
      assert.deepEqual(r, { content: 'offline', source: 'local' });
      assert.equal((await llm.general({ query: 'x', fallback: 'offline' }, { provider: null })).source, 'local');
      assert.match(llm.PERSONA, /Zelora team/);
    });
  });
});

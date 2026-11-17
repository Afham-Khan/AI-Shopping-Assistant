// aspect-based review generator: the AI summarizer mines pros/cons from these sentences,
// so every sentence names its aspect explicitly and sentiment tracks the product rating
const ASPECTS = {
  battery: {
    pos: ['Battery life is excellent, it easily lasts a full day of heavy use.', 'The battery gets me through a day and a half without worrying.', 'Battery backup is impressive, even with maps and video calls.'],
    neg: ['Battery drains much faster than advertised.', 'Battery life is disappointing, I have to charge it twice a day.', 'The battery barely lasts till evening.'],
  },
  camera: {
    pos: ['Camera quality is superb, especially in daylight.', 'The camera takes sharp, detailed photos and portrait mode is lovely.', 'Night mode on the camera is surprisingly good.'],
    neg: ['The camera struggles in low light and photos look grainy.', 'Camera is average at best, colours look washed out.', 'Camera focus is slow and many shots come out blurry.'],
  },
  display: {
    pos: ['The display is bright and sharp, colours really pop.', 'Display quality is stunning for videos and reading.', 'Love the smooth, vivid display.'],
    neg: ['The display is dim outdoors and hard to read in sunlight.', 'Display has a slight yellow tint that bothers me.', 'The display picks up a lot of glare.'],
  },
  performance: {
    pos: ['Performance is smooth, apps open instantly and multitasking is a breeze.', 'Performance is fast with zero lag, even while gaming.', 'Very snappy performance for daily work.'],
    neg: ['Performance is sluggish and it lags when multitasking.', 'Noticeable lag in performance after a few weeks.', 'Performance drops badly under load.'],
  },
  build: {
    pos: ['Build quality feels premium and solid.', 'Excellent build quality, it feels like it will last for years.', 'Sturdy build quality, nothing feels flimsy.'],
    neg: ['Build quality feels cheap and plasticky.', 'The build quality is poor, it started creaking within a week.', 'Build quality is not what I expected at this price.'],
  },
  charging: {
    pos: ['Charging is quick, goes from 0 to 80% in about an hour.', 'Fast charging works really well.'],
    neg: ['Charging is painfully slow.', 'Charging speed is much slower than claimed.'],
  },
  keyboard: {
    pos: ['The keyboard is comfortable to type on for hours.', 'Keyboard has great travel and the backlight is handy.'],
    neg: ['The keyboard feels shallow and mushy.', 'A couple of keys on the keyboard feel sticky.'],
  },
  heat: {
    pos: ['It stays cool and the fan noise is barely noticeable.', 'No heating issues even during long sessions.'],
    neg: ['It heats up quickly and the fan noise gets loud.', 'Heating is a real problem during video calls.'],
  },
  sound: {
    pos: ['Sound quality is rich with deep bass.', 'Sound quality is crisp and clear, vocals sound great.', 'Noise cancellation and sound quality are excellent.'],
    neg: ['Sound quality is tinny and lacks bass.', 'Sound quality distorts at high volume.', 'The sound quality is flat and muffled.'],
  },
  compatibility: {
    pos: ['Compatibility was seamless, it paired instantly with my phone.', 'Works perfectly with both my phone and laptop, great compatibility.'],
    neg: ['Had compatibility issues, it keeps disconnecting.', 'Compatibility is poor with Android devices.'],
  },
  fabric: {
    pos: ['The fabric is soft, breathable and perfect for our weather.', 'Fabric quality is great and it did not shrink after washing.', 'Really nice fabric, feels premium.'],
    neg: ['The fabric feels thin and rough.', 'The fabric faded and shrank after the first wash.', 'Fabric is see-through and feels cheap.'],
  },
  fit: {
    pos: ['The fit is perfect, true to size.', 'Fits really well, the size chart was accurate.'],
    neg: ['The fit is off, it runs a size small.', 'Sizing is inconsistent and the fit was too loose.'],
  },
  stitching: {
    pos: ['Stitching is neat and the finishing is clean.', 'Stitching quality is excellent, no loose threads.'],
    neg: ['Stitching came loose within a few days.', 'Stitching is uneven in a few places.'],
  },
  colour: {
    pos: ['The colour is exactly as shown in the pictures.', 'Beautiful colour, looks even better in person.'],
    neg: ['The colour looks quite different from the pictures.', 'Colour faded noticeably after a few washes.'],
  },
  comfort: {
    pos: ['Very comfortable, I can use it all day.', 'Comfort is excellent even after hours of use.', 'Super comfortable from day one.'],
    neg: ['Not comfortable at all for long hours.', 'Comfort is poor, it started hurting after an hour.', 'Comfort level is lower than I hoped.'],
  },
  grip: {
    pos: ['Grip is excellent on every surface.', 'Great grip, feels secure in hand.'],
    neg: ['Grip is weak and it feels slippery.', 'The grip wore off quickly.'],
  },
  durability: {
    pos: ['Durability is impressive, it still looks new after months of use.', 'Very durable, has taken a beating and survived.'],
    neg: ['Durability is a concern, it is already showing wear.', 'Not durable, it broke within a month.'],
  },
  design: {
    pos: ['The design is elegant and gets lots of compliments.', 'Love the design, it looks more expensive than it is.', 'Sleek, modern design.'],
    neg: ['The design looks dated in person.', 'Design looks cheaper than in the photos.'],
  },
  strap: {
    pos: ['The strap is comfortable and easy to adjust.', 'Strap quality is excellent.'],
    neg: ['The strap feels stiff and uncomfortable.', 'The strap buckle broke after a few weeks.'],
  },
  timekeeping: {
    pos: ['Timekeeping is accurate to the second.', 'Keeps perfect time, very accurate.'],
    neg: ['Timekeeping drifts by a few minutes every week.', 'Timekeeping is unreliable.'],
  },
  material: {
    pos: ['Material quality is excellent and feels durable.', 'The material feels premium to the touch.'],
    neg: ['The material feels cheap and started peeling.', 'Material quality is disappointing.'],
  },
  size: {
    pos: ['The size is just right for everyday use.', 'Perfect size, fits all my essentials.'],
    neg: ['The size is smaller than expected.', 'Size is too bulky for daily use.'],
  },
  finish: {
    pos: ['The finish is flawless and polished.', 'Lovely finish, looks high-end.'],
    neg: ['The finish started tarnishing quickly.', 'The finish has scratches out of the box.'],
  },
  lenses: {
    pos: ['The lenses are clear and cut glare really well.', 'Great lenses, good UV protection on sunny days.'],
    neg: ['The lenses scratch far too easily.', 'Lenses distort the view slightly.'],
  },
  texture: {
    pos: ['The texture is lightweight and blends easily.', 'Lovely smooth texture, not sticky at all.'],
    neg: ['The texture is too thick and cakey.', 'Texture feels greasy on the skin.'],
  },
  longevity: {
    pos: ['Very long-lasting, it stays on all day.', 'Long-lasting wear without touch-ups.'],
    neg: ['Not long-lasting, it fades within a few hours.', 'Needs constant touch-ups, poor longevity.'],
  },
  results: {
    pos: ['Visible results within two weeks of use.', 'Great results, my skin looks much healthier.'],
    neg: ['Did not see any results after a month.', 'Results were underwhelming compared to the claims.'],
  },
  skin: {
    pos: ['Gentle on my sensitive skin, no breakouts.', 'Suits my skin type perfectly.'],
    neg: ['It caused irritation on my skin.', 'Broke my skin out after a few uses.'],
  },
  scent_longevity: {
    pos: ['Scent longevity is amazing, it lasts 8+ hours on skin.', 'The scent lasts all day, even in the heat.'],
    neg: ['Scent longevity is poor, it fades within two hours.', 'The scent disappears far too quickly.'],
  },
  projection: {
    pos: ['Projection is strong, people notice it immediately.', 'Good projection without being overpowering.'],
    neg: ['Projection is weak, it sits very close to the skin.', 'Barely any projection after the first hour.'],
  },
  fragrance: {
    pos: ['The fragrance is elegant and not overpowering.', 'Beautiful fragrance, perfect for evenings.'],
    neg: ['The fragrance smells too synthetic.', 'Not a fan of the fragrance, too sharp.'],
  },
  bottle: {
    pos: ['The bottle looks luxurious on my dresser.', 'Gorgeous bottle and a smooth sprayer.'],
    neg: ['The bottle sprayer leaks.', 'The bottle feels cheap for the price.'],
  },
  assembly: {
    pos: ['Assembly was easy and took under 30 minutes.', 'Simple assembly with clear instructions.'],
    neg: ['Assembly was a nightmare, the instructions were unclear.', 'Assembly took hours and a few screws were missing.'],
  },
  cleaning: {
    pos: ['Very easy to clean, just rinse and done.', 'Cleaning is effortless, nothing sticks.'],
    neg: ['Hard to clean, food sticks to it.', 'Cleaning is a hassle.'],
  },
  taste: {
    pos: ['Taste is great, the whole family loved it.', 'Excellent taste, just like fresh from the market.'],
    neg: ['Taste is bland and disappointing.', 'The taste was off.'],
  },
  freshness: {
    pos: ['Arrived fresh with a long expiry date.', 'Freshness was excellent.'],
    neg: ['Freshness was an issue, it was close to expiry on arrival.', 'Not fresh, had to throw some away.'],
  },
  quantity: {
    pos: ['Quantity is generous for the price.', 'Good quantity, lasts the whole week.'],
    neg: ['Quantity is less than expected for the price.', 'The quantity is too small.'],
  },
  fuel_efficiency: {
    pos: ['Fuel efficiency is excellent, great mileage in city traffic.', 'Mileage and fuel efficiency are better than I expected.'],
    neg: ['Fuel efficiency is poor, mileage is much lower than claimed.', 'Fuel efficiency drops a lot in traffic.'],
  },
  handling: {
    pos: ['Handling is sharp and confident.', 'Handling is smooth even on rough roads.'],
    neg: ['Handling feels heavy at low speeds.', 'Handling is twitchy on highways.'],
  },
  delivery: {
    pos: ['Delivery was super fast, it arrived in two days.', 'Quick delivery, well within the estimate.', 'Delivery was on time and the rider was polite.'],
    neg: ['Delivery took much longer than promised.', 'Delivery was delayed by almost a week.'],
  },
  packaging: {
    pos: ['Packaging was secure and neat.', 'Well packed with proper bubble wrap.'],
    neg: ['Packaging was damaged when it arrived.', 'Poor packaging, the box was crushed.'],
  },
  value: {
    pos: ['Great value for money at this price.', 'Excellent value for money, worth every rupee.'],
    neg: ['Not good value for money, overpriced for what you get.', 'Poor value for money, there are better options at this price.'],
  },
  service: {
    pos: ['Customer service was helpful and responsive.'],
    neg: ['Customer service never replied to my complaint.'],
  },
};

const GROUPS = {
  phone: { item: 'phone', aspects: ['battery', 'camera', 'display', 'performance', 'build', 'charging'] },
  laptop: { item: 'laptop', aspects: ['performance', 'battery', 'display', 'keyboard', 'heat', 'build'] },
  tablet: { item: 'tablet', aspects: ['display', 'battery', 'performance', 'sound', 'build'] },
  accessory: { item: 'accessory', aspects: ['sound', 'battery', 'build', 'compatibility', 'charging', 'comfort'] },
  apparel: { item: 'outfit', aspects: ['fabric', 'fit', 'stitching', 'colour', 'comfort'] },
  shoes: { item: 'pair', aspects: ['comfort', 'fit', 'grip', 'durability', 'design'] },
  watch: { item: 'watch', aspects: ['design', 'strap', 'build', 'timekeeping'] },
  bag: { item: 'bag', aspects: ['design', 'material', 'size', 'stitching'] },
  jewellery: { item: 'piece', aspects: ['design', 'finish', 'material', 'comfort'] },
  sunglasses: { item: 'pair', aspects: ['design', 'lenses', 'build', 'comfort'] },
  makeup: { item: 'product', aspects: ['texture', 'longevity', 'colour', 'skin'] },
  skincare: { item: 'product', aspects: ['texture', 'results', 'skin', 'fragrance'] },
  perfume: { item: 'perfume', aspects: ['scent_longevity', 'projection', 'fragrance', 'bottle'] },
  furniture: { item: 'piece', aspects: ['build', 'assembly', 'comfort', 'design', 'size'] },
  decor: { item: 'piece', aspects: ['design', 'finish', 'size', 'material'] },
  kitchen: { item: 'item', aspects: ['build', 'cleaning', 'durability', 'size'] },
  grocery: { item: 'pack', aspects: ['taste', 'freshness', 'quantity'] },
  sports: { item: 'item', aspects: ['durability', 'grip', 'build', 'size'] },
  vehicle: { item: 'ride', aspects: ['performance', 'fuel_efficiency', 'comfort', 'handling', 'build'] },
};

const CATEGORY_GROUP = {
  smartphones: 'phone', laptops: 'laptop', tablets: 'tablet', 'mobile-accessories': 'accessory',
  'mens-shirts': 'apparel', tops: 'apparel', 'womens-dresses': 'apparel',
  'mens-shoes': 'shoes', 'womens-shoes': 'shoes', 'mens-watches': 'watch', 'womens-watches': 'watch',
  'womens-bags': 'bag', 'womens-jewellery': 'jewellery', sunglasses: 'sunglasses',
  beauty: 'makeup', 'skin-care': 'skincare', fragrances: 'perfume',
  furniture: 'furniture', 'home-decoration': 'decor', 'kitchen-accessories': 'kitchen',
  groceries: 'grocery', 'sports-accessories': 'sports', motorcycle: 'vehicle', vehicle: 'vehicle',
};

const COMMON = ['delivery', 'packaging', 'value', 'service'];

const TITLES = {
  5: ['Absolutely love it', 'Excellent purchase', 'Highly recommended', 'Exceeded my expectations', 'Worth every rupee', 'Best buy this year'],
  4: ['Very good overall', 'Great, with a minor flaw', 'Happy with it', 'Solid choice', 'Good quality'],
  3: ['Decent but not perfect', 'Average experience', 'Mixed feelings', 'Okay for the price'],
  2: ['Disappointed', 'Not as expected', 'Below average', 'Expected better'],
  1: ['Waste of money', 'Terrible quality', 'Do not buy', 'Very disappointed'],
};

const OPENERS = {
  5: ['Really happy with this {item}.', 'Bought this last month and I am impressed.', 'One of my best online purchases.', ''],
  4: ['Pretty happy with this {item} overall.', 'Using it for a few weeks now.', ''],
  3: ['This {item} is okay, nothing special.', 'Has its ups and downs.', ''],
  2: ['Expected a lot more from this {item}.', 'Not very satisfied.', ''],
  1: ['Really regret buying this {item}.', 'Very bad experience.', ''],
};

const CLOSERS = {
  5: ['Would definitely buy again.', 'Highly recommend it!', ''],
  4: ['Still recommended.', 'Overall worth it.', ''],
  3: ['Decent if you get it on sale.', 'Might work for some people.', ''],
  2: ['Would not buy again.', 'Think twice before buying.', ''],
  1: ['Would not recommend to anyone.', 'Returning it.', ''],
};

const reviewRating = (rng, productRating) =>
  Math.max(1, Math.min(5, Math.round(productRating + rng.gaussian() * 0.9)));

const composeReview = (rng, categorySlug, rating) => {
  const group = GROUPS[CATEGORY_GROUP[categorySlug]] || GROUPS.kitchen;
  const own = rng.shuffle(group.aspects);
  const common = rng.shuffle(COMMON);
  const say = (aspect, polarity) => rng.pick(ASPECTS[aspect][polarity]);

  const parts = {
    5: () => [say(own[0], 'pos'), say(own[1], 'pos'), rng.chance(0.6) && say(common[0], 'pos')],
    4: () => [say(own[0], 'pos'), say(own[1], 'pos'), `Only gripe: ${lowerFirst(say(own[2] || common[1], 'neg'))}`],
    3: () => [say(own[0], 'pos'), `However, ${lowerFirst(say(own[1], 'neg'))}`, rng.chance(0.5) && say(common[0], rng.chance(0.5) ? 'pos' : 'neg')],
    2: () => [say(own[0], 'neg'), say(own[1], 'neg'), rng.chance(0.5) && `On the plus side, ${lowerFirst(say(own[2] || common[0], 'pos'))}`],
    1: () => [say(own[0], 'neg'), say(own[1], 'neg'), say(common[0], 'neg')],
  }[rating]();

  const fill = (s) => s.replace('{item}', group.item);
  const sentences = [fill(rng.pick(OPENERS[rating])), ...parts.filter(Boolean), rng.pick(CLOSERS[rating])].filter(Boolean);
  return { title: rng.pick(TITLES[rating]), comment: sentences.join(' ') };
};

const lowerFirst = (s) => s.charAt(0).toLowerCase() + s.slice(1);

const titleForRating = (rating) => TITLES[rating][0];

module.exports = { composeReview, reviewRating, titleForRating, CATEGORY_GROUP };

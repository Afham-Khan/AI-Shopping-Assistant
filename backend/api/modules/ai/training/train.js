// npm run ai:train — trains the intent classifier and writes training/models/intent-model.json
const path = require('path');
const { train, save } = require('../engine/nlu/trainer');

const pct = (v) => `${(v * 100).toFixed(1)}%`;

const main = () => {
  console.log('Training Zelora intent classifier...\n');
  const artifact = train({ log: (line) => console.log(`  ${line}`) });
  const { metrics } = artifact;

  console.log(`\nSamples: ${artifact.trainingSamples} across ${artifact.classes.length} intents (train ${metrics.trainSize} / test ${metrics.testSize})`);
  console.log(`Vocabulary (features): ${artifact.vocabularySize}`);
  console.log(`Test accuracy: ${pct(metrics.testAccuracy)}   macro-F1: ${metrics.macroF1}   ECE: ${metrics.ece}   temperature: ${metrics.temperature}`);
  console.log(`Cross-validation: ${pct(metrics.cvAccuracy)} ± ${pct(metrics.cvStd)}   (naive bayes baseline: ${pct(metrics.baselineNaiveBayesAccuracy)})\n`);

  console.log('Per-class          precision  recall  f1     n');
  for (const [name, m] of Object.entries(metrics.perClass)) {
    console.log(`  ${name.padEnd(17)} ${m.precision.toFixed(2).padStart(6)}  ${m.recall.toFixed(2).padStart(6)}  ${m.f1.toFixed(2).padStart(5)}  ${String(m.support).padStart(3)}`);
  }
  if (metrics.confusions.length) {
    console.log('\nMost frequent confusions (actual -> predicted):');
    for (const c of metrics.confusions) console.log(`  ${c.actual} -> ${c.predicted}: ${c.count}`);
  }
  const file = save(artifact);
  console.log(`\nSaved ${path.relative(process.cwd(), file)} in ${artifact.trainingMs} ms`);
  if (metrics.testAccuracy < 0.9) process.exitCode = 1;
};

main();

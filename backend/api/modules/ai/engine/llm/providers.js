// free-tier llm adapters using global fetch (node >= 18)
const TIMEOUT_MS = 6000;

const gemini = {
  name: 'gemini',
  model: () => process.env.GEMINI_MODEL || 'gemini-2.5-flash-lite',
  enabled: () => Boolean(process.env.GEMINI_API_KEY),
  async complete({ system, user }) {
    const url = `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(gemini.model())}:generateContent`;
    const res = await fetch(url, {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'x-goog-api-key': process.env.GEMINI_API_KEY },
      body: JSON.stringify({
        systemInstruction: { parts: [{ text: system }] },
        contents: [{ role: 'user', parts: [{ text: user }] }],
        generationConfig: { temperature: 0.4, maxOutputTokens: 220 },
      }),
      signal: AbortSignal.timeout(TIMEOUT_MS),
    });
    if (!res.ok) throw new Error(`gemini ${res.status}`);
    const json = await res.json();
    return json.candidates?.[0]?.content?.parts?.map((p) => p.text).join('').trim() || '';
  },
};

const groq = {
  name: 'groq',
  model: () => process.env.GROQ_MODEL || 'llama-3.1-8b-instant',
  enabled: () => Boolean(process.env.GROQ_API_KEY),
  async complete({ system, user }) {
    const res = await fetch('https://api.groq.com/openai/v1/chat/completions', {
      method: 'POST',
      headers: { 'content-type': 'application/json', authorization: `Bearer ${process.env.GROQ_API_KEY}` },
      body: JSON.stringify({
        model: groq.model(),
        temperature: 0.4,
        max_tokens: 220,
        messages: [{ role: 'system', content: system }, { role: 'user', content: user }],
      }),
      signal: AbortSignal.timeout(TIMEOUT_MS),
    });
    if (!res.ok) throw new Error(`groq ${res.status}`);
    const json = await res.json();
    return json.choices?.[0]?.message?.content?.trim() || '';
  },
};

module.exports = { gemini, groq, TIMEOUT_MS };

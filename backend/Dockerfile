# Zelora API as a container image, for any host that runs Docker (Render "Docker" runtime, Koyeb, Fly.io, Cloud Run,
# a Hugging Face Docker Space, a VPS). Build from this folder:   docker build -t zelora-api .
# Run:  docker run -p 7860:7860 -e DATABASE_URL=... -e JWT_ACCESS_SECRET=... -e JWT_REFRESH_SECRET=... zelora-api
#
# AI_VISUAL=on keeps Snap & Find (CLIP, about 500 MB RAM); build with  --build-arg AI_VISUAL=off  on hosts under 1 GB RAM.
FROM node:22-slim

ARG AI_VISUAL=on
ENV NODE_ENV=production \
    PORT=7860 \
    AI_EMBEDDINGS=neural \
    AI_VISUAL=${AI_VISUAL}

# The node image already has the non-root user "node" with id 1000, which is also what Hugging Face Spaces requires.
# The app folder (including .cache for the models) must belong to that user so it can write there.
RUN mkdir -p /home/node/app && chown node:node /home/node/app
WORKDIR /home/node/app
USER node

COPY --chown=node:node package.json package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force

# includes the committed intent model (api/modules/ai/training/models/intent-model.json): no training step on the host
COPY --chown=node:node . .

# download the MiniLM (and CLIP when AI_VISUAL=on) models into .cache now, so the first request after a start is fast.
# A failed download never breaks the build: the API downloads the model later or falls back to TF-IDF search.
RUN npm run ai:prefetch

EXPOSE 7860
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:'+process.env.PORT+'/api/v1/health').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

CMD ["node", "server.js"]

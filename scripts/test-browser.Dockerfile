FROM node:22-bookworm-slim
WORKDIR /opt/browser-tests
RUN npm install --no-audit --no-fund playwright@1.63.0 && npx playwright install --with-deps --only-shell chromium

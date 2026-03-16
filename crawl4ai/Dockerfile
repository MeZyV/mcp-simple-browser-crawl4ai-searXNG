# Crawl4AI Service Dockerfile
FROM python:3.12-slim

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    wget \
    gnupg \
    unzip \
    curl \
    xvfb \
    && rm -rf /var/lib/apt/lists/*

# Install Chrome
RUN wget -q -O - https://dl.google.com/linux/linux_signing_key.pub | gpg --dearmor -o /usr/share/keyrings/googlechrome-linux-keyring.gpg \
    && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/googlechrome-linux-keyring.gpg] http://dl.google.com/linux/chrome/deb/ stable main" >> /etc/apt/sources.list.d/google-chrome.list \
    && apt-get update \
    && apt-get install -y google-chrome-stable \
    && rm -rf /var/lib/apt/lists/*

# Install Crawl4AI and dependencies
COPY pyproject.toml .
RUN pip install --no-cache-dir .

# Install Playwright browsers
RUN playwright install chromium
RUN playwright install-deps

# Create the FastAPI service
WORKDIR /app
# Copy source
COPY . .

EXPOSE 8002

CMD ["python", "/app/crawl4ai_service.py"]
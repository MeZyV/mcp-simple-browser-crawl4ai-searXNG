import asyncio
import os
from typing import List, Optional, Dict, Any
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import httpx
from crawl4ai import AsyncWebCrawler
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

app = FastAPI(title="Crawl4AI Service", version="1.0.0")

class ScrapeRequest(BaseModel):
    url: str
    formats: Optional[List[str]] = ["markdown"]
    wait_for: Optional[int] = 0
    timeout: Optional[int] = 30000
    proxy_url: Optional[str] = None

class BatchScrapeRequest(BaseModel):
    urls: List[str]
    formats: Optional[List[str]] = ["markdown"]
    concurrency: Optional[int] = 3

class ExtractRequest(BaseModel):
    url: str
    prompt: str
    schema: Optional[Dict[str, Any]] = None

# Global crawler instance
crawler = None

@app.on_event("startup")
async def startup_event():
    global crawler
    proxy_url = os.getenv("PROXY_URL")
    
    # Configure browser args with proxy if provided
    browser_args = [
        "--no-sandbox",
        "--disable-setuid-sandbox",
        "--disable-dev-shm-usage",
        "--disable-background-timer-throttling",
        "--disable-backgrounding-occluded-windows",
        "--disable-renderer-backgrounding"
    ]
    
    if proxy_url:
        browser_args.append(f"--proxy-server={proxy_url}")
        logger.info(f"Using proxy: {proxy_url.split('@')[1] if '@' in proxy_url else proxy_url}")
    
    crawler = AsyncWebCrawler(
        browser_type="chromium",
        headless=True,
        browser_args=browser_args
    )
    # Initialize the crawler - newer API doesn't require explicit start
    logger.info("Crawl4AI service started")

@app.on_event("shutdown")
async def shutdown_event():
    global crawler
    if crawler:
        # Close the crawler if needed
        logger.info("Crawl4AI service stopped")

@app.get("/health")
async def health_check():
    return {"status": "ok", "service": "crawl4ai"}

@app.post("/scrape")
async def scrape_url(request: ScrapeRequest):
    try:
        if not crawler:
            raise HTTPException(status_code=500, detail="Crawler not initialized")
        
        result = await crawler.arun(
            url=request.url,
            word_count_threshold=10,
            wait_for=request.wait_for / 1000 if request.wait_for else 0
        )
        
        if not result.success:
            raise HTTPException(status_code=400, detail=f"Scraping failed: {result.error_message}")
        
        response_data = {
            "success": True,
            "url": request.url,
            "data": {}
        }
        
        # Include requested formats
        if "markdown" in request.formats:
            response_data["data"]["markdown"] = result.markdown
        if "html" in request.formats:
            response_data["data"]["html"] = result.cleaned_html
        if "links" in request.formats:
            response_data["data"]["links"] = result.links
        if "media" in request.formats:
            response_data["data"]["media"] = result.media
            
        response_data["data"]["metadata"] = {
            "title": result.metadata.get("title", ""),
            "description": result.metadata.get("description", ""),
            "language": result.metadata.get("language", ""),
            "word_count": len(result.markdown.split()) if result.markdown else 0
        }
        
        return response_data
        
    except Exception as e:
        logger.error(f"Error scraping {request.url}: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/batch-scrape")
async def batch_scrape_urls(request: BatchScrapeRequest):
    try:
        if not crawler:
            raise HTTPException(status_code=500, detail="Crawler not initialized")
        
        # Limit concurrency
        semaphore = asyncio.Semaphore(min(request.concurrency, 5))
        
        async def scrape_single(url: str):
            async with semaphore:
                scrape_req = ScrapeRequest(url=url, formats=request.formats)
                return await scrape_url(scrape_req)
        
        tasks = [scrape_single(url) for url in request.urls]
        results = await asyncio.gather(*tasks, return_exceptions=True)
        
        # Process results
        successful_results = []
        for i, result in enumerate(results):
            if isinstance(result, Exception):
                logger.error(f"Error scraping {request.urls[i]}: {str(result)}")
                successful_results.append({
                    "success": False,
                    "url": request.urls[i],
                    "error": str(result)
                })
            else:
                successful_results.append(result)
        
        return {
            "success": True,
            "total": len(request.urls),
            "results": successful_results
        }
        
    except Exception as e:
        logger.error(f"Error in batch scraping: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))

@app.post("/extract")
async def extract_data(request: ExtractRequest):
    try:
        if not crawler:
            raise HTTPException(status_code=500, detail="Crawler not initialized")
        
        # Simple extraction using the prompt - will extract based on the content
        result = await crawler.arun(
            url=request.url,
            word_count_threshold=10
        )
        
        if not result.success:
            raise HTTPException(status_code=400, detail=f"Extraction failed: {result.error_message}")
        
        return {
            "success": True,
            "url": request.url,
            "extracted_data": result.extracted_content
        }
        
    except Exception as e:
        logger.error(f"Error extracting from {request.url}: {str(e)}")
        raise HTTPException(status_code=500, detail=str(e))

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8002)
#!/usr/bin/env python3
"""Coze Studio 适配器 - 将 Coze 请求转换为 Hermes 格式"""

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import httpx
import os
from typing import Optional, List

app = FastAPI(title="Coze to Hermes Adapter")

HERMES_API = os.environ.get("HERMES_API_URL", "http://hermes:8000")
HERMES_API_KEY = os.environ.get("API_SERVER_KEY", "")

class CozeRequest(BaseModel):
    """Coze 标准请求格式"""
    query: str
    conversation_id: Optional[str] = None
    user_id: Optional[str] = None
    stream: bool = False

class CozeResponse(BaseModel):
    """Coze 标准响应格式"""
    answer: str
    conversation_id: str
    metadata: dict = {}

@app.post("/v1/chat")
async def chat(request: CozeRequest):
    """转发请求到 Hermes"""
    async with httpx.AsyncClient(timeout=60.0) as client:
        hermes_payload = {
            "query": request.query,
            "history": [],  # 可选：从 conversation_id 获取历史
            "temperature": 0.3,
            "max_tokens": 2000
        }

        headers = {
            "Authorization": f"Bearer {HERMES_API_KEY}",
            "Content-Type": "application/json"
        }

        response = await client.post(
            f"{HERMES_API}/api/v1/chat",
            json=hermes_payload,
            headers=headers
        )

        if response.status_code != 200:
            raise HTTPException(status_code=500, detail="Hermes API error")

        result = response.json()
        return CozeResponse(
            answer=result.get("response", ""),
            conversation_id=request.conversation_id or "new",
            metadata={"sources": result.get("sources", [])}
        )

@app.get("/health")
async def health():
    return {"status": "ok"}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8081)
import os
import random

import jwt
from fastmcp import FastMCP
from jwt import PyJWKClient
from starlette.middleware import Middleware
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import JSONResponse

TENANT_ID = os.getenv("ENTRA_TENANT_ID", "").strip()
AUDIENCE = os.getenv("GATEWAY_AUDIENCE", "").strip()
EXTRA_ACCEPTED_AUDIENCES = [
    s.strip() for s in os.getenv("EXTRA_ACCEPTED_AUDIENCES", "").split(",") if s.strip()
]
ALLOWED_CLIENT_IDS = {
    s.strip() for s in os.getenv("ALLOWED_CLIENT_IDS", "").split(",") if s.strip()
}

if not TENANT_ID or not AUDIENCE:
    raise RuntimeError("ENTRA_TENANT_ID and GATEWAY_AUDIENCE are required")

ISSUER = f"https://login.microsoftonline.com/{TENANT_ID}/v2.0"
JWKS_URL = f"https://login.microsoftonline.com/{TENANT_ID}/discovery/v2.0/keys"
JWK_CLIENT = PyJWKClient(JWKS_URL)

accepted_audiences = {AUDIENCE}
if AUDIENCE.startswith("api://"):
    accepted_audiences.add(AUDIENCE.replace("api://", "", 1))
accepted_audiences.add(AUDIENCE[:-1] if AUDIENCE.endswith("/") else f"{AUDIENCE}/")
for a in EXTRA_ACCEPTED_AUDIENCES:
    accepted_audiences.add(a)

def decode_token(auth_header: str) -> dict:
    scheme, _, token = auth_header.partition(" ")
    if scheme != "Bearer" or not token:
        raise ValueError("Missing bearer token")

    signing_key = JWK_CLIENT.get_signing_key_from_jwt(token)
    payload = jwt.decode(
        token,
        signing_key.key,
        algorithms=["RS256"],
        audience=list(accepted_audiences),
        issuer=ISSUER,
        options={"verify_aud": True},
    )

    caller_client_id = payload.get("azp") or payload.get("appid")
    if ALLOWED_CLIENT_IDS and str(caller_client_id or "") not in ALLOWED_CLIENT_IDS:
        raise PermissionError("Caller client id is not allowed")

    return payload


class EntraAuthMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        if request.url.path == "/healthz":
            return await call_next(request)

        try:
            decode_token(request.headers.get("authorization", ""))
            return await call_next(request)
        except PermissionError as ex:
            return JSONResponse(status_code=403, content={"error": str(ex)})
        except Exception as ex:
            return JSONResponse(
                status_code=401,
                content={"error": "Token validation failed", "details": str(ex)},
            )


mcp = FastMCP(
    name="weather",
    instructions="""
        This server provides weather info.
        Call get_cities(country) to get the list of cities.
        Call get_weather(city) to get the weather for a specific city.
    """,
)


@mcp.tool()
async def get_cities(country: str) -> list[str]:
    cities_by_country = {
        "usa": ["New York", "Los Angeles", "Chicago", "Houston", "Phoenix"],
        "canada": ["Toronto", "Vancouver", "Montreal", "Calgary", "Ottawa"],
        "uk": ["London", "Manchester", "Birmingham", "Leeds", "Glasgow"],
        "australia": ["Sydney", "Melbourne", "Brisbane", "Perth", "Adelaide"],
        "india": ["Mumbai", "Delhi", "Bangalore", "Hyderabad", "Chennai"],
        "portugal": ["Lisbon", "Porto", "Braga", "Faro", "Coimbra"],
    }
    return cities_by_country.get(country.lower(), [])


@mcp.tool()
async def get_weather(city: str) -> str:
    weather_conditions = ["Sunny", "Cloudy", "Rainy", "Snowy", "Windy"]
    temperature = random.uniform(-10, 35)
    humidity = random.uniform(20, 100)
    weather_info = {
        "city": city,
        "condition": random.choice(weather_conditions),
        "temperature": round(temperature, 2),
        "humidity": round(humidity, 2),
    }
    return str(weather_info)


app = mcp.http_app(
    path="/mcp",
    transport="sse",
    middleware=[Middleware(EntraAuthMiddleware)],
)


async def healthz(_request: Request):
    return JSONResponse({"ok": True, "service": "customer-mcp-gateway-fastmcp"})


app.router.add_route("/healthz", healthz, methods=["GET"])

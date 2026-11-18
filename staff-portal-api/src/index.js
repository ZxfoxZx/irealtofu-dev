
/**
 * ============================================================
 * CREATE: ULTIMATE AUTOMATION
 * STAFF PORTAL API
 *
 * Phase 1 - API Foundation
 * ============================================================
 *
 * Current endpoints:
 *
 * GET /health
 *     Checks whether the API is responding.
 *
 * GET /health/db
 *     Checks whether the Portal D1 database is accessible.
 *
 * Authentication and staff endpoints will be added later.
 *
 * ============================================================
 */

const SERVICE_NAME = "CUA Staff Portal API";
const API_VERSION = "1.0.0";


// ============================================================
// RESPONSE HELPERS
// ============================================================

function jsonResponse(data, status = 200) {
  return new Response(JSON.stringify(data, null, 2), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
      "X-Content-Type-Options": "nosniff",
      "X-Frame-Options": "DENY",
      "Referrer-Policy": "no-referrer",
      "Permissions-Policy": "camera=(), microphone=(), geolocation=()",
      "Content-Security-Policy": "default-src 'none'; frame-ancestors 'none'"
    }
  });
}


// ============================================================
// HEALTH CHECK
// ============================================================

function healthCheck() {
  return jsonResponse({
    success: true,
    service: SERVICE_NAME,
    version: API_VERSION,
    status: "online",
    timestamp: new Date().toISOString()
  });
}


// ============================================================
// DATABASE HEALTH CHECK
// ============================================================

async function databaseHealthCheck(env) {
  try {
    if (!env.PORTAL_DB) {
      throw new Error("Database binding unavailable");
    }

    const result = await env.PORTAL_DB
      .prepare("SELECT 1 AS connection_test")
      .first();

    if (!result || result.connection_test !== 1) {
      throw new Error("Database connection test failed");
    }

    return jsonResponse({
      success: true,
      service: SERVICE_NAME,
      database: {
        connected: true,
        status: "online"
      },
      timestamp: new Date().toISOString()
    });

  } catch (error) {
    console.error("Database health check failed:", error);

    return jsonResponse({
      success: false,
      service: SERVICE_NAME,
      database: {
        connected: false,
        status: "unavailable"
      },
      error: "Database connection failed",
      timestamp: new Date().toISOString()
    }, 503);
  }
}


// ============================================================
// REQUEST HANDLER
// ============================================================

async function handleRequest(request, env) {
  const url = new URL(request.url);
  const pathname = url.pathname;

  // Only GET requests are currently supported.
  if (request.method !== "GET") {
    return jsonResponse({
      success: false,
      error: "Method not allowed"
    }, 405);
  }

  // API health check.
  if (pathname === "/health") {
    return healthCheck();
  }

  // Database connectivity check.
  if (pathname === "/health/db") {
    return await databaseHealthCheck(env);
  }

  // Unknown endpoint.
  return jsonResponse({
    success: false,
    error: "Endpoint not found"
  }, 404);
}


// ============================================================
// CLOUDFLARE WORKER ENTRY POINT
// ============================================================

export default {
  async fetch(request, env, ctx) {
    try {
      return await handleRequest(request, env);

    } catch (error) {
      console.error("Unhandled API error:", error);

      return jsonResponse({
        success: false,
        error: "Internal server error"
      }, 500);
    }
  }
};

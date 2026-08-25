"use strict";

const http = require("http");
const os = require("os");

const PORT = 8080;
const START_TIME = Date.now();
const APP_VERSION = process.env.APP_VERSION || "v1";

function getMetadata() {
	// Metadata gathered dynamically at request time (no static values).
	return {
		hostname: os.hostname(),
		version: APP_VERSION,
		uptime_seconds: Math.round((Date.now() - START_TIME) / 10) / 100,
		timestamp: new Date().toISOString(),
		pid: process.pid,
	};
}

function sendJson(res, statusCode, body) {
	const payload = JSON.stringify(body);
	res.writeHead(statusCode, { "Content-Type": "application/json" });
	res.end(payload);
}

const server = http.createServer((req, res) => {
	if (req.method === "GET" && req.url === "/health") {
		sendJson(res, 200, { status: "ok" });
		return;
	}

	if (req.method === "GET" && (req.url === "/api" || req.url === "/api/")) {
		sendJson(res, 200, {
			status: "ok",
			service: "proj04-api",
			hostname: os.hostname(),
			metadata: getMetadata(),
		});
		return;
	}

	sendJson(res, 404, { status: "not found" });
});

server.listen(PORT, "0.0.0.0", () => {
	console.log(`proj04-api listening on port ${PORT}`);
});

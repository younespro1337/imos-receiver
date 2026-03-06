/**
 * IMOS XML Receiver Server
 *
 * Runs on 192.168.30.41 (the IMOS machine).
 * Listens on port 3500 for POST /imos/receive with XML body.
 * Saves each XML file to the IMOS_INBOX folder.
 *
 * Usage:
 *   node server.js
 *   or: npm start
 *
 * Environment:
 *   PORT         — listen port (default: 3500)
 *   IMOS_INBOX   — folder to save XML files (default: C:\imos_inbox)
 *   ALLOWED_IPS  — comma-separated IPs to allow (default: allow all)
 */

const express = require("express");
const fs = require("fs");
const path = require("path");
const os = require("os");

// ── File Logger ──────────────────────────────────────────────────────────────
// Writes all output to server.log alongside stdout/stderr
const LOG_FILE = path.join(__dirname, "server.log");
const logStream = fs.createWriteStream(LOG_FILE, { flags: "a" });

const _origLog = console.log.bind(console);
const _origErr = console.error.bind(console);

console.log = (...args) => {
    const msg = args.map(a => (typeof a === "string" ? a : JSON.stringify(a))).join(" ");
    const line = `[${new Date().toISOString()}] ${msg}`;
    _origLog(...args);
    logStream.write(line + "\n");
};

console.error = (...args) => {
    const msg = args.map(a => (typeof a === "string" ? a : JSON.stringify(a))).join(" ");
    const line = `[${new Date().toISOString()}] ERROR: ${msg}`;
    _origErr(...args);
    logStream.write(line + "\n");
};

// ── Config ───────────────────────────────────────────────────────────────────
const PORT = parseInt(process.env.PORT, 10) || 3500;
const IMOS_INBOX = process.env.IMOS_INBOX || "C:\\imos_inbox";
const ALLOWED_IPS = process.env.ALLOWED_IPS
    ? process.env.ALLOWED_IPS.split(",").map((s) => s.trim())
    : null; // null = allow all

// ── Ensure inbox exists ──────────────────────────────────────────────────────
if (!fs.existsSync(IMOS_INBOX)) {
    fs.mkdirSync(IMOS_INBOX, { recursive: true });
    console.log(`[IMOS Receiver] Created inbox folder: ${IMOS_INBOX}`);
}

// ── Crash recovery — keep the process alive ──────────────────────────────────
process.on("uncaughtException", (err) => {
    console.error(`[IMOS Receiver] UNCAUGHT EXCEPTION: ${err.message}`);
    console.error(err.stack);
    // Do NOT exit — keep the server running
});

process.on("unhandledRejection", (reason) => {
    console.error(`[IMOS Receiver] UNHANDLED REJECTION: ${reason}`);
    // Do NOT exit — keep the server running
});

// ── Express app ──────────────────────────────────────────────────────────────
const app = express();

// Accept raw XML body (up to 10 MB)
app.use(express.text({ type: ["application/xml", "text/xml", "text/plain"], limit: "10mb" }));
// Also accept JSON for health checks / future use
app.use(express.json({ limit: "1mb" }));

// ── IP filter middleware ─────────────────────────────────────────────────────
if (ALLOWED_IPS) {
    app.use((req, res, next) => {
        const clientIp = req.ip || req.connection.remoteAddress || "";
        const clean = clientIp.replace(/^::ffff:/, ""); // strip IPv6 prefix
        if (ALLOWED_IPS.includes(clean) || clean === "127.0.0.1" || clean === "::1") {
            return next();
        }
        console.log(`[IMOS Receiver] BLOCKED request from ${clean}`);
        return res.status(403).json({ error: "Forbidden", ip: clean });
    });
}

// ── Health check ─────────────────────────────────────────────────────────────
app.get("/", (req, res) => {
    const files = fs.readdirSync(IMOS_INBOX).filter((f) => f.endsWith(".xml"));
    res.json({
        status: "ok",
        service: "IMOS XML Receiver",
        inbox: IMOS_INBOX,
        files_count: files.length,
        uptime: Math.floor(process.uptime()),
        timestamp: new Date().toISOString(),
    });
});

app.get("/health", (req, res) => {
    res.json({ status: "ok", uptime: Math.floor(process.uptime()) });
});

// ── Receive XML ──────────────────────────────────────────────────────────────
app.post("/imos/receive", (req, res) => {
    const t0 = Date.now();
    const xml = req.body;

    if (!xml || typeof xml !== "string" || xml.trim().length === 0) {
        console.log(`[IMOS Receiver] Empty or invalid XML received`);
        return res.status(400).json({ error: "Empty or invalid XML body" });
    }

    // Extract order number from XML if possible
    let orderNo = "unknown";
    const match = xml.match(/Order\s+No="([^"]+)"/);
    if (match) orderNo = match[1];

    // Generate filename
    const timestamp = new Date().toISOString().replace(/[:.]/g, "-");
    const fileName = `${orderNo}_${timestamp}.xml`;
    const filePath = path.join(IMOS_INBOX, fileName);

    try {
        fs.writeFileSync(filePath, xml, "utf-8");
        const elapsed = Date.now() - t0;

        console.log(`[IMOS Receiver] ✅ Saved: ${fileName} (${xml.length} bytes, ${elapsed}ms)`);

        return res.status(200).json({
            success: true,
            message: "XML received and saved",
            file: fileName,
            path: filePath,
            size: xml.length,
            order_no: orderNo,
            elapsed_ms: elapsed,
        });
    } catch (err) {
        console.error(`[IMOS Receiver] ❌ Write error: ${err.message}`);
        return res.status(500).json({
            error: "Failed to save XML",
            details: err.message,
        });
    }
});

// ── List received files ──────────────────────────────────────────────────────
app.get("/imos/files", (req, res) => {
    try {
        const files = fs.readdirSync(IMOS_INBOX)
            .filter((f) => f.endsWith(".xml"))
            .map((f) => {
                const stat = fs.statSync(path.join(IMOS_INBOX, f));
                return { name: f, size: stat.size, modified: stat.mtime };
            })
            .sort((a, b) => new Date(b.modified) - new Date(a.modified));

        res.json({ count: files.length, files });
    } catch (err) {
        res.status(500).json({ error: err.message });
    }
});

// ── Start ────────────────────────────────────────────────────────────────────
app.listen(PORT, "0.0.0.0", () => {
    const nets = os.networkInterfaces();
    const ips = [];
    for (const iface of Object.values(nets)) {
        for (const cfg of iface) {
            if (cfg.family === "IPv4" && !cfg.internal) ips.push(cfg.address);
        }
    }

    console.log(`\n╔══════════════════════════════════════════════════════════╗`);
    console.log(`║           IMOS XML Receiver Server                      ║`);
    console.log(`╠══════════════════════════════════════════════════════════╣`);
    console.log(`║  Port      : ${PORT}                                      ║`);
    console.log(`║  Inbox     : ${IMOS_INBOX.padEnd(42)}║`);
    console.log(`║  IPs       : ${ips.join(", ").padEnd(42)}║`);
    console.log(`║  Endpoints :                                            ║`);
    console.log(`║    GET  /              — health + stats                  ║`);
    console.log(`║    GET  /health        — simple health check             ║`);
    console.log(`║    POST /imos/receive  — receive XML                     ║`);
    console.log(`║    GET  /imos/files    — list received files              ║`);
    console.log(`╚══════════════════════════════════════════════════════════╝\n`);
});
